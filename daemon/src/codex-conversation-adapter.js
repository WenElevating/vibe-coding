'use strict';

const { spawn, spawnSync } = require('node:child_process');
const { conversationEventTypes } = require('./conversation-protocol');
const { resolveCliInvocation } = require('./cli-resolver');
const { discoverConfiguredModels } = require('./model-discovery');
const { textAttachmentWrapper } = require('./attachment-validation');

const DEFAULT_MAX_JSON_LINE_BYTES = 1024 * 1024;
const DEFAULT_MAX_AGGREGATED_OUTPUT_BYTES = 64 * 1024;
const CODEX_DETECTION_TIMEOUT_MS = 30000;

class CodexConversationAdapter {
  constructor({
    command = 'codex',
    spawnFn = spawn,
    spawnSyncFn = spawnSync,
    cliResolverOptions = {},
    killProcessTreeFn = defaultKillProcessTree,
    maxJsonLineBytes = DEFAULT_MAX_JSON_LINE_BYTES,
    maxAggregatedOutputBytes = DEFAULT_MAX_AGGREGATED_OUTPUT_BYTES
  } = {}) {
    this.name = 'codex';
    this.command = command;
    this.spawnFn = spawnFn;
    this.spawnSyncFn = spawnSyncFn;
    this.killProcessTreeFn = killProcessTreeFn;
    this.maxJsonLineBytes = maxJsonLineBytes;
    this.maxAggregatedOutputBytes = maxAggregatedOutputBytes;
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
      ? buildCodexResumeArgs({ prompt: userMessage.prompt, imagePaths: userMessage.imagePaths, sessionId: this.sessionId, permissionMode: this.permissionMode, workspacePath: this.workspacePath, resumeSupportsCd, model })
      : buildCodexExecArgs({ prompt: userMessage.prompt, imagePaths: userMessage.imagePaths, workspacePath: this.workspacePath, permissionMode: this.permissionMode, model });
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
    const event = mapCodexEvent(raw, { maxAggregatedOutputBytes: this.adapter.maxAggregatedOutputBytes });
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

function buildCodexExecArgs({ prompt, workspacePath, permissionMode = 'default', model, imagePaths = [] }) {
  return [
    '--ask-for-approval', approvalPolicy(permissionMode),
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

function buildCodexResumeArgs({ prompt, sessionId, permissionMode = 'default', workspacePath, resumeSupportsCd = false, model, imagePaths = [] }) {
  return [
    '--ask-for-approval', approvalPolicy(permissionMode),
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
    return {
      type: conversationEventTypes.TOOL_OUTPUT,
      toolUseId: item.id || null,
      toolName: 'command_execution',
      text: output.text,
      exitCode: Number.isInteger(item.exit_code) ? item.exit_code : null,
      status: item.status || null,
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

