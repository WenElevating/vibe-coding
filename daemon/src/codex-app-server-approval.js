'use strict';

const { conversationEventTypes } = require('./conversation-protocol');

const CODEX_APP_SERVER_APPROVAL_CAPABILITY = Object.freeze({
  mobileCallbacks: true,
  scopes: ['session'],
  supportsCancel: true,
  denyBehaviors: ['interrupt', 'continue']
});

const methods = Object.freeze({
  COMMAND: 'item/commandExecution/requestApproval',
  FILE_CHANGE: 'item/fileChange/requestApproval',
  PERMISSIONS: 'item/permissions/requestApproval'
});

function mapCodexAppServerApprovalRequest(message) {
  if (!plainObject(message) || message.id == null || typeof message.method !== 'string') return null;
  const params = plainObject(message.params) ? message.params : {};
  if (message.method === methods.COMMAND) return mapCommandApproval(message.id, params);
  if (message.method === methods.FILE_CHANGE) return mapFileChangeApproval(message.id, params);
  if (message.method === methods.PERMISSIONS) return mapPermissionsApproval(message.id, params);
  return null;
}

function buildCodexAppServerApprovalResponse(context, response) {
  if (!plainObject(context) || context.requestId == null || typeof context.method !== 'string') {
    throw new Error('Codex app-server approval context is required');
  }
  const approval = normalizeApprovalResponse(response);
  if (context.method === methods.PERMISSIONS) {
    return {
      id: context.requestId,
      result: buildPermissionsResult(context, approval)
    };
  }
  return {
    id: context.requestId,
    result: {
      decision: buildDecisionResult(context, approval)
    }
  };
}

function mapCommandApproval(requestId, params) {
  const decisionNames = normalizeDecisionNames(params.availableDecisions);
  const approvalId = stringValue(params.approvalId) || stringValue(params.itemId) || String(requestId);
  const command = stringValue(params.command);
  const reason = stringValue(params.reason);
  const cwd = stringValue(params.cwd);
  const event = {
    type: conversationEventTypes.APPROVAL_REQUESTED,
    approvalId,
    toolName: 'Shell',
    toolUseId: stringValue(params.itemId) || approvalId,
    input: compactObject({ command, cwd, reason }),
    summary: command || reason || 'Command approval requested',
    approvalOptions: compactObject({
      kind: 'command',
      supportsSessionScope: decisionAvailable(decisionNames, 'acceptForSession', false),
      supportsCancel: decisionAvailable(decisionNames, 'cancel', false),
      denyBehavior: decisionAvailable(decisionNames, 'decline', true) ? 'continue' : 'interrupt',
      command,
      cwd,
      reason,
      proposedPermissions: plainObject(params.additionalPermissions) ? params.additionalPermissions : undefined,
      proposedExecPolicyAmendment: Array.isArray(params.proposedExecpolicyAmendment)
        ? params.proposedExecpolicyAmendment
        : undefined
    })
  };
  return {
    context: {
      method: methods.COMMAND,
      requestId,
      approvalId,
      availableDecisionNames: decisionNames
    },
    event
  };
}

function mapFileChangeApproval(requestId, params) {
  const decisionNames = normalizeDecisionNames(params.availableDecisions);
  const approvalId = stringValue(params.itemId) || String(requestId);
  const reason = stringValue(params.reason);
  const event = {
    type: conversationEventTypes.APPROVAL_REQUESTED,
    approvalId,
    toolName: 'apply_patch',
    toolUseId: approvalId,
    input: compactObject({ reason }),
    summary: reason || 'File change approval requested',
    approvalOptions: compactObject({
      kind: 'file_change',
      supportsSessionScope: decisionAvailable(decisionNames, 'acceptForSession', false),
      supportsCancel: decisionAvailable(decisionNames, 'cancel', false),
      denyBehavior: decisionAvailable(decisionNames, 'decline', true) ? 'continue' : 'interrupt',
      reason
    })
  };
  return {
    context: {
      method: methods.FILE_CHANGE,
      requestId,
      approvalId,
      availableDecisionNames: decisionNames
    },
    event
  };
}

function mapPermissionsApproval(requestId, params) {
  const approvalId = stringValue(params.itemId) || String(requestId);
  const reason = stringValue(params.reason);
  const cwd = stringValue(params.cwd);
  const requestedPermissions = plainObject(params.permissions) ? params.permissions : {};
  const event = {
    type: conversationEventTypes.APPROVAL_REQUESTED,
    approvalId,
    toolName: 'request_permissions',
    toolUseId: approvalId,
    input: compactObject({ cwd, reason, permissions: requestedPermissions }),
    summary: reason || 'Permission approval requested',
    approvalOptions: compactObject({
      kind: 'permissions',
      supportsSessionScope: true,
      supportsCancel: false,
      denyBehavior: 'continue',
      cwd,
      reason,
      proposedPermissions: requestedPermissions
    })
  };
  return {
    context: {
      method: methods.PERMISSIONS,
      requestId,
      approvalId,
      requestedPermissions
    },
    event
  };
}

function buildDecisionResult(context, approval) {
  const decisions = Array.isArray(context.availableDecisionNames) ? context.availableDecisionNames : [];
  if (approval.decision === 'allow') {
    if (approval.scope === 'session' && decisionAvailable(decisions, 'acceptForSession', true)) {
      return 'acceptForSession';
    }
    if (decisionAvailable(decisions, 'accept', true)) return 'accept';
    if (decisionAvailable(decisions, 'acceptForSession', false)) return 'acceptForSession';
    return 'accept';
  }
  if (approval.decision === 'cancel') {
    return decisionAvailable(decisions, 'cancel', false) ? 'cancel' : 'decline';
  }
  const interrupt = approval.interrupt === true;
  if (interrupt && decisionAvailable(decisions, 'cancel', false)) return 'cancel';
  if (decisionAvailable(decisions, 'decline', true)) return 'decline';
  return 'cancel';
}

function buildPermissionsResult(context, approval) {
  if (approval.decision !== 'allow') {
    return {
      permissions: {},
      scope: 'turn'
    };
  }
  return {
    permissions: plainObject(context.requestedPermissions) ? context.requestedPermissions : {},
    scope: approval.scope === 'session' ? 'session' : 'turn'
  };
}

function normalizeApprovalResponse(response) {
  const value = typeof response === 'string' ? { decision: response } : response;
  if (!plainObject(value)) throw new Error('approval response must be an object');
  const decision = stringValue(value.decision);
  if (!['allow', 'deny', 'cancel'].includes(decision)) {
    throw new Error('approval decision must be allow, deny, or cancel');
  }
  return {
    decision,
    scope: value.scope === 'session' ? 'session' : 'once',
    interrupt: value.interrupt === true
  };
}

function normalizeDecisionNames(decisions) {
  if (!Array.isArray(decisions)) return [];
  return decisions.map(decisionName).filter(Boolean);
}

function decisionName(value) {
  if (typeof value === 'string') return value;
  if (!plainObject(value)) return null;
  const [key] = Object.keys(value);
  return key || null;
}

function decisionAvailable(decisions, name, fallback) {
  return decisions.length === 0 ? fallback : decisions.includes(name);
}

function compactObject(input) {
  const output = {};
  for (const [key, value] of Object.entries(input)) {
    if (value === undefined || value === null) continue;
    if (typeof value === 'string' && value.trim() === '') continue;
    output[key] = value;
  }
  return output;
}

function stringValue(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function plainObject(value) {
  return !!value && typeof value === 'object' && !Array.isArray(value);
}

module.exports = {
  CODEX_APP_SERVER_APPROVAL_CAPABILITY,
  CODEX_APP_SERVER_APPROVAL_METHODS: methods,
  buildCodexAppServerApprovalResponse,
  mapCodexAppServerApprovalRequest
};
