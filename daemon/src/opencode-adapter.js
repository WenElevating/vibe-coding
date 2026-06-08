'use strict';

const { eventTypes } = require('./protocol');
const { conversationEventTypes } = require('./conversation-protocol');
const { mapOpenCodeEvent } = require('./opencode-event-mapper');
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
    let subscription = null;
    let terminal = false;
    const closeSubscription = () => {
      if (subscription && typeof subscription.close === 'function') subscription.close();
      subscription = null;
    };
    const emitEvent = (event) => {
      if (terminal) return;
      onEvent(event);
    };
    const emitTerminal = (event) => {
      if (terminal) return;
      terminal = true;
      closeSubscription();
      onEvent(event);
    };
    subscription = started.client.subscribeEvents(
      (raw) => {
        const mapped = mapOpenCodeEvent(raw, { workspacePath });
        if (!mapped || mapped.dispatchable === false) return;
        if (mapped.sessionId && mapped.sessionId !== activeSessionId) return;
        if (!mapped.sessionId && isSessionScopedRunEvent(mapped)) return;
        const runEvent = mapOpenCodeRunEvent(mapped, {
          client: started.client,
          sessionId: activeSessionId
        });
        if (!runEvent) return;
        if (isTerminalRunEvent(runEvent)) emitTerminal(runEvent);
        else emitEvent(runEvent);
      },
      (error) => {
        emitTerminal({
          type: eventTypes.RUN_FAILED,
          error: 'OpenCode event stream interrupted before the run completed.',
          code: safeTokenString(error?.code || error?.name) || 'OPENCODE_EVENT_STREAM_INTERRUPTED'
        });
      }
    );
    onEvent({ type: eventTypes.RAW_OUTPUT, text: '', sessionId: activeSessionId, reason: 'opencode_session_active' });
    try {
      await waitForSubscriptionOpen(subscription);
      await this.sendPrompt({ client: started.client, sessionId: activeSessionId, prompt });
    } catch (error) {
      closeSubscription();
      throw error;
    }
    return {
      kill: () => {
        terminal = true;
        closeSubscription();
        return this.abortSession({ client: started.client, sessionId: activeSessionId }).catch(() => {});
      }
    };
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

function mapOpenCodeRunEvent(mapped, { client, sessionId }) {
  switch (mapped.type) {
    case conversationEventTypes.CONVERSATION_COMPLETED:
      return { type: eventTypes.RUN_COMPLETED, exitCode: 0, sessionId };
    case conversationEventTypes.CONVERSATION_CANCELLED:
      return { type: eventTypes.RUN_CANCELLED, sessionId, reason: mapped.reason || 'opencode_cancelled' };
    case conversationEventTypes.RUN_ERROR:
      return {
        type: eventTypes.RUN_FAILED,
        sessionId,
        error: mapped.message || 'OpenCode run failed',
        code: safeTokenString(mapped.code) || 'OPENCODE_RUN_FAILED'
      };
    case conversationEventTypes.ASSISTANT_PARTIAL:
    case conversationEventTypes.ASSISTANT_MESSAGE:
      return { type: eventTypes.ASSISTANT_DELTA, sessionId, text: mapped.text || '', raw: mapped.raw || null };
    case conversationEventTypes.TOOL_STARTED:
      return {
        type: eventTypes.TOOL_STARTED,
        sessionId,
        name: mapped.toolName || 'tool',
        input: mapped.input || {},
        toolUseId: mapped.toolUseId || null,
        raw: mapped.raw || null
      };
    case conversationEventTypes.TOOL_DELTA:
    case conversationEventTypes.TOOL_OUTPUT:
    case conversationEventTypes.TOOL_COMPLETED:
      return {
        type: eventTypes.TOOL_OUTPUT,
        sessionId,
        text: mapped.text || '',
        toolUseId: mapped.toolUseId || null,
        raw: mapped.raw || null
      };
    case conversationEventTypes.APPROVAL_REQUESTED:
      return {
        type: eventTypes.APPROVAL_REQUIRED,
        sessionId,
        approvalId: mapped.approvalId,
        toolName: mapped.toolName || 'tool',
        input: mapped.input || {},
        toolUseId: mapped.toolUseId || null,
        respond: (decision) => client.replyPermission({
          sessionId,
          permissionId: mapped.approvalId,
          decision
        })
      };
    case conversationEventTypes.DIFF_SUMMARY:
      return { type: eventTypes.DIFF_SUMMARY, sessionId, files: mapped.files || [], raw: mapped.raw || null };
    case conversationEventTypes.SYSTEM_NOTICE:
    case conversationEventTypes.PROTOCOL_WARNING:
      return mapped.visible === true
        ? { type: eventTypes.RAW_OUTPUT, sessionId, text: mapped.text || mapped.warning || 'OpenCode notice' }
        : null;
    default:
      return null;
  }
}

function isSessionScopedRunEvent(event) {
  return [
    conversationEventTypes.CONVERSATION_COMPLETED,
    conversationEventTypes.CONVERSATION_CANCELLED,
    conversationEventTypes.RUN_ERROR,
    conversationEventTypes.ASSISTANT_PARTIAL,
    conversationEventTypes.ASSISTANT_MESSAGE,
    conversationEventTypes.TOOL_STARTED,
    conversationEventTypes.TOOL_DELTA,
    conversationEventTypes.TOOL_OUTPUT,
    conversationEventTypes.TOOL_COMPLETED,
    conversationEventTypes.APPROVAL_REQUESTED,
    conversationEventTypes.DIFF_SUMMARY
  ].includes(event?.type);
}

function isTerminalRunEvent(event) {
  return event?.type === eventTypes.RUN_COMPLETED ||
    event?.type === eventTypes.RUN_FAILED ||
    event?.type === eventTypes.RUN_CANCELLED;
}

async function waitForSubscriptionOpen(subscription) {
  if (!subscription || typeof subscription.opened?.then !== 'function') return;
  const result = await subscription.opened;
  if (result?.ok === true) return;
  const cause = result?.error || null;
  const error = new Error('OpenCode event stream interrupted before prompt dispatch.');
  error.status = 503;
  error.code = safeTokenString(cause?.code || cause?.name) || 'OPENCODE_EVENT_STREAM_INTERRUPTED';
  throw error;
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
