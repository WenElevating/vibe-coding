'use strict';

const { spawn, spawnSync } = require('node:child_process');
const { conversationEventTypes } = require('./conversation-protocol');
const { detectClaudeCodeInstallation, unavailableCapability } = require('./claude-adapter');
const { resolveCliInvocation } = require('./cli-resolver');

class ClaudeConversationAdapter {
  constructor({ command = 'claude', spawnFn = spawn, spawnSyncFn = spawnSync, cliResolverOptions = {}, readTextFile } = {}) {
    this.name = 'claude';
    this.command = command;
    this.spawnFn = spawnFn;
    this.spawnSyncFn = spawnSyncFn;
    this.readTextFile = readTextFile;
    this.invocation = resolveCliInvocation(command, { spawnSyncFn, ...cliResolverOptions });
    this.capability = null;
    this.capabilities = { longLivedProcess: true, waitingInput: true, waitingApproval: true, resume: true, partialOutput: true };
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
    this.capability = {
      adapter: 'claude',
      version: detection.version,
      available: true,
      command: this.command,
      path: detection.path,
      detectionMethod: detection.method,
      capabilities: this.capabilities
    };
    return this.capability;
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

  async startConversation({ conversationId, workspacePath, permissionMode = 'default', sessionId, onEvent }) {
    if (!workspacePath || !String(workspacePath).trim()) throw new Error('workspacePath is required');
    this.ensureAvailable();
    const args = [
      '--output-format', 'stream-json',
      '--verbose',
      '--print',
      '--include-partial-messages',
      ...(sessionId ? ['--resume', sessionId] : []),
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
      contentBlocks: new Map(),
      now: () => new Date(),
      initRequestId,
      initialized: false,
      initWaiters: []
    };
    child.stdout.on('data', createJsonLineParser((raw) => handleRawClaudeEvent(raw, state)));
    child.stderr.on('data', (chunk) => onEvent({ type: conversationEventTypes.PROTOCOL_WARNING, text: chunk.toString() }));
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
    const fallback = setTimeout(() => completeInitialize(state, { timedOut: true }), 1500);
    state.initFallback = fallback;
    return new ClaudeConversationHandle({ conversationId, state });
  }
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
    state.onEvent({ type: conversationEventTypes.PROTOCOL_WARNING, text: `Claude API ${event.error_status || ''} ${event.error || 'error'}`, sessionId, raw: event });
    return;
  }
  if (sessionId) state.onEvent({ type: conversationEventTypes.PROTOCOL_WARNING, text: '', sessionId, raw: event });
}

function completeInitialize(state, details = {}) {
  if (state.initialized) return;
  state.initialized = true;
  if (state.initFallback) clearTimeout(state.initFallback);
  if (details.timedOut) {
    state.onEvent({
      type: conversationEventTypes.PROTOCOL_WARNING,
      text: 'Claude initialize handshake timed out; continuing with prompt send fallback.'
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
  const tool = {
    toolUseId,
    name: raw.name || raw.tool_name || previous.name || 'tool',
    input,
    startedAt: previous.startedAt || state.now().toISOString()
  };
  state.pendingTools.set(toolUseId, tool);
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
      handleToolUse(part, state, originalRaw);
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
  state.onEvent({ type: 'tool.delta', toolUseId, text, raw: originalRaw });
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

function isPermissionErrorText(text) {
  return typeof text === 'string'
    && /requested permissions/i.test(text)
    && /haven't granted it yet|permission/i.test(text);
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

function writeUserMessage(child, text) {
  writeJsonLine(child, { type: 'user', message: { role: 'user', content: text }, parent_tool_use_id: null, session_id: '' });
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

module.exports = { ClaudeConversationAdapter, ClaudeConversationHandle };
