'use strict';

const { spawn, spawnSync } = require('node:child_process');
const packageJson = require('../../package.json');
const { resolveCliInvocation } = require('./cli-resolver');

const catalogs = Object.freeze({
  claude: Object.freeze([
    command('/add-dir', 'add additional working directories'),
    command('/agents', 'manage specialized subagents'),
    command('/clear', 'clear conversation history'),
    command('/compact', 'compact conversation with optional instructions'),
    command('/cost', 'show token usage and cost'),
    command('/doctor', 'check Claude Code installation health'),
    command('/help', 'show help and available commands'),
    command('/ide', 'manage IDE integrations'),
    command('/init', 'create a CLAUDE.md project memory file'),
    command('/mcp', 'manage MCP server connections'),
    command('/memory', 'edit memory files'),
    command('/model', 'select model for the current session'),
    command('/permissions', 'review or update permission rules'),
    command('/pr_comments', 'view pull request comments'),
    command('/review', 'request a code review'),
    command('/status', 'show account and system status'),
    command('/terminal-setup', 'install terminal key binding support')
  ]),
  codex: Object.freeze([
    command('/model', 'choose what model and reasoning effort to use'),
    command('/status', 'show current session configuration and account status'),
    command('/approvals', 'choose approval behavior for commands and edits'),
    command('/diff', 'review current code changes'),
    command('/compact', 'summarize the conversation to free context'),
    command('/new', 'start a new conversation'),
    command('/init', 'create project instructions for Codex'),
    command('/help', 'show help and available commands')
  ]),
  opencode: Object.freeze([
    command('/help', 'show help and available commands'),
    command('/model', 'select model for the current session'),
    command('/new', 'start a new session'),
    command('/share', 'share the current session'),
    command('/status', 'show current session status')
  ])
});

class SlashCommandCatalog {
  constructor({ discoverers = {} } = {}) {
    this.discoverers = discoverers;
    this.cache = new Map();
  }

  async list(adapterId, { workspacePath, force = false } = {}) {
    const adapter = normalizeAdapterId(adapterId);
    const cacheKey = `${adapter}\0${workspacePath || ''}`;
    if (!force && workspacePath && this.cache.has(cacheKey)) {
      return {
        adapter,
        commands: this.cache.get(cacheKey)
      };
    }
    const discovered = workspacePath
      ? await this.discover(adapter, { workspacePath })
      : null;
    const hasDiscoveredCommands = Array.isArray(discovered) && discovered.length > 0;
    const commands = normalizeCommands(
      hasDiscoveredCommands ? discovered : catalogs[adapter] || []
    );
    if (workspacePath && hasDiscoveredCommands) this.cache.set(cacheKey, commands);
    return {
      adapter,
      commands
    };
  }

  async discover(adapter, options) {
    const discoverer = this.discoverers[adapter];
    if (!discoverer || typeof discoverer.discover !== 'function') return null;
    try {
      return await discoverer.discover(options);
    } catch {
      return null;
    }
  }
}

class ClaudeSlashCommandDiscoverer {
  constructor({
    command = 'claude',
    spawnFn = spawn,
    spawnSyncFn = spawnSync,
    cliResolverOptions = {},
    timeoutMs = 5000
  } = {}) {
    this.spawnFn = spawnFn;
    this.timeoutMs = timeoutMs;
    this.invocation = resolveCliInvocation(command, {
      spawnSyncFn,
      ...cliResolverOptions
    });
  }

  discover({ workspacePath } = {}) {
    return new Promise((resolve, reject) => {
      let settled = false;
      let timer;
      const child = this.spawnFn(
        this.invocation.command,
        [
          ...this.invocation.argsPrefix,
          '--output-format',
          'stream-json',
          '--verbose',
          '--system-prompt',
          '',
          '--input-format',
          'stream-json'
        ],
        {
          cwd: workspacePath || process.cwd(),
          windowsHide: true,
          env: sdkProcessEnvForWorkspace(process.env, workspacePath)
        }
      );
      const requestId = `slash_init_${Date.now().toString(16)}`;

      const finish = (commands, error) => {
        if (settled) return;
        settled = true;
        if (timer) clearTimeout(timer);
        try {
          if (child.stdin && !child.stdin.destroyed) child.stdin.end();
        } catch {
          // Best effort cleanup only.
        }
        try {
          if (typeof child.kill === 'function') child.kill();
        } catch {
          // Best effort cleanup only.
        }
        if (error) reject(error);
        else resolve(normalizeCommands(commands || []));
      };

      timer = setTimeout(() => finish(null), this.timeoutMs);
      if (typeof timer.unref === 'function') timer.unref();

      child.stdout?.on('data', createJsonLineParser((raw) => {
        const commands = extractClaudeSdkSlashCommands(raw, requestId);
        if (commands) finish(commands);
      }));
      child.stderr?.on('data', () => {});
      child.on?.('error', (error) => finish(null, error));
      child.on?.('exit', () => finish([]));

      try {
        writeJsonLine(child, {
          type: 'control_request',
          request_id: requestId,
          request: { subtype: 'initialize', hooks: null }
        });
      } catch (error) {
        finish(null, error);
      }
    });
  }
}

function command(commandText, description) {
  return Object.freeze({ command: commandText, description });
}

function normalizeAdapterId(value) {
  return String(value || '').trim().toLowerCase();
}

function normalizeCommands(commands) {
  const byKey = new Map();
  for (const item of Array.isArray(commands) ? commands : []) {
    const normalized = normalizeCommandItem(item);
    if (!normalized) continue;
    const key = normalized.command.slice(1).toLowerCase();
    if (!key || byKey.has(key)) continue;
    byKey.set(key, normalized);
  }
  return Array.from(byKey.values()).sort((left, right) =>
    left.command.slice(1).toLowerCase().localeCompare(
      right.command.slice(1).toLowerCase()
    )
  );
}

function normalizeCommandItem(item) {
  if (typeof item === 'string') {
    const normalized = normalizeSlashCommand(item);
    if (!normalized) return null;
    return command(normalized, '');
  }
  if (!item || typeof item !== 'object') return null;
  const raw = item.command || item.name || item.id;
  const normalized = normalizeSlashCommand(raw);
  if (!normalized) return null;
  return command(normalized, String(item.description || item.summary || ''));
}

function normalizeSlashCommand(value) {
  const trimmed = String(value || '').trim();
  if (!trimmed) return '';
  return trimmed.startsWith('/') ? trimmed : `/${trimmed}`;
}

function extractClaudeSdkSlashCommands(raw, requestId) {
  const event = unwrapStreamEvent(raw);
  if (event?.type === 'control_response') {
    const response = event.response || {};
    if (response.request_id && response.request_id !== requestId) return null;
    const payload = response.response && typeof response.response === 'object'
      ? response.response
      : response;
    if (Array.isArray(payload.commands)) return payload.commands;
  }
  if (event?.type === 'system' && event.subtype === 'init') {
    if (Array.isArray(event.slash_commands)) return event.slash_commands;
    if (Array.isArray(event.data?.slash_commands)) {
      return event.data.slash_commands;
    }
  }
  return null;
}

function unwrapStreamEvent(raw) {
  if (raw && raw.type === 'stream_event' && raw.event) return raw.event;
  return raw;
}

function createJsonLineParser(onJson) {
  let buffer = '';
  return (chunk) => {
    buffer += chunk.toString();
    let index;
    while ((index = buffer.indexOf('\n')) >= 0) {
      const line = buffer.slice(0, index).trim();
      buffer = buffer.slice(index + 1);
      if (!line) continue;
      try {
        onJson(JSON.parse(line));
      } catch {
        // Ignore non-protocol output.
      }
    }
  };
}

function writeJsonLine(child, payload) {
  if (!child.stdin || typeof child.stdin.write !== 'function') {
    throw new Error('Claude SDK command discovery requires writable stdin');
  }
  child.stdin.write(`${JSON.stringify(payload)}\n`);
}

function sdkProcessEnvForWorkspace(sourceEnv, workspacePath) {
  const env = { ...sourceEnv };
  delete env.CLAUDECODE;
  env.CLAUDE_CODE_ENTRYPOINT = 'sdk-js';
  env.CLAUDE_AGENT_SDK_VERSION = packageJson.version || '0.0.0';
  env.CLAUDE_CODE_ENABLE_FINE_GRAINED_TOOL_STREAMING = '1';
  if (workspacePath) env.PWD = workspacePath;
  return env;
}

module.exports = {
  SlashCommandCatalog,
  ClaudeSlashCommandDiscoverer,
  extractClaudeSdkSlashCommands,
  normalizeCommands
};
