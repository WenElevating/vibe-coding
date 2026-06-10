'use strict';

const LONG_LIVED_STREAM_METHODS = new Set([
  'command/exec',
  'process/spawn',
  'thread/realtime/appendAudio',
  'thread/realtime/appendText',
  'thread/realtime/start',
  'thread/start',
  'thread/resume',
  'turn/start'
]);

const INBOUND_SERVER_REQUEST_METHODS = new Set([
  'item/commandExecution/requestApproval',
  'item/fileChange/requestApproval',
  'item/permissions/requestApproval'
]);

function classifyCodexAppServerTimeout(method) {
  const value = String(method || '');
  if (INBOUND_SERVER_REQUEST_METHODS.has(value)) {
    return {
      kind: 'inbound-server-request',
      method: value,
      timeoutMs: 120000
    };
  }
  if (LONG_LIVED_STREAM_METHODS.has(value)) {
    return {
      kind: 'long-lived-stream',
      method: value,
      timeoutMs: null
    };
  }
  return {
    kind: 'instant-rpc',
    method: value,
    timeoutMs: 30000
  };
}

module.exports = {
  classifyCodexAppServerTimeout
};
