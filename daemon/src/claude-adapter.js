'use strict';

const { spawn, spawnSync } = require('node:child_process');
const { eventTypes } = require('./protocol');
const { resolveCliInvocation } = require('./cli-resolver');

class ClaudeAdapter {
  constructor({ command = 'claude', spawnFn = spawn, spawnSyncFn = spawnSync, cliResolverOptions = {} } = {}) {
    this.name = 'claude';
    this.command = command;
    this.spawnFn = spawnFn;
    this.spawnSyncFn = spawnSyncFn;
    this.invocation = resolveCliInvocation(command, { spawnSyncFn, ...cliResolverOptions });
    this.capability = null;
  }

  detectCapabilities() {
    const version = this.spawnSyncFn(this.invocation.command, [...this.invocation.argsPrefix, '--version'], { encoding: 'utf8' });
    const help = this.spawnSyncFn(this.invocation.command, [...this.invocation.argsPrefix, '--help'], { encoding: 'utf8' });
    if (version.error || version.status !== 0) {
      this.capability = unavailableCapability(this.command, version.error || version.stderr);
      return this.capability;
    }
    const helpText = `${help.stdout}\n${help.stderr}`;
    const permissionModes = detectPermissionModes(this.invocation, this.spawnSyncFn, helpText);
    this.capability = {
      adapter: 'claude',
      version: String(version.stdout || version.stderr || '').trim(),
      available: true,
      capabilities: {
        print: helpText.includes('-p') || helpText.includes('--print'),
        bare: helpText.includes('--bare'),
        streamJson: helpText.includes('stream-json'),
        inputFormat: helpText.includes('--input-format') || helpText.includes('input-format'),
        verbose: helpText.includes('--verbose'),
        includePartialMessages: helpText.includes('--include-partial-messages'),
        resume: helpText.includes('--resume') || helpText.includes('resume'),
        permissionModes
      }
    };
    const required = ['print', 'streamJson', 'verbose', 'includePartialMessages'];
    const missing = required.filter((key) => !this.capability.capabilities[key]);
    if (missing.length > 0) {
      this.capability.available = false;
      this.capability.error = `Claude CLI missing required capabilities: ${missing.join(', ')}`;
    }
    return this.capability;
  }

  ensureAvailable() {
    const capability = this.capability || this.detectCapabilities();
    if (!capability.available) {
      const error = new Error(capability.error || 'Claude adapter unavailable');
      error.status = 503;
      error.code = 'CLAUDE_UNAVAILABLE';
      error.details = capability;
      throw error;
    }
  }

  startRun({ prompt, workspacePath, sessionId, resume = false, permissionMode = 'default', onEvent }) {
    assertWorkspacePath(workspacePath);
    this.ensureAvailable();
    const launchOptions = buildClaudeArgs({ permissionMode, sessionId, resume }, this.capability);
    const args = launchOptions.args;
    const effectivePermissionMode = launchOptions.effectivePermissionMode;
    const child = this.spawnFn(this.invocation.command, [...this.invocation.argsPrefix, ...args], {
      cwd: workspacePath,
      windowsHide: true,
      env: sdkProcessEnvForWorkspace(process.env, workspacePath)
    });
    const initRequestId = `init_${Date.now().toString(16)}`;
    let promptSent = false;
    let terminalEmitted = false;
    const emitEvent = (event) => {
      if (terminalEmitted) return;
      if (isTerminalEvent(event)) {
        terminalEmitted = true;
      }
      onEvent(event);
    };
    const sendPrompt = () => {
      if (promptSent) return;
      promptSent = true;
      writeJsonLine(child, {
        type: 'user',
        message: { role: 'user', content: prompt },
        parent_tool_use_id: null,
        session_id: ''
      });
      if (shouldCloseStdinAfterPrompt(effectivePermissionMode)) endInput(child);
    };
    const parseStdout = createJsonLineParser((event) => {
      if (event.type === '__control_response' && event.requestId === initRequestId) {
        sendPrompt();
        return;
      }
      if (event.type === '__result' && !shouldCloseStdinAfterPrompt(effectivePermissionMode)) endInput(child);
      handleClaudeEvent(event, child, emitEvent);
    });
    child.stdout.on('data', parseStdout);
    child.stderr.on('data', (chunk) => emitEvent({ type: eventTypes.RAW_OUTPUT, text: chunk.toString() }));
    child.on('error', (error) => emitEvent({ type: eventTypes.RUN_FAILED, error: error.message }));
    child.on('exit', (code, signal) => {
      if (signal) emitEvent({ type: eventTypes.RUN_CANCELLED, signal });
      else if (code === 0) emitEvent({ type: eventTypes.RUN_COMPLETED, exitCode: code });
      else emitEvent({ type: eventTypes.RUN_FAILED, exitCode: code });
    });
    writeJsonLine(child, {
      type: 'control_request',
      request_id: initRequestId,
      request: { subtype: 'initialize', hooks: null }
    });
    const fallback = setTimeout(sendPrompt, 1500);
    if (typeof fallback.unref === 'function') fallback.unref();
    return child;
  }
}


function handleClaudeEvent(event, child, onEvent) {
  if (event.type === '__internal') return;
  if (event.type === '__control_response') return;
  if (event.type === '__result') {
    if (event.isError) {
      onEvent({ type: eventTypes.RUN_FAILED, error: event.text || 'Claude run failed', sessionId: event.sessionId, raw: event.raw });
      return;
    }
    if (event.text) onEvent({ type: eventTypes.ASSISTANT_DELTA, text: event.text, sessionId: event.sessionId, raw: event.raw });
    onEvent({ type: eventTypes.RUN_COMPLETED, sessionId: event.sessionId, raw: event.raw });
    return;
  }
  if (event.type === '__control_request') {
    const request = event.raw || {};
    const requestId = request.request_id;
    const payload = request.request || {};
    if (payload.subtype !== 'can_use_tool' || !requestId) {
      writeControlResponse(child, requestId, { subtype: 'error', error: `Unsupported control request: ${payload.subtype || 'unknown'}` });
      return;
    }
    if (isAskUserQuestionTool(payload.tool_name)) {
      const text = askUserQuestionText(payload.input) || '需要你补充更多信息。';
      onEvent({
        type: eventTypes.ASSISTANT_QUESTION,
        text,
        suggestions: askUserQuestionSuggestions(payload.input),
        toolName: payload.tool_name,
        input: payload.input || {},
        toolUseId: payload.tool_use_id || null,
        agentId: payload.agent_id || null,
        raw: request
      });
      writeControlResponse(child, requestId, {
        subtype: 'success',
        response: { behavior: 'allow', updatedInput: payload.input || {} }
      });
      return;
    }
    onEvent({
      type: eventTypes.APPROVAL_REQUIRED,
      approvalId: requestId,
      toolName: payload.tool_name,
      input: payload.input || {},
      suggestions: payload.permission_suggestions || [],
      toolUseId: payload.tool_use_id || null,
      agentId: payload.agent_id || null,
      raw: request,
      respond: (decision) => {
        const response = decision === 'allow'
          ? { behavior: 'allow', updatedInput: payload.input || {} }
          : { behavior: 'deny', message: 'User denied permission from mobile client.', interrupt: true };
        writeControlResponse(child, requestId, { subtype: 'success', response });
      }
    });
    return;
  }
  onEvent(event);
}

function buildClaudeArgs(input = {}, capability = {}) {
  const { effectivePermissionMode, requestedPermissionMode } = resolvePermissionMode(input.permissionMode, capability);
  const args = [
    '--output-format',
    'stream-json',
    '--verbose',
    '--print',
    '--include-partial-messages',
    ...(input.sessionId ? ['--resume', input.sessionId] : input.resume ? ['--continue'] : []),
    '--permission-mode',
    effectivePermissionMode,
    ...toolControlArgs(input, effectivePermissionMode),
    '--input-format',
    'stream-json'
  ];
  return { args, requestedPermissionMode, effectivePermissionMode };
}

function resolvePermissionMode(requestedPermissionMode = 'default', capability = {}) {
  const requested = requestedPermissionMode || 'default';
  const modes = new Set(capability?.capabilities?.permissionModes || ['default']);
  const effectivePermissionMode = modes.has(requested) ? requested : 'default';
  return { requestedPermissionMode: requested, effectivePermissionMode };
}

function toolControlArgs(input, effectivePermissionMode) {
  const args = [];
  const tools = normalizeToolList(input.tools || input.requestedToolPolicy?.tools);
  const allowedTools = normalizeToolList(input.allowedTools || input.requestedToolPolicy?.allowedTools);
  const disallowedTools = normalizeToolList(input.disallowedTools || input.requestedToolPolicy?.disallowedTools);
  if (tools.length > 0) args.push('--tools', tools.join(','));
  if (disallowedTools.length > 0) args.push('--disallowedTools', disallowedTools.join(','));
  if (allowedTools.length > 0 && effectivePermissionMode !== 'bypassPermissions') args.push('--allowedTools', allowedTools.join(','));
  if (allowedTools.length === 0 && effectivePermissionMode === 'auto') args.push('--allowedTools', defaultAllowedTools().join(','));
  return args;
}

function normalizeToolList(value) {
  if (!Array.isArray(value)) return [];
  return value.map((item) => typeof item === 'string' ? item.trim() : '').filter(Boolean);
}

function defaultAllowedTools() {
  return [
    'Read',
    'Write',
    'Edit',
    'MultiEdit',
    'Glob',
    'Grep',
    'LS',
    'Bash(git status *)',
    'Bash(git diff *)',
    'Bash(node *)',
    'Bash(npm test *)',
    'Bash(pnpm test *)',
    'Bash(python *)',
    'Bash(py *)',
    'Bash(dart test *)',
    'Bash(flutter test *)',
    'Bash(flutter analyze *)'
  ];
}

function shouldCloseStdinAfterPrompt(permissionMode) {
  return ['auto', 'bypassPermissions', 'dontAsk', 'acceptEdits'].includes(permissionMode);
}

function detectPermissionModes(invocation, spawnSyncFn, helpText) {
  const parsed = parsePermissionModes(helpText);
  if (parsed.length > 1) return parsed;
  const probed = probePermissionMode(invocation, spawnSyncFn, 'auto');
  if (probed) return Array.from(new Set([...parsed, 'auto']));
  return parsed;
}

function parsePermissionModes(helpText) {
  const supported = new Set(['default']);
  const text = String(helpText || '');
  const line = text.split(/\r?\n/).find((item) => item.includes('--permission-mode')) || '';
  const bracket = line.match(/\[([^\]]+)\]/)?.[1] || '';
  const source = `${line} ${bracket}`;
  for (const mode of ['auto', 'acceptEdits', 'bypassPermissions', 'plan', 'dontAsk', 'delegate', 'default']) {
    if (source.includes(mode)) supported.add(mode);
  }
  return Array.from(supported);
}

function probePermissionMode(invocation, spawnSyncFn, mode) {
  const result = spawnSyncFn(invocation.command, [...invocation.argsPrefix, '--permission-mode', mode, '--print', '--max-turns', '0', 'true'], { encoding: 'utf8' });
  if (result.error) return false;
  const text = `${result.stdout || ''}\n${result.stderr || ''}`;
  return result.status === 0 || !/invalid|unknown|unsupported|parse|option/i.test(text);
}

function isAskUserQuestionTool(toolName) {
  return toolName === 'AskUserQuestion';
}

function askUserQuestionText(input) {
  if (!input || typeof input !== 'object') return null;
  for (const key of ['question', 'prompt', 'message', 'content', 'text', 'query', 'description']) {
    const value = input[key];
    if (typeof value === 'string' && value.trim()) return value.trim();
  }
  for (const key of ['tool_input', 'toolInput', 'input', 'arguments', 'args']) {
    const value = askUserQuestionText(input[key]);
    if (value) return value;
  }
  return null;
}

function askUserQuestionSuggestions(input) {
  if (!input || typeof input !== 'object') return [];
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
    if (item && typeof item === 'object') {
      return String(item.label || item.title || item.text || item.value || '').trim();
    }
    return '';
  }).filter(Boolean);
}

function writeControlResponse(child, requestId, response) {
  if (!requestId) return;
  writeJsonLine(child, {
    type: 'control_response',
    response: { request_id: requestId, ...response }
  });
}

function writeJsonLine(child, payload) {
  if (!isWritableStdin(child.stdin)) return;
  child.stdin.write(`${JSON.stringify(payload)}\n`);
}

function endInput(child) {
  if (!isWritableStdin(child.stdin)) return;
  if (typeof child.stdin.end === 'function') child.stdin.end();
}

function isWritableStdin(stdin) {
  return !!stdin
    && !stdin.destroyed
    && stdin.writable !== false
    && !stdin.writableEnded
    && !stdin.writableFinished;
}

function sdkProcessEnv(sourceEnv) {
  const env = { ...sourceEnv };
  delete env.CLAUDECODE;
  env.CLAUDE_CODE_ENTRYPOINT = env.CLAUDE_CODE_ENTRYPOINT || 'sdk-js';
  env.CLAUDE_CODE_ENABLE_FINE_GRAINED_TOOL_STREAMING = '1';
  return env;
}

function sdkProcessEnvForWorkspace(sourceEnv, workspacePath) {
  const env = sdkProcessEnv(sourceEnv);
  if (workspacePath) env.PWD = workspacePath;
  return env;
}

function createJsonLineParser(onEvent) {
  let buffer = '';
  return (chunk) => {
    buffer += chunk.toString();
    const lines = buffer.split(/\r?\n/);
    buffer = lines.pop() || '';
    for (const line of lines) parseClaudeLine(line, onEvent);
  };
}

function parseClaudeLine(line, onEvent) {
  const trimmed = line.trim();
  if (!trimmed) return;
  if (!trimmed.startsWith('{')) {
    onEvent({ type: eventTypes.RAW_OUTPUT, text: trimmed });
    return;
  }
  try {
    onEvent(mapClaudeEvent(JSON.parse(trimmed)));
  } catch {
    onEvent({ type: eventTypes.RAW_OUTPUT, text: trimmed });
  }
}

function unavailableCapability(command, reason) {
  return {
    adapter: 'claude',
    version: null,
    available: false,
    command,
    capabilities: { print: false, bare: false, streamJson: false, inputFormat: false, verbose: false, includePartialMessages: false, resume: false },
    error: `Unable to inspect Claude CLI. Run claude --version and claude --help. ${reason ? String(reason) : ''}`.trim()
  };
}

function parseJsonLines(chunk, onEvent) {
  createJsonLineParser(onEvent)(chunk);
}

function mapClaudeEvent(raw) {
  if (raw.type === 'stream_event' && raw.event && typeof raw.event === 'object') {
    return mapClaudeEvent({
      ...raw.event,
      session_id: raw.event.session_id || raw.session_id,
      sessionId: raw.event.sessionId || raw.sessionId
    });
  }
  const rawType = typeof raw.type === 'string' ? raw.type : typeof raw.event === 'string' ? raw.event : 'raw';
  if (rawType === 'control_request') return { type: '__control_request', raw };
  if (rawType === 'control_response') return { type: '__control_response', requestId: raw.response?.request_id, raw };
  if (rawType === 'system' && ['session_start', 'session_end'].includes(raw.subtype)) {
    return {
      type: eventTypes.RAW_OUTPUT,
      text: '',
      sessionId: raw.session_id || raw.sessionId,
      raw
    };
  }
  if (isInternalClaudePayload(raw, rawType)) return { type: '__internal', raw };
  if (rawType === 'result') {
    return {
      type: '__result',
      text: extractText(raw),
      sessionId: raw.session_id || raw.sessionId,
      isError: raw.is_error === true || raw.subtype === 'error',
      raw
    };
  }
  if (rawType === 'system' && raw.subtype === 'api_retry') {
    return {
      type: eventTypes.RAW_OUTPUT,
      text: `Claude API ${raw.error_status || ''} ${raw.error || 'error'}; retry ${raw.attempt}/${raw.max_retries}, next in ${Math.round(Number(raw.retry_delay_ms || 0))}ms`,
      sessionId: raw.session_id || raw.sessionId,
      raw
    };
  }
  if (rawType === 'system' && raw.subtype === 'status') {
    return {
      type: eventTypes.RAW_OUTPUT,
      text: raw.status ? `Claude ${raw.status}` : '',
      sessionId: raw.session_id || raw.sessionId,
      raw
    };
  }
  if (rawType === 'assistant' || rawType.includes('assistant') || raw.message?.role === 'assistant') {
    return { type: eventTypes.ASSISTANT_DELTA, text: extractText(raw), sessionId: raw.session_id || raw.sessionId, raw };
  }
  if (raw.session_id || raw.sessionId) {
    return { type: eventTypes.RAW_OUTPUT, text: '', sessionId: raw.session_id || raw.sessionId, raw };
  }
  if (rawType.includes('tool') && rawType.includes('start')) {
    return { type: eventTypes.TOOL_STARTED, name: raw.name || raw.tool_name || 'tool', input: raw.input || {}, raw };
  }
  if (rawType.includes('tool')) {
    return { type: eventTypes.TOOL_OUTPUT, text: extractText(raw), raw };
  }
  return { type: eventTypes.RAW_OUTPUT, text: extractText(raw) || JSON.stringify(raw), raw };
}


function isInternalClaudePayload(raw, rawType) {
  if (rawType === 'control_response' || rawType === 'control_cancel_request' || rawType === 'transcript_mirror') return true;
  if (raw && typeof raw === 'object') {
    if (Object.prototype.hasOwnProperty.call(raw, 'hookSpecificOutput')) return true;
    if (Object.prototype.hasOwnProperty.call(raw, 'suppressOutput')) return true;
    if (Object.prototype.hasOwnProperty.call(raw, 'continue') && Object.prototype.hasOwnProperty.call(raw, 'suppressOutput')) return true;
    if (raw.hookEventName || raw.hook_event_name || raw.callback_id) return true;
    if (rawType === 'system' && ['hook_callback', 'session_start', 'session_end'].includes(raw.subtype)) return true;
  }
  return false;
}

function extractText(raw) {
  if (typeof raw.result === 'string') return filterProtocolLeak(raw.result);
  if (typeof raw.text === 'string') return filterProtocolLeak(raw.text);
  if (typeof raw.delta === 'string') return filterProtocolLeak(raw.delta);
  if (typeof raw.content === 'string') return filterProtocolLeak(raw.content);
  if (Array.isArray(raw.content)) return raw.content.map((part) => {
    if (part?.type && part.type !== 'text') return '';
    return filterProtocolLeak(part.text || '');
  }).join('');
  if (raw.message?.content) return extractText(raw.message);
  return '';
}

function filterProtocolLeak(text) {
  if (!text || looksLikeProtocolLeak(text)) return '';
  return text;
}

function looksLikeProtocolLeak(text) {
  const trimmed = String(text).trimStart();
  if (trimmed.startsWith('\\n"')
    || trimmed.includes('\\n\\n## Skill Types')
    || trimmed.includes('\\n\\n## User Instructions')) {
    return true;
  }
  const normalized = trimmed.slice(0, 1400)
    .replace(/\\n/g, '\n')
    .replace(/\\"/g, '"');
  if (normalized.includes('"type":"control_')
    || normalized.includes('"type": "control_')
    || normalized.includes('"suppressOutput"')
    || normalized.includes('"hookSpecificOutput"')
    || normalized.includes('"parent_tool_use_id"')
    || (normalized.includes('"session_id"') && normalized.includes('"message"') && normalized.includes('"role"'))) {
    return true;
  }
  return (normalized.startsWith('{') || normalized.startsWith('"{'))
    && normalized.includes('"type"')
    && normalized.includes('"message"');
}

function assertWorkspacePath(workspacePath) {
  if (!workspacePath || !String(workspacePath).trim()) throw new Error('workspacePath is required');
}

function isTerminalEvent(event) {
  return event?.type === eventTypes.RUN_COMPLETED
    || event?.type === eventTypes.RUN_FAILED
    || event?.type === eventTypes.RUN_CANCELLED;
}

module.exports = {
  ClaudeAdapter,
  parseJsonLines,
  mapClaudeEvent,
  unavailableCapability,
  buildClaudeArgs,
  resolvePermissionMode,
  parsePermissionModes
};
