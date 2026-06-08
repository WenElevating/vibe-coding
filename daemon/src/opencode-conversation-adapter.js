'use strict';

const { conversationEventTypes } = require('./conversation-protocol');
const { textAttachmentWrapper } = require('./attachment-validation');
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
      const healthDiagnostics = safeHealthDiagnostics(health);
      return {
        adapter: this.name,
        available: true,
        selectable: true,
        status: 'available',
        version: healthDiagnostics?.version || null,
        serverUrl: publicServerUrl(started.serverUrl),
        mode: safeString(started.mode) || null,
        owned: started.owned === true,
        ...this.getModelCapability(),
        capabilities: this.getCapabilities(),
        diagnostics: {
          lifecycle: this.lifecycleDiagnostics(),
          health: healthDiagnostics
        }
      };
    } catch (error) {
      const code = safeTokenString(safeErrorField(error, 'code') || safeErrorField(error, 'name')) ||
        'OPENCODE_SERVER_UNAVAILABLE';
      return unavailableCapability('OpenCode server unavailable. Start OpenCode server or check OpenCode installation.', {
        code,
        diagnostics: {
          lifecycle: this.lifecycleDiagnostics(),
          cause: safeLifecycleStartupDetails(error, {
            code,
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
        throw sessionMissingError(error);
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
      throw sessionMissingError(new Error('OpenCode readSession returned a different session id'));
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
        message: 'OpenCode abort failed.',
        code: 'OPENCODE_ABORT_FAILED',
        details: { cause: errorDetails(error) }
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
        message: 'OpenCode event stream interrupted.',
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
    safeOwnValue(value, 'sessionId'),
    safeOwnValue(value, 'sessionID'),
    safeOwnValue(value, 'session_id')
  ]);
  if (direct) return direct;
  const session = safeOwnValue(value, 'session');
  if (typeof session === 'string' || typeof session === 'number') return safeString(session);
  if (session && typeof session === 'object') {
    return firstNonBlank([
      safeOwnValue(session, 'id'),
      safeOwnValue(session, 'sessionId'),
      safeOwnValue(session, 'sessionID'),
      safeOwnValue(session, 'session_id')
    ]);
  }
  return null;
}

function safeOwnValue(value, key) {
  if (!value || typeof value !== 'object') return undefined;
  try {
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    if (!descriptor || !Object.prototype.hasOwnProperty.call(descriptor, 'value')) return undefined;
    return descriptor.value;
  } catch (_) {
    return undefined;
  }
}

function safeErrorField(error, key) {
  if (!error || (typeof error !== 'object' && typeof error !== 'function')) return undefined;
  let current = error;
  while (current) {
    const value = safeDataPropertyValue(current, key);
    if (value !== undefined) return value;
    try {
      const descriptor = Object.getOwnPropertyDescriptor(current, key);
      if (descriptor && !Object.prototype.hasOwnProperty.call(descriptor, 'value')) return undefined;
      current = Object.getPrototypeOf(current);
    } catch (_) {
      return undefined;
    }
  }
  return undefined;
}

function safeDataPropertyValue(value, key) {
  if (!value || (typeof value !== 'object' && typeof value !== 'function')) return undefined;
  try {
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    if (!descriptor || !Object.prototype.hasOwnProperty.call(descriptor, 'value')) return undefined;
    return descriptor.value;
  } catch (_) {
    return undefined;
  }
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

function sessionMissingError(cause) {
  const status = isMissingSessionError(cause) ? 409 : 503;
  return conversationError('OpenCode session is missing or unreadable.', {
    status,
    code: 'OPENCODE_SESSION_MISSING',
    details: {
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
  const details = safeErrorField(error, 'details');
  const body = safeOwnValue(details, 'body');
  const bodyError = safeOwnValue(body, 'error');
  return safeErrorField(error, 'status') === 404 ||
    safeOwnValue(details, 'status') === 404 ||
    safeOwnValue(bodyError, 'code') === 'SESSION_NOT_FOUND';
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
    return buildOpenCodePromptText({
      text: message.text ?? message.prompt ?? '',
      attachments: message.attachments
    });
  }
  return '';
}

function buildOpenCodePromptText({ text, attachments = [] } = {}) {
  const parts = [];
  const prompt = String(text ?? '');
  if (prompt) parts.push(prompt);
  for (const attachment of Array.isArray(attachments) ? attachments : []) {
    if (!attachment || typeof attachment !== 'object') continue;
    if (attachment.kind === 'textDocument' && attachment.handling === 'text_extract') {
      parts.push(textAttachmentWrapper({
        name: attachment.name,
        mimeType: attachment.mimeType,
        text: attachment.text
      }));
    }
  }
  return parts.join('\n\n');
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
  const status = safeHttpStatus(safeErrorField(error, 'status')) || 503;
  const code = safeTokenString(safeErrorField(error, 'code') || safeErrorField(error, 'name')) ||
    'OPENCODE_SERVER_UNAVAILABLE';
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
  const details = safeErrorField(error, 'details');
  const detailsCause = safeOwnValue(details, 'cause');
  const cause = safeErrorField(error, 'cause');
  const reason = safeTokenString(safeErrorField(error, 'reason')) ||
    safeTokenString(safeOwnValue(details, 'reason')) ||
    safeTokenString(safeOwnValue(detailsCause, 'code') || safeOwnValue(detailsCause, 'name')) ||
    safeTokenString(safeErrorField(cause, 'code') || safeErrorField(cause, 'name'));
  if (reason && reason !== code) result.reason = reason;
  return Object.keys(result).length > 0 ? result : null;
}

function safeLifecycleDiagnostics(value) {
  if (!value || typeof value !== 'object') return null;
  const result = {};
  const status = safeTokenString(safeOwnValue(value, 'status'));
  if (status) result.status = status;
  const lastError = safeOwnValue(value, 'lastError');
  const lastErrorCode = safeTokenString(safeErrorField(lastError, 'code') || safeOwnValue(lastError, 'code'));
  if (lastErrorCode) result.lastError = { code: lastErrorCode };
  return Object.keys(result).length > 0 ? result : null;
}

function safeHealthDiagnostics(value) {
  if (!value || typeof value !== 'object') return null;
  const result = {};
  const ok = safeOwnValue(value, 'ok');
  if (typeof ok === 'boolean') result.ok = ok;
  const version = safeDisplayString(safeOwnValue(value, 'version'));
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
  const status = safeHttpStatus(safeErrorField(error, 'status'));
  if (status) result.status = status;
  const code = safeTokenString(safeErrorField(error, 'code') || safeErrorField(error, 'name'));
  if (code) result.code = code;
  const details = safePublicErrorDetails(safeErrorField(error, 'details'));
  if (details) result.details = details;
  return Object.keys(result).length > 0 ? result : null;
}

function safePublicErrorDetails(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const result = {};
  const status = safeHttpStatus(safeOwnValue(value, 'status'));
  if (status) result.status = status;
  const method = safeHttpMethod(safeOwnValue(value, 'method'));
  if (method) result.method = method;
  const routePath = safeRoutePath(safeOwnValue(value, 'path'));
  if (routePath) result.path = routePath;
  const code = safeTokenString(safeOwnValue(value, 'code'));
  if (code) result.code = code;
  const providerCode = safeTokenString(safeOwnValue(value, 'providerCode'));
  if (providerCode) result.providerCode = providerCode;
  const providerStatus = safeTokenString(safeOwnValue(value, 'providerStatus'));
  if (providerStatus) result.providerStatus = providerStatus;
  const reason = safeTokenString(safeOwnValue(value, 'reason'));
  if (reason) result.reason = reason;
  const timeoutMs = safeBoundedInteger(safeOwnValue(value, 'timeoutMs'), 1, 300000);
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
    const result = [];
    for (let index = 0; index < Math.min(value.length, 20); index += 1) {
      result.push(safeDiagnosticObject(safeDataPropertyValue(value, String(index)), depth + 1, seen));
    }
    seen.delete(value);
    return result;
  }
  const result = {};
  for (const key of safeEnumerableKeys(value).slice(0, 20)) {
    if (key === '__proto__' || key === 'prototype' || key === 'constructor') continue;
    const fieldValue = safeDataPropertyValue(value, key);
    if (fieldValue !== undefined) result[key] = safeDiagnosticObject(fieldValue, depth + 1, seen);
  }
  seen.delete(value);
  return result;
}

function safeEnumerableKeys(value) {
  try {
    return Object.keys(value);
  } catch (_) {
    return [];
  }
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
  if (typeof value !== 'number' && typeof value !== 'string') return null;
  const status = Number(value);
  if (!Number.isInteger(status) || status < 100 || status > 599) return null;
  return status;
}

function safeBoundedInteger(value, min, max) {
  if (typeof value !== 'number' && typeof value !== 'string') return null;
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
