'use strict';

const crypto = require('node:crypto');
const {
  conversationStatuses,
  conversationSessionBindings,
  conversationEventTypes,
  normalizeConversationCreate,
  normalizeMessagePayload,
  normalizeQuestionResponse,
  normalizeApprovalDecision
} = require('./conversation-protocol');

class ConversationManager {
  constructor({ workspaces, eventStore, auditLog, adapters, persistentStore = null, idleTtlMs = 600000, now = () => new Date() }) {
    this.workspaces = workspaces;
    this.eventStore = eventStore;
    this.auditLog = auditLog;
    this.adapters = adapters;
    this.persistentStore = persistentStore;
    this.idleTtlMs = idleTtlMs;
    this.now = now;
    this.conversations = new Map();
    this.loadPersistedConversations();
  }

  loadPersistedConversations() {
    if (!this.persistentStore) return;
    for (const loaded of this.persistentStore.loadConversations()) {
      const conversation = this.normalizeRestoredConversation(loaded);
      this.conversations.set(conversation.id, conversation);
      if (conversation.status !== loaded.status || loaded.blockingItem || loaded.idleExpiresAt) {
        this.persistConversation(conversation);
      }
    }
  }

  normalizeRestoredConversation(conversation) {
    const restored = { ...conversation, handle: null };
    if ([conversationStatuses.RUNNING, conversationStatuses.WAITING_INPUT, conversationStatuses.WAITING_APPROVAL].includes(restored.status)) {
      restored.status = conversationStatuses.INTERRUPTED;
      restored.blockingItem = null;
      restored.idleExpiresAt = null;
      restored.updatedAt = this.now().toISOString();
    }
    return restored;
  }

  persistConversation(conversation) {
    if (this.persistentStore) this.persistentStore.saveConversation(conversation);
  }

  createConversation(payload, device) {
    const input = normalizeConversationCreate(payload);
    const workspace = this.workspaces.getAuthorized(input.workspaceId, device);
    const adapter = this.getAdapter(input.adapter);
    const conversation = {
      id: `conv_${crypto.randomUUID()}`,
      workspaceId: workspace.id,
      workspacePath: workspace.path,
      adapter: input.adapter,
      permissionMode: input.permissionMode,
      requestedPermissionMode: input.permissionMode,
      effectivePermissionMode: input.permissionMode,
      requestedTools: input.requestedTools,
      requestedToolPolicy: input.requestedToolPolicy,
      resumePolicy: input.resumePolicy,
      systemPromptPolicy: input.systemPromptPolicy,
      permissionSupport: {},
      notices: [],
      protocolVersion: 2,
      deviceId: device.id,
      status: conversationStatuses.IDLE,
      cliSessionId: null,
      sessionBinding: conversationSessionBindings.UNKNOWN,
      userMessageCount: 0,
      blockingItem: null,
      idleExpiresAt: addMs(this.now(), this.idleTtlMs).toISOString(),
      createdAt: this.now().toISOString(),
      updatedAt: this.now().toISOString(),
      capabilities: adapter.capabilities || {},
      handle: null
    };
    this.conversations.set(conversation.id, conversation);
    this.persistConversation(conversation);
    this.eventStore.append(conversation.id, conversationEventTypes.CONVERSATION_STARTED, {
      workspaceId: conversation.workspaceId,
      adapter: conversation.adapter,
      permissionMode: conversation.permissionMode
    });
    return publicConversation(conversation);
  }

  listConversations(device) {
    return Array.from(this.conversations.values())
      .filter((conversation) => this.canAccessConversation(conversation, device))
      .map(publicConversation);
  }

  getConversation(conversationId, device) {
    const conversation = this.conversations.get(conversationId);
    if (!conversation || !this.canAccessConversation(conversation, device)) throw notFound('conversation not found');
    return publicConversation(conversation);
  }

  async sendMessage(conversationId, payload, device) {
    const conversation = this.requireConversation(conversationId, device);
    const message = normalizeMessagePayload(payload);
    if (conversation.status === conversationStatuses.WAITING_INPUT) throw conflict('conversation is waiting for input response');
    if (conversation.status === conversationStatuses.WAITING_APPROVAL) throw conflict('conversation is waiting for approval response');
    await this.ensureStarted(conversation);
    conversation.status = conversationStatuses.RUNNING;
    conversation.blockingItem = null;
    conversation.idleExpiresAt = null;
    conversation.userMessageCount = Number(conversation.userMessageCount || 0) + 1;
    this.touch(conversation);
    this.eventStore.append(conversation.id, conversationEventTypes.USER_MESSAGE, { text: message.text });
    this.eventStore.append(conversation.id, conversationEventTypes.STATUS_CHANGED, { status: conversation.status });
    await conversation.handle.sendUserMessage(message.text);
    this.auditLog.record('conversation.message', { conversationId: conversation.id, deviceId: device.id, textLength: message.text.length });
    return publicConversation(conversation);
  }

  async answerQuestion(conversationId, payload, device) {
    const conversation = this.requireConversation(conversationId, device);
    const answer = normalizeQuestionResponse(payload);
    if (conversation.status !== conversationStatuses.WAITING_INPUT || conversation.blockingItem?.type !== 'input_request') {
      throw conflict('conversation is not waiting for input response');
    }
    if (conversation.blockingItem.questionId !== answer.questionId) throw conflict('questionId does not match pending input request');
    conversation.status = conversationStatuses.RUNNING;
    conversation.blockingItem = null;
    conversation.idleExpiresAt = null;
    this.touch(conversation);
    this.eventStore.append(conversation.id, conversationEventTypes.USER_MESSAGE, { text: answer.text, questionId: answer.questionId });
    this.eventStore.append(conversation.id, conversationEventTypes.STATUS_CHANGED, { status: conversation.status });
    await conversation.handle.answerQuestion(answer.questionId, answer.text);
    this.auditLog.record('conversation.question_answer', { conversationId: conversation.id, deviceId: device.id, questionId: answer.questionId, textLength: answer.text.length });
    return publicConversation(conversation);
  }

  async respondApproval(conversationId, approvalId, payload, device) {
    const conversation = this.requireConversation(conversationId, device);
    const decision = normalizeApprovalDecision(payload);
    if (conversation.status !== conversationStatuses.WAITING_APPROVAL || conversation.blockingItem?.type !== 'approval_request') {
      throw conflict('conversation is not waiting for approval response');
    }
    if (conversation.blockingItem.approvalId !== approvalId) throw conflict('approvalId does not match pending approval request');
    const { type: _blockingType, ...blockingPayload } = conversation.blockingItem;
    const resolved = { ...blockingPayload, decision: decision.decision };
    conversation.status = conversationStatuses.RUNNING;
    conversation.blockingItem = null;
    conversation.idleExpiresAt = null;
    this.touch(conversation);
    this.eventStore.append(conversation.id, conversationEventTypes.APPROVAL_RESOLVED, resolved);
    this.eventStore.append(conversation.id, conversationEventTypes.STATUS_CHANGED, { status: conversation.status });
    await conversation.handle.respondApproval(approvalId, decision.decision);
    this.auditLog.record('conversation.approval', { conversationId: conversation.id, deviceId: device.id, approvalId, decision: decision.decision });
    return publicConversation(conversation);
  }

  async cancelConversation(conversationId, device) {
    const conversation = this.requireConversation(conversationId, device);
    if (conversation.handle && typeof conversation.handle.cancel === 'function') await conversation.handle.cancel();
    conversation.handle = null;
    conversation.status = conversation.cliSessionId ? conversationStatuses.CANCELLED : conversationStatuses.INTERRUPTED;
    conversation.blockingItem = null;
    conversation.idleExpiresAt = null;
    this.touch(conversation);
    this.eventStore.append(conversation.id, conversationEventTypes.CONVERSATION_CANCELLED, {
      reason: 'user_cancelled',
      status: conversation.status,
      cliSessionId: conversation.cliSessionId || null,
      sessionBinding: conversation.sessionBinding || conversationSessionBindings.UNKNOWN
    });
    this.eventStore.append(conversation.id, conversationEventTypes.STATUS_CHANGED, { status: conversation.status });
    this.auditLog.record('conversation.cancel', { conversationId: conversation.id, deviceId: device.id, status: conversation.status });
    return publicConversation(conversation);
  }

  listEvents(conversationId, afterSeq, device) {
    const conversation = this.requireConversation(conversationId, device);
    return this.eventStore.list(conversation.id, afterSeq);
  }

  recordAdapterEvent(conversation, event) {
    if (!event || typeof event !== 'object') return;
    if (event.sessionId) {
      const persisted = this.confirmSessionBinding(conversation, event.sessionId);
      if (!persisted) return;
    }
    if (event.type === conversationEventTypes.ASSISTANT_QUESTION) {
      this.setBlockingItem(conversation, {
        type: 'input_request',
        questionId: event.questionId || event.toolUseId || `q_${crypto.randomUUID()}`,
        text: event.text || '',
        suggestions: Array.isArray(event.suggestions) ? event.suggestions : [],
        multiSelect: event.multiSelect === true,
        input: event.input || {}
      }, conversationStatuses.WAITING_INPUT, event);
      return;
    }
    if (event.type === conversationEventTypes.APPROVAL_REQUESTED) {
      this.setBlockingItem(conversation, {
        type: 'approval_request',
        approvalId: event.approvalId,
        toolName: event.toolName || null,
        toolUseId: event.toolUseId || null,
        input: event.input || {},
        summary: event.summary || summarizeToolInput(event.toolName, event.input)
      }, conversationStatuses.WAITING_APPROVAL, event);
      return;
    }
    if (event.type === 'system.notice') {
      const { type, ...payload } = event;
      this.eventStore.append(conversation.id, type, payload);
      return;
    }
    if (event.type === conversationEventTypes.ASSISTANT_MESSAGE || event.type === conversationEventTypes.CONVERSATION_COMPLETED) {
      conversation.status = conversationStatuses.IDLE;
      conversation.blockingItem = null;
      conversation.idleExpiresAt = addMs(this.now(), this.idleTtlMs).toISOString();
      if (event.type === conversationEventTypes.CONVERSATION_COMPLETED) conversation.handle = null;
      this.touch(conversation);
    }
    if (event.type === conversationEventTypes.CONVERSATION_CANCELLED) {
      conversation.status = conversationStatuses.CANCELLED;
      conversation.blockingItem = null;
      conversation.idleExpiresAt = null;
      conversation.handle = null;
      this.touch(conversation);
    }
    if (event.type === conversationEventTypes.RUN_ERROR) {
      conversation.status = conversationStatuses.FAILED;
      conversation.blockingItem = null;
      conversation.idleExpiresAt = null;
      conversation.handle = null;
      this.touch(conversation);
    }
    const { type, ...payload } = event;
    this.eventStore.append(conversation.id, type || conversationEventTypes.PROTOCOL_WARNING, payload);
    if (event.type === conversationEventTypes.ASSISTANT_MESSAGE || event.type === conversationEventTypes.CONVERSATION_COMPLETED) {
      this.eventStore.append(conversation.id, conversationEventTypes.STATUS_CHANGED, { status: conversation.status });
    }
    if (event.type === conversationEventTypes.RUN_ERROR) {
      this.eventStore.append(conversation.id, conversationEventTypes.STATUS_CHANGED, { status: conversation.status });
    }
  }

  confirmSessionBinding(conversation, receivedSessionId) {
    if (!receivedSessionId) return true;
    if (!conversation.cliSessionId) {
      const previousSessionId = conversation.cliSessionId;
      const previousBinding = conversation.sessionBinding;
      conversation.cliSessionId = receivedSessionId;
      conversation.sessionBinding = conversationSessionBindings.CONFIRMED;
      try {
        this.persistConversation(conversation);
        return true;
      } catch (error) {
        conversation.cliSessionId = previousSessionId || null;
        conversation.sessionBinding = previousBinding || conversationSessionBindings.UNKNOWN;
        conversation.status = conversationStatuses.FAILED;
        conversation.blockingItem = null;
        conversation.idleExpiresAt = null;
        this.eventStore.append(conversation.id, conversationEventTypes.RUN_ERROR, {
          message: `Failed to persist CLI session binding: ${error.message}`,
          recoverable: true
        });
        this.eventStore.append(conversation.id, conversationEventTypes.STATUS_CHANGED, { status: conversation.status });
        return false;
      }
    }
    if (conversation.cliSessionId !== receivedSessionId) {
      conversation.sessionBinding = conversationSessionBindings.DRIFTED;
      this.persistConversation(conversation);
      this.eventStore.append(conversation.id, conversationEventTypes.PROTOCOL_WARNING, {
        warning: 'session_id_drift',
        conversationId: conversation.id,
        expectedSessionId: conversation.cliSessionId,
        receivedSessionId,
        adapter: conversation.adapter
      });
      return true;
    }
    if (conversation.sessionBinding !== conversationSessionBindings.DRIFTED) {
      conversation.sessionBinding = conversationSessionBindings.CONFIRMED;
    }
    return true;
  }

  async ensureStarted(conversation) {
    if (conversation.handle) return conversation.handle;
    const adapter = this.getAdapter(conversation.adapter);
    conversation.handle = await adapter.startConversation({
      conversationId: conversation.id,
      workspacePath: conversation.workspacePath,
      permissionMode: conversation.permissionMode,
      sessionId: conversation.cliSessionId,
      onEvent: (event) => this.recordAdapterEvent(conversation, event)
    });
    return conversation.handle;
  }

  setBlockingItem(conversation, blockingItem, status, event) {
    if (conversation.blockingItem) {
      this.eventStore.append(conversation.id, conversationEventTypes.PROTOCOL_WARNING, {
        warning: 'blocking request ignored because another blocking item is pending',
        existing: conversation.blockingItem,
        ignored: blockingItem
      });
      return;
    }
    const createdAt = this.now().toISOString();
    conversation.blockingItem = {
      ...blockingItem,
      createdAt,
      expiresAt: addMs(this.now(), this.idleTtlMs).toISOString()
    };
    conversation.status = status;
    conversation.idleExpiresAt = null;
    this.touch(conversation);
    const { type, ...payload } = event;
    this.eventStore.append(conversation.id, type, payload);
    this.eventStore.append(conversation.id, conversationEventTypes.STATUS_CHANGED, { status });
  }

  requireConversation(conversationId, device) {
    const conversation = this.conversations.get(conversationId);
    if (!conversation || !this.canAccessConversation(conversation, device)) throw notFound('conversation not found');
    return conversation;
  }

  canAccessConversation(conversation, device) {
    if (conversation.deviceId === device.id) return true;
    try {
      this.workspaces.getAuthorized(conversation.workspaceId, device);
      return true;
    } catch (_err) {
      return false;
    }
  }

  getAdapter(adapterName) {
    const adapter = this.adapters.get(adapterName);
    if (!adapter) throw notFound(`conversation adapter not found: ${adapterName}`);
    return adapter;
  }

  touch(conversation) {
    conversation.updatedAt = this.now().toISOString();
    this.persistConversation(conversation);
  }
}

function publicConversation(conversation) {
  return {
    id: conversation.id,
    workspaceId: conversation.workspaceId,
    adapter: conversation.adapter,
    status: conversation.status,
    cliSessionId: conversation.cliSessionId || null,
    sessionBinding: conversation.sessionBinding || (conversation.cliSessionId ? conversationSessionBindings.CONFIRMED : conversationSessionBindings.UNKNOWN),
    userMessageCount: Number(conversation.userMessageCount || 0),
    blockingItem: conversation.blockingItem || null,
    idleExpiresAt: conversation.idleExpiresAt || null,
    createdAt: conversation.createdAt,
    updatedAt: conversation.updatedAt,
    capabilities: conversation.capabilities || {},
    requestedPermissionMode: conversation.requestedPermissionMode || conversation.permissionMode || 'default',
    effectivePermissionMode: conversation.effectivePermissionMode || conversation.permissionMode || 'default',
    requestedTools: Array.isArray(conversation.requestedTools) ? conversation.requestedTools : [],
    requestedToolPolicy: conversation.requestedToolPolicy || { tools: [], allowedTools: [], disallowedTools: [] },
    resumePolicy: conversation.resumePolicy || { type: 'fresh' },
    systemPromptPolicy: conversation.systemPromptPolicy || { type: 'none' },
    permissionSupport: conversation.permissionSupport || {},
    notices: Array.isArray(conversation.notices) ? conversation.notices : [],
    protocolVersion: conversation.protocolVersion || 1
  };
}

function addMs(date, ms) {
  return new Date(date.getTime() + ms);
}

function summarizeToolInput(toolName, input) {
  if (input && typeof input === 'object') {
    if (typeof input.command === 'string') return input.command;
    if (typeof input.file_path === 'string') return input.file_path;
    if (typeof input.path === 'string') return input.path;
  }
  return toolName || 'Tool request';
}

function conflict(message) {
  const error = new Error(message);
  error.status = 409;
  error.code = 'CONVERSATION_CONFLICT';
  return error;
}

function notFound(message) {
  const error = new Error(message);
  error.status = 404;
  error.code = 'NOT_FOUND';
  return error;
}

module.exports = { ConversationManager };
