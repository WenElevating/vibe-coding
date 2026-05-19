'use strict';

const { spawn, spawnSync } = require('node:child_process');
const { eventTypes } = require('./protocol');
const { resolveCliInvocation } = require('./cli-resolver');
const { discoverConfiguredModels } = require('./model-discovery');

class JsonLineProcessAdapter {
  constructor({ name, command, capabilityArgs = ['--version'], runArgs, requiredHelp = [], modelCapabilityHelpArgs = null, staticCapabilities = {}, spawnFn = spawn, spawnSyncFn = spawnSync, explicitEnabled = true, cliResolverOptions = {} } = {}) {
    this.name = name;
    this.command = command;
    this.capabilityArgs = capabilityArgs;
    this.runArgs = runArgs;
    this.requiredHelp = requiredHelp;
    this.modelCapabilityHelpArgs = modelCapabilityHelpArgs;
    this.staticCapabilities = staticCapabilities;
    this.spawnFn = spawnFn;
    this.spawnSyncFn = spawnSyncFn;
    this.explicitEnabled = explicitEnabled;
    this.capability = null;
    this.modelCapability = defaultModelCapability();
    this.invocation = resolveCliInvocation(command, { spawnSyncFn, ...cliResolverOptions });
  }

  detectCapabilities() {
    if (!this.explicitEnabled) {
      this.capability = capability(this.name, false, 'disabled', `${this.name} requires explicit enablement in Settings.`);
      return this.capability;
    }
    const version = this.spawnSyncFn(this.invocation.command, [...this.invocation.argsPrefix, ...this.capabilityArgs], { encoding: 'utf8' });
    if (version.error || version.status !== 0) {
      this.capability = capability(this.name, false, 'unavailable', `${this.name} CLI unavailable. Check installation and PATH.`, version);
      return this.capability;
    }
    let helpText = '';
    if (this.requiredHelp.length > 0) {
      const help = this.spawnSyncFn(this.invocation.command, [...this.invocation.argsPrefix, '--help'], { encoding: 'utf8' });
      helpText = `${help.stdout || ''}\n${help.stderr || ''}`;
      const missing = this.requiredHelp.filter((needle) => !helpText.includes(needle));
      if (missing.length > 0) {
        this.capability = capability(this.name, false, 'misconfigured', `${this.name} CLI missing capabilities: ${missing.join(', ')}`, version);
        return this.capability;
      }
    }
    const modelHelpText = this.modelCapabilityHelpArgs
      ? resultText(this.spawnSyncFn(this.invocation.command, [...this.invocation.argsPrefix, ...this.modelCapabilityHelpArgs], { encoding: 'utf8' }))
      : helpText;
    this.modelCapability = {
      ...discoverConfiguredModels({ adapter: this.name }),
      canSelectModel: helpHasModelFlag(modelHelpText)
    };
    this.capability = capability(this.name, true, 'available', null, version);
    return this.capability;
  }

  getModelCapability() {
    return this.modelCapability || defaultModelCapability();
  }

  getCapabilities() {
    return this.staticCapabilities || {};
  }

  ensureAvailable() {
    const current = this.capability || this.detectCapabilities();
    if (!current.available) {
      const error = new Error(current.error || `${this.name} adapter unavailable`);
      error.status = 503;
      error.code = 'ADAPTER_UNAVAILABLE';
      error.actionable = current.actionable;
      error.details = current;
      throw error;
    }
  }

  startRun({ prompt, workspacePath, sessionId, resume = false, permissionMode = 'default', onEvent }) {
    this.ensureAvailable();
    const args = this.runArgs(prompt, workspacePath, sessionId, resume, permissionMode);
    const child = this.spawnFn(this.invocation.command, [...this.invocation.argsPrefix, ...args], { cwd: workspacePath, windowsHide: true });
    child.stdout.on('data', (chunk) => parseJsonOrRawLines(chunk, onEvent));
    child.stderr.on('data', (chunk) => onEvent({ type: eventTypes.RAW_OUTPUT, text: chunk.toString() }));
    child.on('error', (error) => onEvent({ type: eventTypes.ADAPTER_ERROR, ...adapterError(this.name, error) }));
    child.on('exit', (code, signal) => {
      if (signal) onEvent({ type: eventTypes.RUN_CANCELLED, signal });
      else if (code === 0) onEvent({ type: eventTypes.RUN_COMPLETED, exitCode: code });
      else onEvent({ type: eventTypes.RUN_FAILED, exitCode: code });
    });
    return child;
  }
}

function defaultModelCapability() {
  return { models: [], selectedModel: null, canSelectModel: false };
}

function helpHasModelFlag(helpText) {
  return /(^|[\s[(,])--model(?=$|[\s=,\])])/m.test(helpText || '');
}

function resultText(result = {}) {
  return `${result.stdout || ''}\n${result.stderr || ''}`;
}

function createCodexAdapter(options = {}) {
  return new JsonLineProcessAdapter({
    name: 'codex',
    command: options.command || 'codex',
    capabilityArgs: ['--version'],
    requiredHelp: ['exec'],
    modelCapabilityHelpArgs: ['exec', '--help'],
    staticCapabilities: {
      attachments: {
        image: 'unsupported',
        textDocument: 'text_extract',
        pdf: 'unsupported'
      }
    },
    runArgs: (prompt, workspacePath, sessionId, resume, permissionMode) => sessionId ? [
      'exec',
      'resume',
      sessionId,
      '--json',
      '--ask-for-approval',
      permissionMode === 'auto' ? 'never' : 'on-request',
      prompt
    ] : resume ? [
      'exec',
      'resume',
      '--last',
      '--json',
      '--ask-for-approval',
      permissionMode === 'auto' ? 'never' : 'on-request',
      prompt
    ] : [
      'exec',
      '--json',
      '--cd',
      workspacePath,
      '--sandbox',
      'workspace-write',
      '--ask-for-approval',
      permissionMode === 'auto' ? 'never' : 'on-request',
      prompt
    ],
    explicitEnabled: options.explicitEnabled ?? false,
    spawnFn: options.spawnFn,
    spawnSyncFn: options.spawnSyncFn,
    cliResolverOptions: options.cliResolverOptions
  });
}

function parseJsonOrRawLines(chunk, onEvent) {
  const text = chunk.toString();
  for (const line of text.split(/\r?\n/)) {
    if (!line.trim()) continue;
    try {
      onEvent(mapGenericEvent(JSON.parse(line)));
    } catch {
      onEvent({ type: eventTypes.RAW_OUTPUT, text: line });
    }
  }
}

function mapGenericEvent(raw) {
  const type = raw.type || raw.event || '';
  if (/diff/i.test(type) || raw.diff) {
    return {
      type: eventTypes.DIFF_SUMMARY,
      filePath: raw.filePath || raw.path || raw.diff?.filePath,
      additions: raw.additions || raw.diff?.additions || 0,
      deletions: raw.deletions || raw.diff?.deletions || 0,
      binary: Boolean(raw.binary || raw.diff?.binary),
      raw
    };
  }
  if (/assistant|message|delta/i.test(type)) return { type: eventTypes.ASSISTANT_DELTA, text: extractText(raw), sessionId: raw.session_id || raw.sessionId || raw.conversationId, raw };
  if (raw.session_id || raw.sessionId || raw.conversationId) {
    return { type: eventTypes.RAW_OUTPUT, text: '', sessionId: raw.session_id || raw.sessionId || raw.conversationId, raw };
  }
  if (/tool.*start|command.*start/i.test(type)) return { type: eventTypes.TOOL_STARTED, name: raw.name || raw.command || 'tool', input: raw.input || {}, raw };
  if (/tool|output|command/i.test(type)) return { type: eventTypes.TOOL_OUTPUT, text: extractText(raw), raw };
  return { type: eventTypes.RAW_OUTPUT, text: extractText(raw) || JSON.stringify(raw), raw };
}

function extractText(raw) {
  if (typeof raw.text === 'string') return raw.text;
  if (typeof raw.delta === 'string') return raw.delta;
  if (typeof raw.message === 'string') return raw.message;
  if (typeof raw.output === 'string') return raw.output;
  if (Array.isArray(raw.content)) return raw.content.map((part) => part.text || '').join('');
  if (typeof raw.content === 'string') return raw.content;
  return '';
}

function capability(adapter, available, status, error, versionResult = {}) {
  return {
    adapter,
    available,
    status,
    version: String(versionResult.stdout || versionResult.stderr || '').trim() || null,
    error,
    actionable: error || null
  };
}

function adapterError(adapter, error) {
  return { adapter, code: error.code || 'ADAPTER_ERROR', message: error.message || String(error) };
}

module.exports = { JsonLineProcessAdapter, createCodexAdapter, parseJsonOrRawLines, mapGenericEvent };
