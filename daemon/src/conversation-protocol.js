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
  TOOL_STARTED: 'tool.started',
  TOOL_OUTPUT: 'tool.output',
  TOOL_COMPLETED: 'tool.completed',
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
    permissionMode: normalizePermissionMode(payload.permissionMode)
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

function stringValue(value) {
  return typeof value === 'string' ? value : '';
}

function badRequest(message) {
  const error = new Error(message);
  error.status = 400;
  error.code = 'BAD_REQUEST';
  return error;
}

module.exports = {
  supportedConversationAdapters,
  conversationStatuses,
  conversationEventTypes,
  normalizeConversationCreate,
  normalizeMessagePayload,
  normalizeQuestionResponse,
  normalizeApprovalDecision
};
