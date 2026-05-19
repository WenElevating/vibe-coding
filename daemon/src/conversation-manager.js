'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const {
  conversationStatuses,
  conversationSessionBindings,
  conversationEventTypes,
  normalizeConversationCreate,
  normalizeConversationModelUpdate,
  normalizeMessagePayload,
  normalizeQuestionResponse,
  normalizeApprovalDecision
} = require('./conversation-protocol');
const { readMultipartConversationMessage } = require('./multipart-message-reader');
const { AttachmentScratchStore } = require('./attachment-scratch-store');
const { payloadHashForNormalizedInput, capabilityVersionForNormalizedInput } = require('./attachment-hashes');
const { normalizeAttachmentCapabilities, applyModelAttachmentCapabilities } = require('./attachment-capabilities');

class ConversationManager {
  constructor({ workspaces, eventStore, auditLog, adapters, persistentStore = null, idleTtlMs = 600000, now = () => new Date(), attachmentScratchStore = null }) {
    this.workspaces = workspaces;
    this.eventStore = eventStore;
    this.auditLog = auditLog;
    this.adapters = adapters;
    this.persistentStore = persistentStore;
    this.idleTtlMs = idleTtlMs;
    this.now = now;
    this.attachmentScratchStore = attachmentScratchStore || new AttachmentScratchStore({ root: path.join(os.tmpdir(), 'vibe-coding-attachment-scratch') });
    this.multipartDeviceLocks = new Map();
    this.multipartActiveCount = 0;
    this.multipartMaxPerDaemon = 4;
    this.messageIdempotencyMaxEntries = 1000;
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
    restored.messageIdempotency = new Map();
    restored.messageInFlightIds = new Set();
    restored.turnAttachmentScratches = [];
    this.rebuildMessageIdempotency(restored);
    if ([conversationStatuses.RUNNING, conversationStatuses.WAITING_INPUT, conversationStatuses.WAITING_APPROVAL].includes(restored.status)) {
      restored.status = conversationStatuses.INTERRUPTED;
      restored.blockingItem = null;
      restored.idleExpiresAt = null;
      restored.updatedAt = this.now().toISOString();
    }
    return restored;
  }

  rebuildMessageIdempotency(conversation) {
    for (const event of this.eventStore.list(conversation.id, 0)) {
      if (event.type !== conversationEventTypes.USER_MESSAGE) continue;
      if (!event.clientMessageId || !event.payloadHash) continue;
      rememberMessageIdempotency(conversation.messageIdempotency, event.clientMessageId, event.payloadHash, this.messageIdempotencyMaxEntries);
    }
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
      model: input.model,
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
      handle: null,
      messageIdempotency: new Map(),
      messageInFlightIds: new Set(),
      turnAttachmentScratches: []
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

  async updateModel(conversationId, payload, device) {
    const conversation = this.requireConversation(conversationId, device);
    const input = normalizeConversationModelUpdate(payload);
    if (activeStateBlocksModelUpdate(conversation)) {
      throw conflict('conversation is active; wait for the current turn before changing model');
    }
    if (conversation.modelUpdateLock) throw conflict('model update already in flight');

    conversation.modelUpdateLock = true;
    try {
      if (activeStateBlocksModelUpdate(conversation)) {
        throw conflict('conversation is active; wait for the current turn before changing model');
      }
      const adapter = this.getAdapter(conversation.adapter);
      const capability = await modelCapabilityFor(adapter);
      assertRequestedModelAllowed(input.model, capability);
      if ((conversation.model || null) === input.model) return publicConversation(conversation);

      const previousModel = conversation.model || null;
      try {
        try {
          await disposeIdleHandle(conversation);
        } catch (error) {
          this.auditLog.record('conversation.model_handle_dispose_error', {
            conversationId: conversation.id,
            error: error.message
          });
          throw error;
        }

        conversation.model = input.model;
        this.touch(conversation);
      } catch (error) {
        conversation.model = previousModel;
        throw error;
      }

      try {
        this.eventStore.append(conversation.id, conversationEventTypes.MODEL_CHANGED, {
          previousModel,
          model: input.model
        });
      } catch (error) {
        this.auditLog.record('conversation.model_change_event_error', {
          conversationId: conversation.id,
          error: error.message
        });
      }
      return publicConversation(conversation);
    } finally {
      conversation.modelUpdateLock = false;
    }
  }

  activeWorkspaceConversations(workspaceId, device) {
    return Array.from(this.conversations.values())
      .filter((conversation) => conversation.workspaceId === workspaceId)
      .filter((conversation) => this.canAccessConversation(conversation, device))
      .filter((conversation) => [
        conversationStatuses.RUNNING,
        conversationStatuses.WAITING_INPUT,
        conversationStatuses.WAITING_APPROVAL
      ].includes(conversation.status));
  }

  async cancelWorkspaceConversations(workspaceId, device) {
    const active = this.activeWorkspaceConversations(workspaceId, device);
    const cancelled = [];
    for (const conversation of active) {
      cancelled.push(await this.cancelConversation(conversation.id, device));
    }
    return cancelled;
  }

  async sendMessage(conversationId, payload, device) {
    const conversation = this.requireConversation(conversationId, device);
    if (payload && typeof payload === 'object' && Object.prototype.hasOwnProperty.call(payload, 'attachments')) {
      throw badRequest('JSON attachment sends are not supported; use multipart/form-data');
    }
    const message = normalizeMessagePayload(payload);
    return this.commitAndDispatchMessage(conversation, message, device);
  }

  async sendMultipartMessage(conversationId, req, device) {
    const conversation = this.requireConversation(conversationId, device);
    this.assertConversationCanStartMessage(conversation);
    if (this.multipartDeviceLocks.has(device.id) || this.multipartActiveCount >= this.multipartMaxPerDaemon) {
      const error = attachmentError(429, 'upload_rate_limited', 'Too many attachment uploads are active. Try again shortly.');
      error.headers = { 'retry-after': '5' };
      throw error;
    }

    this.multipartDeviceLocks.set(device.id, true);
    this.multipartActiveCount += 1;
    let scratch = null;
    let scratchHandled = false;
    try {
      scratch = await this.attachmentScratchStore.createMessageScratch({
        conversationId: conversation.id,
        clientMessageId: null,
        scratchLifetime: 'message'
      });
      const multipart = await readMultipartConversationMessage(req, scratch);
      const message = normalizeMessagePayload({
        ...multipart.payload,
        attachments: multipart.files
      });
      const result = await this.commitAndDispatchMessage(conversation, message, device, { files: multipart.files, scratch });
      scratchHandled = true;
      return result;
    } finally {
      if (scratch && !scratchHandled) await this.cleanupAttachmentScratch(conversation, scratch);
      this.multipartDeviceLocks.delete(device.id);
      this.multipartActiveCount -= 1;
    }
  }

  async commitAndDispatchMessage(conversation, message, device, { files = [], scratch = null } = {}) {
    this.assertConversationCanStartMessage(conversation);
    const hasAttachments = files.length > 0 || message.attachments.length > 0;
    let attachmentCapabilities = null;
    if (hasAttachments) {
      if (!message.clientMessageId) throw badRequest('clientMessageId is required for attachment messages');
      attachmentCapabilities = await this.attachmentCapabilitiesForConversation(conversation);
      const currentCapabilityVersion = attachmentCapabilities.capabilityVersion;
      if (!message.capabilityVersion || message.capabilityVersion !== currentCapabilityVersion) {
        throw attachmentError(409, 'capability_stale', 'Attachment capabilities changed. Refresh adapter capabilities and retry.', {
          currentCapabilityVersion
        });
      }
      if (conversation.messageInFlightIds.has(message.clientMessageId)) {
        throw attachmentError(409, 'message_already_in_flight', 'Message is already in flight.');
      }
    }

    const payloadHash = hasAttachments ? payloadHashForNormalizedInput({
      text: message.text,
      attachments: files.map((file, index) => attachmentPayloadHashInput(file, index))
    }) : null;
    if (hasAttachments && conversation.messageIdempotency.has(message.clientMessageId)) {
      const previousHash = conversation.messageIdempotency.get(message.clientMessageId);
      if (previousHash === payloadHash) {
        if (scratch) await this.cleanupAttachmentScratch(conversation, scratch);
        return publicConversation(conversation);
      }
      throw attachmentError(409, 'message_idempotency_conflict', 'clientMessageId was already used with different content.');
    }

    if (hasAttachments && conversation.status === conversationStatuses.RUNNING) {
      throw attachmentError(409, 'conversation_running', 'Conversation is running; wait for the current turn before sending another attachment message.');
    }

    if (hasAttachments) {
      validateAttachmentHandling(attachmentCapabilities.attachments, files);
      assignAttachmentScratchLifetimes(conversation, files);
      conversation.messageInFlightIds.add(message.clientMessageId);
    }

    if (conversation.sendLock) {
      if (hasAttachments) conversation.messageInFlightIds.delete(message.clientMessageId);
      throw conflict('message already in flight');
    }
    conversation.sendLock = true;
    let committed = false;
    const preCommitSnapshot = snapshotPreCommitState(conversation);
    try {
      conversation.status = conversationStatuses.RUNNING;
      conversation.blockingItem = null;
      conversation.idleExpiresAt = null;
      conversation.userMessageCount = Number(conversation.userMessageCount || 0) + 1;
      this.touch(conversation);
      this.eventStore.append(conversation.id, conversationEventTypes.USER_MESSAGE, {
        text: message.text,
        ...(message.clientMessageId ? { clientMessageId: message.clientMessageId } : {}),
        ...(payloadHash ? { payloadHash } : {}),
        ...(hasAttachments ? { attachments: committedAttachmentMetadata(files) } : {})
      });
      if (hasAttachments) rememberMessageIdempotency(conversation.messageIdempotency, message.clientMessageId, payloadHash, this.messageIdempotencyMaxEntries);
      committed = true;
      this.eventStore.append(conversation.id, conversationEventTypes.STATUS_CHANGED, { status: conversation.status });
      await this.ensureStarted(conversation);
      await conversation.handle.sendUserMessage(hasAttachments ? adapterUserMessage(message, files) : message.text);
      if (hasAttachments && scratch) await this.cleanupDispatchedAttachmentScratch(conversation, scratch, files);
      this.auditLog.record('conversation.message', { conversationId: conversation.id, deviceId: device.id, textLength: message.text.length });
      return publicConversation(conversation);
    } catch (error) {
      if (!committed) {
        if (hasAttachments) conversation.messageInFlightIds.delete(message.clientMessageId);
        this.rollbackPreCommitState(conversation, preCommitSnapshot, error);
        throw error;
      }
      conversation.status = conversationStatuses.FAILED;
      conversation.blockingItem = null;
      conversation.idleExpiresAt = null;
      conversation.handle = null;
      this.touch(conversation);
      this.eventStore.append(conversation.id, conversationEventTypes.RUN_ERROR, { message: error.message });
      this.eventStore.append(conversation.id, conversationEventTypes.STATUS_CHANGED, { status: conversation.status });
      throw error;
    } finally {
      conversation.sendLock = false;
      if (hasAttachments) conversation.messageInFlightIds.delete(message.clientMessageId);
    }
  }

  rollbackPreCommitState(conversation, snapshot, originalError) {
    restorePreCommitState(conversation, snapshot);
    try {
      this.persistConversation(conversation);
    } catch (rollbackError) {
      this.auditLog.record('conversation.pre_commit_rollback_persist_error', {
        conversationId: conversation.id,
        originalError: originalError.message,
        rollbackError: rollbackError.message
      });
    }
  }

  assertConversationCanStartMessage(conversation) {
    if (conversation.status === conversationStatuses.WAITING_INPUT) throw conflict('conversation is waiting for input response');
    if (conversation.status === conversationStatuses.WAITING_APPROVAL) throw conflict('conversation is waiting for approval response');
    if (conversation.modelUpdateLock) throw conflict('model update already in flight');
    if (conversation.sendLock) throw conflict('message already in flight');
  }

  async currentCapabilityVersion(conversation) {
    return (await this.attachmentCapabilitiesForConversation(conversation)).capabilityVersion;
  }

  async attachmentCapabilitiesForConversation(conversation) {
    const adapter = this.getAdapter(conversation.adapter);
    const modelCapability = await modelCapabilityFor(adapter);
    const status = adapter.capability || {};
    const rawCapabilities = status.capabilities || (typeof adapter.getCapabilities === 'function' ? adapter.getCapabilities() : (adapter.capabilities || {}));
    const attachments = normalizeAttachmentCapabilities(rawCapabilities?.attachments);
    const models = Array.isArray(modelCapability.models)
      ? modelCapability.models.map((model) => applyModelAttachmentCapabilities(model, attachments)).sort((a, b) => String(a.id).localeCompare(String(b.id)))
      : [];
    const selectedModel = typeof modelCapability.selectedModel === 'string' ? modelCapability.selectedModel.trim() || null : null;
    const effectiveModelId = conversation.model || selectedModel;
    const effectiveModel = models.find((model) => model.id === effectiveModelId) || models.find((model) => model.id === selectedModel) || null;
    return {
      capabilityVersion: capabilityVersionForNormalizedInput({
        adapterId: conversation.adapter,
        attachments,
        cliPath: status.cliPath || status.path || adapter.cliPath || adapter.path || adapter.name || status.command || adapter.command || conversation.adapter,
        cliVersion: status.cliVersion || status.version || adapter.cliVersion || adapter.version || null,
        models: models.map((model) => modelCapabilityHashInput(model, attachments)),
        selectedModelId: selectedModel
      }),
      attachments: effectiveModel ? effectiveModel.attachments : attachments
    };
  }

  async cleanupDispatchedAttachmentScratch(conversation, scratch, files) {
    const hasTurnScratch = files.some((file) => file.scratchLifetime === 'turn');
    if (!hasTurnScratch) {
      await this.cleanupAttachmentScratch(conversation, scratch);
      return;
    }
    const sendTimeFiles = files.filter((file) => file.scratchLifetime === 'send_time');
    await Promise.all(sendTimeFiles.map((file) => this.cleanupAttachmentFile(conversation, file)));
    if (isAttachmentTurnActive(conversation)) {
      rememberTurnAttachmentScratch(conversation, scratch);
      await scratch.writeMetadata({ active: true }).catch((cleanupError) => {
        this.auditLog.record('conversation.attachment_cleanup_failed', {
          conversationId: conversation.id,
          error: cleanupFailureReason(cleanupError)
        });
      });
      return;
    }
    await this.cleanupAttachmentScratch(conversation, scratch);
  }

  async cleanupAttachmentFile(conversation, file) {
    if (!file?.scratchPath) return;
    await fs.rm(file.scratchPath, { force: true }).catch((cleanupError) => {
      this.auditLog.record('conversation.attachment_cleanup_failed', {
        conversationId: conversation.id,
        error: cleanupFailureReason(cleanupError)
      });
    });
  }

  async cleanupAttachmentScratch(conversation, scratch) {
    forgetTurnAttachmentScratch(conversation, scratch);
    await scratch.cleanup().catch((cleanupError) => {
      this.auditLog.record('conversation.attachment_cleanup_failed', {
        conversationId: conversation.id,
        error: cleanupFailureReason(cleanupError)
      });
    });
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
    const targetStatus = conversation.cliSessionId ? conversationStatuses.CANCELLED : conversationStatuses.INTERRUPTED;
    try {
      if (conversation.handle && typeof conversation.handle.cancel === 'function') await conversation.handle.cancel();
    } catch (err) {
      this.auditLog.record('conversation.cancel_error', { conversationId, error: err.message });
    } finally {
      conversation.handle = null;
      conversation.status = targetStatus;
      conversation.blockingItem = null;
      conversation.idleExpiresAt = null;
    }
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
    if (eventCompletesTurn(event)) {
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
    if (eventCompletesTurn(event) || event.type === conversationEventTypes.CONVERSATION_CANCELLED || event.type === conversationEventTypes.RUN_ERROR) {
      this.cleanupTurnAttachmentScratch(conversation);
    }
    const { type, ...payload } = event;
    this.eventStore.append(conversation.id, type || conversationEventTypes.PROTOCOL_WARNING, payload);
    if (eventCompletesTurn(event)) {
      this.eventStore.append(conversation.id, conversationEventTypes.STATUS_CHANGED, { status: conversation.status });
    }
    if (event.type === conversationEventTypes.RUN_ERROR) {
      this.eventStore.append(conversation.id, conversationEventTypes.STATUS_CHANGED, { status: conversation.status });
    }
  }

  confirmSessionBinding(conversation, receivedSessionId) {
    if (!receivedSessionId) return true;
    if (!conversation.cliSessionId) {
      const previousBinding = conversation.sessionBinding;
      conversation.cliSessionId = receivedSessionId;
      conversation.sessionBinding = conversationSessionBindings.CONFIRMED;
      try {
        this.persistConversation(conversation);
        return true;
      } catch (error) {
        conversation.cliSessionId = null;
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
      model: conversation.model,
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

  cleanupTurnAttachmentScratch(conversation) {
    const scratches = Array.isArray(conversation.turnAttachmentScratches)
      ? conversation.turnAttachmentScratches.splice(0)
      : [];
    for (const scratch of scratches) {
      this.cleanupAttachmentScratch(conversation, scratch);
    }
  }
}

function eventCompletesTurn(event) {
  if (event.type === conversationEventTypes.CONVERSATION_COMPLETED) return true;
  if (event.type !== conversationEventTypes.ASSISTANT_MESSAGE) return false;
  return event.turnFinal !== false;
}

function activeStateBlocksModelUpdate(conversation) {
  return [
    conversationStatuses.RUNNING,
    conversationStatuses.WAITING_INPUT,
    conversationStatuses.WAITING_APPROVAL
  ].includes(conversation.status) || Boolean(conversation.sendLock);
}

async function disposeIdleHandle(conversation) {
  if (!conversation.handle) return;
  const handle = conversation.handle;
  try {
    if (typeof handle.dispose === 'function') await handle.dispose();
  } finally {
    conversation.handle = null;
  }
}

async function modelCapabilityFor(adapter) {
  if (typeof adapter.detectCapabilities === 'function') {
    await adapter.detectCapabilities();
  }
  if (typeof adapter.getModelCapability !== 'function') {
    return { canSelectModel: false, selectedModel: null, models: [] };
  }
  const capability = await adapter.getModelCapability();
  return {
    canSelectModel: capability?.canSelectModel === true,
    selectedModel: typeof capability?.selectedModel === 'string' ? capability.selectedModel : null,
    models: Array.isArray(capability?.models) ? capability.models : []
  };
}

function assertRequestedModelAllowed(requestedModel, capability) {
  if (requestedModel == null) return;
  if (capability.canSelectModel !== true) {
    throw unprocessable('adapter does not support model selection');
  }
  if (capability.models.length === 0) {
    throw unprocessable('adapter model capability has no selectable models');
  }
  if (!capability.models.some((model) => model && model.id === requestedModel)) {
    throw unprocessable(`model is not available for this adapter: ${requestedModel}`);
  }
}

function attachmentError(status, code, message, details) {
  const error = new Error(message);
  error.status = status;
  error.code = code;
  error.details = details;
  return error;
}

function committedAttachmentMetadata(files) {
  return files.map((file, index) => ({
    id: `att_${index}_${crypto.randomBytes(4).toString('hex')}`,
    name: file.name,
    kind: file.kind,
    mimeType: file.mimeType,
    sizeBytes: file.sizeBytes,
    handling: file.handling
  }));
}

function attachmentPayloadHashInput(file, index) {
  return {
    contentSha256Prefix: file.contentSha256Prefix || String(file.contentSha256 || '').slice(0, 32),
    index,
    kind: file.kind,
    mimeType: file.mimeType,
    name: file.name,
    sizeBytes: file.sizeBytes
  };
}

function assignAttachmentScratchLifetimes(conversation, files) {
  for (const file of files) {
    file.scratchLifetime = attachmentScratchLifetime(conversation, file);
  }
}

function attachmentScratchLifetime(conversation, file) {
  if (conversation.adapter === 'codex' && file.kind === 'image' && file.handling === 'native') return 'turn';
  return 'send_time';
}

function adapterUserMessage(message, files) {
  return {
    text: message.text,
    attachments: files.map((file) => ({
      name: file.name,
      kind: file.kind,
      mimeType: file.mimeType,
      sizeBytes: file.sizeBytes,
      handling: file.handling,
      scratchPath: file.scratchPath,
      scratchLifetime: file.scratchLifetime,
      ...(file.text == null ? {} : { text: file.text })
    }))
  };
}

function validateAttachmentHandling(capabilities, files) {
  const normalized = normalizeAttachmentCapabilities(capabilities);
  for (const file of files) {
    if (!file.name || !file.kind || !file.mimeType || !Number.isSafeInteger(file.sizeBytes) || file.sizeBytes < 0) {
      throw badRequest('attachment metadata is invalid');
    }
    if (!file.contentSha256Prefix) throw badRequest('attachment content hash is required');
    const handling = normalized[file.kind];
    if (!handling || handling === 'unsupported') {
      throw attachmentError(415, 'UNSUPPORTED_MEDIA_TYPE', 'unsupported media type', { kind: file.kind });
    }
    file.handling = handling;
  }
}

function rememberTurnAttachmentScratch(conversation, scratch) {
  if (!Array.isArray(conversation.turnAttachmentScratches)) conversation.turnAttachmentScratches = [];
  if (!conversation.turnAttachmentScratches.includes(scratch)) conversation.turnAttachmentScratches.push(scratch);
}

function forgetTurnAttachmentScratch(conversation, scratch) {
  if (!Array.isArray(conversation.turnAttachmentScratches)) return;
  const index = conversation.turnAttachmentScratches.indexOf(scratch);
  if (index !== -1) conversation.turnAttachmentScratches.splice(index, 1);
}

function isAttachmentTurnActive(conversation) {
  return [
    conversationStatuses.RUNNING,
    conversationStatuses.WAITING_INPUT,
    conversationStatuses.WAITING_APPROVAL
  ].includes(conversation.status);
}

function cleanupFailureReason(error) {
  return error?.code || error?.message || 'cleanup failed';
}

function rememberMessageIdempotency(map, clientMessageId, payloadHash, maxEntries) {
  if (!clientMessageId || !payloadHash) return;
  if (map.has(clientMessageId)) map.delete(clientMessageId);
  map.set(clientMessageId, payloadHash);
  while (map.size > maxEntries) {
    const firstKey = map.keys().next().value;
    map.delete(firstKey);
  }
}

function snapshotPreCommitState(conversation) {
  return {
    status: conversation.status,
    blockingItem: conversation.blockingItem,
    idleExpiresAt: conversation.idleExpiresAt,
    userMessageCount: conversation.userMessageCount,
    updatedAt: conversation.updatedAt
  };
}

function restorePreCommitState(conversation, snapshot) {
  conversation.status = snapshot.status;
  conversation.blockingItem = snapshot.blockingItem;
  conversation.idleExpiresAt = snapshot.idleExpiresAt;
  conversation.userMessageCount = snapshot.userMessageCount;
  conversation.updatedAt = snapshot.updatedAt;
}

function modelCapabilityHashInput(model, adapterAttachments) {
  const input = {
    id: model.id,
    inputModalities: model.inputModalities
  };
  const defaultProjection = applyModelAttachmentCapabilities({
    id: model.id,
    inputModalities: model.inputModalities
  }, adapterAttachments);
  if (!sameAttachments(model.attachments, defaultProjection.attachments)) {
    input.attachments = model.attachments;
  }
  return input;
}

function sameAttachments(left, right) {
  return left?.image === right?.image && left?.pdf === right?.pdf && left?.textDocument === right?.textDocument;
}

function publicConversation(conversation) {
  return {
    id: conversation.id,
    workspaceId: conversation.workspaceId,
    adapter: conversation.adapter,
    model: conversation.model || null,
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

function badRequest(message) {
  const error = new Error(message);
  error.status = 400;
  error.code = 'BAD_REQUEST';
  return error;
}

function unprocessable(message) {
  const error = new Error(message);
  error.status = 422;
  error.code = 'CONVERSATION_MODEL_UNSUPPORTED';
  return error;
}

function notFound(message) {
  const error = new Error(message);
  error.status = 404;
  error.code = 'NOT_FOUND';
  return error;
}

module.exports = { ConversationManager };
