'use strict';

const HIGH_RISK_METHODS = new Set([
  'command/exec',
  'command/exec/resize',
  'command/exec/terminate',
  'command/exec/write',
  'config/batchWrite',
  'config/value/write',
  'environment/add',
  'fs/copy',
  'fs/createDirectory',
  'fs/remove',
  'fs/unwatch',
  'fs/watch',
  'fs/writeFile',
  'marketplace/add',
  'marketplace/remove',
  'marketplace/upgrade',
  'memory/reset',
  'plugin/install',
  'plugin/installed',
  'plugin/share/checkout',
  'plugin/share/delete',
  'plugin/share/save',
  'plugin/share/updateTargets',
  'plugin/uninstall',
  'process/kill',
  'process/resizePty',
  'process/spawn',
  'process/writeStdin',
  'remoteControl/client/revoke',
  'remoteControl/disable',
  'remoteControl/enable',
  'remoteControl/pairing/start',
  'skills/config/write',
  'skills/extraRoots/set',
  'thread/archive',
  'thread/backgroundTerminals/clean',
  'thread/compact/start',
  'thread/fork',
  'thread/goal/clear',
  'thread/goal/set',
  'thread/inject_items',
  'thread/memoryMode/set',
  'thread/metadata/update',
  'thread/name/set',
  'thread/realtime/appendAudio',
  'thread/realtime/appendText',
  'thread/realtime/start',
  'thread/realtime/stop',
  'thread/rollback',
  'thread/settings/update',
  'thread/shellCommand',
  'thread/unarchive',
  'turn/steer'
]);

function riskForCodexAppServerMethod(method) {
  const value = String(method || '');
  if (HIGH_RISK_METHODS.has(value)) {
    if (value.startsWith('fs/')) return 'write';
    if (value.startsWith('command/') || value.startsWith('process/')) return 'process';
    if (value.startsWith('remoteControl/')) return 'network';
    if (value.startsWith('config/') || value.startsWith('skills/') || value.startsWith('plugin/') || value.startsWith('marketplace/')) return 'write';
    return 'write';
  }
  if (value.startsWith('account/') || value.includes('login') || value.includes('logout')) return 'account';
  if (value.includes('oauth')) return 'account';
  if (value.startsWith('mcpServer/tool/call') || value === 'item/tool/call') return 'permission';
  return 'read';
}

function isHighRiskCodexAppServerMethod(method) {
  return HIGH_RISK_METHODS.has(String(method || '')) ||
    ['process', 'write', 'network'].includes(riskForCodexAppServerMethod(method));
}

module.exports = {
  HIGH_RISK_METHODS,
  isHighRiskCodexAppServerMethod,
  riskForCodexAppServerMethod
};
