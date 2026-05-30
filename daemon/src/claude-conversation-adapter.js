'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { spawn, spawnSync } = require('node:child_process');
const { conversationEventTypes } = require('./conversation-protocol');
const { detectClaudeCodeInstallation, unavailableCapability } = require('./claude-adapter');
const { resolveCliInvocation } = require('./cli-resolver');
const { discoverConfiguredModels } = require('./model-discovery');
const { textAttachmentWrapper } = require('./attachment-validation');
const packageJson = require('../../package.json');

const CLAUDE_MAX_IMAGE_BYTES = 5 * 1024 * 1024;
const DEFAULT_MAX_FILE_CHANGE_DIFF_BYTES = 32 * 1024;

class ClaudeConversationAdapter {
  constructor({ command = 'claude', spawnFn = spawn, spawnSyncFn = spawnSync, cliResolverOptions = {}, readTextFile } = {}) {
    this.name = 'claude';
    this.command = command;
    this.spawnFn = spawnFn;
    this.spawnSyncFn = spawnSyncFn;
    this.readTextFile = readTextFile;
    this.invocation = resolveCliInvocation(command, { spawnSyncFn, ...cliResolverOptions });
    this.capability = null;
    this.modelCapability = defaultModelCapability();
    this.capabilities = {
      longLivedProcess: true,
      waitingInput: true,
      waitingApproval: true,
      resume: true,
      partialOutput: true,
      attachments: {
        image: 'native',
        textDocument: 'text_extract',
        pdf: 'unsupported'
      }
    };
  }

  detectCapabilities() {
    const detection = detectClaudeCodeInstallation({
      command: this.command,
      invocation: this.invocation,
      spawnSyncFn: this.spawnSyncFn,
      ...(this.readTextFile ? { readTextFile: this.readTextFile } : {})
    });
    if (!detection.installed) {
      this.capability = unavailableCapability(this.command, detection.error || 'Claude Code CLI was not found');
      return this.capability;
    }
    this.modelCapability = {
      ...discoverConfiguredModels({ adapter: 'claude' }),
      canSelectModel: Boolean(detection.supportsModelFlag)
    };
    this.capability = {
      adapter: 'claude',
      version: detection.version,
      available: true,
      command: this.command,
      path: detection.path,
      detectionMethod: detection.method,
      ...this.modelCapability,
      capabilities: {
        ...this.capabilities,
        supportsModelFlag: Boolean(detection.supportsModelFlag)
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
        image: 'native',
        textDocument: 'text_extract',
        pdf: 'unsupported'
      }
    };
  }

  ensureAvailable() {
    const capability = this.capability || this.detectCapabilities();
    if (!capability.available) {
      const error = new Error(capability.error || 'Claude conversation adapter unavailable');
      error.status = 503;
      error.code = 'CLAUDE_CONVERSATION_UNAVAILABLE';
      error.details = capability;
      throw error;
    }
  }

  async startConversation({ conversationId, workspacePath, permissionMode = 'default', sessionId, model, requestedToolPolicy, claudeOptions, onEvent }) {
    if (!workspacePath || !String(workspacePath).trim()) throw new Error('workspacePath is required');
    this.ensureAvailable();
    const selectedModel = this.modelCapability?.canSelectModel === true ? model : null;
    const explicitAllowedTools = Array.isArray(claudeOptions?.allowedTools) || Array.isArray(requestedToolPolicy?.allowedTools);
    const args = [
      '--output-format', 'stream-json',
      '--verbose',
      '--print',
      ...buildClaudeOptionArgs({ requestedToolPolicy, claudeOptions }),
      '--include-partial-messages',
      ...(sessionId ? ['--resume', sessionId] : []),
      ...(selectedModel ? ['--model', selectedModel] : []),
      '--permission-prompt-tool', 'stdio',
      '--permission-mode', permissionMode === 'default' ? 'default' : 'auto',
      ...(permissionMode === 'auto' && !explicitAllowedTools ? ['--allowedTools', allowedTools()] : []),
      '--input-format', 'stream-json'
    ];
    const child = this.spawnFn(this.invocation.command, [...this.invocation.argsPrefix, ...args], {
      cwd: workspacePath,
      windowsHide: true,
      env: sdkProcessEnvForWorkspace(process.env, workspacePath)
    });
    const initRequestId = `init_${Date.now().toString(16)}`;
    const state = {
      child,
      onEvent,
      pendingQuestions: new Map(),
      pendingApprovals: new Map(),
      pendingTools: new Map(),
      claudeTasks: new Map(),
      claudeTaskToolIds: new Map(),
      claudeTaskProgressSnapshot: '',
      contentBlocks: new Map(),
      visibleApiRetryWarnings: new Set(),
      reportedPlanApprovalToolUseIds: new Set(),
      reportedPermissionDenialToolUseIds: new Set(),
      now: () => new Date(),
      workspacePath,
      spawnSyncFn: this.spawnSyncFn,
      initRequestId,
      initialized: false,
      initWaiters: [],
      controlCounter: 0,
      pendingControlResponses: new Map()
    };
    child.stdout.on('data', createJsonLineParser((raw) => handleRawClaudeEvent(raw, state)));
    child.stderr.on('data', (chunk) => {
      const text = chunk.toString().trim();
      if (text) onEvent({ type: conversationEventTypes.PROTOCOL_WARNING, text, visible: false });
    });
    child.on('error', (error) => onEvent({ type: conversationEventTypes.RUN_ERROR, error: error.message }));
    child.on('exit', (code, signal) => {
      if (signal) onEvent({ type: conversationEventTypes.CONVERSATION_CANCELLED, signal });
      else if (code === 0) onEvent({ type: conversationEventTypes.CONVERSATION_COMPLETED });
      else if (code !== 0) onEvent({ type: conversationEventTypes.RUN_ERROR, exitCode: code });
    });
    await writeJsonLine(child, {
      type: 'control_request',
      request_id: initRequestId,
      request: { subtype: 'initialize', hooks: null }
    });
    const fallback = setTimeout(() => completeInitialize(state, { timedOut: true }), claudeInitializeTimeoutMs(process.env));
    if (typeof fallback?.unref === 'function') fallback.unref();
    state.initFallback = fallback;
    return new ClaudeConversationHandle({ conversationId, state });
  }
}

function defaultModelCapability() {
  return { models: [], selectedModel: null, canSelectModel: false };
}

function claudeInitializeTimeoutMs(env = process.env) {
  const parsed = Number.parseInt(env.CLAUDE_CODE_STREAM_CLOSE_TIMEOUT || '', 10);
  if (!Number.isFinite(parsed) || parsed <= 0) return 60000;
  return Math.max(parsed, 60000);
}

class ClaudeConversationHandle {
  constructor({ conversationId, state }) {
    this.conversationId = conversationId;
    this.state = state;
  }

  async sendUserMessage(text) {
    await waitForInitialize(this.state);
    await writeUserMessage(this.state.child, text);
  }

  async answerQuestion(questionId, text) {
    await waitForInitialize(this.state);
    const pending = this.state.pendingQuestions.get(questionId);
    if (pending?.toolUseId && !pending.requestId) {
      await writeToolResultMessage(this.state.child, pending.toolUseId, text);
      this.state.pendingQuestions.delete(questionId);
      return;
    }
    await writeUserMessage(this.state.child, text);
    if (pending) {
      if (pending.requestId) {
        await writeControlResponse(this.state.child, pending.requestId, {
          subtype: 'success',
          response: { behavior: 'allow', updatedInput: pending.input || {} }
        });
      }
      this.state.pendingQuestions.delete(questionId);
    }
  }

  async respondApproval(approvalId, decision) {
    await waitForInitialize(this.state);
    const pending = this.state.pendingApprovals.get(approvalId);
    const input = pending?.input || {};
    const approval = typeof decision === 'string' ? { decision } : (decision || {});
    const response = approval.decision === 'allow'
      ? {
          behavior: 'allow',
          updatedInput: approval.updatedInput || input,
          ...(Array.isArray(approval.updatedPermissions) ? { updatedPermissions: approval.updatedPermissions } : {})
        }
      : {
          behavior: 'deny',
          message: 'User denied permission from mobile client.',
          interrupt: Object.prototype.hasOwnProperty.call(approval, 'interrupt') ? approval.interrupt === true : true
        };
    await writeControlResponse(this.state.child, approvalId, { subtype: 'success', response });
    this.state.pendingApprovals.delete(approvalId);
  }

  async cancel() {
    const child = this.state.child;
    if (!child) return;
    try {
      if (isWritableStdin(child.stdin) && typeof child.stdin.end === 'function') child.stdin.end();
    } catch (_err) {}
    if (typeof child.kill !== 'function') return;
    const exited = await waitForChildExit(child, 1000);
    if (!exited) child.kill('SIGTERM');
    const terminated = await waitForChildExit(child, 1000);
    if (!terminated) child.kill('SIGKILL');
  }

  async dispose() {
    await this.cancel();
  }

  async interrupt() {
    await sendControlRequest(this.state, { subtype: 'interrupt' });
  }

  async setPermissionMode(mode) {
    await sendControlRequest(this.state, { subtype: 'set_permission_mode', mode });
  }

  async setModel(model) {
    await sendControlRequest(this.state, { subtype: 'set_model', model });
  }

  async getContextUsage() {
    return sendControlRequest(this.state, { subtype: 'get_context_usage' });
  }

  async getMcpStatus() {
    return sendControlRequest(this.state, { subtype: 'mcp_status' });
  }

  async reconnectMcpServer(name) {
    await sendControlRequest(this.state, { subtype: 'mcp_reconnect', serverName: name });
  }

  async toggleMcpServer(name, enabled) {
    await sendControlRequest(this.state, { subtype: 'mcp_toggle', serverName: name, enabled });
  }

  async stopTask(taskId) {
    await sendControlRequest(this.state, { subtype: 'stop_task', task_id: taskId });
  }
}

function handleRawClaudeEvent(raw, state) {
  const event = unwrapClaudeEvent(raw);
  const rawType = typeof event.type === 'string' ? event.type : 'raw';
  if (rawType === 'control_response') {
    const requestId = event.response?.request_id || event.request_id;
    if (handlePendingControlResponse(state, requestId, event.response || event)) return;
    if (requestId === state.initRequestId || !state.initialized) completeInitialize(state);
    return;
  }
  if (!state.initialized) completeInitialize(state);
  if (rawType === 'control_cancel_request') {
    handleControlCancelRequest(event, state);
    return;
  }
  if (rawType === 'control_request') {
    handleControlRequest(event, state);
    return;
  }
  if (rawType === 'tool_use') return handleToolUse(event, state, raw);
  if (rawType === 'tool_use_delta') return handleToolDelta(event, state, raw);
  if (rawType === 'tool_result') return handleToolResult(event, state, raw);
  if (rawType === 'content_block_start') return handleContentBlockStart(event, state, raw);
  if (rawType === 'content_block_delta') return handleContentBlockDelta(event, state, raw);
  if (rawType === 'content_block_stop') return handleContentBlockStop(event, state, raw);
  const sessionId = event.session_id || event.sessionId;
  if (rawType === 'result') {
    handlePermissionDenials(event, state);
    const text = extractText(event);
    if (text) state.onEvent({ type: conversationEventTypes.ASSISTANT_MESSAGE, text, sessionId, raw: event });
    else state.onEvent({ type: conversationEventTypes.CONVERSATION_COMPLETED, sessionId, raw: event });
    return;
  }
  if (rawType === 'assistant' || event.message?.role === 'assistant') {
    handleAssistantToolEvents(event, state, raw);
    const parts = extractAssistantParts(event);
    for (const part of parts) {
      if (part.type === conversationEventTypes.ASSISTANT_QUESTION) {
        state.pendingQuestions.set(part.questionId, { input: part.input || {}, toolUseId: part.toolUseId || null });
        state.onEvent({ ...part, sessionId, raw: event });
      } else {
        state.onEvent({ type: part.type, text: part.text, sessionId, raw: event });
      }
    }
    return;
  }
  if (rawType === 'user' || event.message?.role === 'user') {
    handleUserToolResults(event, state, raw);
    return;
  }
  if (rawType === 'system' && event.subtype === 'api_retry') {
    const text = formatClaudeApiRetryText(event);
    const warningKey = `${event.error_status || ''}:${event.error || 'error'}`;
    const visible = isClaudeAuthenticationRetry(event) && !state.visibleApiRetryWarnings.has(warningKey);
    if (visible) state.visibleApiRetryWarnings.add(warningKey);
    state.onEvent({ type: conversationEventTypes.PROTOCOL_WARNING, text, visible, sessionId, raw: event });
    return;
  }
  const text = extractText(event);
  if (text.trim()) {
    state.onEvent({ type: conversationEventTypes.PROTOCOL_WARNING, text, sessionId, raw: event });
  }
}

function isClaudeAuthenticationRetry(event) {
  const status = Number(event.error_status);
  const error = String(event.error || '').toLowerCase();
  return status === 401 || error.includes('auth');
}

function formatClaudeApiRetryText(event) {
  const status = event.error_status || '';
  const error = event.error || 'error';
  const attempt = Number(event.attempt);
  const maxRetries = Number(event.max_retries);
  const retryText = Number.isFinite(attempt) && Number.isFinite(maxRetries) && attempt > 0 && maxRetries > 0
    ? ` (retry ${attempt}/${maxRetries})`
    : '';
  return `Claude API ${status} ${error}${retryText}`.replace(/\s+/g, ' ').trim();
}

function completeInitialize(state, details = {}) {
  if (state.initialized) return;
  state.initialized = true;
  if (state.initFallback) clearTimeout(state.initFallback);
  if (details.timedOut) {
    state.onEvent({
      type: conversationEventTypes.PROTOCOL_WARNING,
      text: 'Claude initialize handshake timed out; continuing with prompt send fallback.',
      visible: false
    });
  }
  const waiters = state.initWaiters.splice(0);
  for (const resolve of waiters) resolve();
}

function waitForInitialize(state) {
  if (state.initialized) return Promise.resolve();
  return new Promise((resolve) => state.initWaiters.push(resolve));
}

function unwrapClaudeEvent(raw) {
  if (raw && raw.type === 'stream_event' && raw.event && typeof raw.event === 'object') {
    return {
      ...raw.event,
      session_id: raw.event.session_id || raw.session_id,
      sessionId: raw.event.sessionId || raw.sessionId
    };
  }
  return raw;
}

function handleToolUse(raw, state, originalRaw = raw) {
  const toolUseId = raw.id || raw.tool_use_id;
  if (!toolUseId) return;
  const previous = state.pendingTools.get(toolUseId) || {};
  const input = raw.input && typeof raw.input === 'object' ? raw.input : previous.input || {};
  const toolName = raw.name || raw.tool_name || previous.name || 'tool';
  if (isAskUserQuestionToolName(toolName)) {
    emitAskUserQuestion(state, {
      questionId: toolUseId,
      input,
      toolUseId,
      raw: originalRaw
    });
    return;
  }
  const tool = {
    toolUseId,
    name: toolName,
    input,
    startedAt: previous.startedAt || state.now().toISOString()
  };
  state.pendingTools.set(toolUseId, tool);
  if (isClaudeTaskToolName(tool.name)) {
    handleClaudeTaskToolUse(state, {
      toolName: tool.name,
      toolUseId,
      input: tool.input,
      raw: originalRaw
    });
    return;
  }
  state.onEvent({
    type: conversationEventTypes.TOOL_STARTED,
    toolUseId,
    toolName: tool.name,
    input: tool.input,
    summary: summarizeToolInput(tool.name, tool.input),
    raw: originalRaw
  });
}

function handleContentBlockStart(raw, state, originalRaw = raw) {
  const block = raw.content_block || {};
  if (block.type === 'tool_use') {
    const index = raw.index;
    if (index !== undefined && index !== null) {
      state.contentBlocks.set(index, {
        kind: 'tool_use',
        toolUseId: block.id,
        name: block.name,
        input: block.input && typeof block.input === 'object' ? block.input : {},
        inputJson: ''
      });
    }
    if (block.input && Object.keys(block.input).length > 0) {
      handleToolUse({ id: block.id, name: block.name, input: block.input }, state, originalRaw);
    }
    return;
  }
  if (block.type === 'tool_result') {
    const index = raw.index;
    if (index !== undefined && index !== null) {
      state.contentBlocks.set(index, {
        kind: 'tool_result',
        toolUseId: block.tool_use_id || block.id,
        content: block.content || '',
        isError: block.is_error === true
      });
    }
  }
}

function handleContentBlockDelta(raw, state, originalRaw = raw) {
  const block = state.contentBlocks.get(raw.index);
  const delta = raw.delta || {};
  if (!block) return;
  if (block.kind === 'tool_use' && delta.type === 'input_json_delta') {
    block.inputJson = `${block.inputJson || ''}${delta.partial_json || ''}`;
    state.contentBlocks.set(raw.index, block);
    return;
  }
  if (block.kind === 'tool_result') {
    const text = delta.text || delta.content || delta.partial_json || '';
    if (text) {
      block.content = `${block.content || ''}${text}`;
      state.contentBlocks.set(raw.index, block);
    }
  }
}

function handleContentBlockStop(raw, state, originalRaw = raw) {
  const block = state.contentBlocks.get(raw.index);
  if (!block) return;
  state.contentBlocks.delete(raw.index);
  if (block.kind === 'tool_use') {
    const parsedInput = parsePartialJsonObject(block.inputJson);
    const input = parsedInput || block.input || {};
    handleToolUse({ id: block.toolUseId, name: block.name, input }, state, originalRaw);
    return;
  }
  if (block.kind === 'tool_result') {
    handleToolResult({
      tool_use_id: block.toolUseId,
      content: block.content || '',
      is_error: block.isError === true
    }, state, originalRaw);
  }
}

function handleAssistantToolEvents(raw, state, originalRaw = raw) {
  const content = raw.message?.content || raw.content;
  if (!Array.isArray(content)) return;
  for (const part of content) {
    if (!part || typeof part !== 'object') continue;
    if (part.type === 'tool_use' && part.name !== 'AskUserQuestion') {
      if (!state.pendingTools.has(part.id)) handleToolUse(part, state, originalRaw);
      continue;
    }
    if (part.type === 'tool_result') {
      handleToolResult(part, state, originalRaw);
    }
  }
}

function handleUserToolResults(raw, state, originalRaw = raw) {
  const content = raw.message?.content || raw.content;
  if (!Array.isArray(content)) return;
  for (const part of content) {
    if (!part || typeof part !== 'object') continue;
    if (part.type === 'tool_result') handleToolResult(part, state, originalRaw);
  }
}

function handleToolDelta(raw, state, originalRaw = raw) {
  const toolUseId = raw.tool_use_id || raw.id;
  if (!toolUseId) return;
  const text = extractToolText(raw);
  if (!text) return;
  state.onEvent({ type: conversationEventTypes.TOOL_DELTA, toolUseId, text, raw: originalRaw });
}

function handleToolResult(raw, state, originalRaw = raw) {
  const toolUseId = raw.tool_use_id || raw.id;
  if (!toolUseId) return;
  const pending = state.pendingTools.get(toolUseId) || null;
  const text = extractToolText(raw);
  const exitCode = Number.isInteger(raw.exit_code) ? raw.exit_code : null;
  const isError = raw.is_error === true;
  const permissionError = isPermissionErrorText(text);
  const toolName = pending?.name || raw.name || raw.tool_name || null;
  const input = pending?.input || {};
  if (isAskUserQuestionToolName(toolName) || state.pendingQuestions.has(toolUseId)) {
    state.pendingTools.delete(toolUseId);
    return;
  }
  if (isClaudeTaskToolName(toolName)) {
    handleClaudeTaskToolResult(state, {
      toolName,
      toolUseId,
      input,
      text,
      raw,
      originalRaw
    });
    state.pendingTools.delete(toolUseId);
    return;
  }
  if (isExitPlanModePrompt(toolName, text)) {
    emitExitPlanModeQuestion(state, {
      toolUseId,
      input,
      raw: originalRaw
    });
  }
  if (permissionError) {
    state.onEvent({
      type: conversationEventTypes.SYSTEM_NOTICE,
      text: permissionNoticeText(toolName, input),
      noticeKind: 'permission_unavailable',
      toolUseId,
      toolName,
      input,
      raw: originalRaw
    });
  }
  state.onEvent({
    type: conversationEventTypes.TOOL_OUTPUT,
    toolUseId,
    toolName,
    input,
    text,
    exitCode,
    isError,
    permissionError,
    raw: originalRaw
  });
  state.onEvent({
    type: conversationEventTypes.TOOL_COMPLETED,
    toolUseId,
    toolName,
    input,
    exitCode,
    isError,
    permissionError,
    durationMs: pending ? Math.max(0, state.now().getTime() - Date.parse(pending.startedAt)) : null,
    raw: originalRaw
  });
  const fileChangeNotice = claudeFileChangeNoticeForTool(state, {
    toolName,
    input,
    isError,
    permissionError,
    exitCode,
    raw: originalRaw
  });
  if (fileChangeNotice) state.onEvent(fileChangeNotice);
  state.pendingTools.delete(toolUseId);
}

function claudeFileChangeNoticeForTool(state, { toolName, input, isError, permissionError, exitCode, raw }) {
  if (isError || permissionError) return null;
  if (exitCode !== null && exitCode !== 0) return null;
  const normalizedToolName = String(toolName || '').toLowerCase();
  if (!['write', 'edit', 'multiedit'].includes(normalizedToolName)) return null;
  const filePath = claudeFileChangeInputPath(input);
  if (!filePath) return null;
  const change = normalizeClaudeFileChange({
    filePath,
    toolName: normalizedToolName,
    input,
    workspacePath: state.workspacePath,
    spawnSyncFn: state.spawnSyncFn
  });
  if (!change) return null;
  return {
    type: conversationEventTypes.SYSTEM_NOTICE,
    text: formatClaudeFileChangeText([change]),
    noticeKind: 'codex_file_change',
    visible: true,
    changes: [change],
    raw
  };
}

function claudeFileChangeInputPath(input) {
  if (!input || typeof input !== 'object') return '';
  for (const key of ['file_path', 'filePath', 'path']) {
    const value = input[key];
    if (typeof value === 'string' && value.trim()) return value.trim();
  }
  for (const key of ['tool_input', 'toolInput', 'input', 'arguments', 'args']) {
    const nested = claudeFileChangeInputPath(input[key]);
    if (nested) return nested;
  }
  return '';
}

function normalizeClaudeFileChange({ filePath, toolName, input, workspacePath, spawnSyncFn }) {
  const resolved = resolveWorkspaceFilePath(filePath, workspacePath);
  if (!resolved) return null;
  const relativePath = relativeWorkspacePath(resolved, workspacePath);
  if (!relativePath) return null;
  const maxBytes = DEFAULT_MAX_FILE_CHANGE_DIFF_BYTES;
  const gitDiff = workspaceGitDiffForFile(relativePath, workspacePath, spawnSyncFn, maxBytes);
  const inputPreview = gitDiff ? '' : claudeFileChangeInputPreview(toolName, input, maxBytes);
  const filePreview = gitDiff || inputPreview
    ? ''
    : (toolName === 'write' ? addedFilePreview(resolved, maxBytes) : currentFilePreview(resolved, maxBytes));
  const preview = gitDiff || inputPreview || filePreview;
  const kind = claudeFileChangeKind(toolName, preview);
  const change = { path: relativePath.replace(/\\/g, '/'), kind };
  if (preview) change.diff = preview;
  return change;
}

function workspaceGitDiffForFile(relativePath, workspacePath, spawnSyncFn, maxBytes) {
  if (!workspacePath || typeof spawnSyncFn !== 'function') return '';
  const result = spawnSyncFn('git', ['diff', '--no-ext-diff', '--unified=20', '--', relativePath], {
    cwd: workspacePath,
    encoding: 'utf8',
    timeout: 2000,
    windowsHide: true,
    maxBuffer: maxBytes * 2
  });
  if (result.error || result.status === null) return '';
  return truncateText(stripAnsi(result.stdout || ''), maxBytes).text.trim();
}

function addedFilePreview(resolvedPath, maxBytes) {
  try {
    const stat = fs.statSync(resolvedPath);
    if (!stat.isFile() || stat.size > maxBytes) return '';
    const content = fs.readFileSync(resolvedPath, 'utf8');
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

function currentFilePreview(resolvedPath, maxBytes) {
  try {
    const stat = fs.statSync(resolvedPath);
    if (!stat.isFile() || stat.size > maxBytes) return '';
    const content = fs.readFileSync(resolvedPath, 'utf8');
    const lines = content.replace(/\r\n/g, '\n').replace(/\r/g, '\n').split('\n');
    const preview = lines
      .slice(0, 80)
      .map((line) => ` ${line}`)
      .join('\n');
    return preview ? `@@ file preview @@\n${preview}` : '';
  } catch (_) {
    return '';
  }
}

function claudeFileChangeInputPreview(toolName, input, maxBytes) {
  if (!input || typeof input !== 'object') return '';
  if (toolName === 'edit') {
    return claudeEditPreview([
      {
        oldText: stringValue(input.old_string) ?? stringValue(input.oldString),
        newText: stringValue(input.new_string) ?? stringValue(input.newString)
      }
    ], maxBytes);
  }
  if (toolName === 'multiedit') {
    const edits = Array.isArray(input.edits) ? input.edits : [];
    return claudeEditPreview(edits.map((edit) => ({
      oldText: stringValue(edit?.old_string) ?? stringValue(edit?.oldString),
      newText: stringValue(edit?.new_string) ?? stringValue(edit?.newString)
    })), maxBytes);
  }
  if (toolName === 'write') {
    const content = stringValue(input.content) ?? stringValue(input.file_content) ?? stringValue(input.fileContent);
    if (content == null) return '';
    return truncateText(`@@ new file preview @@\n${prefixedPreviewLines(content, '+')}`, maxBytes).text.trim();
  }
  return '';
}

function claudeEditPreview(edits, maxBytes) {
  const hunks = [];
  for (const edit of edits) {
    if (edit.oldText == null || edit.newText == null) continue;
    hunks.push([
      '@@ edit preview @@',
      prefixedPreviewLines(edit.oldText, '-'),
      prefixedPreviewLines(edit.newText, '+')
    ].filter(Boolean).join('\n'));
  }
  if (hunks.length === 0) return '';
  return truncateText(hunks.join('\n'), maxBytes).text.trim();
}

function prefixedPreviewLines(text, prefix) {
  return String(text)
    .replace(/\r\n/g, '\n')
    .replace(/\r/g, '\n')
    .split('\n')
    .slice(0, 80)
    .map((line) => `${prefix}${line}`)
    .join('\n');
}

function stringValue(value) {
  return typeof value === 'string' ? value : null;
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

function relativeWorkspacePath(resolvedPath, workspacePath) {
  const relativePath = path.relative(path.resolve(workspacePath), resolvedPath);
  if (!relativePath || relativePath.startsWith('..') || path.isAbsolute(relativePath)) return '';
  return relativePath;
}

function claudeFileChangeKind(toolName, diff) {
  if (/^new file mode /m.test(diff) || /^@@ new file preview @@/m.test(diff)) return 'add';
  if (/^deleted file mode /m.test(diff)) return 'delete';
  if (toolName === 'write' && diff.startsWith('@@ new file preview @@')) return 'add';
  return 'update';
}

function formatClaudeFileChangeText(changes) {
  const parts = changes.map((change) => `${claudeFileChangeKindLabel(change.kind)} ${change.path}`);
  if (parts.length === 1) return `File changed: ${parts[0]}`;
  const visibleParts = parts.slice(0, 3);
  const remaining = parts.length - visibleParts.length;
  return `Files changed: ${visibleParts.join('; ')}${remaining > 0 ? `; and ${remaining} more` : ''}`;
}

function claudeFileChangeKindLabel(kind) {
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

function handlePendingControlResponse(state, requestId, response) {
  if (!requestId || !state.pendingControlResponses?.has(requestId)) return false;
  const waiter = state.pendingControlResponses.get(requestId);
  state.pendingControlResponses.delete(requestId);
  if (response?.subtype === 'error') {
    const message = response.error?.message || response.message || `Claude control request failed: ${requestId}`;
    waiter.reject(new Error(message));
    return true;
  }
  const responseData = response?.response && typeof response.response === 'object' ? response.response : {};
  waiter.resolve(responseData);
  return true;
}

async function sendControlRequest(state, request, timeoutMs = 60000) {
  await waitForInitialize(state);
  state.controlCounter = Number(state.controlCounter || 0) + 1;
  const requestId = `req_${state.controlCounter}_${Date.now().toString(16)}`;
  const responsePromise = new Promise((resolve, reject) => {
    state.pendingControlResponses.set(requestId, { resolve, reject });
  });
  const timeout = setTimeout(() => {
    const waiter = state.pendingControlResponses.get(requestId);
    if (!waiter) return;
    state.pendingControlResponses.delete(requestId);
    waiter.reject(new Error(`Control request timeout: ${request.subtype || 'unknown'}`));
  }, timeoutMs);
  if (typeof timeout.unref === 'function') timeout.unref();
  try {
    await writeJsonLine(state.child, { type: 'control_request', request_id: requestId, request });
  } catch (error) {
    clearTimeout(timeout);
    state.pendingControlResponses.delete(requestId);
    throw error;
  }
  return responsePromise.finally(() => clearTimeout(timeout));
}

function isClaudeTaskToolName(toolName) {
  const name = String(toolName || '').toLowerCase();
  return name === 'taskcreate' || name === 'taskupdate';
}

function isAskUserQuestionToolName(toolName) {
  return String(toolName || '').toLowerCase() === 'askuserquestion';
}

function handleClaudeTaskToolUse(state, { toolName, toolUseId, input, raw }) {
  const name = String(toolName || '').toLowerCase();
  if (name === 'taskcreate') {
    upsertClaudeCreatedTask(state, { input, result: {}, toolUseId });
  } else if (name === 'taskupdate') {
    upsertClaudeUpdatedTask(state, { input, result: {}, toolUseId });
  }
  emitClaudeTaskProgress(state, raw);
}

function handleClaudeTaskToolResult(state, { toolName, toolUseId, input, text, raw, originalRaw }) {
  const name = String(toolName || '').toLowerCase();
  const result = extractClaudeToolUseResult(raw) || extractClaudeToolUseResult(originalRaw) || {};
  if (name === 'taskcreate') {
    upsertClaudeCreatedTask(state, { input, result, resultText: text, toolUseId });
  } else if (name === 'taskupdate') {
    upsertClaudeUpdatedTask(state, { input, result, toolUseId });
  }
  emitClaudeTaskProgress(state, originalRaw || raw);
}

function upsertClaudeCreatedTask(state, { input, result, resultText, toolUseId }) {
  const task = objectValue(result.task);
  const parsedResult = parseClaudeCreatedTaskText(resultText);
  const previousTaskId = state.claudeTaskToolIds.get(toolUseId);
  const taskId =
    stringValue(task.id) ||
    stringValue(result.taskId) ||
    stringValue(input.taskId) ||
    parsedResult.id ||
    parseClaudeTaskId(result) ||
    toolUseId;
  if (previousTaskId && previousTaskId !== taskId) {
    state.claudeTasks.delete(previousTaskId);
  }
  const title =
    stringValue(task.subject) ||
    stringValue(task.title) ||
    stringValue(input.subject) ||
    stringValue(input.title) ||
    stringValue(input.description) ||
    parsedResult.title ||
    stringValue(state.claudeTasks.get(previousTaskId || taskId)?.title) ||
    `Task #${taskId}`;
  if (!taskId || !title) return;
  const previous = state.claudeTasks.get(taskId) || {};
  state.claudeTaskToolIds.set(toolUseId, taskId);
  state.claudeTasks.set(taskId, {
    id: taskId,
    title,
    status: normalizeClaudeTaskStatus(previous.status || result.status || input.status || 'pending')
  });
}

function upsertClaudeUpdatedTask(state, { input, result, toolUseId }) {
  const statusChange = objectValue(result.statusChange);
  const taskId =
    stringValue(input.taskId) ||
    stringValue(input.id) ||
    stringValue(result.taskId) ||
    stringValue(result.id) ||
    state.claudeTaskToolIds.get(toolUseId) ||
    parseClaudeTaskId(result) ||
    toolUseId;
  if (!taskId) return;
  const previous = state.claudeTasks.get(taskId) || {};
  const title =
    stringValue(previous.title) ||
    stringValue(input.subject) ||
    stringValue(input.title) ||
    `Task #${taskId}`;
  const status = normalizeClaudeTaskStatus(
    stringValue(input.status) ||
    stringValue(statusChange.to) ||
    stringValue(result.status) ||
    previous.status ||
    'pending'
  );
  state.claudeTasks.set(taskId, { id: taskId, title, status });
}

function emitClaudeTaskProgress(state, raw) {
  const items = Array.from(state.claudeTasks.values())
    .filter((item) => item && item.id && item.title)
    .map((item) => ({
      id: item.id,
      title: item.title,
      status: normalizeClaudeTaskStatus(item.status)
    }));
  if (items.length === 0) return;
  const snapshot = JSON.stringify(items.map((item) => ({
    title: item.title,
    status: item.status
  })));
  if (snapshot === state.claudeTaskProgressSnapshot) return;
  state.claudeTaskProgressSnapshot = snapshot;
  const completedCount = items.filter((item) => item.status === 'completed').length;
  state.onEvent({
    type: conversationEventTypes.TASK_PROGRESS_UPDATED,
    taskId: 'claude_tasks',
    source: 'claude',
    updatedAt: state.now().toISOString(),
    items,
    completedCount,
    totalCount: items.length,
    raw
  });
}

function normalizeClaudeTaskStatus(status) {
  const value = String(status || '').trim().toLowerCase();
  if (value === 'completed' || value === 'complete' || value === 'done' || value === 'success') return 'completed';
  if (value === 'in_progress' || value === 'in-progress' || value === 'running' || value === 'active') return 'in_progress';
  return 'pending';
}

function extractClaudeToolUseResult(raw) {
  if (!raw || typeof raw !== 'object') return null;
  if (raw.tool_use_result && typeof raw.tool_use_result === 'object') return raw.tool_use_result;
  if (raw.result && typeof raw.result === 'object') return raw.result;
  const nestedRaw = raw.raw && typeof raw.raw === 'object' ? extractClaudeToolUseResult(raw.raw) : null;
  if (nestedRaw) return nestedRaw;
  const content = raw.content;
  if (content && typeof content === 'object' && !Array.isArray(content)) {
    const fromContent = extractClaudeToolUseResult(content);
    if (fromContent) return fromContent;
  }
  if (typeof content === 'string') return parseClaudeToolResultJson(content);
  return null;
}

function parseClaudeToolResultJson(text) {
  const trimmed = String(text || '').trim();
  if (!trimmed.startsWith('{')) return null;
  try {
    const parsed = JSON.parse(trimmed);
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : null;
  } catch (_err) {
    return null;
  }
}

function parseClaudeTaskId(result) {
  const text = JSON.stringify(result || {});
  const match = text.match(/task\s*#?\s*([A-Za-z0-9_-]+)/i);
  return match ? match[1] : null;
}

function parseClaudeCreatedTaskText(text) {
  const value = stringValue(text);
  if (!value) return {};
  const match = value.match(/task\s*#?\s*([A-Za-z0-9_-]+)/i);
  const colonIndex = value.indexOf(':');
  const title = colonIndex >= 0 && colonIndex < value.length - 1
    ? value.slice(colonIndex + 1).trim()
    : '';
  return {
    id: match ? match[1] : '',
    title
  };
}

function objectValue(value) {
  return value && typeof value === 'object' && !Array.isArray(value) ? value : {};
}

function stringValue(value) {
  if (typeof value !== 'string' && typeof value !== 'number') return '';
  return String(value).trim();
}

function isExitPlanModePrompt(toolName, text) {
  return String(toolName || '').toLowerCase() === 'exitplanmode'
    && typeof text === 'string'
    && /exit\s+plan\s+mode\?/i.test(text.trim());
}

function emitExitPlanModeQuestion(state, { toolUseId, input, raw }) {
  if (!toolUseId || state.reportedPlanApprovalToolUseIds.has(toolUseId)) return;
  state.reportedPlanApprovalToolUseIds.add(toolUseId);
  state.pendingQuestions.set(toolUseId, {
    input: input || {},
    toolUseId
  });
  state.onEvent({
    type: conversationEventTypes.ASSISTANT_QUESTION,
    questionId: toolUseId,
    text: 'Exit plan mode?',
    suggestions: ['批准计划并继续', '调整计划'],
    toolName: 'ExitPlanMode',
    input: input || {},
    toolUseId,
    raw
  });
}

function emitAskUserQuestion(state, { questionId, input, toolUseId, raw }) {
  if (!questionId || state.pendingQuestions.has(questionId)) return;
  state.pendingQuestions.set(questionId, {
    input: input || {},
    toolUseId
  });
  state.onEvent({
    type: conversationEventTypes.ASSISTANT_QUESTION,
    questionId,
    text: askUserQuestionText(input) || '需要你补充更多信息。',
    suggestions: askUserQuestionSuggestions(input),
    toolName: 'AskUserQuestion',
    input: input || {},
    toolUseId,
    raw
  });
}

function handlePermissionDenials(event, state) {
  const denials = Array.isArray(event.permission_denials) ? event.permission_denials : [];
  for (const denial of denials) {
    if (!denial || typeof denial !== 'object') continue;
    const toolName = denial.tool_name || denial.toolName || null;
    const toolUseId = denial.tool_use_id || denial.toolUseId || null;
    const input = denial.tool_input && typeof denial.tool_input === 'object'
      ? denial.tool_input
      : denial.input && typeof denial.input === 'object'
        ? denial.input
        : {};
    if (String(toolName || '').toLowerCase() === 'exitplanmode') {
      emitExitPlanModeQuestion(state, { toolUseId, input, raw: event });
      continue;
    }
    const key = toolUseId || `${toolName || 'tool'}:${JSON.stringify(input)}`;
    if (state.reportedPermissionDenialToolUseIds.has(key)) continue;
    state.reportedPermissionDenialToolUseIds.add(key);
    state.onEvent({
      type: conversationEventTypes.SYSTEM_NOTICE,
      text: permissionNoticeText(toolName, input),
      noticeKind: 'permission_unavailable',
      toolUseId,
      toolName,
      input,
      raw: event
    });
  }
}

function isPermissionErrorText(text) {
  return typeof text === 'string'
    && (
      (/requested permissions/i.test(text) && /haven't granted it yet|permission/i.test(text))
      || /requires approval/i.test(text)
      || /approval required/i.test(text)
      || /permission required/i.test(text)
      || /permission for this action was denied/i.test(text)
      || /auto mode classifier/i.test(text)
    );
}

function permissionNoticeText(toolName, input) {
  const target = summarizeToolInput(toolName, input);
  return `Claude 需要权限执行 ${target}，但当前 CLI 没有发出可响应的移动端审批请求；请使用“默认”审批模式重新发送请求，或在可交互终端中授权。`;
}

function extractToolText(raw) {
  if (typeof raw.content === 'string') return raw.content;
  if (typeof raw.text === 'string') return raw.text;
  if (typeof raw.delta === 'string') return raw.delta;
  if (Array.isArray(raw.content)) return raw.content.map((part) => part?.text || part?.content || '').join('');
  return '';
}

function parsePartialJsonObject(value) {
  if (!value || typeof value !== 'string') return null;
  try {
    const parsed = JSON.parse(value);
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : null;
  } catch (_err) {
    return null;
  }
}

function handleControlRequest(raw, state) {
  const requestId = raw.request_id;
  const request = raw.request || {};
  if (!requestId) return;
  if (request.subtype !== 'can_use_tool') {
    const message = request.subtype === 'hook_callback'
      ? `No hook callback found for ID: ${request.callback_id || 'unknown'}`
      : request.subtype === 'mcp_message'
        ? `No MCP handler found for server: ${request.server_name || request.serverName || 'unknown'}`
        : `Unsupported control request subtype: ${request.subtype || 'unknown'}`;
    writeControlResponse(state.child, requestId, {
      subtype: 'error',
      error: { message }
    }).catch((error) => {
      state.onEvent({
        type: conversationEventTypes.PROTOCOL_WARNING,
        warning: 'control_response_write_failed',
        message: error.message,
        visible: false
      });
    });
    return;
  }
  if (request.tool_name === 'AskUserQuestion') {
    const questionId = request.tool_use_id || requestId;
    state.pendingQuestions.set(questionId, { requestId, input: request.input || {}, toolName: request.tool_name, toolUseId: request.tool_use_id || null });
    const questionText = askUserQuestionText(request.input) || '需要你补充更多信息。';
    state.onEvent({
      type: conversationEventTypes.ASSISTANT_QUESTION,
      questionId,
      text: questionText,
      suggestions: askUserQuestionSuggestions(request.input),
      toolName: request.tool_name,
      input: request.input || {},
      toolUseId: request.tool_use_id || null,
      raw
    });
    return;
  }
  state.pendingApprovals.set(requestId, {
    input: request.input || {},
    toolName: request.tool_name,
    toolUseId: request.tool_use_id || null
  });
  if (request.tool_use_id && request.input && typeof request.input === 'object') {
    const pendingTool = state.pendingTools.get(request.tool_use_id) || {
      toolUseId: request.tool_use_id,
      name: request.tool_name,
      startedAt: state.now().toISOString()
    };
    state.pendingTools.set(request.tool_use_id, {
      ...pendingTool,
      name: request.tool_name || pendingTool.name,
      input: request.input || pendingTool.input || {}
    });
  }
  state.onEvent({
    type: conversationEventTypes.APPROVAL_REQUESTED,
    approvalId: requestId,
    toolName: request.tool_name,
    input: request.input || {},
    suggestions: request.permission_suggestions || [],
    toolUseId: request.tool_use_id || null,
    summary: summarizeToolInput(request.tool_name, request.input),
    raw
  });
}

function handleControlCancelRequest(raw, state) {
  const requestId = raw.request_id;
  if (!requestId) return;
  const approval = state.pendingApprovals.get(requestId);
  if (approval) {
    state.pendingApprovals.delete(requestId);
    state.onEvent({
      type: conversationEventTypes.BLOCKING_REQUEST_CANCELLED,
      requestId,
      approvalId: requestId,
      blockingType: 'approval_request',
      toolName: approval.toolName || null,
      toolUseId: approval.toolUseId || null,
      input: approval.input || {},
      raw
    });
    return;
  }
  for (const [questionId, question] of state.pendingQuestions.entries()) {
    if (question?.requestId !== requestId) continue;
    state.pendingQuestions.delete(questionId);
    state.onEvent({
      type: conversationEventTypes.BLOCKING_REQUEST_CANCELLED,
      requestId,
      questionId,
      blockingType: 'input_request',
      toolName: question.toolName || 'AskUserQuestion',
      toolUseId: question.toolUseId || null,
      input: question.input || {},
      raw
    });
    return;
  }
  state.onEvent({
    type: conversationEventTypes.PROTOCOL_WARNING,
    warning: 'control_cancel_request_without_pending_blocking_item',
    requestId,
    visible: false,
    raw
  });
}

function createJsonLineParser(onJson) {
  let buffer = '';
  return (chunk) => {
    buffer += chunk.toString();
    const lines = buffer.split(/\r?\n/);
    buffer = lines.pop() || '';
    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed) continue;
      try { onJson(JSON.parse(trimmed)); } catch (_) {}
    }
  };
}

function buildClaudeUserContent({ text, attachments = [] } = {}) {
  const content = [];
  const prompt = String(text || '');
  if (prompt) content.push({ type: 'text', text: prompt });
  for (const attachment of Array.isArray(attachments) ? attachments : []) {
    if (!attachment || typeof attachment !== 'object') continue;
    if (attachment.kind === 'image' && attachment.handling === 'native') {
      content.push(buildClaudeImageBlock(attachment));
      continue;
    }
    if (attachment.kind === 'textDocument' && attachment.handling === 'text_extract') {
      content.push({
        type: 'text',
        text: textAttachmentWrapper({
          name: attachment.name,
          mimeType: attachment.mimeType,
          text: attachment.text
        })
      });
    }
  }
  return content;
}

function buildClaudeImageBlock(attachment) {
  const declaredSize = Number.isSafeInteger(attachment.sizeBytes) ? attachment.sizeBytes : null;
  if (declaredSize != null && declaredSize > CLAUDE_MAX_IMAGE_BYTES) throwClaudeImageTooLarge();
  const bytes = bytesForAttachment(attachment);
  if (bytes.length > CLAUDE_MAX_IMAGE_BYTES) throwClaudeImageTooLarge();
  return {
    type: 'image',
    source: {
      type: 'base64',
      media_type: attachment.mimeType || 'application/octet-stream',
      data: bytes.toString('base64')
    }
  };
}

function bytesForAttachment(attachment) {
  if (Buffer.isBuffer(attachment.bytes)) return attachment.bytes;
  if (attachment.bytes) return Buffer.from(attachment.bytes);
  if (attachment.scratchPath) return fs.readFileSync(attachment.scratchPath);
  return Buffer.alloc(0);
}

function throwClaudeImageTooLarge() {
  const error = new Error('Claude image attachment exceeds 5 MB limit');
  error.status = 413;
  error.code = 'ATTACHMENT_LIMIT_EXCEEDED';
  throw error;
}

async function writeUserMessage(child, message) {
  const content = typeof message === 'string'
    ? buildClaudeUserContent({ text: message })
    : buildClaudeUserContent(message);
  await writeJsonLine(child, { type: 'user', message: { role: 'user', content }, parent_tool_use_id: null, session_id: '' });
}

async function writeToolResultMessage(child, toolUseId, text) {
  await writeJsonLine(child, {
    type: 'user',
    message: {
      role: 'user',
      content: [{ type: 'tool_result', tool_use_id: toolUseId, content: text, is_error: false }]
    },
    parent_tool_use_id: null,
    session_id: ''
  });
}

async function writeControlResponse(child, requestId, response) {
  if (!requestId) return;
  await writeJsonLine(child, { type: 'control_response', response: { request_id: requestId, ...response } });
}

function writeJsonLine(child, payload) {
  return new Promise((resolve, reject) => {
    if (!isWritableStdin(child?.stdin)) {
      reject(new Error('Claude stdin is not writable'));
      return;
    }
    const line = `${JSON.stringify(payload)}\n`;
    let settled = false;
    const done = (error) => {
      if (settled) return;
      settled = true;
      cleanup();
      if (error) reject(error);
      else resolve();
    };
    const onError = (error) => done(error || new Error('Claude stdin write failed'));
    const onDrain = () => done();
    const cleanup = () => {
      if (typeof child.stdin.off === 'function') {
        child.stdin.off('error', onError);
        child.stdin.off('drain', onDrain);
      } else if (typeof child.stdin.removeListener === 'function') {
        child.stdin.removeListener('error', onError);
        child.stdin.removeListener('drain', onDrain);
      }
    };
    if (typeof child.stdin.once === 'function') child.stdin.once('error', onError);
    try {
      const flushed = child.stdin.write(line, (error) => done(error));
      if (flushed !== false || typeof child.stdin.once !== 'function') done();
      else child.stdin.once('drain', onDrain);
    } catch (error) {
      done(error);
    }
  });
}

function isWritableStdin(stdin) {
  return !!stdin
    && !stdin.destroyed
    && stdin.writable !== false
    && !stdin.writableEnded
    && !stdin.writableFinished;
}

function waitForChildExit(child, timeoutMs) {
  return new Promise((resolve) => {
    if (!child || typeof child.once !== 'function') return resolve(true);
    let settled = false;
    const finish = (value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (typeof child.off === 'function') child.off('exit', onExit);
      else if (typeof child.removeListener === 'function') child.removeListener('exit', onExit);
      resolve(value);
    };
    const onExit = () => finish(true);
    const timer = setTimeout(() => finish(false), timeoutMs);
    if (typeof timer.unref === 'function') timer.unref();
    child.once('exit', onExit);
  });
}

function askUserQuestionText(input) {
  if (!input || typeof input !== 'object') return null;
  const questionBlock = askUserQuestionFromQuestions(input);
  if (questionBlock) return questionBlock.text;
  const parts = [];
  for (const key of ['prompt', 'message', 'content', 'text', 'query', 'description', 'question']) {
    const value = input[key];
    if (typeof value === 'string' && value.trim()) parts.push(value.trim());
  }
  if (parts.length > 0) {
    const suggestions = askUserQuestionSuggestions(input);
    if (suggestions.length > 0) parts.push(suggestions.map((item) => `- ${item}`).join('\n'));
    return dedupeTextParts(parts).join('\n\n');
  }
  for (const key of ['tool_input', 'toolInput', 'input', 'arguments', 'args']) {
    const nested = input[key];
    const value = askUserQuestionText(nested);
    if (value) return value;
  }
  return null;
}

function askUserQuestionFromQuestions(input) {
  const questions = Array.isArray(input.questions) ? input.questions : null;
  if (!questions || questions.length === 0) return null;
  const parts = [];
  for (const item of questions) {
    if (!item || typeof item !== 'object') continue;
    const header = stringContent(item.header);
    const question = stringContent(item.question);
    if (header) parts.push(header);
    if (question) parts.push(question);
    const options = askUserQuestionOptionDescriptions(item);
    if (options.length > 0) parts.push(options.map((option) => `- ${option}`).join('\n'));
  }
  return parts.length > 0 ? { text: dedupeTextParts(parts).join('\n\n') } : null;
}

function askUserQuestionOptionDescriptions(input) {
  if (!input || typeof input !== 'object' || !Array.isArray(input.options)) return [];
  return input.options.map((option) => {
    if (typeof option === 'string') return option.trim();
    if (!option || typeof option !== 'object') return '';
    const label = stringContent(option.label) || stringContent(option.title) || stringContent(option.value) || '';
    const description = stringContent(option.description) || stringContent(option.text) || '';
    if (label && description) return `${label} — ${description}`;
    return label || description;
  }).filter(Boolean);
}

function dedupeTextParts(parts) {
  const seen = new Set();
  return parts.filter((part) => {
    const key = part.replace(/\s+/g, ' ').trim();
    if (!key || seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function askUserQuestionSuggestions(input) {
  if (!input || typeof input !== 'object') return [];
  if (Array.isArray(input.questions)) {
    const nested = input.questions.flatMap((question) => askUserQuestionSuggestions(question));
    if (nested.length > 0) return nested;
  }
  if (Array.isArray(input.options)) {
    return input.options.map((item) => {
      if (typeof item === 'string') return item.trim();
      if (item && typeof item === 'object') return String(item.label || item.title || item.text || item.value || '').trim();
      return '';
    }).filter(Boolean);
  }
  const raw = input.suggestions || input.options || input.choices || input.recommendations;
  if (!Array.isArray(raw)) {
    for (const key of ['tool_input', 'toolInput', 'input', 'arguments', 'args']) {
      const nested = askUserQuestionSuggestions(input[key]);
      if (nested.length > 0) return nested;
    }
    return [];
  }
  return raw.map((item) => {
    if (typeof item === 'string') return item.trim();
    if (item && typeof item === 'object') return String(item.label || item.title || item.text || item.value || '').trim();
    return '';
  }).filter(Boolean);
}

function extractText(raw) {
  if (typeof raw.result === 'string') return raw.result;
  if (typeof raw.text === 'string') return raw.text;
  if (typeof raw.delta === 'string') return raw.delta;
  if (Array.isArray(raw.content)) return raw.content.map((part) => part?.type === 'text' ? part.text || '' : '').join('');
  if (raw.message?.content) return extractText(raw.message);
  return '';
}

function extractAssistantParts(raw) {
  const content = raw.message?.content || raw.content;
  if (!Array.isArray(content)) {
    const text = extractText(raw);
    return text ? [{ type: conversationEventTypes.ASSISTANT_PARTIAL, text }] : [];
  }
  return content.map((part) => {
    if (!part || typeof part !== 'object') return null;
    if (part.type === 'thinking') {
      const text = stringContent(part.thinking) || stringContent(part.text) || stringContent(part.content);
      return text ? { type: conversationEventTypes.ASSISTANT_THINKING, text } : null;
    }
    if (!part.type || part.type === 'text') {
      const text = stringContent(part.text) || stringContent(part.content);
      return text ? { type: conversationEventTypes.ASSISTANT_PARTIAL, text } : null;
    }
    if (part.type === 'tool_use' && part.name === 'AskUserQuestion') {
      const input = part.input && typeof part.input === 'object' ? part.input : {};
      const questionId = part.id || `ask_${Date.now().toString(16)}`;
      const text = askUserQuestionText(input) || '需要你补充更多信息。';
      return {
        type: conversationEventTypes.ASSISTANT_QUESTION,
        questionId,
        text,
        suggestions: askUserQuestionSuggestions(input),
        toolName: part.name,
        input,
        toolUseId: part.id || null
      };
    }
    return null;
  }).filter(Boolean);
}

function stringContent(value) {
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

function summarizeToolInput(toolName, input) {
  if (input && typeof input === 'object') {
    if (typeof input.command === 'string') return input.command;
    if (typeof input.file_path === 'string') return input.file_path;
    if (typeof input.path === 'string') return input.path;
  }
  return toolName || 'Tool request';
}

function buildClaudeOptionArgs({ requestedToolPolicy, claudeOptions } = {}) {
  const options = claudeOptions && typeof claudeOptions === 'object' && !Array.isArray(claudeOptions) ? claudeOptions : {};
  const args = [];
  const tools = Array.isArray(options.tools) ? options.tools : requestedToolPolicy?.tools;
  const allowed = Array.isArray(options.allowedTools) ? options.allowedTools : requestedToolPolicy?.allowedTools;
  const disallowed = Array.isArray(options.disallowedTools) ? options.disallowedTools : requestedToolPolicy?.disallowedTools;
  pushListArg(args, '--tools', tools, { includeEmpty: Array.isArray(options.tools) });
  pushListArg(args, '--allowedTools', allowed);
  pushListArg(args, '--disallowedTools', disallowed);
  pushStringArg(args, '--system-prompt', options.systemPrompt);
  pushStringArg(args, '--system-prompt-file', options.systemPromptFile);
  pushStringArg(args, '--append-system-prompt', options.appendSystemPrompt);
  pushNumberArg(args, '--max-turns', options.maxTurns);
  pushNumberArg(args, '--max-budget-usd', options.maxBudgetUsd);
  pushNumberArg(args, '--task-budget', options.taskBudgetTotal);
  pushStringArg(args, '--fallback-model', options.fallbackModel);
  pushListArg(args, '--betas', options.betas);
  pushStringArg(args, '--settings', options.settings);
  for (const directory of Array.isArray(options.addDirs) ? options.addDirs : []) pushStringArg(args, '--add-dir', directory);
  if (options.mcpConfig) {
    args.push('--mcp-config', typeof options.mcpConfig === 'string'
      ? options.mcpConfig
      : JSON.stringify({ mcpServers: options.mcpConfig }));
  }
  if (options.forkSession === true) args.push('--fork-session');
  if (Array.isArray(options.settingSources)) args.push(`--setting-sources=${options.settingSources.join(',')}`);
  if (Array.isArray(options.plugins)) {
    for (const plugin of options.plugins) {
      if (plugin?.type === 'local' && plugin.path) args.push('--plugin-dir', String(plugin.path));
    }
  }
  if (options.extraArgs && typeof options.extraArgs === 'object' && !Array.isArray(options.extraArgs)) {
    for (const [flag, value] of Object.entries(options.extraArgs)) {
      if (!/^[a-zA-Z0-9][a-zA-Z0-9_-]*$/.test(flag)) continue;
      args.push(`--${flag}`);
      if (value != null) args.push(String(value));
    }
  }
  const thinking = options.thinking && typeof options.thinking === 'object' ? options.thinking : null;
  if (thinking?.type === 'adaptive') args.push('--thinking', 'adaptive');
  else if (thinking?.type === 'enabled') pushNumberArg(args, '--max-thinking-tokens', thinking.budgetTokens);
  else if (thinking?.type === 'disabled') args.push('--thinking', 'disabled');
  else pushNumberArg(args, '--max-thinking-tokens', options.maxThinkingTokens);
  pushStringArg(args, '--effort', options.effort);
  const outputFormat = options.outputFormat && typeof options.outputFormat === 'object' ? options.outputFormat : null;
  if (outputFormat?.type === 'json_schema' && outputFormat.schema) {
    args.push('--json-schema', JSON.stringify(outputFormat.schema));
  }
  return args;
}

function pushStringArg(args, flag, value) {
  if (typeof value !== 'string' || !value.trim()) return;
  args.push(flag, value);
}

function pushNumberArg(args, flag, value) {
  if (!Number.isFinite(Number(value))) return;
  args.push(flag, String(value));
}

function pushListArg(args, flag, value, { includeEmpty = false } = {}) {
  if (!Array.isArray(value)) return;
  const list = value.map((item) => String(item).trim()).filter(Boolean);
  if (list.length === 0 && !includeEmpty) return;
  args.push(flag, list.join(','));
}

function allowedTools() {
  return ['Read', 'Write', 'Edit', 'MultiEdit', 'Glob', 'Grep', 'LS', 'Bash(git status *)', 'Bash(git diff *)', 'Bash(node *)', 'Bash(npm test *)', 'Bash(pnpm test *)', 'Bash(python *)', 'Bash(py *)', 'Bash(dart test *)', 'Bash(flutter test *)', 'Bash(flutter analyze *)'].join(',');
}

function sdkProcessEnvForWorkspace(sourceEnv, workspacePath) {
  const env = { ...sourceEnv };
  delete env.CLAUDECODE;
  env.CLAUDE_CODE_ENTRYPOINT = 'sdk-js';
  env.CLAUDE_AGENT_SDK_VERSION = packageJson.version || '0.0.0';
  env.CLAUDE_CODE_ENABLE_FINE_GRAINED_TOOL_STREAMING = '1';
  if (workspacePath) env.PWD = workspacePath;
  return env;
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

module.exports = { ClaudeConversationAdapter, ClaudeConversationHandle, buildClaudeUserContent };
