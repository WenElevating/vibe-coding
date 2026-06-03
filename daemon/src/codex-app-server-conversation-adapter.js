'use strict';

const { buildCodexAppServerAvailability } = require('./codex-app-server-availability');
const { conversationEventTypes } = require('./conversation-protocol');
const {
  buildCodexAppServerApprovalResponse,
  mapCodexAppServerApprovalRequest
} = require('./codex-app-server-approval');
const {
  buildCodexAppServerThreadResumeRequest,
  buildCodexAppServerThreadStartRequest,
  buildCodexAppServerTurnInterruptRequest,
  buildCodexAppServerTurnStartRequest,
  mapCodexAppServerNotification
} = require('./codex-app-server-bridge');

class CodexAppServerConversationAdapter {
  constructor({
    availability = null,
    lifecycle = null,
    toolTimeoutSec = null,
    approvalTimeoutMs = 120000,
    initializeTimeoutMs = 10000
  } = {}) {
    this.name = 'codex-app-server';
    this.toolTimeoutSec = toolTimeoutSec;
    this.approvalTimeoutMs = Math.max(1, Number(approvalTimeoutMs) || 120000);
    this.initializeTimeoutMs = Math.max(1, Number(initializeTimeoutMs) || 10000);
    this.lifecycle = lifecycle;
    this.availability = availability || buildCodexAppServerAvailability({ enabled: false });
    this.capabilities = this.availability.effectiveCapabilities || {};
    this.metrics = {
      spawnFailure: 0,
      initializeLatencyMs: null,
      approvalRequestedCount: 0,
      approvalTimeoutCount: 0,
      approvalRoundTripLatencyMs: [],
      transportCloseCount: 0,
      runErrorAfterTurnStartedCount: 0
    };
  }

  detectCapabilities() {
    return {
      adapter: this.name,
      available: this.availability.selectable === true,
      status: this.availability.selectable === true ? 'available' : 'unavailable',
      ...this.availability,
      capabilities: this.availability.effectiveCapabilities || {},
      diagnostics: {
        metrics: snapshotMetrics(this.metrics)
      }
    };
  }

  getCapabilities() {
    return this.availability.effectiveCapabilities || {};
  }

  async startConversation({ conversationId, workspacePath, permissionMode = 'default', sessionId, model, onEvent } = {}) {
    if (!this.availability || this.availability.selectable !== true) {
      const reason = this.availability?.unavailableReason || 'unavailable';
      const error = new Error(`Codex app-server adapter is not selectable: ${reason}`);
      error.status = 503;
      error.code = 'CODEX_APP_SERVER_UNAVAILABLE';
      throw error;
    }
    if (!this.lifecycle || typeof this.lifecycle.spawn !== 'function') {
      const error = new Error('Codex app-server lifecycle is not configured');
      error.status = 503;
      error.code = 'CODEX_APP_SERVER_LIFECYCLE_MISSING';
      throw error;
    }
    let processHandle;
    try {
      processHandle = this.lifecycle.spawn();
    } catch (error) {
      this.metrics.spawnFailure += 1;
      error.codexAppServerFallbackAllowed = true;
      throw error;
    }
    const conversationHandle = new CodexAppServerConversationHandle({
      adapter: this,
      processHandle,
      conversationId,
      workspacePath,
      permissionMode,
      sessionId,
      model,
      onEvent
    });
    try {
      await conversationHandle.initialize();
      return conversationHandle;
    } catch (error) {
      await conversationHandle.dispose();
      error.codexAppServerFallbackAllowed = conversationHandle.sideEffectBoundaryCrossed !== true;
      throw error;
    }
  }
}

class CodexAppServerConversationHandle {
  constructor({ adapter, processHandle, conversationId, workspacePath, permissionMode, sessionId, model, onEvent }) {
    if (!processHandle || !processHandle.transport) throw new Error('Codex app-server process handle must expose a transport');
    if (!workspacePath || !String(workspacePath).trim()) throw new Error('workspacePath is required');
    this.adapter = adapter;
    this.processHandle = processHandle;
    this.transport = processHandle.transport;
    this.conversationId = conversationId || null;
    this.workspacePath = workspacePath;
    this.permissionMode = permissionMode || 'default';
    this.sessionId = sessionId || null;
    this.model = model || null;
    this.onEvent = typeof onEvent === 'function' ? onEvent : () => {};
    this.threadId = sessionId || null;
    this.activeTurnId = null;
    this.pendingApprovals = new Map();
    this.resolvedApprovals = new Set();
    this.providerSessionCreatedAt = new Date().toISOString();
    this.disposed = false;
    this.closed = false;
    this.initialized = false;
    this.turnHadRunError = false;
    this.sideEffectBoundaryCrossed = false;
    this._bindTransport();
  }

  async initialize() {
    const initializeStarted = Date.now();
    await this.transport.sendRequest('initialize', {
      clientInfo: {
        name: 'vibe-coding-daemon',
        title: 'vibe-coding daemon',
        version: '0.1.0'
      },
      capabilities: {
        experimentalApi: true,
        requestAttestation: false
      }
    }, { timeoutMs: this.adapter.initializeTimeoutMs });
    this.adapter.metrics.initializeLatencyMs = Date.now() - initializeStarted;
    this.transport.sendNotification('initialized', {});
    const resuming = !!this.sessionId;
    const threadRequest = resuming
      ? buildCodexAppServerThreadResumeRequest({
        threadId: this.sessionId,
        workspacePath: this.workspacePath,
        permissionMode: this.permissionMode,
        model: this.model,
        toolTimeoutSec: this.adapter.toolTimeoutSec
      })
      : buildCodexAppServerThreadStartRequest({
        workspacePath: this.workspacePath,
        permissionMode: this.permissionMode,
        model: this.model,
        toolTimeoutSec: this.adapter.toolTimeoutSec
      });
    this.sideEffectBoundaryCrossed = true;
    const response = await this.transport.sendRequest(threadRequest.method, threadRequest.params);
    const threadId = stringValue(response?.thread?.id) || this.sessionId;
    if (!threadId) throw new Error(`${threadRequest.method} did not return thread.id`);
    this.threadId = threadId;
    this.sessionId = threadId;
    this.initialized = true;
    this.onEvent({
      type: conversationEventTypes.SYSTEM_NOTICE,
      noticeKind: resuming ? 'codex_app_server_thread_ready' : 'codex_app_server_thread_started',
      visible: false,
      sessionId: threadId,
      providerSession: this.buildProviderSession()
    });
  }

  async sendUserMessage(message) {
    if (!this.initialized) throw new Error('Codex app-server conversation is not initialized');
    if (this.activeTurnId) {
      const error = new Error('Codex app-server turn is already running');
      error.status = 409;
      throw error;
    }
    const turnRequest = buildCodexAppServerTurnStartRequest({
      threadId: this.threadId,
      clientUserMessageId: plainObject(message) ? message.clientMessageId : null,
      workspacePath: this.workspacePath,
      permissionMode: this.permissionMode,
      model: this.model,
      message
    });
    const response = await this.transport.sendRequest(turnRequest.method, turnRequest.params);
    const turnId = stringValue(response?.turn?.id);
    if (!turnId) throw new Error('turn/start did not return turn.id');
    this.activeTurnId = turnId;
    this.turnHadRunError = false;
  }

  async respondApproval(approvalId, response) {
    const context = this.pendingApprovals.get(approvalId);
    if (!context) {
      if (this.resolvedApprovals.has(approvalId)) return;
      const error = new Error('approval request is not pending');
      error.status = 409;
      throw error;
    }
    this.resolveApproval(approvalId, response);
  }

  async cancel() {
    if (!this.activeTurnId || !this.threadId || this.closed) return;
    const interrupt = buildCodexAppServerTurnInterruptRequest({
      threadId: this.threadId,
      turnId: this.activeTurnId
    });
    try {
      await this.transport.sendRequest(interrupt.method, interrupt.params);
    } catch (error) {
      this.onEvent({
        type: conversationEventTypes.PROTOCOL_WARNING,
        warning: 'codex_app_server_turn_interrupt_failed',
        message: error.message
      });
    }
  }

  async dispose() {
    this.disposed = true;
    this.cancelPendingApprovals('disposed');
    if (this.processHandle && typeof this.processHandle.shutdown === 'function') {
      await this.processHandle.shutdown();
    }
  }

  _bindTransport() {
    this.transport.on('notification', (message) => this.handleNotification(message));
    this.transport.on('serverRequest', (message) => this.handleServerRequest(message));
    this.transport.on('protocolError', ({ error }) => {
      this.onEvent({
        type: conversationEventTypes.PROTOCOL_WARNING,
        warning: 'codex_app_server_protocol_error',
        message: error.message
      });
    });
    this.transport.on('protocolWarning', (warning) => {
      this.onEvent({
        type: conversationEventTypes.PROTOCOL_WARNING,
        warning: 'codex_app_server_protocol_warning',
        detail: warning
      });
    });
    this.transport.on('stderr', (text) => {
      if (!String(text || '').trim()) return;
      this.onEvent({
        type: conversationEventTypes.PROTOCOL_WARNING,
        warning: 'codex_app_server_stderr',
        text
      });
    });
    this.transport.on('closed', (error) => this.handleTransportClosed(error));
  }

  handleNotification(message) {
    if (message?.method === 'serverRequest/resolved' && message.params) {
      this.markApprovalResolvedByRequestId(message.params.requestId ?? message.params.request_id);
    }
    if (message?.method === 'turn/started') {
      const turnId = stringValue(message.params?.turn?.id) || stringValue(message.params?.turnId);
      if (turnId) this.activeTurnId = turnId;
    }
    const event = mapCodexAppServerNotification(message, { workspacePath: this.workspacePath });
    if (!event) return;
    if (event.sessionId) {
      event.providerSession = this.buildProviderSession();
    }
    this.onEvent(event);
    if (
      event.type === conversationEventTypes.CONVERSATION_COMPLETED ||
      event.type === conversationEventTypes.CONVERSATION_CANCELLED ||
      event.type === conversationEventTypes.RUN_ERROR
    ) {
      this.activeTurnId = null;
      this.cancelPendingApprovals('turn_completed');
    }
  }

  handleServerRequest(message) {
    const approval = mapCodexAppServerApprovalRequest(message);
    if (!approval) {
      this.failClosedServerRequest(message, 'unsupported Codex app-server server request');
      return;
    }
    const { context, event } = approval;
    this.adapter.metrics.approvalRequestedCount += 1;
    const timer = setTimeout(() => {
      if (!this.pendingApprovals.has(context.approvalId)) return;
      this.resolveApproval(context.approvalId, { decision: 'deny', interrupt: false }, { timedOut: true });
    }, this.adapter.approvalTimeoutMs);
    if (typeof timer.unref === 'function') timer.unref();
    this.pendingApprovals.set(context.approvalId, { ...context, timer, requestedAt: Date.now() });
    this.onEvent(event);
  }

  failClosedServerRequest(message, reason) {
    if (message?.id !== undefined) {
      this.transport.sendError(message.id, {
        code: -32601,
        message: reason
      });
    }
    this.onEvent({
      type: conversationEventTypes.RUN_ERROR,
      message: `${reason}: ${message?.method || 'unknown'}`
    });
  }

  resolveApproval(approvalId, response, { timedOut = false } = {}) {
    const context = this.pendingApprovals.get(approvalId);
    if (!context) return;
    clearTimeout(context.timer);
    this.pendingApprovals.delete(approvalId);
    this.resolvedApprovals.add(approvalId);
    if (timedOut) this.adapter.metrics.approvalTimeoutCount += 1;
    if (context.requestedAt) {
      this.adapter.metrics.approvalRoundTripLatencyMs.push(Date.now() - context.requestedAt);
      if (this.adapter.metrics.approvalRoundTripLatencyMs.length > 100) {
        this.adapter.metrics.approvalRoundTripLatencyMs.shift();
      }
    }
    const rpcResponse = buildCodexAppServerApprovalResponse(context, response);
    this.transport.sendResult(rpcResponse.id, rpcResponse.result);
    this.onEvent({
      type: conversationEventTypes.APPROVAL_RESOLVED,
      approvalId,
      decision: response?.decision || null,
      timedOut
    });
  }

  markApprovalResolvedByRequestId(requestId) {
    for (const [approvalId, context] of this.pendingApprovals.entries()) {
      if (context.requestId !== requestId) continue;
      clearTimeout(context.timer);
      this.pendingApprovals.delete(approvalId);
      this.resolvedApprovals.add(approvalId);
      this.onEvent({
        type: conversationEventTypes.APPROVAL_RESOLVED,
        approvalId
      });
      return;
    }
  }

  cancelPendingApprovals(reason) {
    for (const [approvalId, context] of this.pendingApprovals.entries()) {
      clearTimeout(context.timer);
      this.pendingApprovals.delete(approvalId);
      this.resolvedApprovals.add(approvalId);
      this.onEvent({
        type: conversationEventTypes.BLOCKING_REQUEST_CANCELLED,
        blockingType: 'approval_request',
        approvalId,
        reason
      });
    }
  }

  handleTransportClosed(error) {
    if (this.closed) return;
    this.closed = true;
    this.adapter.metrics.transportCloseCount += 1;
    this.cancelPendingApprovals('transport_closed');
    if (!this.disposed && this.activeTurnId) {
      this.adapter.metrics.runErrorAfterTurnStartedCount += 1;
      this.turnHadRunError = true;
      this.onEvent({
        type: conversationEventTypes.RUN_ERROR,
        message: error?.message || 'Codex app-server transport closed'
      });
    }
  }

  buildProviderSession() {
    return {
      provider: 'codex-app-server',
      threadId: this.threadId,
      protocolVersion: 2,
      cwd: this.workspacePath,
      model: this.model,
      sandboxProfile: 'read-only-thread/workspace-write-turn',
      createdAt: this.providerSessionCreatedAt
    };
  }
}

function plainObject(value) {
  return !!value && typeof value === 'object' && !Array.isArray(value);
}

function stringValue(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function snapshotMetrics(metrics) {
  return {
    spawnFailure: Number(metrics.spawnFailure || 0),
    initializeLatencyMs: Number.isFinite(metrics.initializeLatencyMs) ? metrics.initializeLatencyMs : null,
    approvalRequestedCount: Number(metrics.approvalRequestedCount || 0),
    approvalTimeoutCount: Number(metrics.approvalTimeoutCount || 0),
    approvalRoundTripLatencyMs: Array.isArray(metrics.approvalRoundTripLatencyMs)
      ? metrics.approvalRoundTripLatencyMs.slice(-20).filter(Number.isFinite)
      : [],
    transportCloseCount: Number(metrics.transportCloseCount || 0),
    runErrorAfterTurnStartedCount: Number(metrics.runErrorAfterTurnStartedCount || 0)
  };
}

module.exports = {
  CodexAppServerConversationAdapter,
  CodexAppServerConversationHandle
};
