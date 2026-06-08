'use strict';

const { conversationEventTypes } = require('./conversation-protocol');
const { mapOpenCodeEvent } = require('./opencode-event-mapper');
const { OpenCodeServerLifecycle } = require('./opencode-server-lifecycle');
const {
  extractSessionId,
  extractSessionDirectory,
  validateSessionDirectory,
  pathContainsOrEquals
} = require('./opencode-session-boundary');

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

class OpenCodeConversationAdapter {
  constructor({ lifecycle = null, now = () => new Date() } = {}) {
    this.name = 'opencode';
    this.lifecycle = lifecycle || new OpenCodeServerLifecycle();
    this.now = now;
    this.capabilities = cloneCapabilities();
  }

  async detectCapabilities() {
    if (!this.lifecycle || typeof this.lifecycle.ensureStarted !== 'function') {
      return unavailableCapability('OpenCode server lifecycle is not configured', {
        code: 'OPENCODE_SERVER_LIFECYCLE_MISSING',
        diagnostics: this.lifecycleDiagnostics()
      });
    }
    try {
      const started = await this.lifecycle.ensureStarted();
      if (!started?.client || typeof started.client.health !== 'function') {
        throw conversationError('OpenCode server lifecycle did not return a usable client', {
          status: 503,
          code: 'OPENCODE_SERVER_CLIENT_MISSING'
        });
      }
      const health = await started.client.health();
      return {
        adapter: this.name,
        available: true,
        selectable: true,
        status: 'available',
        serverUrl: publicServerUrl(started.serverUrl),
        mode: safeString(started.mode) || null,
        owned: started.owned === true,
        ...this.getModelCapability(),
        capabilities: this.getCapabilities(),
        diagnostics: {
          lifecycle: this.lifecycleDiagnostics(),
          health: safeHealthDiagnostics(health)
        }
      };
    } catch (error) {
      return unavailableCapability('OpenCode server unavailable. Start OpenCode server or check OpenCode installation.', {
        code: safeTokenString(error?.code || error?.name) || 'OPENCODE_SERVER_UNAVAILABLE',
        diagnostics: {
          lifecycle: this.lifecycleDiagnostics(),
          cause: safeLifecycleStartupDetails(error, {
            code: safeTokenString(error?.code || error?.name) || 'OPENCODE_SERVER_UNAVAILABLE',
            status: 503
          })
        }
      });
    }
  }

  getCapabilities() {
    return cloneCapabilities();
  }

  getModelCapability() {
    return { ...MODEL_CAPABILITY };
  }

  async startConversation({
    conversationId,
    workspacePath,
    permissionMode = 'default',
    sessionId,
    model,
    sessionBindingActions,
    onEvent
  } = {}) {
    const workspace = requireWorkspacePath(workspacePath);
    if (permissionMode === 'auto') {
      throw conversationError('OpenCode does not support automatic permission bypass for daemon conversations.', {
        status: 422,
        code: 'OPENCODE_PERMISSION_MODE_UNSUPPORTED'
      });
    }
    if (model) {
      throw conversationError('OpenCode model selection is not supported by this daemon integration yet.', {
        status: 422,
        code: 'CONVERSATION_MODEL_UNSUPPORTED'
      });
    }
    const started = await this.ensureStarted();
    const client = started.client;
    const initialSessionId = safeString(sessionId);
    let session = null;
    if (initialSessionId) {
      try {
        session = await this.readExistingSession(client, initialSessionId);
      } catch (error) {
        clearMissingSessionBinding(sessionBindingActions, initialSessionId, error);
        throw sessionMissingError(error, initialSessionId);
      }
    } else {
      session = await client.createSession({ directory: workspace });
    }
    const providerSessionId = extractSessionId(session) || initialSessionId;
    if (!providerSessionId) {
      throw conversationError('OpenCode server did not return a session id.', {
        status: 502,
        code: 'OPENCODE_SESSION_ID_MISSING'
      });
    }
    if (initialSessionId && providerSessionId !== initialSessionId) {
      markDriftedSessionBinding(sessionBindingActions, {
        expectedSessionId: initialSessionId,
        receivedSessionId: providerSessionId,
        reason: 'OpenCode readSession returned a different session id',
        code: 'OPENCODE_SESSION_MISSING'
      });
      throw sessionMissingError(new Error('OpenCode readSession returned a different session id'), initialSessionId);
    }
    const sessionDirectory = extractSessionDirectory(session);
    try {
      validateSessionDirectory(sessionDirectory, workspace);
    } catch (error) {
      if (initialSessionId && error?.code === 'OPENCODE_SESSION_DIRECTORY_MISMATCH') {
        markDriftedSessionBinding(sessionBindingActions, {
          expectedSessionId: initialSessionId,
          receivedSessionId: providerSessionId,
          reason: 'OpenCode session directory mismatch',
          code: 'OPENCODE_SESSION_DIRECTORY_MISMATCH'
        });
      }
      throw error;
    }
    const providerSession = buildProviderSession({
      sessionId: providerSessionId,
      now: this.now
    });
    const handle = new OpenCodeConversationHandle({
      conversationId,
      client,
      sessionId: providerSessionId,
      workspacePath: workspace,
      providerSession,
      onEvent,
      mapper: mapOpenCodeEvent
    });
    handle.subscribe();
    handle.emitSessionNotice(initialSessionId ? 'opencode_session_resumed' : 'opencode_session_started');
    return handle;
  }

  async ensureStarted() {
    if (!this.lifecycle || typeof this.lifecycle.ensureStarted !== 'function') {
      throw conversationError('OpenCode server lifecycle is not configured.', {
        status: 503,
        code: 'OPENCODE_SERVER_LIFECYCLE_MISSING'
      });
    }
    try {
      const started = await this.lifecycle.ensureStarted();
      if (!started?.client) {
        throw conversationError('OpenCode server lifecycle did not return a client.', {
          status: 503,
          code: 'OPENCODE_SERVER_CLIENT_MISSING'
        });
      }
      return started;
    } catch (error) {
      throw publicLifecycleStartupError(error);
    }
  }

  async readExistingSession(client, sessionId) {
    return client.readSession({ sessionId });
  }

  lifecycleDiagnostics() {
    if (!this.lifecycle || typeof this.lifecycle.getDiagnostics !== 'function') return null;
    try {
      return safeLifecycleDiagnostics(this.lifecycle.getDiagnostics());
    } catch (error) {
      return { status: 'diagnostics_error' };
    }
  }
}

class OpenCodeConversationHandle {
  constructor({ conversationId, client, sessionId, workspacePath, providerSession, onEvent, mapper }) {
    this.conversationId = conversationId || null;
    this.client = client;
    this.sessionId = sessionId;
    this.workspacePath = workspacePath;
    this.providerSession = providerSession;
    this.onEvent = typeof onEvent === 'function' ? onEvent : () => {};
    this.mapper = mapper;
    this.subscription = null;
    this.streamOpened = null;
    this.pendingApprovals = new Map();
    this.locallyResolvedApprovals = new Set();
    this.missingSessionWarnings = new Set();
    this.promptDispatching = false;
    this.activeTurn = false;
    this.disposed = false;
    this.streamFailed = false;
    this.streamDisconnected = false;
  }

  subscribe() {
    if (this.subscription) return;
    this.subscription = this.client.subscribeEvents(
      (event) => this.handleRawEvent(event),
      (error) => this.handleStreamError(error)
    );
    this.streamOpened = isPromiseLike(this.subscription?.opened)
      ? this.subscription.opened
      : Promise.resolve({ ok: true });
  }

  emitSessionNotice(noticeKind) {
    this.onEvent({
      type: conversationEventTypes.SYSTEM_NOTICE,
      noticeKind,
      visible: false,
      sessionId: this.sessionId,
      providerSession: this.providerSession
    });
  }

  async sendUserMessage(message) {
    if (this.disposed) {
      throw conversationError('OpenCode conversation handle is disposed.', {
        status: 409,
        code: 'OPENCODE_CONVERSATION_DISPOSED'
      });
    }
    if (this.activeTurn || this.promptDispatching) {
      throw conversationError('OpenCode turn is already running.', {
        status: 409,
        code: 'OPENCODE_TURN_IN_PROGRESS'
      });
    }
    if (this.streamDisconnected || !this.subscription) {
      throw streamInterruptedError();
    }
    this.promptDispatching = true;
    try {
      await this.waitForEventStreamOpen();
      this.activeTurn = true;
      this.streamFailed = false;
      await this.client.promptAsync({
        sessionId: this.sessionId,
        text: messageText(message)
      });
    } catch (error) {
      this.activeTurn = false;
      throw error;
    } finally {
      this.promptDispatching = false;
    }
  }

  async waitForEventStreamOpen() {
    if (!this.streamOpened) return;
    const result = await this.streamOpened;
    if (this.disposed) {
      throw conversationError('OpenCode conversation handle is disposed.', {
        status: 409,
        code: 'OPENCODE_CONVERSATION_DISPOSED'
      });
    }
    if (this.streamDisconnected || !this.subscription || result?.ok !== true) {
      throw streamInterruptedError();
    }
  }

  async respondApproval(approvalId, decision) {
    const approvalKey = safeString(approvalId);
    const context = this.pendingApprovals.get(approvalKey);
    if (!context) {
      throw conversationError('OpenCode approval request is not pending.', {
        status: 409,
        code: 'OPENCODE_APPROVAL_NOT_PENDING'
      });
    }
    const normalizedDecision = typeof decision === 'string' ? { decision } : (decision || {});
    try {
      await this.client.replyPermission({
        sessionId: context.sessionId,
        permissionId: context.permissionId,
        decision: normalizedDecision.decision,
        scope: normalizedDecision.scope
      });
    } catch (error) {
      this.terminalize();
      throw error;
    }
    this.pendingApprovals.delete(approvalKey);
    this.locallyResolvedApprovals.add(approvalKey);
    if (normalizedDecision.decision === 'cancel') {
      await this.cancel();
      this.onEvent({
        type: conversationEventTypes.CONVERSATION_CANCELLED,
        reason: 'approval_cancelled',
        sessionId: this.sessionId
      });
      this.terminalize();
    }
  }

  async cancel() {
    if (!this.sessionId) {
      this.terminalize();
      return;
    }
    this.activeTurn = false;
    try {
      await this.client.abortSession({ sessionId: this.sessionId });
    } catch (error) {
      this.onEvent({
        type: conversationEventTypes.PROTOCOL_WARNING,
        warning: 'opencode_abort_failed',
        visible: false,
        message: limitString(error?.message || 'OpenCode abort failed'),
        code: safeString(error?.code) || 'OPENCODE_ABORT_FAILED'
      });
    } finally {
      this.terminalize();
    }
  }

  async dispose() {
    if (this.disposed) return;
    this.disposed = true;
    this.cancelPendingApprovals('opencode_conversation_disposed');
    this.closeSubscription();
  }

  closeSubscription() {
    if (this.subscription && typeof this.subscription.close === 'function') {
      this.subscription.close();
    }
    this.subscription = null;
    this.streamOpened = null;
  }

  terminalize() {
    this.disposed = true;
    this.promptDispatching = false;
    this.activeTurn = false;
    this.closeSubscription();
  }

  handleRawEvent(raw) {
    if (this.disposed || this.streamFailed || this.streamDisconnected) return;
    const rawSessionId = extractEventSessionId(raw);
    if (rawSessionId && rawSessionId !== this.sessionId) return;
    if (!rawSessionId) {
      const warning = this.mapper(raw, { workspacePath: this.workspacePath });
      if (warning?.type === conversationEventTypes.PROTOCOL_WARNING && warning.dispatchable === false) {
        this.emitMissingSessionWarning(warning);
      }
      return;
    }
    const mapped = this.mapper(raw, { workspacePath: this.workspacePath });
    if (!mapped || mapped.dispatchable === false) return;
    if (mapped.sessionId && mapped.sessionId !== this.sessionId) return;
    if (mapped.type === conversationEventTypes.APPROVAL_REQUESTED && mapped.approvalId) {
      const approvalId = safeString(mapped.approvalId);
      this.pendingApprovals.set(approvalId, {
        sessionId: this.sessionId,
        permissionId: approvalId
      });
    }
    if (mapped.type === conversationEventTypes.APPROVAL_RESOLVED && mapped.approvalId) {
      const approvalId = safeString(mapped.approvalId);
      if (this.locallyResolvedApprovals.has(approvalId)) return;
      this.pendingApprovals.delete(approvalId);
    }
    if (isTerminalEvent(mapped)) {
      this.cancelPendingApprovals('opencode_turn_ended');
      this.activeTurn = false;
    }
    this.onEvent(mapped);
    if (isTerminalEvent(mapped)) {
      this.terminalize();
    }
  }

  emitMissingSessionWarning(warning) {
    const key = safeString(warning.rawType || warning.warning || 'missing_session');
    if (this.missingSessionWarnings.has(key)) return;
    this.missingSessionWarnings.add(key);
    this.onEvent({
      ...warning,
      visible: false
    });
  }

  handleStreamError(error) {
    if (this.disposed || this.streamFailed) return;
    this.streamDisconnected = true;
    if (!this.activeTurn && this.pendingApprovals.size === 0) {
      this.closeSubscription();
      this.onEvent({
        type: conversationEventTypes.PROTOCOL_WARNING,
        warning: 'opencode_event_stream_interrupted',
        visible: false,
        message: limitString(error?.message || 'OpenCode event stream interrupted'),
        code: 'OPENCODE_EVENT_STREAM_INTERRUPTED',
        details: { cause: errorDetails(error) }
      });
      return;
    }
    this.streamFailed = true;
    this.terminalize();
    this.cancelPendingApprovals('opencode_event_stream_interrupted');
    this.onEvent({
      type: conversationEventTypes.RUN_ERROR,
      code: 'OPENCODE_EVENT_STREAM_INTERRUPTED',
      status: 503,
      message: 'OpenCode event stream interrupted before the active turn completed.',
      details: { cause: errorDetails(error) }
    });
  }

  cancelPendingApprovals(reason) {
    if (this.pendingApprovals.size === 0) return;
    const pending = Array.from(this.pendingApprovals.values());
    this.pendingApprovals.clear();
    for (const item of pending) {
      this.onEvent({
        type: conversationEventTypes.BLOCKING_REQUEST_CANCELLED,
        blockingType: 'approval_request',
        approvalId: item.permissionId,
        reason,
        code: reason === 'opencode_event_stream_interrupted'
          ? 'OPENCODE_EVENT_STREAM_INTERRUPTED'
          : 'OPENCODE_APPROVAL_CANCELLED'
      });
    }
  }
}

function unavailableCapability(message, { code, diagnostics } = {}) {
  return {
    adapter: 'opencode',
    available: false,
    selectable: false,
    status: 'unavailable',
    unavailableReason: code || 'OPENCODE_SERVER_UNAVAILABLE',
    error: message,
    ...MODEL_CAPABILITY,
    capabilities: cloneCapabilities(),
    diagnostics: diagnostics || null
  };
}

function cloneCapabilities() {
  return {
    ...CAPABILITIES,
    approval: { ...CAPABILITIES.approval, scopes: [...CAPABILITIES.approval.scopes], denyBehaviors: [...CAPABILITIES.approval.denyBehaviors] },
    attachments: { ...CAPABILITIES.attachments }
  };
}

function buildProviderSession({ sessionId, now }) {
  return {
    provider: 'opencode',
    threadId: sessionId,
    protocolVersion: 1,
    createdAt: now().toISOString()
  };
}

function extractEventSessionId(value) {
  if (!value || typeof value !== 'object') return null;
  const direct = firstNonBlank([
    value.sessionId,
    value.sessionID,
    value.session_id
  ]);
  if (direct) return direct;
  if (typeof value.session === 'string' || typeof value.session === 'number') return safeString(value.session);
  if (value.session && typeof value.session === 'object') {
    return firstNonBlank([
      value.session.id,
      value.session.sessionId,
      value.session.sessionID,
      value.session.session_id
    ]);
  }
  return null;
}

function clearMissingSessionBinding(actions, expectedSessionId, cause) {
  if (!actions || typeof actions.clearSessionBinding !== 'function') return;
  actions.clearSessionBinding({
    expectedSessionId,
    reason: isMissingSessionError(cause)
      ? 'OpenCode session missing'
      : 'OpenCode session unreadable',
    code: 'OPENCODE_SESSION_MISSING',
    noticeKind: 'opencode_session_expired',
    visible: true
  });
}

function markDriftedSessionBinding(actions, {
  expectedSessionId,
  receivedSessionId,
  reason,
  code
}) {
  if (!actions || typeof actions.markSessionBindingDrifted !== 'function') return;
  actions.markSessionBindingDrifted({
    expectedSessionId,
    receivedSessionId,
    reason,
    code,
    clear: true
  });
}

function sessionMissingError(cause, sessionId) {
  const status = isMissingSessionError(cause) ? 409 : 503;
  return conversationError('OpenCode session is missing or unreadable.', {
    status,
    code: 'OPENCODE_SESSION_MISSING',
    details: {
      sessionId,
      cause: errorDetails(cause)
    }
  });
}

function streamInterruptedError() {
  return conversationError('OpenCode event stream is interrupted; start a new conversation handle before sending.', {
    status: 503,
    code: 'OPENCODE_EVENT_STREAM_INTERRUPTED'
  });
}

function isMissingSessionError(error) {
  return error?.status === 404 ||
    error?.details?.status === 404 ||
    error?.details?.body?.error?.code === 'SESSION_NOT_FOUND';
}

function requireWorkspacePath(workspacePath) {
  const workspace = safeString(workspacePath);
  if (!workspace) {
    throw conversationError('workspacePath is required', {
      status: 400,
      code: 'BAD_REQUEST'
    });
  }
  return workspace;
}

function messageText(message) {
  if (typeof message === 'string' || typeof message === 'number') return String(message);
  if (message && typeof message === 'object') {
    return String(message.text ?? message.prompt ?? '');
  }
  return '';
}

function isPromiseLike(value) {
  return !!value && typeof value.then === 'function';
}

function isTerminalEvent(event) {
  return event?.type === conversationEventTypes.CONVERSATION_COMPLETED ||
    event?.type === conversationEventTypes.CONVERSATION_CANCELLED ||
    event?.type === conversationEventTypes.RUN_ERROR;
}

function conversationError(message, { status, code, details } = {}) {
  const error = new Error(message);
  if (status !== undefined) error.status = status;
  if (code) error.code = code;
  if (details !== undefined) error.details = safeDiagnosticObject(details);
  return error;
}

function publicLifecycleStartupError(error) {
  const status = safeHttpStatus(error?.status) || 503;
  const code = safeTokenString(error?.code || error?.name) || 'OPENCODE_SERVER_UNAVAILABLE';
  return conversationError('OpenCode server unavailable.', {
    status,
    code,
    details: safeLifecycleStartupDetails(error, { code, status })
  });
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

function safeLifecycleDiagnostics(value) {
  if (!value || typeof value !== 'object') return null;
  const result = {};
  const status = safeTokenString(value.status);
  if (status) result.status = status;
  const lastErrorCode = safeTokenString(value.lastError?.code);
  if (lastErrorCode) result.lastError = { code: lastErrorCode };
  return Object.keys(result).length > 0 ? result : null;
}

function safeHealthDiagnostics(value) {
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

function errorDetails(error) {
  if (!error) return null;
  const result = {};
  const status = safeHttpStatus(error.status);
  if (status) result.status = status;
  const code = safeTokenString(error.code || error.name);
  if (code) result.code = code;
  const details = safePublicErrorDetails(error.details);
  if (details) result.details = details;
  return Object.keys(result).length > 0 ? result : null;
}

function safePublicErrorDetails(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const result = {};
  const status = safeHttpStatus(value.status);
  if (status) result.status = status;
  const method = safeHttpMethod(value.method);
  if (method) result.method = method;
  const routePath = safeRoutePath(value.path);
  if (routePath) result.path = routePath;
  const code = safeTokenString(value.code);
  if (code) result.code = code;
  const providerCode = safeTokenString(value.providerCode);
  if (providerCode) result.providerCode = providerCode;
  const providerStatus = safeTokenString(value.providerStatus);
  if (providerStatus) result.providerStatus = providerStatus;
  const reason = safeTokenString(value.reason);
  if (reason) result.reason = reason;
  const timeoutMs = safeBoundedInteger(value.timeoutMs, 1, 300000);
  if (timeoutMs !== null) result.timeoutMs = timeoutMs;
  return Object.keys(result).length > 0 ? result : null;
}

function safeDiagnosticObject(value, depth = 0, seen = new Set()) {
  if (value === null || value === undefined) return value;
  if (typeof value === 'string') return limitString(value);
  if (typeof value === 'number' || typeof value === 'boolean') return value;
  if (typeof value !== 'object') return limitString(String(value));
  if (depth >= 4) return '[Truncated]';
  if (seen.has(value)) return '[Circular]';
  seen.add(value);
  if (Array.isArray(value)) {
    const result = value.slice(0, 20).map((item) => safeDiagnosticObject(item, depth + 1, seen));
    seen.delete(value);
    return result;
  }
  const result = {};
  for (const key of Object.keys(value).slice(0, 20)) {
    if (key === '__proto__' || key === 'prototype' || key === 'constructor') continue;
    result[key] = safeDiagnosticObject(value[key], depth + 1, seen);
  }
  seen.delete(value);
  return result;
}

function firstNonBlank(values) {
  for (const value of values) {
    const text = safeString(value);
    if (text) return text;
  }
  return null;
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

function safeBoundedInteger(value, min, max) {
  const number = Number(value);
  if (!Number.isSafeInteger(number) || number < min || number > max) return null;
  return number;
}

function safeHttpMethod(value) {
  const method = safeTokenString(value, 16);
  if (!method) return null;
  return ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS'].includes(method) ? method : null;
}

function safeRoutePath(value) {
  const text = safeString(value);
  if (!text || text.length > 128 || !text.startsWith('/') || text.includes('?')) return null;
  return /^[A-Za-z0-9_/:.-]+$/.test(text) ? text : null;
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

function limitString(value, maxLength = 512) {
  const text = String(value || '');
  if (text.length <= maxLength) return text;
  return `${text.slice(0, maxLength - 14)}...[truncated]`;
}

module.exports = {
  OpenCodeConversationAdapter,
  pathContainsOrEquals
};
