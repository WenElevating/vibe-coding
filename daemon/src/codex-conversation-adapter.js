'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { spawn, spawnSync } = require('node:child_process');
const { conversationEventTypes } = require('./conversation-protocol');
const { resolveCliInvocation } = require('./cli-resolver');
const { discoverConfiguredModels } = require('./model-discovery');
const { textAttachmentWrapper } = require('./attachment-validation');

const DEFAULT_MAX_JSON_LINE_BYTES = 1024 * 1024;
const DEFAULT_MAX_AGGREGATED_OUTPUT_BYTES = 64 * 1024;
const DEFAULT_MAX_FILE_CHANGE_DIFF_BYTES = 32 * 1024;
const DEFAULT_CODEX_TOOL_TIMEOUT_SEC = 600;
const CODEX_DETECTION_TIMEOUT_MS = 30000;

class CodexConversationAdapter {
  constructor({
    command = 'codex',
    spawnFn = spawn,
    spawnSyncFn = spawnSync,
    cliResolverOptions = {},
    killProcessTreeFn = defaultKillProcessTree,
    maxJsonLineBytes = DEFAULT_MAX_JSON_LINE_BYTES,
    maxAggregatedOutputBytes = DEFAULT_MAX_AGGREGATED_OUTPUT_BYTES,
    toolTimeoutSec = DEFAULT_CODEX_TOOL_TIMEOUT_SEC
  } = {}) {
    this.name = 'codex';
    this.command = command;
    this.spawnFn = spawnFn;
    this.spawnSyncFn = spawnSyncFn;
    this.killProcessTreeFn = killProcessTreeFn;
    this.maxJsonLineBytes = maxJsonLineBytes;
    this.maxAggregatedOutputBytes = maxAggregatedOutputBytes;
    this.toolTimeoutSec = normalizeCodexToolTimeoutSec(toolTimeoutSec);
    this.invocation = resolveCliInvocation(command, { spawnSyncFn, ...cliResolverOptions });
    this.capability = null;
    this.modelCapability = defaultModelCapability();
    this.imageInputSupported = false;
    this.capabilities = {
      longLivedProcess: false,
      waitingInput: false,
      waitingApproval: false,
      resume: true,
      partialOutput: true,
      toolEvents: true,
      approvalPolicy: 'cli-policy',
      mobileApprovalCallbacks: false,
      approval: {
        mobileCallbacks: false,
        scopes: [],
        supportsCancel: false,
        denyBehaviors: []
      },
      attachments: {
        image: 'unsupported',
        textDocument: 'text_extract',
        pdf: 'unsupported'
      }
    };
  }

  detectCapabilities() {
    const version = this.spawnSyncFn(this.invocation.command, [...this.invocation.argsPrefix, '--version'], { encoding: 'utf8', timeout: CODEX_DETECTION_TIMEOUT_MS });
    if (version.error || version.status !== 0) {
      this.capability = unavailableCapability(this.command, `Codex CLI unavailable. Check installation and PATH. ${resultText(version)}`);
      return this.capability;
    }
    const execHelp = this.spawnSyncFn(this.invocation.command, [...this.invocation.argsPrefix, 'exec', '--help'], { encoding: 'utf8', timeout: CODEX_DETECTION_TIMEOUT_MS });
    if (execHelp.error || execHelp.status !== 0 || !resultText(execHelp).includes('--json')) {
      this.capability = unavailableCapability(this.command, 'Codex CLI missing required exec --json capability');
      this.capability.version = resultText(version).trim() || null;
      return this.capability;
    }
    const execHelpText = resultText(execHelp);
    const resumeHelp = this.spawnSyncFn(this.invocation.command, [...this.invocation.argsPrefix, 'exec', 'resume', '--help'], { encoding: 'utf8', timeout: CODEX_DETECTION_TIMEOUT_MS });
    if (resumeHelp.error || resumeHelp.status !== 0 || !/resume/i.test(resultText(resumeHelp)) || !resultText(resumeHelp).includes('--json')) {
      this.capability = unavailableCapability(this.command, 'Codex CLI missing required exec resume --json capability');
      this.capability.version = resultText(version).trim() || null;
      return this.capability;
    }
    const resumeHelpText = resultText(resumeHelp);
    const execSupportsModel = helpHasModelFlag(execHelpText);
    const resumeSupportsModel = helpHasModelFlag(resumeHelpText);
    const execSupportsImage = helpHasImageFlag(execHelpText);
    const resumeSupportsImage = helpHasImageFlag(resumeHelpText);
    this.imageInputSupported = execSupportsImage && resumeSupportsImage;
    this.modelCapability = {
      ...discoverConfiguredModels({ adapter: 'codex' }),
      canSelectModel: execSupportsModel && resumeSupportsModel
    };
    this.capability = {
      adapter: 'codex',
      version: resultText(version).trim() || null,
      available: true,
      command: this.command,
      ...this.modelCapability,
      capabilities: {
        ...this.getCapabilities(),
        execJson: true,
        resumeJson: true,
        execSupportsModelFlag: execSupportsModel,
        resumeSupportsModelFlag: resumeSupportsModel,
        execSupportsImageFlag: execSupportsImage,
        resumeSupportsImageFlag: resumeSupportsImage,
        resumeWorkspaceOverride: /\b--cd\b|\s-C,\s*--cd|\s-C\s/.test(resumeHelpText)
      }
    };
    return this.capability;
  }

  getModelCapability() {
    return this.modelCapability || defaultModelCapability();
  }

  getCapabilities() {
    return {
      ...this.capabilities,
      attachments: {
        image: this.imageInputSupported ? 'native' : 'unsupported',
        textDocument: 'text_extract',
        pdf: 'unsupported'
      }
    };
  }

  ensureAvailable() {
    const capability = this.capability || this.detectCapabilities();
    if (!capability.available) {
      const error = new Error(capability.error || 'Codex conversation adapter unavailable');
      error.status = 503;
      error.code = 'CODEX_CONVERSATION_UNAVAILABLE';
      error.details = capability;
      throw error;
    }
  }

  async startConversation({ conversationId, workspacePath, permissionMode = 'default', sessionId, model, onEvent }) {
    if (!workspacePath || !String(workspacePath).trim()) throw new Error('workspacePath is required');
    this.ensureAvailable();
    return new CodexConversationHandle({
      conversationId,
      adapter: this,
      workspacePath,
      permissionMode,
      sessionId,
      model,
      onEvent
    });
  }
}

class CodexConversationHandle {
  constructor({ conversationId, adapter, workspacePath, permissionMode, sessionId, model, onEvent }) {
    this.conversationId = conversationId;
    this.adapter = adapter;
    this.workspacePath = workspacePath;
    this.permissionMode = permissionMode;
    this.sessionId = sessionId || null;
    this.model = model || null;
    this.onEvent = onEvent;
    this.activeChild = null;
    this.cancelling = false;
    this.turnCompleted = false;
    this.validJsonStarted = false;
    this.stderrText = '';
  }

  async sendUserMessage(message) {
    if (this.activeChild) {
      const error = new Error('Codex turn is already running');
      error.status = 409;
      throw error;
    }
    const userMessage = typeof message === 'string'
      ? { prompt: message, imagePaths: [] }
      : buildAdapterUserMessage(message);
    this.cancelling = false;
    this.turnCompleted = false;
    this.validJsonStarted = false;
    this.stderrText = '';
    const resumeSupportsCd = this.adapter.capability?.capabilities?.resumeWorkspaceOverride === true;
    const model = this.adapter.modelCapability?.canSelectModel === true ? this.model : null;
    const args = this.sessionId
      ? buildCodexResumeArgs({ prompt: userMessage.prompt, imagePaths: userMessage.imagePaths, sessionId: this.sessionId, permissionMode: this.permissionMode, workspacePath: this.workspacePath, resumeSupportsCd, model, toolTimeoutSec: this.adapter.toolTimeoutSec })
      : buildCodexExecArgs({ prompt: userMessage.prompt, imagePaths: userMessage.imagePaths, workspacePath: this.workspacePath, permissionMode: this.permissionMode, model, toolTimeoutSec: this.adapter.toolTimeoutSec });
    const child = this.adapter.spawnFn(this.adapter.invocation.command, [...this.adapter.invocation.argsPrefix, ...args], {
      cwd: this.workspacePath,
      windowsHide: true,
      env: processEnvForWorkspace(process.env, this.workspacePath)
    });
    this.activeChild = child;
    const parseStdout = createJsonLineParser({
      maxJsonLineBytes: this.adapter.maxJsonLineBytes,
      onJson: (raw) => this.handleJson(raw)
    });
    child.stdout.on('data', parseStdout);
    child.stderr.on('data', (chunk) => this.handleStderr(chunk));
    child.on('error', (error) => {
      this.onEvent({ type: conversationEventTypes.RUN_ERROR, message: error.message });
    });
    child.on('exit', (code, signal) => this.handleExit(code, signal));
    closeChildInput(child);
  }

  handleJson(raw) {
    if (this.turnCompleted && raw?.type === 'error') return;
    this.validJsonStarted = true;
    const event = mapCodexEvent(raw, {
      maxAggregatedOutputBytes: this.adapter.maxAggregatedOutputBytes,
      workspacePath: this.workspacePath,
      includeFileChangeDiff: true
    });
    if (!event) return;
    if (event.sessionId) this.sessionId = event.sessionId;
    this.onEvent(event);
    if (event.type === conversationEventTypes.CONVERSATION_COMPLETED || event.type === conversationEventTypes.RUN_ERROR) {
      this.turnCompleted = true;
    }
  }

  handleStderr(chunk) {
    const text = stripAnsi(chunk.toString());
    this.stderrText += text;
    if (this.validJsonStarted && text.trim()) {
      this.onEvent({ type: conversationEventTypes.PROTOCOL_WARNING, text });
    }
  }

  handleExit(code, signal) {
    const child = this.activeChild;
    if (child) this.activeChild = null;
    if (this.cancelling || signal) {
      this.onEvent({ type: conversationEventTypes.CONVERSATION_CANCELLED, signal: signal || null });
      return;
    }
    if (code === 0) {
      if (!this.turnCompleted) this.onEvent({ type: conversationEventTypes.CONVERSATION_COMPLETED });
      return;
    }
    if (!this.validJsonStarted && this.stderrText.trim()) {
      this.onEvent({ type: conversationEventTypes.RUN_ERROR, message: this.stderrText.trim(), exitCode: code });
      return;
    }
    if (!this.turnCompleted) this.onEvent({ type: conversationEventTypes.RUN_ERROR, exitCode: code });
  }

  async answerQuestion() {
    const error = new Error('Codex CLI does not expose mobile input callbacks');
    error.status = 409;
    throw error;
  }

  async respondApproval() {
    const error = new Error('Codex CLI approval is handled by local CLI policy');
    error.status = 409;
    throw error;
  }

  async cancel() {
    if (!this.activeChild) return;
    this.cancelling = true;
    await this.adapter.killProcessTreeFn(this.activeChild);
  }

  async dispose() {
    await this.cancel();
  }
}

function defaultModelCapability() {
  return { models: [], selectedModel: null, canSelectModel: false };
}

function helpHasModelFlag(helpText) {
  return /(^|[\s[(,])--model(?=$|[\s=,\])])/m.test(helpText || '');
}

function helpHasImageFlag(helpText) {
  return /(^|[\s[(,])--image(?=$|[\s=,\])])|(^|[\s[(,])-i(?=$|[\s=,\])])/m.test(helpText || '');
}

function buildAdapterUserMessage({ text, attachments = [] } = {}) {
  const parts = [];
  const prompt = String(text || '');
  if (prompt) parts.push(prompt);
  const imagePaths = [];
  for (const attachment of Array.isArray(attachments) ? attachments : []) {
    if (!attachment || typeof attachment !== 'object') continue;
    if (attachment.kind === 'image' && attachment.handling === 'native' && attachment.scratchPath) {
      imagePaths.push(String(attachment.scratchPath));
      continue;
    }
    if (attachment.kind === 'textDocument' && attachment.handling === 'text_extract') {
      parts.push(textAttachmentWrapper({
        name: attachment.name,
        mimeType: attachment.mimeType,
        text: attachment.text
      }));
    }
  }
  return {
    prompt: parts.join('\n\n'),
    imagePaths
  };
}

function buildImageArgs(imagePaths) {
  const args = [];
  for (const imagePath of Array.isArray(imagePaths) ? imagePaths : []) {
    if (typeof imagePath === 'string' && imagePath.trim()) args.push('--image', imagePath);
  }
  return args;
}

function buildCodexExecArgs({ prompt, workspacePath, permissionMode = 'default', model, imagePaths = [], toolTimeoutSec = null }) {
  return [
    '--ask-for-approval', approvalPolicy(permissionMode),
    ...buildCodexToolTimeoutConfig(toolTimeoutSec),
    'exec',
    '--json',
    ...(model ? ['--model', model] : []),
    '-C', workspacePath,
    '--skip-git-repo-check',
    '--sandbox', 'workspace-write',
    prompt,
    ...buildImageArgs(imagePaths)
  ];
}

function buildCodexResumeArgs({ prompt, sessionId, permissionMode = 'default', workspacePath, resumeSupportsCd = false, model, imagePaths = [], toolTimeoutSec = null }) {
  return [
    '--ask-for-approval', approvalPolicy(permissionMode),
    ...buildCodexToolTimeoutConfig(toolTimeoutSec),
    'exec',
    'resume',
    '--json',
    ...(model ? ['--model', model] : []),
    '--skip-git-repo-check',
    ...(resumeSupportsCd ? ['--cd', workspacePath] : []),
    sessionId,
    prompt,
    ...buildImageArgs(imagePaths)
  ];
}

function approvalPolicy(permissionMode) {
  return permissionMode === 'auto' ? 'never' : 'on-request';
}

function buildCodexToolTimeoutConfig(toolTimeoutSec) {
  const normalized = normalizeCodexToolTimeoutSec(toolTimeoutSec);
  return normalized === null ? [] : ['-c', `tool_timeout_sec=${normalized}`];
}

function normalizeCodexToolTimeoutSec(value) {
  if (value === null || value === false) return null;
  if (value === undefined || value === '') return DEFAULT_CODEX_TOOL_TIMEOUT_SEC;
  const numeric = Number(value);
  if (!Number.isFinite(numeric) || numeric <= 0) return DEFAULT_CODEX_TOOL_TIMEOUT_SEC;
  return Math.floor(numeric);
}

function mapCodexEvent(raw, options = {}) {
  const maxAggregatedOutputBytes = options.maxAggregatedOutputBytes || DEFAULT_MAX_AGGREGATED_OUTPUT_BYTES;
  if (!raw || typeof raw !== 'object') return null;
  if (raw.type === 'thread.started') {
    return {
      type: conversationEventTypes.SYSTEM_NOTICE,
      text: 'Codex thread started',
      noticeKind: 'codex_thread_started',
      sessionId: raw.thread_id || raw.threadId,
      visible: false,
      raw
    };
  }
  if (raw.type === 'turn.started') {
    return {
      type: conversationEventTypes.SYSTEM_NOTICE,
      text: 'Codex turn started',
      noticeKind: 'codex_turn_started',
      visible: false,
      raw
    };
  }
  if (raw.type === 'turn.completed') return { type: conversationEventTypes.CONVERSATION_COMPLETED, usage: raw.usage || null, raw };
  if (raw.type === 'turn.failed') {
    return {
      type: conversationEventTypes.RUN_ERROR,
      message: raw.error?.message || raw.message || 'Codex turn failed',
      error: raw.error || null,
      raw
    };
  }
  if (raw.type === 'error') {
    return {
      type: conversationEventTypes.SYSTEM_NOTICE,
      text: raw.message || 'Codex error',
      noticeKind: 'codex_error',
      raw
    };
  }
  const item = raw.item && typeof raw.item === 'object' ? raw.item : null;
  if (['item.started', 'item.updated', 'item.completed'].includes(raw.type) && item?.type === 'todo_list') {
    return mapCodexTodoListEvent(raw, item);
  }
  if (['item.started', 'item.completed'].includes(raw.type) && item?.type === 'file_change') {
    return mapCodexFileChangeEvent(raw, item, options);
  }
  if (['item.started', 'item.completed'].includes(raw.type) && item?.type === 'mcp_tool_call') {
    return mapCodexMcpToolCallEvent(raw, item, options);
  }
  if (raw.type === 'item.started' && item?.type === 'command_execution') {
    return {
      type: conversationEventTypes.TOOL_STARTED,
      toolUseId: item.id || null,
      toolName: 'command_execution',
      input: { command: item.command || '' },
      summary: item.command || 'command_execution',
      raw
    };
  }
  if (raw.type === 'item.completed' && item?.type === 'command_execution') {
    const output = truncateText(stripAnsi(item.aggregated_output || ''), maxAggregatedOutputBytes);
    if (item.status === 'declined') {
      return {
        type: conversationEventTypes.SYSTEM_NOTICE,
        text: 'Codex CLI blocked this command under the current local policy.',
        noticeKind: 'codex_policy_blocked',
        toolUseId: item.id || null,
        command: item.command || '',
        output: output.text,
        truncated: output.truncated,
        raw
      };
    }
    const exitCode = Number.isInteger(item.exit_code) ? item.exit_code : null;
    const status = item.status || null;
    return {
      type: conversationEventTypes.TOOL_COMPLETED,
      toolUseId: item.id || null,
      toolName: 'command_execution',
      text: output.text,
      exitCode,
      status,
      isError: exitCode !== null ? exitCode !== 0 : ['failed', 'error'].includes(status),
      truncated: output.truncated,
      raw
    };
  }
  if (raw.type === 'item.completed' && item?.type === 'agent_message') {
    return {
      type: conversationEventTypes.ASSISTANT_MESSAGE,
      text: stripAnsi(item.text || ''),
      turnFinal: false,
      raw
    };
  }
  return {
    type: conversationEventTypes.SYSTEM_NOTICE,
    text: `Codex event: ${raw.type || 'unknown'}`,
    noticeKind: 'codex_unknown_event',
    visible: false,
    raw
  };
}

function mapCodexMcpToolCallEvent(raw, item, options = {}) {
  const maxAggregatedOutputBytes = options.maxAggregatedOutputBytes || DEFAULT_MAX_AGGREGATED_OUTPUT_BYTES;
  const server = String(item.server || 'mcp').trim() || 'mcp';
  const tool = String(item.tool || item.name || 'tool').trim() || 'tool';
  const toolName = `${server}.${tool}`;
  const summary = formatCodexMcpToolSummary(server, tool, item.arguments);
  if (raw.type === 'item.started') {
    return {
      type: conversationEventTypes.TOOL_STARTED,
      toolUseId: item.id || null,
      toolName,
      input: codexMcpToolInput(server, tool, item.arguments),
      summary,
      raw
    };
  }

  const errorText = codexMcpToolErrorText(item.error);
  const resultText = errorText || codexMcpToolResultText(item.result);
  const output = truncateText(resultText || 'MCP tool call completed.', maxAggregatedOutputBytes);
  const status = item.status || null;
  return {
    type: conversationEventTypes.TOOL_COMPLETED,
    toolUseId: item.id || null,
    toolName,
    text: output.text,
    status,
    isError: Boolean(errorText) || ['failed', 'error'].includes(String(status || '').toLowerCase()),
    truncated: output.truncated,
    raw
  };
}

function codexMcpToolInput(server, tool, args) {
  const input = { server, tool };
  if (args && typeof args === 'object') input.arguments = args;
  return input;
}

function formatCodexMcpToolSummary(server, tool, args) {
  const argsText = args && typeof args === 'object' ? safeJsonStringify(args) : '';
  return argsText ? `${server}.${tool} ${argsText}` : `${server}.${tool}`;
}

function codexMcpToolErrorText(error) {
  if (!error) return '';
  if (typeof error === 'string') return error;
  if (typeof error === 'object') {
    return error.message || error.text || safeJsonStringify(error);
  }
  return String(error);
}

function codexMcpToolResultText(result) {
  if (result == null) return '';
  if (typeof result === 'string') return stripAnsi(result);
  if (Array.isArray(result.content)) {
    return result.content
      .map(codexMcpContentPartText)
      .filter((text) => text.trim())
      .join('\n');
  }
  const structured = result.structured_content || result.structuredContent;
  if (structured != null) return safeJsonStringify(structured);
  return safeJsonStringify(result);
}

function codexMcpContentPartText(part) {
  if (part == null) return '';
  if (typeof part === 'string') return stripAnsi(part);
  if (typeof part === 'object') {
    if (typeof part.text === 'string') return stripAnsi(part.text);
    if (typeof part.content === 'string') return stripAnsi(part.content);
    return safeJsonStringify(part);
  }
  return String(part);
}

function safeJsonStringify(value) {
  try {
    return JSON.stringify(value);
  } catch (_) {
    return String(value);
  }
}

function mapCodexFileChangeEvent(raw, item, options = {}) {
  const changes = normalizeCodexFileChanges(
    item.changes,
    options.workspacePath,
    {
      ...options,
      includeFileChangeDiff:
        raw.type === 'item.completed' && options.includeFileChangeDiff === true
    }
  );
  if (changes.length === 0) return null;
  if (raw.type !== 'item.completed') {
    return {
      type: conversationEventTypes.SYSTEM_NOTICE,
      text: 'Codex file change started',
      noticeKind: 'codex_file_change_started',
      visible: false,
      changes,
      raw
    };
  }
  return {
    type: conversationEventTypes.SYSTEM_NOTICE,
    text: formatCodexFileChangeText(changes),
    noticeKind: 'codex_file_change',
    visible: true,
    changes,
    raw
  };
}

function normalizeCodexFileChanges(changes, workspacePath, options = {}) {
  if (!Array.isArray(changes)) return [];
  const normalized = [];
  for (const change of changes) {
    if (!change || typeof change !== 'object') continue;
    const rawPath = typeof change.path === 'string' ? change.path.trim() : '';
    if (!rawPath) continue;
    const normalizedChange = {
      path: relativeCodexFilePath(rawPath, workspacePath),
      kind: typeof change.kind === 'string' && change.kind.trim()
        ? change.kind.trim()
        : 'change'
    };
    const diff = codexFileChangeDiff(change, rawPath, workspacePath, options);
    if (diff) normalizedChange.diff = diff;
    normalized.push(normalizedChange);
  }
  return normalized;
}

function codexFileChangeDiff(change, rawPath, workspacePath, options = {}) {
  const maxBytes = Number.isInteger(options.maxFileChangeDiffBytes) && options.maxFileChangeDiffBytes > 0
    ? options.maxFileChangeDiffBytes
    : DEFAULT_MAX_FILE_CHANGE_DIFF_BYTES;
  if (typeof change.diff === 'string' && change.diff.trim()) {
    return truncateText(stripAnsi(change.diff), maxBytes).text;
  }
  if (options.includeFileChangeDiff !== true) return '';
  const gitDiff = workspaceGitDiffForFile(rawPath, workspacePath, maxBytes);
  if (gitDiff) return gitDiff;
  if (['add', 'added'].includes(String(change.kind || '').toLowerCase())) {
    return addedFilePreview(rawPath, workspacePath, maxBytes);
  }
  return '';
}

function workspaceGitDiffForFile(rawPath, workspacePath, maxBytes) {
  const resolved = resolveWorkspaceFilePath(rawPath, workspacePath);
  if (!resolved) return '';
  const relativePath = path.relative(path.resolve(workspacePath), resolved);
  if (!relativePath || relativePath.startsWith('..') || path.isAbsolute(relativePath)) return '';
  const result = spawnSync('git', ['diff', '--no-ext-diff', '--unified=20', '--', relativePath], {
    cwd: workspacePath,
    encoding: 'utf8',
    timeout: 2000,
    windowsHide: true,
    maxBuffer: maxBytes * 2
  });
  if (result.error || result.status === null) return '';
  return truncateText(stripAnsi(result.stdout || ''), maxBytes).text.trim();
}

function addedFilePreview(rawPath, workspacePath, maxBytes) {
  const resolved = resolveWorkspaceFilePath(rawPath, workspacePath);
  if (!resolved) return '';
  try {
    const stat = fs.statSync(resolved);
    if (!stat.isFile() || stat.size > maxBytes) return '';
    const content = fs.readFileSync(resolved, 'utf8');
    const lines = content.replace(/\r\n/g, '\n').replace(/\r/g, '\n').split('\n');
    const preview = lines
      .slice(0, 80)
      .map((line) => `+${line}`)
      .join('\n');
    return preview ? `@@ new file preview @@\n${preview}` : '';
  } catch (_) {
    return '';
  }
}

function resolveWorkspaceFilePath(rawPath, workspacePath) {
  if (!workspacePath || !String(workspacePath).trim()) return null;
  const workspaceRoot = path.resolve(workspacePath);
  const candidate = path.isAbsolute(rawPath)
    ? path.resolve(rawPath)
    : path.resolve(workspaceRoot, rawPath);
  const comparableRoot =
    process.platform === 'win32' ? workspaceRoot.toLowerCase() : workspaceRoot;
  const comparableCandidate =
    process.platform === 'win32' ? candidate.toLowerCase() : candidate;
  if (
    comparableCandidate === comparableRoot ||
    comparableCandidate.startsWith(`${comparableRoot}${path.sep}`)
  ) {
    return candidate;
  }
  return null;
}

function relativeCodexFilePath(filePath, workspacePath) {
  const normalizedPath = String(filePath || '').replace(/\\/g, '/');
  const normalizedWorkspace = String(workspacePath || '').replace(/\\/g, '/').replace(/\/+$/, '');
  if (normalizedWorkspace && normalizedPath.toLowerCase().startsWith(`${normalizedWorkspace.toLowerCase()}/`)) {
    return normalizedPath.slice(normalizedWorkspace.length + 1);
  }
  return normalizedPath;
}

function formatCodexFileChangeText(changes) {
  const parts = changes.map((change) => `${codexFileChangeKindLabel(change.kind)} ${change.path}`);
  if (parts.length === 1) return `File changed: ${parts[0]}`;
  const visibleParts = parts.slice(0, 3);
  const remaining = parts.length - visibleParts.length;
  return `Files changed: ${visibleParts.join('; ')}${remaining > 0 ? `; and ${remaining} more` : ''}`;
}

function codexFileChangeKindLabel(kind) {
  switch (String(kind || '').toLowerCase()) {
    case 'add':
    case 'added':
      return 'added';
    case 'delete':
    case 'deleted':
    case 'remove':
    case 'removed':
      return 'deleted';
    case 'update':
    case 'updated':
    case 'modify':
    case 'modified':
      return 'updated';
    default:
      return 'changed';
  }
}

function mapCodexTodoListEvent(raw, item) {
  const sourceItems = Array.isArray(item.items) ? item.items : item.todos;
  if (!Array.isArray(sourceItems) || sourceItems.length === 0) return null;

  const progressItems = [];
  for (const sourceItem of sourceItems) {
    if (!sourceItem || typeof sourceItem !== 'object') return null;
    const title = String(sourceItem.text || sourceItem.content || '').trim();
    if (!title) return null;
    progressItems.push({
      title,
      status: normalizeCodexTodoStatus(raw.type, sourceItem)
    });
  }

  const completedCount = progressItems.filter((progressItem) => progressItem.status === 'completed').length;
  return {
    type: conversationEventTypes.TASK_PROGRESS_UPDATED,
    taskId: item.id || null,
    source: 'codex',
    updatedAt: new Date().toISOString(),
    items: progressItems,
    completedCount,
    totalCount: progressItems.length,
    raw
  };
}

function normalizeCodexTodoStatus(rawType, item) {
  if (rawType === 'item.completed') return 'completed';
  if (item.completed === true) return 'completed';
  if (item.status === 'completed') return 'completed';
  if (item.status === 'in_progress') return 'in_progress';
  return 'pending';
}

function createJsonLineParser({ maxJsonLineBytes, onJson }) {
  let buffer = '';
  return (chunk) => {
    buffer += chunk.toString();
    const lines = buffer.split(/\r?\n/);
    buffer = lines.pop() || '';
    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed) continue;
      if (Buffer.byteLength(trimmed, 'utf8') > maxJsonLineBytes) {
        onJson({ type: 'error', message: 'Codex JSONL event exceeded maxJsonLineBytes' });
        continue;
      }
      try {
        onJson(JSON.parse(trimmed));
      } catch (_err) {
        onJson({ type: 'error', message: 'Codex emitted invalid JSONL', rawLine: truncateText(trimmed, 4096).text });
      }
    }
  };
}

function truncateText(text, maxBytes) {
  const value = String(text || '');
  if (Buffer.byteLength(value, 'utf8') <= maxBytes) return { text: value, truncated: false };
  let bytes = 0;
  let output = '';
  for (const char of value) {
    const next = Buffer.byteLength(char, 'utf8');
    if (bytes + next > maxBytes) break;
    bytes += next;
    output += char;
  }
  return { text: output, truncated: true };
}

function stripAnsi(value) {
  return String(value || '').replace(/\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])/g, '');
}

function resultText(result = {}) {
  return `${result.stdout || ''}${result.stderr || ''}${result.error?.message || ''}`;
}

function closeChildInput(child) {
  const stdin = child?.stdin;
  if (!stdin || stdin.destroyed || stdin.writableEnded || stdin.writableFinished) return;
  if (typeof stdin.end === 'function') stdin.end();
}

function unavailableCapability(command, error) {
  return {
    adapter: 'codex',
    available: false,
    status: 'unavailable',
    command,
    error,
    actionable: error,
    capabilities: {
      approvalPolicy: 'cli-policy',
      mobileApprovalCallbacks: false,
      approval: {
        mobileCallbacks: false,
        scopes: [],
        supportsCancel: false,
        denyBehaviors: []
      },
      attachments: {
        image: 'unsupported',
        textDocument: 'text_extract',
        pdf: 'unsupported'
      }
    }
  };
}

function defaultKillProcessTree(child) {
  if (!child) return Promise.resolve();
  if (process.platform === 'win32' && child.pid) {
    return new Promise((resolve) => {
      const killer = spawn('taskkill', ['/PID', String(child.pid), '/T', '/F'], { windowsHide: true });
      killer.on('exit', () => resolve());
      killer.on('error', () => {
        if (typeof child.kill === 'function') child.kill('SIGTERM');
        resolve();
      });
    });
  }
  if (typeof child.kill === 'function') child.kill('SIGTERM');
  return Promise.resolve();
}

function processEnvForWorkspace(sourceEnv, workspacePath) {
  const env = { ...sourceEnv };
  if (workspacePath) env.PWD = workspacePath;
  return env;
}

module.exports = {
  CodexConversationAdapter,
  CodexConversationHandle,
  buildAdapterUserMessage,
  buildCodexExecArgs,
  buildCodexResumeArgs,
  mapCodexEvent,
  truncateText
};

