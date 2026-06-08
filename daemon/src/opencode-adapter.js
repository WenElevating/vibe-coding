'use strict';

const { eventTypes } = require('./protocol');
const { OpenCodeServerLifecycle } = require('./opencode-server-lifecycle');

const MODEL_CAPABILITY = Object.freeze({
  models: [],
  selectedModel: null,
  canSelectModel: false
});

const CAPABILITIES = Object.freeze({
  longLivedProcess: true,
  waitingInput: false,
  waitingApproval: true,
  resume: true,
  partialOutput: true,
  toolEvents: true,
  approval: {
    mobileCallbacks: true,
    scopes: ['once', 'session'],
    supportsCancel: false,
    denyBehaviors: ['interrupt']
  },
  attachments: {
    image: 'unsupported',
    textDocument: 'text_extract',
    pdf: 'unsupported'
  }
});

class OpenCodeAdapter {
  constructor({
    serverUrl = process.env.OPENCODE_SERVER_URL || '',
    command = process.env.OPENCODE_COMMAND || 'opencode',
    lifecycle = null
  } = {}) {
    this.name = 'opencode';
    this.serverUrl = serverUrl || null;
    this.lifecycle = lifecycle || new OpenCodeServerLifecycle({
      externalUrl: serverUrl || '',
      command
    });
    this.capability = null;
  }

  async detectCapabilities() {
    try {
      const started = await this.ensureStarted();
      if (!started.client || typeof started.client.health !== 'function') {
        throw adapterError('OpenCode server lifecycle did not return a usable client', {
          code: 'OPENCODE_SERVER_CLIENT_MISSING'
        });
      }
      const health = await started.client.health();
      this.capability = capability(true, 'available', null, {
        serverUrl: started.serverUrl,
        mode: started.mode,
        owned: started.owned,
        diagnostics: {
          lifecycle: listingLifecycleDiagnostics(this.lifecycleDiagnostics()),
          health: listingHealthDiagnostics(health)
        }
      });
      return this.capability;
    } catch (error) {
      this.capability = capability(false, 'unavailable', 'OpenCode server unavailable. Start OpenCode server or check OpenCode installation.', {
        unavailableReason: safeTokenString(error?.code) || 'OPENCODE_SERVER_UNAVAILABLE',
        diagnostics: {
          lifecycle: listingLifecycleDiagnostics(this.lifecycleDiagnostics()),
          cause: listingErrorDiagnostics(error)
        }
      });
      return this.capability;
    }
  }

  getCapabilities() {
    return cloneCapabilities();
  }

  getModelCapability() {
    return { ...MODEL_CAPABILITY };
  }

  async ensureAvailable() {
    const current = this.capability || await this.detectCapabilities();
    if (!current.available) {
      const error = new Error(current.error);
      error.status = 503;
      error.code = 'ADAPTER_UNAVAILABLE';
      error.actionable = current.actionable;
      error.details = current;
      throw error;
    }
  }

  async ensureStarted() {
    if (!this.lifecycle || typeof this.lifecycle.ensureStarted !== 'function') {
      throw adapterError('OpenCode server lifecycle is not configured', {
        code: 'OPENCODE_SERVER_LIFECYCLE_MISSING'
      });
    }
    const started = await this.lifecycle.ensureStarted();
    if (!started?.client) {
      throw adapterError('OpenCode server lifecycle did not return a client', {
        code: 'OPENCODE_SERVER_CLIENT_MISSING'
      });
    }
    return started;
  }

  async startRun({ prompt, sessionId, resume = false, workspacePath, onEvent }) {
    let started;
    try {
      started = await this.ensureStarted();
    } catch (error) {
      throw publicLifecycleStartupError(error);
    }
    if (resume && !sessionId) {
      const error = new Error('OpenCode resume requires a captured server session id');
      error.status = 409;
      error.code = 'OPENCODE_SESSION_REQUIRED';
      throw error;
    }
    const activeSessionId = sessionId || await this.createSession({ client: started.client, workspacePath });
    onEvent({ type: eventTypes.RAW_OUTPUT, text: '', sessionId: activeSessionId, reason: 'opencode_session_active' });
    await this.sendPrompt({ client: started.client, sessionId: activeSessionId, prompt });
    onEvent({ type: eventTypes.RUN_COMPLETED, exitCode: 0, sessionId: activeSessionId });
    return { kill: () => this.abortSession({ client: started.client, sessionId: activeSessionId }).catch(() => {}) };
  }

  async createSession({ client, workspacePath } = {}) {
    const effectiveClient = client || (await this.ensureStarted()).client;
    const response = await effectiveClient.createSession({ directory: workspacePath || process.cwd() });
    const sessionId = parseSessionId(response);
    if (!sessionId) {
      throw adapterError('OpenCode server did not return a session id', {
        code: 'OPENCODE_SESSION_ID_MISSING'
      });
    }
    return sessionId;
  }

  async sendPrompt({ client, sessionId, prompt }) {
    const effectiveClient = client || (await this.ensureStarted()).client;
    await effectiveClient.promptAsync({ sessionId, text: prompt });
  }

  async abortSession({ client, sessionId }) {
    const effectiveClient = client || (await this.ensureStarted()).client;
    await effectiveClient.abortSession({ sessionId });
  }

  lifecycleDiagnostics() {
    if (!this.lifecycle || typeof this.lifecycle.getDiagnostics !== 'function') return null;
    try {
      return this.lifecycle.getDiagnostics();
    } catch (error) {
      return { status: 'diagnostics_error' };
    }
  }
}

function capability(available, status, error, {
  serverUrl = null,
  mode = null,
  owned = false,
  unavailableReason = null,
  diagnostics = null
} = {}) {
  return {
    adapter: 'opencode',
    available,
    selectable: available,
    status,
    serverUrl: publicServerUrl(serverUrl),
    mode: safeString(mode) || null,
    owned: owned === true,
    error,
    actionable: error,
    unavailableReason,
    ...MODEL_CAPABILITY,
    capabilities: cloneCapabilities(),
    diagnostics
  };
}

function cloneCapabilities() {
  return {
    ...CAPABILITIES,
    approval: {
      ...CAPABILITIES.approval,
      scopes: [...CAPABILITIES.approval.scopes],
      denyBehaviors: [...CAPABILITIES.approval.denyBehaviors]
    },
    attachments: { ...CAPABILITIES.attachments }
  };
}

function parseJson(text) {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

function parseSessionId(value) {
  if (!value) return null;
  if (typeof value === 'string') {
    const parsed = parseJson(value);
    return parsed ? parseSessionId(parsed) : value.trim() || null;
  }
  if (typeof value === 'object') {
    return value.id || value.sessionId || value.session_id || value.session?.id || null;
  }
  return null;
}

function adapterError(message, { code } = {}) {
  const error = new Error(message);
  if (code) error.code = code;
  return error;
}

function publicLifecycleStartupError(error) {
  const status = safeHttpStatus(error?.status) || 503;
  const code = safeTokenString(error?.code || error?.name) || 'OPENCODE_SERVER_UNAVAILABLE';
  const safe = new Error('OpenCode server unavailable.');
  safe.status = status;
  safe.code = code;
  safe.details = safeLifecycleStartupDetails(error, { code, status });
  return safe;
}

function safeLifecycleStartupDetails(error, { code, status }) {
  const result = {};
  if (code) result.code = code;
  if (status) result.status = status;
  const reason = safeTokenString(error?.reason) ||
    safeTokenString(error?.details?.reason) ||
    safeTokenString(error?.details?.cause?.code) ||
    safeTokenString(error?.cause?.code || error?.cause?.name);
  if (reason && reason !== code) result.reason = reason;
  return Object.keys(result).length > 0 ? result : null;
}

function listingErrorDiagnostics(error) {
  if (!error) return null;
  const code = safeTokenString(error.code || error.name);
  return code ? { code } : null;
}

function listingLifecycleDiagnostics(value) {
  if (!value || typeof value !== 'object') return null;
  const result = {};
  const status = safeTokenString(value.status);
  if (status) result.status = status;
  const lastErrorCode = safeTokenString(value.lastError?.code);
  if (lastErrorCode) result.lastError = { code: lastErrorCode };
  return Object.keys(result).length > 0 ? result : null;
}

function listingHealthDiagnostics(value) {
  if (!value || typeof value !== 'object') return null;
  const result = {};
  if (typeof value.ok === 'boolean') result.ok = value.ok;
  const version = safeDisplayString(value.version);
  if (version) result.version = version;
  return Object.keys(result).length > 0 ? result : null;
}

function publicServerUrl(value) {
  const text = safeString(value);
  if (!text) return null;
  try {
    return new URL(text).origin;
  } catch {
    const queryIndex = text.indexOf('?');
    return safeDisplayString(queryIndex === -1 ? text : text.slice(0, queryIndex));
  }
}

function safeString(value) {
  if (typeof value !== 'string' && typeof value !== 'number') return '';
  return String(value).trim();
}

function safeTokenString(value, maxLength = 128) {
  const text = safeString(value);
  if (!text || text.length > maxLength) return null;
  return /^[A-Za-z0-9_.-]+$/.test(text) ? text : null;
}

function safeHttpStatus(value) {
  const status = Number(value);
  if (!Number.isInteger(status) || status < 100 || status > 599) return null;
  return status;
}

function safeDisplayString(value, maxLength = 128) {
  const text = safeString(value);
  if (!text) return null;
  const safeParts = [];
  for (const part of text.split(/\s+/)) {
    if (!/^[A-Za-z0-9_.()+-]+$/.test(part)) break;
    safeParts.push(part);
  }
  if (safeParts.length === 0) return null;
  return limitString(safeParts.join(' '), maxLength);
}

function limitString(value, maxLength) {
  const text = String(value || '');
  if (text.length <= maxLength) return text;
  return `${text.slice(0, maxLength - 14)}...[truncated]`;
}

module.exports = { OpenCodeAdapter };
