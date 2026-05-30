'use strict';

const fs = require('node:fs');
const { spawn, spawnSync } = require('node:child_process');
const { conversationEventTypes } = require('./conversation-protocol');
const { detectClaudeCodeInstallation, unavailableCapability } = require('./claude-adapter');
const { resolveCliInvocation } = require('./cli-resolver');
const { discoverConfiguredModels } = require('./model-discovery');
const { textAttachmentWrapper } = require('./attachment-validation');

const CLAUDE_MAX_IMAGE_BYTES = 5 * 1024 * 1024;

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

  async startConversation({ conversationId, workspacePath, permissionMode = 'default', sessionId, model, onEvent }) {
    if (!workspacePath || !String(workspacePath).trim()) throw new Error('workspacePath is required');
    this.ensureAvailable();
    const selectedModel = this.modelCapability?.canSelectModel === true ? model : null;
    const args = [
      '--output-format', 'stream-json',
      '--verbose',
      '--print',
      '--include-partial-messages',
      ...(sessionId ? ['--resume', sessionId] : []),
      ...(selectedModel ? ['--model', selectedModel] : []),
      '--permission-mode', permissionMode === 'default' ? 'default' : 'auto',
      ...(permissionMode === 'auto' ? ['--allowedTools', allowedTools()] : []),
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
      initRequestId,
      initialized: false,
      initWaiters: []
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
    writeJsonLine(child, {
      type: 'control_request',
      request_id: initRequestId,
      request: { subtype: 'initialize', hooks: null }
    });
    const fallback = setTimeout(() => completeInitialize(state, { timedOut: true }), 5000);
    state.initFallback = fallback;
    return new ClaudeConversationHandle({ conversationId, state });
  }
}

function defaultModelCapability() {
  return { models: [], selectedModel: null, canSelectModel: false };
}

class ClaudeConversationHandle {
  constructor({ conversationId, state }) {
    this.conversationId = conversationId;
    this.state = state;
  }

  async sendUserMessage(text) {
    await waitForInitialize(this.state);
    writeUserMessage(this.state.child, text);
  }

  async answerQuestion(questionId, text) {
    await waitForInitialize(this.state);
    const pending = this.state.pendingQuestions.get(questionId);
    if (pending?.toolUseId && !pending.requestId) {
      writeToolResultMessage(this.state.child, pending.toolUseId, text);
      this.state.pendingQuestions.delete(questionId);
      return;
    }
    writeUserMessage(this.state.child, text);
    if (pending) {
      if (pending.requestId) {
        writeControlResponse(this.state.child, pending.requestId, {
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
    const response = decision === 'allow'
      ? { behavior: 'allow', updatedInput: input }
      : { behavior: 'deny', message: 'User denied permission from mobile client.', interrupt: true };
    writeControlResponse(this.state.child, approvalId, { subtype: 'success', response });
    this.state.pendingApprovals.delete(approvalId);
  }

  async cancel() {
    if (this.state.child && typeof this.state.child.kill === 'function') this.state.child.kill('SIGTERM');
  }

  async dispose() {
    await this.cancel();
  }
}

function handleRawClaudeEvent(raw, state) {
  const event = unwrapClaudeEvent(raw);
  const rawType = typeof event.type === 'string' ? event.type : 'raw';
  if (rawType === 'control_response') {
    const requestId = event.response?.request_id || event.request_id;
    if (requestId === state.initRequestId || !state.initialized) completeInitialize(state);
    return;
  }
  if (!state.initialized) completeInitialize(state);
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
  state.pendingTools.delete(toolUseId);
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
    );
}

function permissionNoticeText(toolName, input) {
  const target = summarizeToolInput(toolName, input);
  return `Claude 需要权限执行 ${target}，但当前 CLI 没有发出可响应的移动端审批请求；请切换到自动权限模式或在可交互终端中授权。`;
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
  if (request.subtype !== 'can_use_tool' || !requestId) return;
  if (request.tool_name === 'AskUserQuestion') {
    const questionId = request.tool_use_id || requestId;
    state.pendingQuestions.set(questionId, { requestId, input: request.input || {} });
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
  state.pendingApprovals.set(requestId, { input: request.input || {} });
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

function writeUserMessage(child, message) {
  const content = typeof message === 'string'
    ? buildClaudeUserContent({ text: message })
    : buildClaudeUserContent(message);
  writeJsonLine(child, { type: 'user', message: { role: 'user', content }, parent_tool_use_id: null, session_id: '' });
}

function writeToolResultMessage(child, toolUseId, text) {
  writeJsonLine(child, {
    type: 'user',
    message: {
      role: 'user',
      content: [{ type: 'tool_result', tool_use_id: toolUseId, content: text, is_error: false }]
    },
    parent_tool_use_id: null,
    session_id: ''
  });
}

function writeControlResponse(child, requestId, response) {
  if (!requestId) return;
  writeJsonLine(child, { type: 'control_response', response: { request_id: requestId, ...response } });
}

function writeJsonLine(child, payload) {
  if (!isWritableStdin(child.stdin)) return;
  child.stdin.write(`${JSON.stringify(payload)}\n`);
}

function isWritableStdin(stdin) {
  return !!stdin
    && !stdin.destroyed
    && stdin.writable !== false
    && !stdin.writableEnded
    && !stdin.writableFinished;
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

function allowedTools() {
  return ['Read', 'Write', 'Edit', 'MultiEdit', 'Glob', 'Grep', 'LS', 'Bash(git status *)', 'Bash(git diff *)', 'Bash(node *)', 'Bash(npm test *)', 'Bash(pnpm test *)', 'Bash(python *)', 'Bash(py *)', 'Bash(dart test *)', 'Bash(flutter test *)', 'Bash(flutter analyze *)'].join(',');
}

function sdkProcessEnvForWorkspace(sourceEnv, workspacePath) {
  const env = { ...sourceEnv };
  delete env.CLAUDECODE;
  env.CLAUDE_CODE_ENTRYPOINT = env.CLAUDE_CODE_ENTRYPOINT || 'sdk-js';
  env.CLAUDE_CODE_ENABLE_FINE_GRAINED_TOOL_STREAMING = '1';
  if (workspacePath) env.PWD = workspacePath;
  return env;
}

module.exports = { ClaudeConversationAdapter, ClaudeConversationHandle, buildClaudeUserContent };
