'use strict';

const unavailableCapabilities = Object.freeze({
  longLivedProcess: false,
  waitingInput: false,
  waitingApproval: false,
  resume: false,
  partialOutput: false,
  toolEvents: false,
  mobileApprovalCallbacks: false,
  approval: Object.freeze({
    mobileCallbacks: false,
    scopes: Object.freeze([]),
    supportsCancel: false,
    denyBehaviors: Object.freeze([])
  }),
  attachments: Object.freeze({
    image: 'unsupported',
    textDocument: 'unsupported',
    pdf: 'unsupported'
  })
});

const selectableCapabilities = Object.freeze({
  longLivedProcess: true,
  waitingInput: false,
  waitingApproval: true,
  resume: true,
  partialOutput: true,
  toolEvents: true,
  mobileApprovalCallbacks: true,
  approval: Object.freeze({
    mobileCallbacks: true,
    scopes: Object.freeze(['once', 'session']),
    supportsCancel: true,
    denyBehaviors: Object.freeze(['interrupt', 'continue'])
  }),
  attachments: Object.freeze({
    image: 'native',
    textDocument: 'text_extract',
    pdf: 'unsupported'
  })
});

function buildCodexAppServerAvailability(input = {}) {
  const enabled = input.enabled === true;
  const installed = enabled && input.installed === true;
  const protocolCompatible = installed && input.protocolCompatible === true;
  const transportHealthy = protocolCompatible && input.transportHealthy === true;
  const selectable = enabled && installed && protocolCompatible && transportHealthy;
  return {
    adapter: 'codex-app-server',
    installed,
    protocolCompatible,
    transportHealthy,
    selectable,
    lastProbeAt: normalizeTimestamp(input.lastProbeAt),
    unavailableReason: selectable ? null : unavailableReason(input, {
      enabled,
      installed,
      protocolCompatible,
      transportHealthy
    }),
    effectiveCapabilities: cloneCapabilities(selectable ? selectableCapabilities : unavailableCapabilities)
  };
}

function unavailableReason(input, status) {
  if (!status.enabled) return 'disabled';
  if (!status.installed) return 'not_installed';
  if (!status.protocolCompatible) return sanitizeReason(input.unavailableReason) || 'protocol_incompatible';
  if (!status.transportHealthy) return sanitizeReason(input.unavailableReason) || 'transport_unhealthy';
  return sanitizeReason(input.unavailableReason) || 'unavailable';
}

function normalizeTimestamp(value) {
  if (typeof value !== 'string') return null;
  const timestamp = Date.parse(value);
  return Number.isFinite(timestamp) ? new Date(timestamp).toISOString() : null;
}

function sanitizeReason(value) {
  if (typeof value !== 'string') return null;
  const sanitized = value
    .replace(/sk-[A-Za-z0-9_-]+/g, '<REDACTED_SECRET>')
    .replace(/[A-Za-z]:\\Users\\[^\\\s]+/g, '<USER_HOME>')
    .replace(/Bearer\s+[A-Za-z0-9._-]+/gi, 'Bearer <REDACTED_SECRET>')
    .replace(/\s+/g, ' ')
    .trim();
  return sanitized || null;
}

function cloneCapabilities(capabilities) {
  return {
    longLivedProcess: capabilities.longLivedProcess,
    waitingInput: capabilities.waitingInput,
    waitingApproval: capabilities.waitingApproval,
    resume: capabilities.resume,
    partialOutput: capabilities.partialOutput,
    toolEvents: capabilities.toolEvents,
    mobileApprovalCallbacks: capabilities.mobileApprovalCallbacks,
    approval: {
      mobileCallbacks: capabilities.approval.mobileCallbacks,
      scopes: [...capabilities.approval.scopes],
      supportsCancel: capabilities.approval.supportsCancel,
      denyBehaviors: [...capabilities.approval.denyBehaviors]
    },
    attachments: {
      image: capabilities.attachments.image,
      textDocument: capabilities.attachments.textDocument,
      pdf: capabilities.attachments.pdf
    }
  };
}

module.exports = {
  buildCodexAppServerAvailability
};
