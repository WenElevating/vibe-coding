'use strict';

const supportedConversationAdapters = Object.freeze(['claude', 'codex', 'opencode']);

const conversationStatuses = Object.freeze({
  IDLE: 'idle',
  RUNNING: 'running',
  WAITING_INPUT: 'waiting_input',
  WAITING_APPROVAL: 'waiting_approval',
  INTERRUPTED: 'interrupted',
  COMPLETED: 'completed',
  FAILED: 'failed',
  CANCELLED: 'cancelled',
  EXPIRED: 'expired'
});

const conversationSessionBindings = Object.freeze({
  UNKNOWN: 'unknown',
  CONFIRMED: 'confirmed',
  DRIFTED: 'drifted'
});

const activeConversationStatuses = new Set([
  conversationStatuses.RUNNING,
  conversationStatuses.WAITING_INPUT,
  conversationStatuses.WAITING_APPROVAL
]);

const reusableConversationStatuses = new Set([
  conversationStatuses.IDLE,
  conversationStatuses.CANCELLED,
  conversationStatuses.FAILED,
  conversationStatuses.INTERRUPTED
]);

const terminalConversationStatuses = new Set([
  conversationStatuses.COMPLETED,
  conversationStatuses.EXPIRED
]);

const conversationEventTypes = Object.freeze({
  CONVERSATION_STARTED: 'conversation.started',
  STATUS_CHANGED: 'conversation.status_changed',
  USER_MESSAGE: 'user.message',
  ASSISTANT_THINKING: 'assistant.thinking',
  ASSISTANT_PARTIAL: 'assistant.partial',
  ASSISTANT_MESSAGE: 'assistant.message',
  ASSISTANT_QUESTION: 'assistant.question',
  APPROVAL_REQUESTED: 'approval.requested',
  APPROVAL_RESOLVED: 'approval.resolved',
  SYSTEM_NOTICE: 'system.notice',
  TOOL_STARTED: 'tool.started',
  TOOL_DELTA: 'tool.delta',
  TOOL_OUTPUT: 'tool.output',
  TOOL_COMPLETED: 'tool.completed',
  TASK_PROGRESS_UPDATED: 'task.progress.updated',
  DIFF_SUMMARY: 'diff.summary',
  RUN_ERROR: 'run.error',
  CONVERSATION_COMPLETED: 'conversation.completed',
  CONVERSATION_CANCELLED: 'conversation.cancelled',
  PROTOCOL_WARNING: 'protocol.warning'
});

function normalizeConversationCreate(payload) {
  if (!payload || typeof payload !== 'object') throw badRequest('payload must be an object');
  const workspaceId = stringValue(payload.workspaceId).trim();
  if (!workspaceId) throw badRequest('workspaceId is required');
  const adapter = stringValue(payload.adapter || payload.tool || 'claude').trim();
  if (!supportedConversationAdapters.includes(adapter)) {
    throw badRequest(`unsupported adapter: ${adapter}`);
  }
  return {
    workspaceId,
    adapter,
    model: optionalString(payload.model),
    permissionMode: normalizePermissionMode(payload.permissionMode),
    requestedTools: normalizeStringList(payload.requestedTools),
    requestedToolPolicy: normalizeToolPolicy(payload.requestedToolPolicy),
    resumePolicy: normalizeResumePolicy(payload.resumePolicy),
    systemPromptPolicy: normalizeSystemPromptPolicy(payload.systemPromptPolicy)
  };
}

function normalizeMessagePayload(payload) {
  if (!payload || typeof payload !== 'object') throw badRequest('payload must be an object');
  const text = stringValue(payload.text || payload.prompt).trim();
  if (!text) throw badRequest('text is required');
  return { text };
}

function normalizeQuestionResponse(payload) {
  if (!payload || typeof payload !== 'object') throw badRequest('payload must be an object');
  const questionId = stringValue(payload.questionId).trim();
  const text = stringValue(payload.text).trim();
  if (!questionId) throw badRequest('questionId is required');
  if (!text) throw badRequest('text is required');
  return { questionId, text };
}

function normalizeApprovalDecision(payload) {
  if (!payload || typeof payload !== 'object') throw badRequest('payload must be an object');
  const decision = stringValue(payload.decision).trim();
  if (!['allow', 'deny'].includes(decision)) throw badRequest('decision must be allow or deny');
  return { decision };
}

function normalizePermissionMode(value) {
  if (value == null || value === '') return 'default';
  if (!['default', 'auto'].includes(value)) {
    throw badRequest('permissionMode must be default or auto');
  }
  return value;
}

function normalizeStringList(value) {
  if (!Array.isArray(value)) return [];
  return value.map((item) => stringValue(item).trim()).filter(Boolean);
}

function normalizeToolPolicy(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return { tools: [], allowedTools: [], disallowedTools: [] };
  }
  return {
    tools: normalizeStringList(value.tools),
    allowedTools: normalizeStringList(value.allowedTools),
    disallowedTools: normalizeStringList(value.disallowedTools)
  };
}

function normalizeResumePolicy(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return { type: 'fresh' };
  const type = stringValue(value.type).trim() || 'fresh';
  if (!['fresh', 'continue', 'resume', 'fork'].includes(type)) {
    throw badRequest('resumePolicy.type is invalid');
  }
  const policy = { type };
  const sessionId = stringValue(value.sessionId).trim();
  const name = stringValue(value.name).trim();
  if (sessionId) policy.sessionId = sessionId;
  if (name) policy.name = name;
  return policy;
}

function normalizeSystemPromptPolicy(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return { type: 'none' };
  const type = stringValue(value.type).trim() || 'none';
  if (!['none', 'append'].includes(type)) {
    throw badRequest('systemPromptPolicy.type is invalid');
  }
  const policy = { type };
  const text = stringValue(value.text);
  if (text) policy.text = text;
  return policy;
}

function stringValue(value) {
  return typeof value === 'string' ? value : '';
}

function optionalString(value) {
  const text = stringValue(value).trim();
  return text || null;
}

function badRequest(message) {
  const error = new Error(message);
  error.status = 400;
  error.code = 'BAD_REQUEST';
  return error;
}

function isConversationActiveStatus(status) {
  return activeConversationStatuses.has(status);
}

function isConversationReusableStatus(status) {
  return reusableConversationStatuses.has(status);
}

function isConversationTerminalStatus(status) {
  return terminalConversationStatuses.has(status);
}

module.exports = {
  supportedConversationAdapters,
  conversationStatuses,
  conversationSessionBindings,
  conversationEventTypes,
  normalizeConversationCreate,
  normalizeMessagePayload,
  normalizeQuestionResponse,
  normalizeApprovalDecision,
  isConversationActiveStatus,
  isConversationReusableStatus,
  isConversationTerminalStatus
};
