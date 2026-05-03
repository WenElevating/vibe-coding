'use strict';

const { spawn, spawnSync } = require('node:child_process');
const { conversationEventTypes } = require('./conversation-protocol');
const { unavailableCapability } = require('./claude-adapter');

class ClaudeConversationAdapter {
  constructor({ command = 'claude', spawnFn = spawn, spawnSyncFn = spawnSync } = {}) {
    this.name = 'claude';
    this.command = command;
    this.spawnFn = spawnFn;
    this.spawnSyncFn = spawnSyncFn;
    this.capability = null;
    this.capabilities = { longLivedProcess: true, waitingInput: true, waitingApproval: true, resume: true, partialOutput: true };
  }

  detectCapabilities() {
    const version = this.spawnSyncFn(this.command, ['--version'], { encoding: 'utf8' });
    if (version.error || version.status !== 0) {
      this.capability = unavailableCapability(this.command, version.error || version.stderr);
      return this.capability;
    }
    this.capability = {
      adapter: 'claude',
      version: String(version.stdout || version.stderr || '').trim(),
      available: true,
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
    this.ensureAvailable();
    const args = [
      '--output-format', 'stream-json',
      '--verbose',
      '--print',
      '--system-prompt', '',
      '--include-partial-messages',
      ...(sessionId ? ['--resume', sessionId] : []),
      ...(permissionMode === 'default'
        ? ['--permission-prompt-tool', 'stdio', '--permission-mode', 'default']
        : ['--permission-mode', 'auto']),
      ...(permissionMode === 'auto' ? ['--allowedTools', allowedTools()] : []),
      '--input-format', 'stream-json'
    ];
    const child = this.spawnFn(this.command, args, {
      cwd: workspacePath,
      windowsHide: true,
      env: sdkProcessEnvForWorkspace(process.env, workspacePath)
    });
    const state = { child, onEvent, pendingQuestions: new Map(), pendingApprovals: new Map() };
    const initRequestId = `init_${Date.now().toString(16)}`;
    child.stdout.on('data', createJsonLineParser((raw) => handleRawClaudeEvent(raw, state)));
    child.stderr.on('data', (chunk) => onEvent({ type: conversationEventTypes.PROTOCOL_WARNING, text: chunk.toString() }));
    child.on('error', (error) => onEvent({ type: conversationEventTypes.RUN_ERROR, error: error.message }));
    child.on('exit', (code, signal) => {
      if (signal) onEvent({ type: conversationEventTypes.CONVERSATION_CANCELLED, signal });
      else if (code !== 0) onEvent({ type: conversationEventTypes.RUN_ERROR, exitCode: code });
    });
    writeJsonLine(child, {
      type: 'control_request',
      request_id: initRequestId,
      request: { subtype: 'initialize', hooks: null }
    });
    return new ClaudeConversationHandle({ conversationId, state });
  }
}

class ClaudeConversationHandle {
  constructor({ conversationId, state }) {
    this.conversationId = conversationId;
    this.state = state;
  }

  async sendUserMessage(text) {
    writeUserMessage(this.state.child, text);
  }

  async answerQuestion(questionId, text) {
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
  const rawType = typeof raw.type === 'string' ? raw.type : 'raw';
  if (rawType === 'control_response') return;
  if (rawType === 'control_request') {
    handleControlRequest(raw, state);
    return;
  }
  const sessionId = raw.session_id || raw.sessionId;
  if (rawType === 'result') {
    const text = extractText(raw);
    if (text) state.onEvent({ type: conversationEventTypes.ASSISTANT_MESSAGE, text, sessionId, raw });
    else state.onEvent({ type: conversationEventTypes.CONVERSATION_COMPLETED, sessionId, raw });
    return;
  }
  if (rawType === 'assistant' || raw.message?.role === 'assistant') {
    const parts = extractAssistantParts(raw);
    for (const part of parts) {
      if (part.type === conversationEventTypes.ASSISTANT_QUESTION) {
        state.pendingQuestions.set(part.questionId, { input: part.input || {}, toolUseId: part.toolUseId || null });
        state.onEvent({ ...part, sessionId, raw });
      } else {
        state.onEvent({ type: part.type, text: part.text, sessionId, raw });
      }
    }
    return;
  }
  if (rawType === 'system' && raw.subtype === 'api_retry') {
    state.onEvent({ type: conversationEventTypes.PROTOCOL_WARNING, text: `Claude API ${raw.error_status || ''} ${raw.error || 'error'}`, sessionId, raw });
    return;
  }
  if (sessionId) state.onEvent({ type: conversationEventTypes.PROTOCOL_WARNING, text: '', sessionId, raw });
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
  if (!child.stdin || child.stdin.destroyed) return;
  child.stdin.write(`${JSON.stringify(payload)}\n`);
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
