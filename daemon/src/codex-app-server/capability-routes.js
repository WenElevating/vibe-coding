'use strict';

const { CODEX_APP_SERVER_CAPABILITY_MATRIX } = require('./capability-matrix');

function buildCodexAppServerRouteCapabilities(rows = CODEX_APP_SERVER_CAPABILITY_MATRIX) {
  return rows
    .filter((row) => row.daemonOwner === 'server route' && row.direction === 'request' && row.testRequirement === 'route test')
    .map((row) => ({
      method: row.method,
      group: routeGroupForMethod(row.method),
      localStatus: row.localStatus,
      mobileStatus: row.mobileStatus,
      risk: row.risk,
      readOnly: isReadOnlyCapability(row),
      requiresApproval: requiresCapabilityApproval(row),
      source: 'capability-matrix'
    }));
}

function isReadOnlyCapability(row) {
  if (row.risk === 'none' || row.risk === 'read') return true;
  if (row.risk === 'account') return isAccountReadMethod(row.method);
  return false;
}

function requiresCapabilityApproval(row) {
  if (row.localStatus === 'diagnostic-only') return false;
  if (row.risk === 'account') return !isAccountReadMethod(row.method);
  return ['write', 'process', 'network', 'permission'].includes(row.risk);
}

function isAccountReadMethod(method) {
  const value = String(method || '');
  return value === 'account/read' || value === 'account/rateLimits/read' || value.endsWith('/read');
}

function routeGroupForMethod(method) {
  const value = String(method || '');
  if (value.startsWith('thread/')) return 'history';
  if (value.startsWith('model/') || value.startsWith('mcpServer/') || value.startsWith('skills/') || value.startsWith('plugin/') || value.startsWith('app/')) return 'discovery';
  if (value.startsWith('account/')) return 'account';
  if (value.startsWith('fs/') || value.startsWith('process/') || value.startsWith('command/') || value.startsWith('remoteControl/')) return 'high-risk';
  return 'other';
}

module.exports = {
  buildCodexAppServerRouteCapabilities,
  isAccountReadMethod,
  isReadOnlyCapability,
  requiresCapabilityApproval,
  routeGroupForMethod
};
