'use strict';

const { conversationEventTypes } = require('./conversation-protocol');
const {
  buildAdapterUserMessage,
  mapCodexEvent
} = require('./codex-conversation-adapter');

const DEFAULT_CODEX_TOOL_TIMEOUT_SEC = 600;

function buildCodexAppServerThreadStartRequest({
  requestId,
  workspacePath,
  permissionMode = 'default',
  model,
  toolTimeoutSec
} = {}) {
  return {
    id: requestId,
    method: 'thread/start',
    params: compactObject({
      cwd: optionalString(workspacePath),
      approvalPolicy: approvalPolicy(permissionMode),
      approvalsReviewer: 'user',
      sandbox: 'read-only',
      config: buildCodexAppServerConfig(toolTimeoutSec),
      model: optionalString(model)
    })
  };
}

function buildCodexAppServerThreadResumeRequest({
  requestId,
  threadId,
  workspacePath,
  permissionMode = 'default',
  model,
  toolTimeoutSec
} = {}) {
  return {
    id: requestId,
    method: 'thread/resume',
    params: compactObject({
      threadId: requiredString(threadId, 'threadId'),
      cwd: optionalString(workspacePath),
      approvalPolicy: approvalPolicy(permissionMode),
      approvalsReviewer: 'user',
      sandbox: 'read-only',
      config: buildCodexAppServerConfig(toolTimeoutSec),
      model: optionalString(model)
    })
  };
}

function buildCodexAppServerTurnStartRequest({
  requestId,
  threadId,
  clientUserMessageId,
  workspacePath,
  permissionMode = 'default',
  model,
  message,
  prompt,
  imagePaths
} = {}) {
  const userMessage = normalizeTurnUserMessage({ message, prompt, imagePaths });
  return {
    id: requestId,
    method: 'turn/start',
    params: compactObject({
      threadId: requiredString(threadId, 'threadId'),
      clientUserMessageId: optionalString(clientUserMessageId),
      input: buildAppServerUserInput(userMessage),
      cwd: optionalString(workspacePath),
      approvalPolicy: approvalPolicy(permissionMode),
      approvalsReviewer: 'user',
      sandboxPolicy: buildWorkspaceWriteSandboxPolicy(workspacePath),
      model: optionalString(model)
    })
  };
}

function buildCodexAppServerTurnInterruptRequest({ requestId, threadId, turnId } = {}) {
  return {
    id: requestId,
    method: 'turn/interrupt',
    params: {
      threadId: requiredString(threadId, 'threadId'),
      turnId: requiredString(turnId, 'turnId')
    }
  };
}

function mapCodexAppServerNotification(message, options = {}) {
  if (!plainObject(message) || typeof message.method !== 'string') return null;
  if (message.method === 'item/commandExecution/outputDelta') {
    const params = plainObject(message.params) ? message.params : {};
    const text = stringValue(params.delta);
    if (!text) return null;
    return {
      type: conversationEventTypes.TOOL_DELTA,
      toolUseId: stringValue(params.itemId) || null,
      toolName: 'command_execution',
      text,
      raw: message
    };
  }
  if (message.method === 'item/agentMessage/delta') {
    const params = plainObject(message.params) ? message.params : {};
    const text = stringValue(params.delta || params.text);
    return text
      ? { type: conversationEventTypes.ASSISTANT_PARTIAL, text, raw: message }
      : null;
  }
  if (message.method === 'turn/completed') {
    const event = mapAppServerTurnCompleted(message);
    if (event) return event;
  }
  const raw = mapCodexAppServerNotificationToExecEvent(message);
  if (!raw) return null;
  return mapCodexEvent(raw, options);
}

function mapCodexAppServerNotificationToExecEvent(message) {
  const params = plainObject(message.params) ? message.params : {};
  switch (message.method) {
    case 'thread/started':
      return {
        type: 'thread.started',
        thread_id: stringValue(params.thread?.id) || stringValue(params.threadId)
      };
    case 'turn/started':
      return { type: 'turn.started' };
    case 'turn/completed':
      return { type: 'turn.completed', usage: params.usage || null };
    case 'turn/plan/updated':
      return mapTurnPlanUpdated(params);
    case 'item/started':
      return mapLifecycleItem('item.started', params);
    case 'item/completed':
      return mapLifecycleItem('item.completed', params);
    case 'error':
      return {
        type: 'error',
        message: stringValue(params.message) || stringValue(message.message) || 'Codex app-server error',
        raw: message
      };
    default:
      return {
        type: message.method,
        params,
        raw: message
      };
  }
}

function mapAppServerTurnCompleted(message) {
  const params = plainObject(message.params) ? message.params : {};
  const turn = plainObject(params.turn) ? params.turn : {};
  if (turn.status === 'interrupted') {
    return {
      type: conversationEventTypes.CONVERSATION_CANCELLED,
      raw: message
    };
  }
  if (turn.status === 'failed') {
    return mapCodexEvent({
      type: 'turn.failed',
      error: turn.error || { message: 'Codex turn failed' }
    });
  }
  return null;
}

function mapLifecycleItem(type, params) {
  const item = normalizeAppServerItem(plainObject(params.item) ? params.item : null);
  if (!item) return null;
  return { type, item };
}

function normalizeAppServerItem(item) {
  if (!item || typeof item.type !== 'string') return null;
  if (item.type === 'agentMessage') {
    return {
      ...item,
      type: 'agent_message',
      text: stringValue(item.text)
    };
  }
  if (item.type === 'commandExecution') {
    return {
      ...item,
      type: 'command_execution',
      status: normalizeAppServerStatus(item.status),
      aggregated_output: item.aggregatedOutput == null ? '' : String(item.aggregatedOutput),
      exit_code: Number.isInteger(item.exitCode) ? item.exitCode : null
    };
  }
  if (item.type === 'fileChange') {
    return {
      ...item,
      type: 'file_change',
      status: normalizeAppServerStatus(item.status)
    };
  }
  if (item.type === 'mcpToolCall') {
    return {
      ...item,
      type: 'mcp_tool_call',
      status: normalizeAppServerStatus(item.status)
    };
  }
  return {
    ...item,
    type: item.type
  };
}

function mapTurnPlanUpdated(params) {
  if (!Array.isArray(params.plan) || params.plan.length === 0) return null;
  return {
    type: 'item.updated',
    item: {
      id: stringValue(params.turnId) || stringValue(params.threadId) || 'codex_plan',
      type: 'todo_list',
      todos: params.plan.map((item) => ({
        content: stringValue(item?.step),
        status: normalizeAppServerStatus(item?.status)
      }))
    }
  };
}

function buildAppServerUserInput(userMessage) {
  const input = [];
  const prompt = stringValue(userMessage.prompt);
  if (prompt) {
    input.push({
      type: 'text',
      text: prompt,
      text_elements: []
    });
  }
  for (const imagePath of Array.isArray(userMessage.imagePaths) ? userMessage.imagePaths : []) {
    const path = optionalString(imagePath);
    if (path) input.push({ type: 'localImage', path });
  }
  return input;
}

function normalizeTurnUserMessage({ message, prompt, imagePaths }) {
  if (typeof message === 'string') return { prompt: message, imagePaths: [] };
  if (plainObject(message)) return buildAdapterUserMessage(message);
  return {
    prompt: stringValue(prompt),
    imagePaths: Array.isArray(imagePaths) ? imagePaths.map(String).filter(Boolean) : []
  };
}

function buildWorkspaceWriteSandboxPolicy(workspacePath) {
  const root = optionalString(workspacePath);
  if (!root) return undefined;
  return {
    type: 'workspaceWrite',
    writableRoots: [root],
    networkAccess: false,
    excludeTmpdirEnvVar: false,
    excludeSlashTmp: false
  };
}

function buildCodexAppServerConfig(toolTimeoutSec) {
  const normalized = normalizeCodexToolTimeoutSec(toolTimeoutSec);
  return normalized === null ? undefined : { tool_timeout_sec: normalized };
}

function approvalPolicy(permissionMode) {
  return permissionMode === 'auto' ? 'never' : 'on-request';
}

function normalizeCodexToolTimeoutSec(value) {
  if (value === null || value === false) return null;
  if (value === undefined || value === '') return DEFAULT_CODEX_TOOL_TIMEOUT_SEC;
  const numeric = Number(value);
  if (!Number.isFinite(numeric) || numeric <= 0) return DEFAULT_CODEX_TOOL_TIMEOUT_SEC;
  return Math.floor(numeric);
}

function normalizeAppServerStatus(status) {
  return status === 'inProgress' ? 'in_progress' : stringValue(status);
}

function requiredString(value, name) {
  const text = optionalString(value);
  if (!text) throw new Error(`${name} is required`);
  return text;
}

function optionalString(value) {
  const text = stringValue(value).trim();
  return text || undefined;
}

function stringValue(value) {
  return typeof value === 'string' ? value : '';
}

function compactObject(input) {
  const output = {};
  for (const [key, value] of Object.entries(input)) {
    if (value === undefined || value === null) continue;
    output[key] = value;
  }
  return output;
}

function plainObject(value) {
  return !!value && typeof value === 'object' && !Array.isArray(value);
}

module.exports = {
  buildCodexAppServerThreadResumeRequest,
  buildCodexAppServerThreadStartRequest,
  buildCodexAppServerTurnInterruptRequest,
  buildCodexAppServerTurnStartRequest,
  mapCodexAppServerNotification,
  mapCodexAppServerNotificationToExecEvent
};
