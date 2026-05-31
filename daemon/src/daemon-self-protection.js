'use strict';

const DEFAULT_DAEMON_PORT = 4317;

function daemonSelfProtectionForTool({
  toolName,
  input,
  daemonPid = process.pid,
  daemonPort = process.env.PORT || DEFAULT_DAEMON_PORT
} = {}) {
  const command = toolCommand(toolName, input);
  if (!command) return { blocked: false };
  return daemonSelfProtectionForCommand(command, { daemonPid, daemonPort });
}

function daemonSelfProtectionForCommand(command, {
  daemonPid = process.pid,
  daemonPort = process.env.PORT || DEFAULT_DAEMON_PORT
} = {}) {
  const normalized = normalizeCommand(command);
  if (!looksLikeProcessKill(normalized)) return { blocked: false };

  const pid = normalizePositiveInteger(daemonPid);
  if (pid != null && commandMentionsNumber(normalized, pid)) {
    return daemonProtectionBlock(
      `refers to daemon PID ${pid}`,
      { daemonPid: pid, daemonPort }
    );
  }

  const port = normalizePositiveInteger(daemonPort);
  if (port != null && commandMentionsNumber(normalized, port)) {
    return daemonProtectionBlock(
      `refers to daemon port ${port}`,
      { daemonPid: pid, daemonPort: port }
    );
  }

  return { blocked: false };
}

function daemonProtectionBlock(reason, { daemonPid, daemonPort }) {
  return {
    blocked: true,
    reason,
    message: daemonProtectionMessage({ daemonPid, daemonPort, reason })
  };
}

function daemonProtectionMessage({ daemonPid, daemonPort, reason }) {
  const pidPart = daemonPid ? ` PID ${daemonPid}` : '';
  const portPart = daemonPort ? ` port ${daemonPort}` : '';
  return `Blocked a shell command that could stop the mobile daemon${pidPart}${portPart} (${reason}). Use a different project server port or target a non-daemon process.`;
}

function toolCommand(toolName, input) {
  const name = String(toolName || '').toLowerCase();
  if (!name.includes('bash') && name !== 'shell' && name !== 'command_execution') {
    return null;
  }
  if (!input || typeof input !== 'object') return null;
  return typeof input.command === 'string' ? input.command : null;
}

function normalizeCommand(command) {
  return String(command || '')
    .replace(/\/\//g, '/')
    .replace(/\s+/g, ' ')
    .trim()
    .toLowerCase();
}

function looksLikeProcessKill(command) {
  return /\b(taskkill|tskill|kill|pkill|stop-process)\b/.test(command);
}

function commandMentionsNumber(command, value) {
  return new RegExp(`(^|[^0-9])${escapeRegExp(String(value))}([^0-9]|$)`).test(command);
}

function normalizePositiveInteger(value) {
  const number = Number.parseInt(String(value ?? ''), 10);
  return Number.isFinite(number) && number > 0 ? number : null;
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

module.exports = {
  daemonSelfProtectionForCommand,
  daemonSelfProtectionForTool,
  daemonProtectionMessage
};
