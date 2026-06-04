'use strict';

const crypto = require('node:crypto');
const { loadCodexAppServerMethods } = require('./methods');

const REVIEWED_METHOD_SURFACE_SIGNATURE = 'd73ae1187282b17fa5620a414460f1e7fc7916be5b22dc2b6d693fe68aa8dbb1';

const DIRECTIONS = new Set(['request', 'notification', 'serverRequest']);
const STABILITIES = new Set(['stable', 'experimental']);
const CATEGORIES = new Set([
  'lifecycle',
  'model',
  'thread',
  'turn',
  'item',
  'command',
  'file',
  'mcp',
  'skill',
  'plugin',
  'app',
  'config',
  'auth',
  'sandbox',
  'remote-control',
  'diagnostics',
  'unknown'
]);
const LOCAL_STATUSES = new Set([
  'supported',
  'partial',
  'planned',
  'diagnostic-only',
  'unsupported',
  'intentionally-blocked'
]);
const DAEMON_OWNERS = new Set([
  'client',
  'conversation adapter',
  'listing adapter',
  'server route',
  'diagnostics',
  'none'
]);
const MOBILE_STATUSES = new Set(['consumed', 'protocol-only', 'planned', 'not planned']);
const RISKS = new Set(['none', 'read', 'write', 'process', 'account', 'network', 'permission', 'unknown']);
const TEST_REQUIREMENTS = new Set(['unit', 'integration fake transport', 'route test', 'mobile contract test', 'manual-only']);

const EXPLICIT_ROWS = [
  row('initialize', 'request', 'stable', 'lifecycle', 'supported', 'client', 'protocol-only', 'none', 'unit', 'Existing initialization request.'),
  row('initialized', 'notification', 'stable', 'lifecycle', 'supported', 'client', 'protocol-only', 'none', 'unit', 'Existing initialized notification.'),
  row('model/list', 'request', 'stable', 'model', 'supported', 'listing adapter', 'consumed', 'read', 'unit', 'Existing model picker source through /api/adapters.'),
  row('thread/start', 'request', 'stable', 'thread', 'supported', 'conversation adapter', 'consumed', 'write', 'integration fake transport', 'Existing conversation startup path.'),
  row('thread/resume', 'request', 'stable', 'thread', 'supported', 'conversation adapter', 'consumed', 'write', 'integration fake transport', 'Existing conversation resume path.'),
  row('turn/start', 'request', 'stable', 'turn', 'supported', 'conversation adapter', 'consumed', 'write', 'integration fake transport', 'Existing user message path.'),
  row('turn/interrupt', 'request', 'stable', 'turn', 'supported', 'conversation adapter', 'consumed', 'write', 'integration fake transport', 'Existing cancel path; side-effecting after request write.'),
  row('item/commandExecution/requestApproval', 'serverRequest', 'stable', 'command', 'supported', 'conversation adapter', 'consumed', 'permission', 'unit', 'Existing mobile approval request mapping.'),
  row('item/fileChange/requestApproval', 'serverRequest', 'stable', 'file', 'supported', 'conversation adapter', 'consumed', 'permission', 'unit', 'Existing file-change approval request mapping.'),
  row('item/permissions/requestApproval', 'serverRequest', 'stable', 'item', 'supported', 'conversation adapter', 'consumed', 'permission', 'unit', 'Existing permission approval request mapping.'),
  row('item/agentMessage/delta', 'notification', 'stable', 'item', 'supported', 'conversation adapter', 'consumed', 'none', 'integration fake transport', 'Existing streaming assistant.partial mapping.'),
  row('item/commandExecution/outputDelta', 'notification', 'stable', 'command', 'supported', 'conversation adapter', 'consumed', 'none', 'integration fake transport', 'Existing tool.delta mapping.'),
  row('thread/started', 'notification', 'stable', 'thread', 'supported', 'conversation adapter', 'consumed', 'none', 'integration fake transport', 'Existing event mapping.'),
  row('turn/started', 'notification', 'stable', 'turn', 'supported', 'conversation adapter', 'consumed', 'none', 'integration fake transport', 'Existing event mapping.'),
  row('turn/completed', 'notification', 'stable', 'turn', 'supported', 'conversation adapter', 'consumed', 'none', 'integration fake transport', 'Existing completion mapping.'),
  row('turn/plan/updated', 'notification', 'stable', 'turn', 'partial', 'conversation adapter', 'consumed', 'none', 'integration fake transport', 'Mapped to todo list events.'),
  row('item/started', 'notification', 'stable', 'item', 'partial', 'conversation adapter', 'consumed', 'none', 'integration fake transport', 'Mapped through current Codex event bridge.'),
  row('item/completed', 'notification', 'stable', 'item', 'partial', 'conversation adapter', 'consumed', 'none', 'integration fake transport', 'Mapped through current Codex event bridge.'),
  row('error', 'notification', 'stable', 'diagnostics', 'supported', 'conversation adapter', 'consumed', 'none', 'integration fake transport', 'Existing run error mapping.')
];

const CODEX_APP_SERVER_CAPABILITY_MATRIX = buildMatrix();

function row(method, direction, stability, category, localStatus, daemonOwner, mobileStatus, risk, testRequirement, rationale) {
  return { method, direction, stability, category, localStatus, daemonOwner, mobileStatus, risk, testRequirement, rationale };
}

function buildMatrix(methods = loadCodexAppServerMethods()) {
  const rows = new Map();
  for (const explicit of EXPLICIT_ROWS) rows.set(explicit.method, explicit);
  addGeneratedDefaults(rows, methods.clientRequests || methods.requests, 'request');
  addGeneratedDefaults(rows, methods.clientNotifications, 'notification');
  addGeneratedDefaults(rows, methods.serverRequests, 'serverRequest');
  addGeneratedDefaults(rows, methods.serverNotifications || methods.notifications, 'notification');
  return [...rows.values()].sort((left, right) => left.method.localeCompare(right.method));
}

function addGeneratedDefaults(rows, methods, direction) {
  for (const method of methods || []) {
    if (rows.has(method)) continue;
    rows.set(method, row(
      method,
      direction,
      inferStability(method),
      inferCategory(method),
      'unsupported',
      'none',
      'not planned',
      'unknown',
      'unit',
      'Generated from official app-server schema; not classified yet.'
    ));
  }
}

function validateCodexAppServerCapabilityMatrix(rows = CODEX_APP_SERVER_CAPABILITY_MATRIX, methods = loadCodexAppServerMethods()) {
  const errors = [];
  const seen = new Set();
  const signature = codexAppServerMethodSurfaceSignature(methods);
  if (signature !== REVIEWED_METHOD_SURFACE_SIGNATURE) {
    errors.push(`official method surface changed: ${signature}`);
  }
  for (const current of rows) {
    if (!current || typeof current !== 'object') {
      errors.push('matrix row must be an object');
      continue;
    }
    if (!current.method) errors.push('matrix row missing method');
    if (seen.has(current.method)) errors.push(`${current.method} duplicate row`);
    seen.add(current.method);
    validateEnum(errors, current, 'direction', DIRECTIONS);
    validateEnum(errors, current, 'stability', STABILITIES);
    validateEnum(errors, current, 'category', CATEGORIES);
    validateEnum(errors, current, 'localStatus', LOCAL_STATUSES);
    validateEnum(errors, current, 'daemonOwner', DAEMON_OWNERS);
    validateEnum(errors, current, 'mobileStatus', MOBILE_STATUSES);
    validateEnum(errors, current, 'risk', RISKS);
    validateEnum(errors, current, 'testRequirement', TEST_REQUIREMENTS);
    if (current.risk === 'unknown' && current.localStatus !== 'unsupported') {
      errors.push(`${current.method} has active status with unknown risk`);
    }
    if (current.risk === 'unknown' && current.mobileStatus !== 'not planned') {
      errors.push(`${current.method} is mobile-accessible with unknown risk`);
    }
  }
  requireRows(errors, seen, methods.clientRequests || methods.requests, 'client request');
  requireRows(errors, seen, methods.clientNotifications, 'client notification');
  requireRows(errors, seen, methods.serverRequests, 'serverRequest');
  requireRows(errors, seen, methods.serverNotifications || methods.notifications, 'server notification');
  return { errors };
}

function requireRows(errors, seen, methods, label) {
  for (const method of methods || []) {
    if (!seen.has(method)) errors.push(`${method} missing ${label} row`);
  }
}

function codexAppServerMethodSurfaceSignature(methods = loadCodexAppServerMethods()) {
  const payload = JSON.stringify({
    clientRequests: sortedMethods(methods.clientRequests || methods.requests),
    clientNotifications: sortedMethods(methods.clientNotifications),
    serverRequests: sortedMethods(methods.serverRequests),
    serverNotifications: sortedMethods(methods.serverNotifications || methods.notifications)
  });
  return crypto.createHash('sha256').update(payload).digest('hex');
}

function sortedMethods(methods) {
  return [...(methods || [])].sort();
}

function summarizeCodexAppServerCapabilityMatrix(rows = CODEX_APP_SERVER_CAPABILITY_MATRIX) {
  const validation = validateCodexAppServerCapabilityMatrix(rows);
  return {
    totalMethods: rows.length,
    supportedMethods: rows.filter((row) => row.localStatus === 'supported').length,
    partialMethods: rows.filter((row) => row.localStatus === 'partial').length,
    plannedMethods: rows.filter((row) => row.localStatus === 'planned').length,
    unsupportedMethods: rows.filter((row) => row.localStatus === 'unsupported').length,
    diagnosticOnlyMethods: rows.filter((row) => row.localStatus === 'diagnostic-only').length,
    intentionallyBlockedMethods: rows.filter((row) => row.localStatus === 'intentionally-blocked').length,
    invalidRows: validation.errors.length
  };
}

function validateEnum(errors, current, key, allowed) {
  if (!allowed.has(current[key])) errors.push(`${current.method || '<unknown>'} has invalid ${key}: ${current[key]}`);
}

function inferStability(method) {
  return /experimental|fuzzy|attestation|dynamic|mock/i.test(method) ? 'experimental' : 'stable';
}

function inferCategory(method) {
  const lower = String(method || '').toLowerCase();
  if (lower === 'initialize' || lower === 'initialized') return 'lifecycle';
  if (lower.startsWith('model/')) return 'model';
  if (lower.startsWith('thread/')) return 'thread';
  if (lower.startsWith('turn/')) return 'turn';
  if (lower.startsWith('item/commandexecution')) return 'command';
  if (lower.startsWith('item/filechange')) return 'file';
  if (lower.startsWith('item/')) return 'item';
  if (lower.startsWith('mcp/')) return 'mcp';
  if (lower.startsWith('skills/') || lower.startsWith('skill/')) return 'skill';
  if (lower.startsWith('plugin/') || lower.startsWith('marketplace/')) return 'plugin';
  if (lower.startsWith('apps/') || lower.startsWith('app/')) return 'app';
  if (lower.startsWith('config/')) return 'config';
  if (lower.includes('auth') || lower.includes('account') || lower.includes('login') || lower.includes('logout')) return 'auth';
  if (lower.includes('sandbox')) return 'sandbox';
  if (lower.startsWith('remotecontrol/')) return 'remote-control';
  if (lower.startsWith('command/') || lower.startsWith('process/')) return 'command';
  if (lower.startsWith('fs/')) return 'file';
  if (lower.includes('feedback') || lower.includes('warning') || lower.includes('deprecation')) return 'diagnostics';
  return 'unknown';
}

module.exports = {
  CODEX_APP_SERVER_CAPABILITY_MATRIX,
  buildCodexAppServerCapabilityMatrix: buildMatrix,
  codexAppServerMethodSurfaceSignature,
  summarizeCodexAppServerCapabilityMatrix,
  validateCodexAppServerCapabilityMatrix
};
