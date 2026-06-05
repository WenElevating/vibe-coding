'use strict';

function recordCodexAppServerAudit(auditLog, event, details) {
  if (!auditLog || typeof auditLog.record !== 'function') return;
  auditLog.record(`codex_app_server.${event}`, {
    timestamp: new Date().toISOString(),
    method: details.method,
    workspaceId: details.workspaceId || null,
    threadId: details.threadId || null,
    deviceId: details.deviceId || null,
    risk: details.risk || null,
    decision: details.decision || null,
    result: details.result || (details.ok === true ? 'success' : 'failure'),
    errorCode: details.errorCode || null,
    downstreamStatus: details.downstreamStatus || null,
    correlationId: details.correlationId || null
  });
}

module.exports = { recordCodexAppServerAudit };
