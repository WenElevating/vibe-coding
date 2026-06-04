'use strict';

const { CODEX_APP_SERVER_CAPABILITY_MATRIX } = require('./capability-matrix');

function buildCodexAppServerRouteCapabilities(rows = CODEX_APP_SERVER_CAPABILITY_MATRIX) {
  return rows
    .filter((row) => row.daemonOwner === 'server route' || row.mobileStatus === 'planned' || row.mobileStatus === 'consumed')
    .map((row) => ({
      method: row.method,
      group: routeGroupForMethod(row.method),
      localStatus: row.localStatus,
      mobileStatus: row.mobileStatus,
      risk: row.risk,
      readOnly: row.risk === 'none' || row.risk === 'read' || row.risk === 'account',
      requiresApproval: ['write', 'process', 'network', 'permission'].includes(row.risk),
      source: 'capability-matrix'
    }));
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
  routeGroupForMethod
};
