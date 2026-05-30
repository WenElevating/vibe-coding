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
  MODEL_CHANGED: 'conversation.model_changed',
  USER_MESSAGE: 'user.message',
  ASSISTANT_THINKING: 'assistant.thinking',
  ASSISTANT_PARTIAL: 'assistant.partial',
  ASSISTANT_MESSAGE: 'assistant.message',
  ASSISTANT_QUESTION: 'assistant.question',
  APPROVAL_REQUESTED: 'approval.requested',
  APPROVAL_RESOLVED: 'approval.resolved',
  BLOCKING_REQUEST_CANCELLED: 'blocking.request_cancelled',
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
    systemPromptPolicy: normalizeSystemPromptPolicy(payload.systemPromptPolicy),
    claudeOptions: normalizeClaudeOptions(payload.claudeOptions)
  };
}

function normalizeConversationModelUpdate(payload) {
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
    throw badRequest('payload must be an object');
  }
  if (!Object.prototype.hasOwnProperty.call(payload, 'model')) {
    throw badRequest('model is required');
  }
  if (payload.model == null) return { model: null };
  if (typeof payload.model !== 'string') {
    throw badRequest('model must be a string or null');
  }
  const model = payload.model.trim();
  return { model: model || null };
}

function normalizeMessagePayload(payload) {
  if (!payload || typeof payload !== 'object') throw badRequest('payload must be an object');
  const text = stringValue(payload.text || payload.prompt).trim();
  const attachments = Array.isArray(payload.attachments) ? payload.attachments : [];
  const clientMessageId = optionalString(payload.clientMessageId);
  const capabilityVersion = optionalString(payload.capabilityVersion);
  if (!text && attachments.length === 0) throw badRequest('text or attachments are required');
  if (attachments.length === 0 && !text) throw badRequest('text is required');
  return { text, clientMessageId, capabilityVersion, attachments };
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
  const normalized = { decision };
  if (Object.prototype.hasOwnProperty.call(payload, 'updatedInput')) {
    if (!plainObject(payload.updatedInput)) throw badRequest('updatedInput must be an object');
    normalized.updatedInput = payload.updatedInput;
  }
  if (Object.prototype.hasOwnProperty.call(payload, 'updatedPermissions')) {
    if (!Array.isArray(payload.updatedPermissions)) throw badRequest('updatedPermissions must be an array');
    normalized.updatedPermissions = payload.updatedPermissions.filter(plainObject);
  }
  if (decision === 'deny') {
    normalized.interrupt = Object.prototype.hasOwnProperty.call(payload, 'interrupt')
      ? payload.interrupt === true
      : true;
  } else if (Object.prototype.hasOwnProperty.call(payload, 'interrupt')) {
    normalized.interrupt = payload.interrupt === true;
  }
  return normalized;
}

function normalizePermissionModeUpdate(payload) {
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) throw badRequest('payload must be an object');
  if (!Object.prototype.hasOwnProperty.call(payload, 'permissionMode')) throw badRequest('permissionMode is required');
  return { permissionMode: normalizePermissionMode(payload.permissionMode) };
}

function normalizeConversationControl(payload) {
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) throw badRequest('payload must be an object');
  const action = stringValue(payload.action).trim();
  if (!action) throw badRequest('action is required');
  return {
    action,
    ...(Object.prototype.hasOwnProperty.call(payload, 'model') ? { model: payload.model == null ? null : optionalString(payload.model) } : {}),
    ...(Object.prototype.hasOwnProperty.call(payload, 'permissionMode') ? { permissionMode: normalizePermissionMode(payload.permissionMode) } : {}),
    ...(Object.prototype.hasOwnProperty.call(payload, 'name') ? { name: optionalString(payload.name) } : {}),
    ...(Object.prototype.hasOwnProperty.call(payload, 'enabled') ? { enabled: payload.enabled === true } : {}),
    ...(Object.prototype.hasOwnProperty.call(payload, 'taskId') ? { taskId: optionalString(payload.taskId) } : {})
  };
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

function normalizeClaudeOptions(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return {};
  const options = {};
  copyStringListOption(options, value, 'tools');
  copyStringListOption(options, value, 'allowedTools');
  copyStringListOption(options, value, 'disallowedTools');
  copyStringOption(options, value, 'systemPrompt');
  copyStringOption(options, value, 'systemPromptFile');
  copyStringOption(options, value, 'appendSystemPrompt');
  copyIntegerOption(options, value, 'maxTurns');
  copyNumberOption(options, value, 'maxBudgetUsd');
  copyNumberOption(options, value, 'taskBudgetTotal');
  copyStringOption(options, value, 'fallbackModel');
  copyStringListOption(options, value, 'betas');
  copyStringOption(options, value, 'settings');
  copyStringListOption(options, value, 'addDirs');
  if (plainObject(value.mcpConfig) || typeof value.mcpConfig === 'string') options.mcpConfig = value.mcpConfig;
  if (value.forkSession === true) options.forkSession = true;
  copyStringListOption(options, value, 'settingSources');
  if (Array.isArray(value.skills)) options.skills = normalizeStringList(value.skills);
  else if (value.skills === 'all') options.skills = 'all';
  if (plainObject(value.sandbox)) options.sandbox = value.sandbox;
  if (Array.isArray(value.plugins)) {
    options.plugins = value.plugins
      .filter(plainObject)
      .map((plugin) => ({ type: stringValue(plugin.type).trim(), path: stringValue(plugin.path).trim() }))
      .filter((plugin) => plugin.type && plugin.path);
  }
  if (plainObject(value.extraArgs)) {
    options.extraArgs = {};
    for (const [key, raw] of Object.entries(value.extraArgs)) {
      const flag = stringValue(key).trim();
      if (!/^[a-zA-Z0-9][a-zA-Z0-9_-]*$/.test(flag)) continue;
      options.extraArgs[flag] = raw == null ? null : String(raw);
    }
  }
  if (plainObject(value.thinking)) options.thinking = normalizeThinking(value.thinking);
  copyIntegerOption(options, value, 'maxThinkingTokens');
  copyStringOption(options, value, 'effort');
  if (plainObject(value.outputFormat)) options.outputFormat = value.outputFormat;
  if (plainObject(value.jsonSchema)) options.outputFormat = { type: 'json_schema', schema: value.jsonSchema };
  return options;
}

function normalizeThinking(value) {
  const type = stringValue(value.type).trim();
  if (type === 'enabled') return { type, budgetTokens: Number(value.budgetTokens || value.budget_tokens || 0) };
  if (type === 'adaptive' || type === 'disabled') return { type };
  return {};
}

function copyStringOption(target, source, key) {
  const value = stringValue(source[key]).trim();
  if (value) target[key] = value;
}

function copyStringListOption(target, source, key) {
  const value = normalizeStringList(source[key]);
  if (value.length > 0 || Array.isArray(source[key])) target[key] = value;
}

function copyIntegerOption(target, source, key) {
  if (!Object.prototype.hasOwnProperty.call(source, key)) return;
  const value = Number(source[key]);
  if (Number.isSafeInteger(value) && value > 0) target[key] = value;
}

function copyNumberOption(target, source, key) {
  if (!Object.prototype.hasOwnProperty.call(source, key)) return;
  const value = Number(source[key]);
  if (Number.isFinite(value) && value >= 0) target[key] = value;
}

function plainObject(value) {
  return !!value && typeof value === 'object' && !Array.isArray(value);
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
  normalizeConversationModelUpdate,
  normalizePermissionModeUpdate,
  normalizeConversationControl,
  normalizeMessagePayload,
  normalizeQuestionResponse,
  normalizeApprovalDecision,
  isConversationActiveStatus,
  isConversationReusableStatus,
  isConversationTerminalStatus
};
