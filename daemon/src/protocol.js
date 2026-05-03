'use strict';

const PROTOCOL_VERSION = 'agent-control.v1';
const SUPPORTED_TOOLS = Object.freeze(['claude', 'codex', 'opencode', 'synthetic-jsonl', 'synthetic-text', 'synthetic-error', 'synthetic-slow']);

const eventTypes = Object.freeze({
  RUN_STARTED: 'run.started',
  RUN_QUEUED: 'run.queued',
  RUN_DEQUEUED: 'run.dequeued',
  RUN_BLOCKED: 'run.blocked',
  RUN_CANCELLING: 'run.cancelling',
  ASSISTANT_QUESTION: 'assistant.question',
  ASSISTANT_DELTA: 'assistant.delta',
  TOOL_STARTED: 'tool.started',
  TOOL_OUTPUT: 'tool.output',
  APPROVAL_REQUIRED: 'approval.required',
  APPROVAL_RESPONDED: 'approval.responded',
  DIFF_SUMMARY: 'diff.summary',
  ADAPTER_ERROR: 'adapter.error',
  ADAPTER_PARSE_ERROR: 'adapter.parse_error',
  ADAPTER_RAW_STDOUT: 'adapter.raw_stdout',
  ADAPTER_RAW_STDERR: 'adapter.raw_stderr',
  QUEUE_UPDATED: 'queue.updated',
  GIT_STATUS_UPDATED: 'git.status.updated',
  COMMAND_TEMPLATE_STARTED: 'command_template.started',
  COMMAND_TEMPLATE_OUTPUT: 'command_template.output',
  COMMAND_TEMPLATE_COMPLETED: 'command_template.completed',
  COMMAND_TEMPLATE_FAILED: 'command_template.failed',
  RUN_COMPLETED: 'run.completed',
  RUN_FAILED: 'run.failed',
  RUN_CANCELLED: 'run.cancelled',
  RAW_OUTPUT: 'raw.output'
});

const errorCodes = Object.freeze({
  RAW_COMMAND_REJECTED: 'RAW_COMMAND_REJECTED',
  RAW_CWD_REJECTED: 'RAW_CWD_REJECTED',
  RAW_ARGS_REJECTED: 'RAW_ARGS_REJECTED',
  WORKSPACE_BUSY: 'WORKSPACE_BUSY',
  WORKSPACE_NOT_FOUND: 'WORKSPACE_NOT_FOUND',
  WORKSPACE_ACCESS_DENIED: 'WORKSPACE_ACCESS_DENIED',
  COMMAND_TEMPLATE_NOT_FOUND: 'COMMAND_TEMPLATE_NOT_FOUND',
  COMMAND_TEMPLATE_REQUIRES_APPROVAL: 'COMMAND_TEMPLATE_REQUIRES_APPROVAL',
  ADAPTER_INVOCATION_FAILED: 'ADAPTER_INVOCATION_FAILED',
  ADAPTER_PARSE_ERROR: 'ADAPTER_PARSE_ERROR',
  GIT_NOT_REPOSITORY: 'GIT_NOT_REPOSITORY',
  GIT_DIFF_TOO_LARGE: 'GIT_DIFF_TOO_LARGE',
  TOKEN_REVOKED: 'TOKEN_REVOKED',
  DAEMON_UNHEALTHY: 'DAEMON_UNHEALTHY',
  DAEMON_VERSION_MISMATCH: 'DAEMON_VERSION_MISMATCH',
  SCHEMA_MIGRATION_FAILED: 'SCHEMA_MIGRATION_FAILED',
  DIAGNOSTIC_EXPORT_FAILED: 'DIAGNOSTIC_EXPORT_FAILED',
  DIAGNOSTIC_REDACTION_FAILED: 'DIAGNOSTIC_REDACTION_FAILED',
  DEV_API_DISABLED: 'DEV_API_DISABLED',
  RELEASE_MODE_REQUIRED: 'RELEASE_MODE_REQUIRED',
  MOBILE_VERSION_UNSUPPORTED: 'MOBILE_VERSION_UNSUPPORTED',
  PAIRING_CODE_EXPIRED: 'PAIRING_CODE_EXPIRED',
  PAIRING_DAEMON_MISMATCH: 'PAIRING_DAEMON_MISMATCH',
  ADAPTER_SETUP_REQUIRED: 'ADAPTER_SETUP_REQUIRED',
  SYNTHETIC_ADAPTER_HIDDEN: 'SYNTHETIC_ADAPTER_HIDDEN'
});

function envelope(type, payload = {}, protocol = PROTOCOL_VERSION) {
  return { protocol, type, payload };
}

function assertNoV1TerminalRequest(payload) {
  if (!payload || typeof payload !== 'object') return;
  const forbidden = [
    ['cmd', errorCodes.RAW_COMMAND_REJECTED],
    ['command', errorCodes.RAW_COMMAND_REJECTED],
    ['shell', errorCodes.RAW_COMMAND_REJECTED],
    ['cwd', errorCodes.RAW_CWD_REJECTED],
    ['args', errorCodes.RAW_ARGS_REJECTED],
    ['argv', errorCodes.RAW_ARGS_REJECTED],
    ['pty', errorCodes.RAW_COMMAND_REJECTED],
    ['terminalSession', errorCodes.RAW_COMMAND_REJECTED],
    ['terminalInput', errorCodes.RAW_COMMAND_REJECTED]
  ];
  const found = forbidden.find(([key]) => Object.prototype.hasOwnProperty.call(payload, key));
  if (found) {
    const error = new Error(`V1.2 rejects unrestricted terminal/shell field: ${found[0]}`);
    error.code = found[1];
    error.status = 400;
    error.recoverable = true;
    error.userAction = 'Use a configured command template or adapter run instead.';
    throw error;
  }
}

function validateRunCreate(payload) {
  assertNoV1TerminalRequest(payload);
  if (!payload || typeof payload !== 'object') throw badRequest('payload must be an object');
  if (!SUPPORTED_TOOLS.includes(payload.tool)) throw badRequest(`tool must be one of: ${SUPPORTED_TOOLS.join(', ')}`);
  if (!payload.workspaceId || typeof payload.workspaceId !== 'string') throw badRequest('workspaceId is required');
  if (!payload.prompt || typeof payload.prompt !== 'string') throw badRequest('prompt is required');
  return {
    tool: payload.tool,
    workspaceId: payload.workspaceId,
    prompt: payload.prompt,
    sessionId: typeof payload.sessionId === 'string' && payload.sessionId.trim() ? payload.sessionId.trim() : null,
    permissionMode: normalizePermissionMode(payload.permissionMode),
    shortcutId: payload.shortcutId || null,
    queuePolicy: payload.queuePolicy || 'workspace-write'
  };
}


function normalizePermissionMode(value) {
  if (value == null || value === '') return 'default';
  if (!['default', 'auto'].includes(value)) throw badRequest('permissionMode must be default or auto');
  return value;
}

function normalizeAdapterError(adapter, error) {
  return {
    adapter,
    code: error.code || errorCodes.ADAPTER_INVOCATION_FAILED,
    message: error.message || String(error),
    recoverable: error.recoverable !== false,
    userAction: error.userAction || error.actionable || `Check ${adapter} installation and settings.`
  };
}

function badRequest(message) {
  const error = new Error(message);
  error.status = 400;
  error.code = 'BAD_REQUEST';
  return error;
}

module.exports = {
  PROTOCOL_VERSION,
  SUPPORTED_TOOLS,
  eventTypes,
  errorCodes,
  envelope,
  assertNoV1TerminalRequest,
  validateRunCreate,
  normalizeAdapterError
};

