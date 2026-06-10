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
  normalizePermissionModeUpdate,
  normalizeConversationControl,
  normalizeMessagePayload,
  normalizeQuestionResponse,
  normalizeApprovalDecision,
  normalizeApprovalOptions
} = require('./conversation-protocol');
const { readMultipartConversationMessage } = require('./multipart-message-reader');
const { AttachmentScratchStore } = require('./attachment-scratch-store');
const { payloadHashForNormalizedInput, capabilityVersionForNormalizedInput } = require('./attachment-hashes');
const { normalizeAttachmentCapabilities, applyModelAttachmentCapabilities } = require('./attachment-capabilities');
const { textAttachmentWrapper } = require('./attachment-validation');
const { deriveConversationTitle } = require('./conversation-title');
const { mapCodexEvent } = require('./codex-conversation-adapter');

const claudeMaxNativeImageBytes = 5 * 1024 * 1024;
const sessionBindingEventMaxChars = 512;

class ConversationManager {
  constructor({ workspaces, eventStore, auditLog, adapters, persistentStore = null, idleTtlMs = 600000, now = () => new Date(), attachmentScratchStore = null, perfTracer = null }) {
    this.workspaces = workspaces;
    this.eventStore = eventStore;
    this.auditLog = auditLog;
    this.adapters = adapters;
    this.persistentStore = persistentStore;
    this.perfTracer = perfTracer;
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
      if (
        conversation.status !== loaded.status ||
        loaded.blockingItem ||
        loaded.idleExpiresAt ||
        JSON.stringify(conversation.providerSession || null) !== JSON.stringify(loaded.providerSession || null)
      ) {
        this.persistConversation(conversation);
      }
    }
  }

  normalizeRestoredConversation(conversation) {
    const restored = { ...conversation, handle: null };
    const restoredProviderSession = publicProviderSession(restored.providerSession);
    restored.providerSession = restoredProviderSession;
    restored.messageIdempotency = new Map();
    restored.messageInFlightIds = new Set();
    restored.blockingQueue = [];
    restored.turnAttachmentScratches = [];
    restored.attachmentDispatchRedactionContext = null;
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
    const selection = this.resolveAdapterSelection(input.adapter);
    const adapter = selection.requestedAdapter;
    const effectiveAdapter = selection.effectiveAdapter;
    const conversation = {
      id: `conv_${crypto.randomUUID()}`,
      workspaceId: workspace.id,
      workspacePath: workspace.path,
      adapter: input.adapter,
      requestedAdapter: input.adapter,
      effectiveAdapter: selection.effectiveAdapterName,
      model: input.model,
      permissionMode: input.permissionMode,
      requestedPermissionMode: input.permissionMode,
      effectivePermissionMode: input.permissionMode,
      requestedTools: input.requestedTools,
      requestedToolPolicy: input.requestedToolPolicy,
      resumePolicy: input.resumePolicy,
      systemPromptPolicy: input.systemPromptPolicy,
      claudeOptions: input.claudeOptions,
      permissionSupport: {},
      notices: [],
      protocolVersion: 2,
      deviceId: device.id,
      status: conversationStatuses.IDLE,
      cliSessionId: null,
      sessionBinding: conversationSessionBindings.UNKNOWN,
      title: null,
      userMessageCount: 0,
      blockingItem: null,
      idleExpiresAt: addMs(this.now(), this.idleTtlMs).toISOString(),
      createdAt: this.now().toISOString(),
      updatedAt: this.now().toISOString(),
      capabilities: capabilitiesForAdapter(adapter),
      effectiveCapabilities: capabilitiesForAdapter(effectiveAdapter),
      fallbackNotice: selection.fallbackNotice,
      providerSession: null,
      handle: null,
      messageIdempotency: new Map(),
      messageInFlightIds: new Set(),
      blockingQueue: [],
      turnAttachmentScratches: [],
      attachmentDispatchRedactionContext: null
    };
    this.persistConversation(conversation);
    this.eventStore.append(conversation.id, conversationEventTypes.CONVERSATION_STARTED, {
      workspaceId: conversation.workspaceId,
      adapter: conversation.adapter,
      permissionMode: conversation.permissionMode
    });
    this.conversations.set(conversation.id, conversation);
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
    const activeHandle = effectiveAdapterName(conversation) === 'claude' && conversation.handle && typeof conversation.handle.setModel === 'function';
    if (!activeHandle && activeStateBlocksModelUpdate(conversation)) {
      throw conflict('conversation is active; wait for the current turn before changing model');
    }
    if (conversation.modelUpdateLock) throw conflict('model update already in flight');

    conversation.modelUpdateLock = true;
    try {
      if (!activeHandle && activeStateBlocksModelUpdate(conversation)) {
        throw conflict('conversation is active; wait for the current turn before changing model');
      }
      const adapter = this.getAdapter(effectiveAdapterName(conversation));
      const capability = await modelCapabilityFor(adapter);
      assertRequestedModelAllowed(input.model, capability);
      if ((conversation.model || null) === input.model) return publicConversation(conversation);

      const previousModel = conversation.model || null;
      try {
        if (activeHandle) {
          await conversation.handle.setModel(input.model);
        } else {
          try {
            await disposeIdleHandle(conversation);
          } catch (error) {
            this.auditLog.record('conversation.model_handle_dispose_error', {
              conversationId: conversation.id,
              error: error.message
            });
            throw error;
          }
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

  async updatePermissionMode(conversationId, payload, device) {
    const conversation = this.requireConversation(conversationId, device);
    const input = normalizePermissionModeUpdate(payload);
    if ((conversation.permissionMode || 'default') === input.permissionMode) return publicConversation(conversation);
    const previousPermissionMode = {
      permissionMode: conversation.permissionMode,
      requestedPermissionMode: conversation.requestedPermissionMode,
      effectivePermissionMode: conversation.effectivePermissionMode
    };
    try {
      if (effectiveAdapterName(conversation) === 'claude' && conversation.handle && typeof conversation.handle.setPermissionMode === 'function') {
        await conversation.handle.setPermissionMode(input.permissionMode);
      }
      conversation.permissionMode = input.permissionMode;
      conversation.requestedPermissionMode = input.permissionMode;
      conversation.effectivePermissionMode = input.permissionMode;
      this.touch(conversation);
    } catch (error) {
      conversation.permissionMode = previousPermissionMode.permissionMode;
      conversation.requestedPermissionMode = previousPermissionMode.requestedPermissionMode;
      conversation.effectivePermissionMode = previousPermissionMode.effectivePermissionMode;
      throw error;
    }
    try {
      this.eventStore.append(conversation.id, conversationEventTypes.STATUS_CHANGED, {
        status: conversation.status,
        permissionMode: input.permissionMode
      });
    } catch (error) {
      this.auditLog.record('conversation.permission_mode_event_error', {
        conversationId: conversation.id,
        error: error.message
      });
    }
    return publicConversation(conversation);
  }

  async controlConversation(conversationId, payload, device) {
    const conversation = this.requireConversation(conversationId, device);
    const input = normalizeConversationControl(payload);
    if (effectiveAdapterName(conversation) !== 'claude' || !conversation.handle) throw conflict('conversation is not controlled by an active Claude session');
    const handle = conversation.handle;
    let result;
    switch (input.action) {
      case 'interrupt':
        result = await requireHandleMethod(handle, 'interrupt').call(handle);
        break;
      case 'set_permission_mode':
        result = await requireHandleMethod(handle, 'setPermissionMode').call(handle, input.permissionMode);
        {
          const previousPermissionMode = {
            permissionMode: conversation.permissionMode,
            requestedPermissionMode: conversation.requestedPermissionMode,
            effectivePermissionMode: conversation.effectivePermissionMode
          };
          try {
            conversation.permissionMode = input.permissionMode;
            conversation.requestedPermissionMode = input.permissionMode;
            conversation.effectivePermissionMode = input.permissionMode;
            this.touch(conversation);
          } catch (error) {
            conversation.permissionMode = previousPermissionMode.permissionMode;
            conversation.requestedPermissionMode = previousPermissionMode.requestedPermissionMode;
            conversation.effectivePermissionMode = previousPermissionMode.effectivePermissionMode;
            throw error;
          }
        }
        break;
      case 'set_model':
        result = await requireHandleMethod(handle, 'setModel').call(handle, input.model);
        {
          const previousModel = conversation.model || null;
          try {
            conversation.model = input.model || null;
            this.touch(conversation);
          } catch (error) {
            conversation.model = previousModel;
            throw error;
          }
        }
        break;
      case 'get_context_usage':
        result = await requireHandleMethod(handle, 'getContextUsage').call(handle);
        break;
      case 'get_mcp_status':
        result = await requireHandleMethod(handle, 'getMcpStatus').call(handle);
        break;
      case 'reconnect_mcp_server':
        if (!input.name) throw badRequest('name is required');
        result = await requireHandleMethod(handle, 'reconnectMcpServer').call(handle, input.name);
        break;
      case 'toggle_mcp_server':
        if (!input.name) throw badRequest('name is required');
        result = await requireHandleMethod(handle, 'toggleMcpServer').call(handle, input.name, input.enabled);
        break;
      case 'stop_task':
        if (!input.taskId) throw badRequest('taskId is required');
        result = await requireHandleMethod(handle, 'stopTask').call(handle, input.taskId);
        break;
      default:
        throw badRequest(`unsupported control action: ${input.action}`);
    }
    return { conversation: publicConversation(conversation), result: result || {} };
  }

  async commitAndDispatchMessage(conversation, message, device, { files = [], scratch = null } = {}) {
    this.assertConversationCanStartMessage(conversation);
    this.markPerf('conversation.send.received', {
      conversationId: conversation.id
    });
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
      validateAdapterAttachmentLimits(conversation, files);
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
      conversation.blockingQueue = [];
      conversation.idleExpiresAt = null;
      conversation.userMessageCount = Number(conversation.userMessageCount || 0) + 1;
      const attachmentMetadata = hasAttachments ? this.committedAttachmentMetadata(conversation, files) : [];
      if (!conversation.title) {
        conversation.title = deriveConversationTitle({
          text: message.text,
          attachments: attachmentMetadata
        });
      }
      this.touch(conversation);
      const userEvent = this.eventStore.append(conversation.id, conversationEventTypes.USER_MESSAGE, {
        text: message.text,
        ...(message.clientMessageId ? { clientMessageId: message.clientMessageId } : {}),
        ...(payloadHash ? { payloadHash } : {}),
        ...(hasAttachments ? { attachments: attachmentMetadata } : {})
      });
      this.markPerf('conversation.user.persisted', {
        conversationId: conversation.id,
        seq: userEvent.seq,
        eventType: userEvent.type,
        metadata: {
          eventType: userEvent.type
        }
      });
      if (hasAttachments) rememberMessageIdempotency(conversation.messageIdempotency, message.clientMessageId, payloadHash, this.messageIdempotencyMaxEntries);
      committed = true;
      this.eventStore.append(conversation.id, conversationEventTypes.STATUS_CHANGED, { status: conversation.status });
      const handle = await this.ensureStarted(conversation);
      if (!handle || conversation.status !== conversationStatuses.RUNNING || conversation.handle !== handle) {
        return publicConversation(conversation);
      }
      if (hasAttachments) conversation.attachmentDispatchRedactionContext = attachmentDispatchRedactionContext(files);
      this.markPerf('adapter.send.started', {
        conversationId: conversation.id,
        metadata: {
          adapter: effectiveAdapterName(conversation)
        }
      });
      await handle.sendUserMessage(hasAttachments ? adapterUserMessage(message, files) : message.text);
      this.markPerf('adapter.send.accepted', {
        conversationId: conversation.id,
        metadata: {
          adapter: effectiveAdapterName(conversation)
        }
      });
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
      conversation.blockingQueue = [];
      conversation.idleExpiresAt = null;
      await this.disposeFailedConversationHandle(conversation);
      conversation.handle = null;
      this.touch(conversation);
      const dispatchError = sanitizeAdapterDispatchError(error, { hasAttachments, files });
      this.eventStore.append(conversation.id, conversationEventTypes.RUN_ERROR, runErrorPayload(dispatchError));
      this.eventStore.append(conversation.id, conversationEventTypes.STATUS_CHANGED, { status: conversation.status });
      if (hasAttachments) conversation.attachmentDispatchRedactionContext = null;
      throw dispatchError;
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
    const adapterName = effectiveAdapterName(conversation);
    const adapter = this.getAdapter(adapterName);
    const status = await detectedAdapterStatusFor(adapter);
    const modelCapability = await modelCapabilityFor(adapter, status);
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
        adapterId: adapterName,
        attachments,
        cliPath: status.cliPath || status.path || adapter.cliPath || adapter.path || adapter.name || status.command || adapter.command || adapterName,
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

  committedAttachmentMetadata(_conversation, files) {
    return committedAttachmentMetadata(files);
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
    const preCommitSnapshot = snapshotPreCommitState(conversation);
    let committed = false;
    try {
      conversation.status = conversationStatuses.RUNNING;
      conversation.blockingItem = null;
      conversation.idleExpiresAt = null;
      this.touch(conversation);
      this.eventStore.append(conversation.id, conversationEventTypes.USER_MESSAGE, { text: answer.text, questionId: answer.questionId });
      committed = true;
      this.eventStore.append(conversation.id, conversationEventTypes.STATUS_CHANGED, { status: conversation.status });
      await conversation.handle.answerQuestion(answer.questionId, answer.text);
    } catch (error) {
      if (!committed) {
        this.rollbackPreCommitState(conversation, preCommitSnapshot, error);
        throw error;
      }
      this.markConversationDispatchFailed(conversation, error);
      throw error;
    }
    this.promoteNextBlockingItem(conversation);
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
    validateApprovalDecisionForRequest(decision, conversation.blockingItem);
    const { type: _blockingType, ...blockingPayload } = conversation.blockingItem;
    const resolved = {
      ...blockingPayload,
      decision: decision.decision,
      ...(decision.scope ? { scope: decision.scope } : {}),
      ...(Object.prototype.hasOwnProperty.call(decision, 'interrupt') ? { interrupt: decision.interrupt } : {})
    };
    const preCommitSnapshot = snapshotPreCommitState(conversation);
    let committed = false;
    try {
      conversation.status = conversationStatuses.RUNNING;
      conversation.blockingItem = null;
      conversation.idleExpiresAt = null;
      this.touch(conversation);
      this.eventStore.append(conversation.id, conversationEventTypes.APPROVAL_RESOLVED, resolved);
      committed = true;
      this.eventStore.append(conversation.id, conversationEventTypes.STATUS_CHANGED, { status: conversation.status });
      await conversation.handle.respondApproval(approvalId, decision);
    } catch (error) {
      if (!committed) {
        this.rollbackPreCommitState(conversation, preCommitSnapshot, error);
        throw error;
      }
      this.markConversationDispatchFailed(conversation, error);
      throw error;
    }
    this.promoteNextBlockingItem(conversation);
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
      conversation.blockingQueue = [];
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
    await this.cleanupTurnAttachmentScratch(conversation);
    conversation.attachmentDispatchRedactionContext = null;
    return publicConversation(conversation);
  }

  listEvents(conversationId, afterSeq, device) {
    const conversation = this.requireConversation(conversationId, device);
    const events = this.eventStore.listAfter(conversation.id, afterSeq);
    return normalizeConversationEventsForReplay(events, conversation, this.eventStore);
  }

  markConversationDispatchFailed(conversation, error) {
    this.disposeFailedConversationHandle(conversation);
    conversation.status = conversationStatuses.FAILED;
    conversation.blockingItem = null;
    conversation.idleExpiresAt = null;
    conversation.handle = null;
    this.touch(conversation);
    this.eventStore.append(conversation.id, conversationEventTypes.RUN_ERROR, runErrorPayload(error));
    this.eventStore.append(conversation.id, conversationEventTypes.STATUS_CHANGED, { status: conversation.status });
  }

  async disposeFailedConversationHandle(conversation) {
    const failedHandle = conversation.handle;
    if (!failedHandle || typeof failedHandle.dispose !== 'function') return;
    try {
      await failedHandle.dispose();
    } catch (disposeError) {
      this.auditLog.record('conversation.handle_dispose_error', {
        conversationId: conversation.id,
        error: disposeError.message
      });
    }
  }

  listEventPage(conversationId, pageRequest, device) {
    const conversation = this.requireConversation(conversationId, device);
    const page = pageRequest.mode === 'tail'
      ? this.eventStore.listTail(conversation.id, pageRequest.limit)
      : this.eventStore.listBefore(conversation.id, pageRequest.beforeSeq, pageRequest.limit);
    return {
      events: normalizeConversationEventsForReplay(page.events, conversation, this.eventStore),
      page: {
        mode: pageRequest.mode,
        oldestSeq: page.oldestSeq,
        newestSeq: page.newestSeq,
        hasMoreBefore: page.hasMoreBefore
      }
    };
  }

  recordAdapterEvent(conversation, event) {
    if (!event || typeof event !== 'object') return;
    const publicEvent = sanitizeProviderSessionEvent(event);
    this.markPerf('adapter.raw_event.received', {
      conversationId: conversation.id,
      eventType: typeof event.type === 'string' ? event.type : null,
      metadata: {
        eventType: typeof event.type === 'string' ? event.type : 'unknown',
        byteLength: safeJsonByteLength(event)
      }
    });
    if (publicEvent.sessionId) {
      const persisted = this.confirmSessionBinding(conversation, publicEvent.sessionId);
      if (!persisted) return;
    }
    if (publicEvent.providerSession && typeof publicEvent.providerSession === 'object' && !Array.isArray(publicEvent.providerSession)) {
      conversation.providerSession = publicEvent.providerSession;
      this.persistConversation(conversation);
    }
    if (publicEvent.type === conversationEventTypes.ASSISTANT_QUESTION) {
      this.setBlockingItem(conversation, {
        type: 'input_request',
        questionId: publicEvent.questionId || publicEvent.toolUseId || `q_${crypto.randomUUID()}`,
        text: publicEvent.text || '',
        suggestions: Array.isArray(publicEvent.suggestions) ? publicEvent.suggestions : [],
        multiSelect: publicEvent.multiSelect === true,
        input: publicEvent.input || {}
      }, conversationStatuses.WAITING_INPUT, publicEvent);
      return;
    }
    if (publicEvent.type === conversationEventTypes.APPROVAL_REQUESTED) {
      const approvalOptions = normalizeApprovalOptions(
        publicEvent.approvalOptions,
        adapterApprovalCapability(conversation)
      );
      this.setBlockingItem(conversation, {
        type: 'approval_request',
        approvalId: publicEvent.approvalId,
        toolName: publicEvent.toolName || null,
        toolUseId: publicEvent.toolUseId || null,
        input: publicEvent.input || {},
        summary: publicEvent.summary || summarizeToolInput(publicEvent.toolName, publicEvent.input),
        approvalOptions
      }, conversationStatuses.WAITING_APPROVAL, { ...publicEvent, approvalOptions });
      return;
    }
    if (publicEvent.type === conversationEventTypes.BLOCKING_REQUEST_CANCELLED) {
      const matchesApproval = conversation.blockingItem?.type === 'approval_request' &&
        publicEvent.blockingType === 'approval_request' &&
        conversation.blockingItem.approvalId === publicEvent.approvalId;
      const matchesQuestion = conversation.blockingItem?.type === 'input_request' &&
        publicEvent.blockingType === 'input_request' &&
        conversation.blockingItem.questionId === publicEvent.questionId;
      if (matchesApproval || matchesQuestion) {
        conversation.status = conversationStatuses.RUNNING;
        conversation.blockingItem = null;
        conversation.idleExpiresAt = null;
        this.touch(conversation);
        const { type, ...payload } = sanitizeAdapterEvent(publicEvent, conversation.attachmentDispatchRedactionContext);
        this.eventStore.append(conversation.id, type, payload);
        this.eventStore.append(conversation.id, conversationEventTypes.STATUS_CHANGED, { status: conversation.status });
        this.promoteNextBlockingItem(conversation);
        return;
      }
      if (this.removeQueuedBlockingItem(conversation, publicEvent)) return;
      this.eventStore.append(conversation.id, conversationEventTypes.PROTOCOL_WARNING, {
        warning: 'blocking request cancellation ignored because no matching blocking item is pending',
        current: conversation.blockingItem || null,
        ignored: publicEvent
      });
      return;
    }
    if (publicEvent.type === conversationEventTypes.APPROVAL_RESOLVED) {
      const matchesApproval = conversation.blockingItem?.type === 'approval_request' &&
        conversation.blockingItem.approvalId === publicEvent.approvalId;
      if (matchesApproval) {
        const blockingPayload = { ...conversation.blockingItem };
        delete blockingPayload.type;
        delete blockingPayload.createdAt;
        delete blockingPayload.expiresAt;
        conversation.status = conversationStatuses.RUNNING;
        conversation.blockingItem = null;
        conversation.idleExpiresAt = null;
        this.touch(conversation);
        const { type, ...payload } = sanitizeAdapterEvent({
          ...blockingPayload,
          ...publicEvent
        }, conversation.attachmentDispatchRedactionContext);
        this.eventStore.append(conversation.id, type, payload);
        this.eventStore.append(conversation.id, conversationEventTypes.STATUS_CHANGED, { status: conversation.status });
        this.promoteNextBlockingItem(conversation);
        return;
      }
      if (this.removeQueuedResolvedApproval(conversation, publicEvent)) return;
    }
    const eventToAppend = sanitizeAdapterEvent(publicEvent, conversation.attachmentDispatchRedactionContext);
    this.markPerf('adapter.event.normalized', {
      conversationId: conversation.id,
      eventType: eventToAppend.type || conversationEventTypes.PROTOCOL_WARNING,
      metadata: {
        eventType: eventToAppend.type || conversationEventTypes.PROTOCOL_WARNING
      }
    });
    if (eventToAppend.type === 'system.notice') {
      const { type, ...payload } = eventToAppend;
      this.eventStore.append(conversation.id, type, payload);
      return;
    }
    if (eventCompletesTurn(eventToAppend)) {
      conversation.status = conversationStatuses.IDLE;
      conversation.blockingItem = null;
      conversation.blockingQueue = [];
      conversation.idleExpiresAt = addMs(this.now(), this.idleTtlMs).toISOString();
      if (eventToAppend.type === conversationEventTypes.CONVERSATION_COMPLETED) conversation.handle = null;
      this.touch(conversation);
    }
    if (eventToAppend.type === conversationEventTypes.CONVERSATION_CANCELLED) {
      conversation.status = conversationStatuses.CANCELLED;
      conversation.blockingItem = null;
      conversation.blockingQueue = [];
      conversation.idleExpiresAt = null;
      conversation.handle = null;
      this.touch(conversation);
    }
    if (eventToAppend.type === conversationEventTypes.RUN_ERROR) {
      conversation.status = conversationStatuses.FAILED;
      conversation.blockingItem = null;
      conversation.blockingQueue = [];
      conversation.idleExpiresAt = null;
      conversation.handle = null;
      this.touch(conversation);
    }
    const terminalEvent = eventCompletesTurn(eventToAppend) || eventToAppend.type === conversationEventTypes.CONVERSATION_CANCELLED || eventToAppend.type === conversationEventTypes.RUN_ERROR;
    if (terminalEvent) {
      this.cleanupTurnAttachmentScratch(conversation);
    }
    const { type, ...payload } = eventToAppend;
    this.eventStore.append(conversation.id, type || conversationEventTypes.PROTOCOL_WARNING, payload);
    if (terminalEvent) conversation.attachmentDispatchRedactionContext = null;
    if (eventCompletesTurn(eventToAppend)) {
      this.eventStore.append(conversation.id, conversationEventTypes.STATUS_CHANGED, { status: conversation.status });
    }
    if (eventToAppend.type === conversationEventTypes.RUN_ERROR) {
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
        conversation.blockingQueue = [];
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
        expectedSessionId: sessionBindingEventString(conversation.cliSessionId),
        receivedSessionId: sessionBindingEventString(receivedSessionId),
        adapter: conversation.adapter
      });
      return false;
    }
    if (conversation.sessionBinding !== conversationSessionBindings.DRIFTED) {
      conversation.sessionBinding = conversationSessionBindings.CONFIRMED;
    }
    return true;
  }

  clearSessionBinding(conversation, {
    expectedSessionId,
    reason,
    code,
    noticeKind = 'session_binding_cleared',
    visible = false
  } = {}) {
    const expectedConflict = sessionBindingExpectedConflict(conversation, expectedSessionId);
    if (expectedConflict) return expectedConflict;
    const safeNoticeKind = sessionBindingEventString(noticeKind) || 'session_binding_cleared';
    const safeReason = sessionBindingEventString(reason);
    const safeCode = sessionBindingEventString(code);
    const snapshot = snapshotSessionBindingState(conversation);
    conversation.cliSessionId = null;
    conversation.sessionBinding = conversationSessionBindings.UNKNOWN;
    conversation.providerSession = null;
    try {
      this.touch(conversation);
    } catch (error) {
      restoreSessionBindingState(conversation, snapshot);
      throw error;
    }
    try {
      this.eventStore.append(conversation.id, conversationEventTypes.SYSTEM_NOTICE, {
        noticeKind: safeNoticeKind,
        visible: visible === true,
        ...(safeReason ? { reason: safeReason } : {}),
        ...(safeCode ? { code: safeCode } : {})
      });
    } catch (error) {
      restoreSessionBindingState(conversation, snapshot);
      this.persistConversation(conversation);
      throw error;
    }
    return { ok: true };
  }

  markSessionBindingDrifted(conversation, {
    expectedSessionId,
    receivedSessionId,
    reason,
    code,
    clear = false
  } = {}) {
    const expectedConflict = sessionBindingExpectedConflict(conversation, expectedSessionId);
    if (expectedConflict) return expectedConflict;
    const safeExpectedSessionId = sessionBindingEventString(expectedSessionId);
    const safeReceivedSessionId = sessionBindingEventString(receivedSessionId);
    const safeReason = sessionBindingEventString(reason);
    const safeCode = sessionBindingEventString(code);
    const snapshot = snapshotSessionBindingState(conversation);
    conversation.sessionBinding = conversationSessionBindings.DRIFTED;
    if (clear) {
      conversation.cliSessionId = null;
      conversation.providerSession = null;
    }
    try {
      this.touch(conversation);
    } catch (error) {
      restoreSessionBindingState(conversation, snapshot);
      throw error;
    }
    try {
      this.eventStore.append(conversation.id, conversationEventTypes.PROTOCOL_WARNING, {
        warning: 'session_binding_drifted',
        ...(safeExpectedSessionId ? { expectedSessionId: safeExpectedSessionId } : {}),
        ...(safeReceivedSessionId ? { receivedSessionId: safeReceivedSessionId } : {}),
        ...(safeReason ? { reason: safeReason } : {}),
        ...(safeCode ? { code: safeCode } : {})
      });
    } catch (error) {
      restoreSessionBindingState(conversation, snapshot);
      this.persistConversation(conversation);
      throw error;
    }
    return { ok: true };
  }

  async ensureStarted(conversation) {
    if (conversation.handle) return conversation.handle;
    const adapterName = effectiveAdapterName(conversation);
    const adapter = this.getAdapter(adapterName);
    let startedHandle = null;
    try {
      startedHandle = await this.startConversationWithAdapter(conversation, adapterName, adapter);
    } catch (error) {
      if (conversation.status !== conversationStatuses.RUNNING) return null;
      if (!canFallbackFromAppServerStart(conversation, adapterName, error) || !this.adapters.has('codex')) throw error;
      if (adapter && typeof adapter.recordFallbackBeforeFirstRequest === 'function') {
        adapter.recordFallbackBeforeFirstRequest();
      }
      const fallbackAdapter = this.getAdapter('codex');
      conversation.effectiveAdapter = 'codex';
      conversation.effectiveCapabilities = capabilitiesForAdapter(fallbackAdapter);
      conversation.fallbackNotice = {
        from: 'codex-app-server',
        to: 'codex',
        reason: error.message || 'app_server_start_failed',
        boundary: 'before_provider_request',
        at: this.now().toISOString()
      };
      this.touch(conversation);
      this.eventStore.append(conversation.id, conversationEventTypes.SYSTEM_NOTICE, {
        noticeKind: 'adapter_fallback',
        visible: false,
        ...conversation.fallbackNotice
      });
      startedHandle = await this.startConversationWithAdapter(conversation, 'codex', fallbackAdapter);
    }
    if (conversation.status !== conversationStatuses.RUNNING) {
      await disposeDetachedHandle(startedHandle);
      return null;
    }
    conversation.handle = startedHandle;
    return conversation.handle;
  }

  async startConversationWithAdapter(conversation, adapterName, adapter) {
    let startedHandle = null;
    startedHandle = await adapter.startConversation({
      conversationId: conversation.id,
      workspacePath: conversation.workspacePath,
      permissionMode: conversation.permissionMode,
      sessionId: conversation.cliSessionId,
      model: conversation.model,
      requestedToolPolicy: conversation.requestedToolPolicy,
      claudeOptions: conversation.claudeOptions,
      initialTaskProgress: adapterName === 'claude'
        ? buildClaudeTaskProgressSeed(this.eventStore.list(conversation.id, 0))
        : null,
      sessionBindingActions: {
        clearSessionBinding: (options) => this.clearSessionBinding(conversation, options),
        markSessionBindingDrifted: (options) => this.markSessionBindingDrifted(conversation, options)
      },
      onEvent: (event) => {
        if (startedHandle && conversation.handle !== startedHandle) return;
        if (!startedHandle && conversation.status !== conversationStatuses.RUNNING) return;
        this.recordAdapterEvent(conversation, event);
      }
    });
    return startedHandle;
  }

  markPerf(name, input = {}) {
    if (!this.perfTracer || typeof this.perfTracer.mark !== 'function') return;
    try {
      this.perfTracer.mark({
        name,
        conversationId: input.conversationId ?? null,
        seq: input.seq ?? null,
        eventType: input.eventType ?? null,
        correlationId: input.correlationId ?? null,
        metadata: input.metadata ?? {}
      });
    } catch {
      // Perf tracing is best-effort and must not affect conversations.
    }
  }

  setBlockingItem(conversation, blockingItem, status, event) {
    if (conversation.blockingItem) {
      this.enqueueBlockingItem(conversation, blockingItem, status, event);
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

  enqueueBlockingItem(conversation, blockingItem, status, event) {
    const queue = Array.isArray(conversation.blockingQueue) ? conversation.blockingQueue : [];
    const duplicate = queue.some((item) => blockingItemsMatch(item.blockingItem, blockingItem));
    if (!duplicate && !blockingItemsMatch(conversation.blockingItem, blockingItem)) {
      queue.push({ blockingItem, status, event });
    }
    conversation.blockingQueue = queue;
  }

  promoteNextBlockingItem(conversation) {
    const queue = Array.isArray(conversation.blockingQueue) ? conversation.blockingQueue : [];
    if (conversation.blockingItem || queue.length === 0) {
      conversation.blockingQueue = queue;
      return false;
    }
    const next = queue.shift();
    conversation.blockingQueue = queue;
    this.setBlockingItem(conversation, next.blockingItem, next.status, next.event);
    return true;
  }

  removeQueuedBlockingItem(conversation, event) {
    const queue = Array.isArray(conversation.blockingQueue) ? conversation.blockingQueue : [];
    const index = queue.findIndex((item) => blockingCancellationMatches(item.blockingItem, event));
    if (index < 0) return false;
    queue.splice(index, 1);
    conversation.blockingQueue = queue;
    const { type, ...payload } = sanitizeAdapterEvent(event, conversation.attachmentDispatchRedactionContext);
    this.eventStore.append(conversation.id, type, payload);
    return true;
  }

  removeQueuedResolvedApproval(conversation, event) {
    const queue = Array.isArray(conversation.blockingQueue) ? conversation.blockingQueue : [];
    const index = queue.findIndex((item) => resolvedApprovalMatches(item.blockingItem, event));
    if (index < 0) return false;
    const [removed] = queue.splice(index, 1);
    conversation.blockingQueue = queue;
    const blockingPayload = { ...(removed?.blockingItem || {}) };
    delete blockingPayload.type;
    delete blockingPayload.createdAt;
    delete blockingPayload.expiresAt;
    const { type, ...payload } = sanitizeAdapterEvent({
      ...blockingPayload,
      ...event
    }, conversation.attachmentDispatchRedactionContext);
    this.eventStore.append(conversation.id, type, payload);
    return true;
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

  resolveAdapterSelection(requestedAdapterName) {
    const requestedAdapter = this.adapters.get(requestedAdapterName);
    if (requestedAdapterName !== 'codex-app-server') {
      if (!requestedAdapter) throw notFound(`conversation adapter not found: ${requestedAdapterName}`);
      return {
        requestedAdapterName,
        requestedAdapter,
        effectiveAdapterName: requestedAdapterName,
        effectiveAdapter: requestedAdapter,
        fallbackNotice: null
      };
    }

    const requestedStatus = codexAppServerSelectionStatus(requestedAdapter);
    if (requestedAdapter && requestedStatus.selectable) {
      return {
        requestedAdapterName,
        requestedAdapter,
        effectiveAdapterName: requestedAdapterName,
        effectiveAdapter: requestedAdapter,
        fallbackNotice: null
      };
    }

    const codexAdapter = this.adapters.get('codex');
    if (!codexAdapter) {
      if (!requestedAdapter) throw notFound(`conversation adapter not found: ${requestedAdapterName}`);
      return {
        requestedAdapterName,
        requestedAdapter,
        effectiveAdapterName: requestedAdapterName,
        effectiveAdapter: requestedAdapter,
        fallbackNotice: null
      };
    }
    if (requestedAdapter && typeof requestedAdapter.recordFallbackBeforeFirstRequest === 'function') {
      requestedAdapter.recordFallbackBeforeFirstRequest();
    }

    return {
      requestedAdapterName,
      requestedAdapter: requestedAdapter || missingAdapterCapabilities(),
      effectiveAdapterName: 'codex',
      effectiveAdapter: codexAdapter,
      fallbackNotice: {
        from: requestedAdapterName,
        to: 'codex',
        reason: requestedStatus.unavailableReason || 'adapter_not_configured',
        boundary: 'before_provider_request',
        at: this.now().toISOString()
      }
    };
  }

  touch(conversation) {
    conversation.updatedAt = this.now().toISOString();
    this.persistConversation(conversation);
  }

  async cleanupTurnAttachmentScratch(conversation) {
    const scratches = Array.isArray(conversation.turnAttachmentScratches)
      ? conversation.turnAttachmentScratches.splice(0)
      : [];
    await Promise.all(scratches.map((scratch) => this.cleanupAttachmentScratch(conversation, scratch)));
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

function effectiveAdapterName(conversation) {
  return conversation.effectiveAdapter || conversation.adapter;
}

function canFallbackFromAppServerStart(conversation, adapterName, error) {
  return adapterName === 'codex-app-server' &&
    conversation.requestedAdapter === 'codex-app-server' &&
    conversation.effectiveAdapter === 'codex-app-server' &&
    error?.codexAppServerFallbackAllowed === true;
}

function capabilitiesForAdapter(adapter) {
  if (!adapter) return {};
  if (typeof adapter.getCapabilities === 'function') return adapter.getCapabilities() || {};
  return adapter.capabilities || {};
}

function codexAppServerSelectionStatus(adapter) {
  if (!adapter) return { selectable: false, unavailableReason: 'adapter_not_configured' };
  if (typeof adapter.detectCapabilities === 'function') {
    const status = adapter.detectCapabilities() || {};
    return {
      selectable: status.selectable === true || status.available === true,
      unavailableReason: status.unavailableReason || (status.status === 'unavailable' ? 'unavailable' : null)
    };
  }
  return {
    selectable: adapter.selectable === true,
    unavailableReason: adapter.unavailableReason || 'unavailable'
  };
}

function missingAdapterCapabilities() {
  return {
    capabilities: {}
  };
}

function normalizeConversationEventsForReplay(events, conversation, eventStore) {
  const normalized = events
    .map((event) => normalizeLegacyConversationEventForReplay(event, conversation))
    .map(sanitizeProviderSessionEvent);
  if (effectiveAdapterName(conversation) !== 'claude' || normalized.length === 0) return normalized;
  const firstSeq = Number(normalized[0]?.seq || 0);
  const seed = buildClaudeTaskProgressSeed(
    eventStore.list(conversation.id, 0).filter((event) => Number(event.seq || 0) < firstSeq)
  );
  return repairClaudeTaskProgressEvents(normalized, seed);
}

function normalizeLegacyConversationEventForReplay(event, conversation) {
  if (effectiveAdapterName(conversation) !== 'codex') return event;
  if (!event || event.type !== conversationEventTypes.SYSTEM_NOTICE) return event;
  if (event.noticeKind !== 'codex_unknown_event') return event;
  const mapped = mapCodexEvent(event.raw, { workspacePath: conversation.workspacePath });
  if (!mapped) return event;
  if (
    mapped.type === conversationEventTypes.SYSTEM_NOTICE &&
    mapped.noticeKind === 'codex_unknown_event'
  ) {
    return event;
  }
  return {
    seq: event.seq,
    conversationId: event.conversationId,
    createdAt: event.createdAt,
    ...mapped
  };
}

function buildClaudeTaskProgressSeed(events) {
  const tasks = new Map();
  for (const event of events || []) {
    if (!isClaudeTaskProgressEvent(event)) continue;
    mergeClaudeTaskProgressItems(tasks, event.items, event);
  }
  return { items: Array.from(tasks.values()) };
}

function repairClaudeTaskProgressEvents(events, seed) {
  const tasks = new Map();
  mergeClaudeTaskProgressItems(tasks, seed?.items, null);
  return events.map((event) => {
    if (!isClaudeTaskProgressEvent(event)) return event;
    const repairedItems = repairClaudeTaskProgressItems(tasks, event.items, event);
    mergeClaudeTaskProgressItems(tasks, repairedItems, event);
    return { ...event, items: repairedItems };
  });
}

function isClaudeTaskProgressEvent(event) {
  return event &&
    event.type === conversationEventTypes.TASK_PROGRESS_UPDATED &&
    event.source === 'claude' &&
    event.taskId === 'claude_tasks' &&
    Array.isArray(event.items);
}

function mergeClaudeTaskProgressItems(tasks, items, event) {
  for (const item of Array.isArray(items) ? items : []) {
    const normalized = normalizedClaudeTaskProgressItem(tasks, item, event);
    if (!normalized) continue;
    tasks.set(normalized.id, normalized);
  }
}

function repairClaudeTaskProgressItems(tasks, items, event) {
  return (Array.isArray(items) ? items : [])
    .map((item) => normalizedClaudeTaskProgressItem(tasks, item, event))
    .filter(Boolean);
}

function normalizedClaudeTaskProgressItem(tasks, item, event) {
  if (!item || typeof item !== 'object') return null;
  const id = stringValue(item.id);
  if (!id) return null;
  const previous = tasks.get(id) || null;
  const incomingTitle = stringValue(item.title);
  const previousTitle = stringValue(previous?.title);
  const knownPreviousTitle = isFallbackClaudeTaskTitle(id, previousTitle) ? '' : previousTitle;
  const eventTitle = claudeTaskDescriptionForProgressEvent(event, id);
  const title = isFallbackClaudeTaskTitle(id, incomingTitle)
    ? knownPreviousTitle || eventTitle || incomingTitle
    : incomingTitle || knownPreviousTitle || eventTitle;
  if (!title) return null;
  return {
    id,
    title,
    status: stringValue(item.status) || stringValue(previous?.status) || 'pending'
  };
}

function isFallbackClaudeTaskTitle(id, title) {
  return title === `Task #${id}`;
}

function claudeTaskDescriptionForProgressEvent(event, taskId) {
  if (!event || !event.raw || typeof event.raw !== 'object') return '';
  const input = firstClaudeToolUseInput(event.raw);
  const rawTaskId = stringValue(input?.taskId || input?.id);
  if (rawTaskId && rawTaskId !== taskId) return '';
  return stringValue(event.raw.task_description || event.raw.taskDescription);
}

function firstClaudeToolUseInput(raw) {
  const content = raw.message && typeof raw.message === 'object' ? raw.message.content : null;
  if (!Array.isArray(content)) return null;
  for (const item of content) {
    if (item && typeof item === 'object' && item.type === 'tool_use' && item.input && typeof item.input === 'object') {
      return item.input;
    }
  }
  return null;
}

function stringValue(value) {
  if (typeof value !== 'string' && typeof value !== 'number') return '';
  return String(value).trim();
}

function sessionBindingEventString(value) {
  const text = redactSessionBindingPathText(stringValue(value));
  if (!text) return null;
  if (text.length <= sessionBindingEventMaxChars) return text;
  return `${text.slice(0, sessionBindingEventMaxChars - 3)}...`;
}

function sessionBindingExpectedConflict(conversation, expectedSessionId) {
  if (!expectedSessionId || expectedSessionId === conversation.cliSessionId) return null;
  return {
    ok: false,
    conflict: true,
    expectedSessionId: sessionBindingEventString(expectedSessionId),
    actualSessionId: sessionBindingEventString(conversation.cliSessionId) || null
  };
}

function redactSessionBindingPathText(value) {
  let text = String(value || '');
  if (!text) return '';
  text = text.replace(/file:\/\/[^\r\n"'`<>{}|]*/gi, '[Redacted path]');
  text = text.replace(/[A-Za-z]:[\\/][^\r\n"'`<>{}|]*/g, '[Redacted path]');
  text = text.replace(/\\\\[^\\/\s]+[\\/][^\r\n"'`<>{}|]*/g, '[Redacted path]');
  text = text.replace(/(^|[\s([{=:])\/(?:bin|dev|etc|home|mnt|opt|private|proc|root|sbin|sys|tmp|users|usr|var|workspace)(?:\/[^\r\n"'`<>{}|]*)?/gi, '$1[Redacted path]');
  return text.trim();
}

function snapshotSessionBindingState(conversation) {
  return {
    cliSessionId: conversation.cliSessionId,
    sessionBinding: conversation.sessionBinding,
    providerSession: conversation.providerSession,
    updatedAt: conversation.updatedAt
  };
}

function restoreSessionBindingState(conversation, snapshot) {
  conversation.cliSessionId = snapshot.cliSessionId;
  conversation.sessionBinding = snapshot.sessionBinding;
  conversation.providerSession = snapshot.providerSession;
  conversation.updatedAt = snapshot.updatedAt;
}

async function disposeIdleHandle(conversation) {
  if (!conversation.handle) return;
  const handle = conversation.handle;
  try {
    await disposeDetachedHandle(handle);
  } finally {
    conversation.handle = null;
  }
}

async function disposeDetachedHandle(handle) {
  if (!handle) return;
  if (typeof handle.dispose === 'function') {
    await handle.dispose();
    return;
  }
  if (typeof handle.cancel === 'function') await handle.cancel();
}

async function detectedAdapterStatusFor(adapter) {
  if (typeof adapter.detectCapabilities === 'function') {
    return await adapter.detectCapabilities() || adapter.capability || {};
  }
  return adapter.capability || {};
}

async function modelCapabilityFor(adapter, status = null) {
  const detectedStatus = status || await detectedAdapterStatusFor(adapter);
  if (typeof adapter.getModelCapability !== 'function') {
    return { canSelectModel: false, selectedModel: null, models: [] };
  }
  const capability = await adapter.getModelCapability(detectedStatus);
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

function requireHandleMethod(handle, name) {
  if (typeof handle[name] !== 'function') throw conflict(`active conversation does not support ${name}`);
  return handle[name];
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
  if (effectiveAdapterName(conversation) === 'codex' && file.kind === 'image' && file.handling === 'native') return 'turn';
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

function validateAdapterAttachmentLimits(conversation, files) {
  if (effectiveAdapterName(conversation) !== 'claude') return;
  for (const file of files) {
    if (file.kind === 'image' && file.handling === 'native' && file.sizeBytes > claudeMaxNativeImageBytes) {
      throw attachmentError(413, 'ATTACHMENT_LIMIT_EXCEEDED', 'Claude image attachment exceeds 5 MB limit', {
        adapter: 'claude',
        maxImageAttachmentBytes: claudeMaxNativeImageBytes
      });
    }
  }
}

function sanitizeAdapterDispatchError(error, { hasAttachments, files = [] } = {}) {
  if (!hasAttachments) return error;
  const context = attachmentDispatchRedactionContext(files);
  if (!isRedactableAttachmentDispatchValue(error, context)) return error;
  const safe = new Error('Attachment dispatch failed');
  safe.status = 502;
  safe.code = 'attachment_dispatch_failed';
  return safe;
}

function attachmentDispatchRedactionContext(files) {
  return {
    files: files.map((file) => ({
      name: file.name,
      scratchPath: file.scratchPath
    })),
    textMarkers: files.flatMap(textAttachmentRedactionMarkers)
  };
}

function sanitizeAdapterEvent(event, context) {
  const sanitizableTypes = [
    conversationEventTypes.RUN_ERROR,
    conversationEventTypes.PROTOCOL_WARNING,
    'system.notice'
  ];
  if (!context || !sanitizableTypes.includes(event.type)) return event;
  if (!isRedactableAttachmentDispatchEvent(event, context)) return event;
  const safe = new Error('Attachment dispatch failed');
  safe.status = 502;
  safe.code = 'attachment_dispatch_failed';
  if (event.type === conversationEventTypes.RUN_ERROR) {
    return { type: conversationEventTypes.RUN_ERROR, ...runErrorPayload(safe) };
  }
  return {
    type: conversationEventTypes.PROTOCOL_WARNING,
    text: safe.message,
    message: safe.message,
    ...(Object.prototype.hasOwnProperty.call(event, 'visible') ? { visible: event.visible } : {})
  };
}

function isRedactableAttachmentDispatchValue(value, context) {
  return isPathLikeAttachmentDispatchError(value, context.files) ||
    isRawAttachmentDispatchError(value) ||
    hasTextAttachmentEcho(value, context);
}

function isRedactableAttachmentDispatchEvent(event, context) {
  return isPathLikeAttachmentDispatchEvent(event, context.files) ||
    hasRawAttachmentDispatchPayload(event) ||
    hasTextAttachmentEcho(event, context);
}

function isRawAttachmentDispatchError(error) {
  if (hasRawAttachmentDispatchPayload(error)) return true;
  return hasRawAttachmentDispatchPayload(typeof error?.message === 'string' ? error.message : '');
}

function isPathLikeAttachmentDispatchEvent(event, files) {
  const strings = collectDiagnosticStringValues(event);
  const code = typeof event.code === 'string' ? event.code : '';
  return isPathLikeAttachmentDispatchError({ message: strings.join(' '), code }, files);
}

function hasRawAttachmentDispatchPayload(value, key = '', seen = new Set()) {
  if (typeof value === 'string') return looksLikeRawAttachmentContent(value, key);
  if (!value || typeof value !== 'object') return false;
  if (seen.has(value)) return false;
  seen.add(value);
  if (Buffer.isBuffer(value)) return isSuspiciousRawAttachmentKey(key) && value.length >= 16;
  if (Array.isArray(value)) return value.some((item) => hasRawAttachmentDispatchPayload(item, key, seen));
  return Object.entries(value).some(([childKey, childValue]) => hasRawAttachmentDispatchPayload(childValue, childKey, seen));
}

function looksLikeRawAttachmentContent(value, key) {
  const compact = value.replace(/\s+/g, '');
  if (imageMagicHexPattern().test(compact)) return true;
  if (imageMagicBase64Pattern().test(compact)) return true;
  if (!isSuspiciousRawAttachmentKey(key)) return false;
  if (/^[0-9a-fA-F]{48,}$/.test(compact)) return true;
  return compact.length >= 80 && /^[A-Za-z0-9+/]+={0,2}$/.test(compact);
}

function isSuspiciousRawAttachmentKey(key) {
  return /^(?:rawbytes|bytes|buffer|base64|image|data)$/i.test(String(key || ''));
}

function imageMagicHexPattern() {
  return /(?:89504e470d0a1a0a|ffd8ff|52494646[0-9a-fA-F]{8}57454250)/i;
}

function imageMagicBase64Pattern() {
  return /(?:iVBORw0KGgo|\/9j\/|UklGR)/;
}

function collectStringValues(value, seen = new Set()) {
  if (typeof value === 'string') return [value];
  if (!value || typeof value !== 'object') return [];
  if (seen.has(value)) return [];
  seen.add(value);
  if (Array.isArray(value)) return value.flatMap((item) => collectStringValues(item, seen));
  return Object.values(value).flatMap((item) => collectStringValues(item, seen));
}

function collectDiagnosticStringValues(value) {
  const strings = collectStringValues(value);
  if (value && typeof value === 'object') {
    if (typeof value.message === 'string') strings.push(value.message);
    if (typeof value.code === 'string') strings.push(value.code);
  }
  return strings;
}

function safeJsonByteLength(value) {
  try {
    return Buffer.byteLength(JSON.stringify(value), 'utf8');
  } catch {
    return null;
  }
}

function isPathLikeAttachmentDispatchError(error, files) {
  const message = collectDiagnosticStringValues(error).join(' ');
  const code = typeof error?.code === 'string' ? error.code : '';
  if (!message && !code) return false;
  for (const file of files) {
    if (file?.scratchPath && includesScratchPath(message, file.scratchPath)) return true;
  }
  if (looksLikeAttachmentScratchPath(message)) return true;
  if (/\braw bytes?\b/i.test(message)) return true;
  return false;
}

function includesScratchPath(message, scratchPath) {
  const rawPath = String(scratchPath);
  if (message.includes(rawPath)) return true;
  return String(message).replace(/\\/g, '/').includes(rawPath.replace(/\\/g, '/'));
}

function looksLikeAttachmentScratchPath(message) {
  const normalized = String(message || '').replace(/\\/g, '/');
  return /(?:^|[\s'"])(?:[A-Za-z]:)?\/?[^\s'"]*\/(?:vibe-coding-)?attachment-scratch(?:-[^/\s'"]*)?\/[^\s'"]+/i.test(normalized);
}

function textAttachmentRedactionMarkers(file) {
  if (file?.kind !== 'textDocument' || file.text == null) return [];
  const text = String(file.text);
  const wrapper = textAttachmentWrapper({ name: file.name, mimeType: file.mimeType, text });
  return uniqueRedactionMarkers([
    wrapper,
    ...prefixRedactionMarkers(wrapper),
    ...textContentRedactionMarkers(text)
  ]);
}

function hasTextAttachmentEcho(value, context) {
  const markers = Array.isArray(context?.textMarkers) ? context.textMarkers.filter(Boolean) : [];
  if (markers.length === 0) return false;
  const strings = collectDiagnosticStringValues(value);
  return strings.some((item) => markers.some((marker) => includesMarker(item, marker)));
}

function includesMarker(value, marker) {
  if (value.includes(marker)) return true;
  const normalizedValue = normalizeRedactionMarker(value);
  const normalizedMarker = normalizeRedactionMarker(marker);
  return normalizedMarker.length >= 12 && normalizedValue.includes(normalizedMarker);
}

function prefixRedactionMarkers(value) {
  const markers = [];
  for (const length of [32, 48, 64, 96]) {
    if (value.length >= length) markers.push(value.slice(0, length));
  }
  return markers;
}

function textContentRedactionMarkers(text) {
  const normalized = normalizeRedactionMarker(text);
  if (!normalized) return [];
  const markers = [normalized];
  if (normalized.length < 12) return markers;
  const words = normalized.match(/[^\s]+/g) || [];
  for (let index = 0; index < words.length; index += 1) {
    let snippet = '';
    for (let end = index; end < words.length && snippet.length < 48; end += 1) {
      snippet = snippet ? `${snippet} ${words[end]}` : words[end];
      if (snippet.length >= 12) markers.push(snippet);
    }
  }
  return markers;
}

function normalizeRedactionMarker(value) {
  return String(value).replace(/\s+/g, ' ').trim();
}

function uniqueRedactionMarkers(markers) {
  return [...new Set(markers.filter((marker) => normalizeRedactionMarker(marker).length > 0))];
}

function runErrorPayload(error) {
  return {
    message: error.message,
    ...(error.code ? { code: error.code } : {}),
    ...(error.status ? { status: error.status } : {})
  };
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
  const code = typeof error?.code === 'string' ? error.code.trim() : '';
  if (/^[A-Z][A-Z0-9_]*$/.test(code)) return code;
  return 'cleanup_failed';
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

function blockingItemsMatch(left, right) {
  if (!left || !right || left.type !== right.type) return false;
  if (left.type === 'approval_request') return !!left.approvalId && left.approvalId === right.approvalId;
  if (left.type === 'input_request') return !!left.questionId && left.questionId === right.questionId;
  return false;
}

function blockingCancellationMatches(blockingItem, event) {
  if (!blockingItem || !event || blockingItem.type !== event.blockingType) return false;
  if (blockingItem.type === 'approval_request') return !!blockingItem.approvalId && blockingItem.approvalId === event.approvalId;
  if (blockingItem.type === 'input_request') return !!blockingItem.questionId && blockingItem.questionId === event.questionId;
  return false;
}

function resolvedApprovalMatches(blockingItem, event) {
  return !!blockingItem &&
    !!event &&
    blockingItem.type === 'approval_request' &&
    !!blockingItem.approvalId &&
    blockingItem.approvalId === event.approvalId;
}

function validateApprovalDecisionForRequest(decision, blockingItem) {
  const options = blockingItem?.approvalOptions || {};
  if (decision.decision === 'allow' && decision.scope === 'session' && options.supportsSessionScope !== true) {
    throw badRequest('approval request does not support session scope');
  }
  if (decision.decision === 'deny' && decision.interrupt === false && options.denyBehavior !== 'continue') {
    throw badRequest('approval request does not support continuing after deny');
  }
}

function snapshotPreCommitState(conversation) {
  return {
    status: conversation.status,
    blockingItem: conversation.blockingItem,
    blockingQueue: Array.isArray(conversation.blockingQueue) ? [...conversation.blockingQueue] : [],
    idleExpiresAt: conversation.idleExpiresAt,
    title: conversation.title,
    userMessageCount: conversation.userMessageCount,
    updatedAt: conversation.updatedAt
  };
}

function restorePreCommitState(conversation, snapshot) {
  conversation.status = snapshot.status;
  conversation.blockingItem = snapshot.blockingItem;
  conversation.blockingQueue = snapshot.blockingQueue;
  conversation.idleExpiresAt = snapshot.idleExpiresAt;
  conversation.title = snapshot.title;
  conversation.userMessageCount = snapshot.userMessageCount;
  conversation.updatedAt = snapshot.updatedAt;
}

function modelCapabilityHashInput(model, adapterAttachments) {
  const input = {
    id: model.id
  };
  if (Array.isArray(model.inputModalities)) {
    input.inputModalities = model.inputModalities;
  }
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

function sanitizeProviderSession(input) {
  const output = {};
  for (const key of ['provider', 'threadId', 'protocolVersion', 'model', 'sandboxProfile', 'createdAt']) {
    const value = input[key];
    if (value === undefined || value === null) continue;
    if (typeof value === 'string') {
      const trimmed = value.trim();
      if (trimmed) output[key] = trimmed;
      continue;
    }
    if (key === 'protocolVersion' && Number.isInteger(value)) {
      output[key] = value;
    }
  }
  return output;
}

function publicProviderSession(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) return null;
  const sanitized = sanitizeProviderSession(input);
  return Object.keys(sanitized).length > 0 ? sanitized : null;
}

function sanitizeProviderSessionEvent(event) {
  if (!event || typeof event !== 'object' || Array.isArray(event)) return event;
  if (!Object.prototype.hasOwnProperty.call(event, 'providerSession')) return event;
  const providerSession = publicProviderSession(event.providerSession);
  if (providerSession) return { ...event, providerSession };
  const sanitized = { ...event };
  delete sanitized.providerSession;
  return sanitized;
}

function publicConversation(conversation) {
  const requestedAdapter = conversation.requestedAdapter || conversation.adapter;
  const effectiveAdapter = conversation.effectiveAdapter || conversation.adapter;
  const capabilities = conversation.capabilities || {};
  const effectiveCapabilities = conversation.effectiveCapabilities || capabilities;
  return {
    id: conversation.id,
    workspaceId: conversation.workspaceId,
    adapter: conversation.adapter,
    requestedAdapter,
    effectiveAdapter,
    model: conversation.model || null,
    status: conversation.status,
    cliSessionId: conversation.cliSessionId || null,
    sessionBinding: conversation.sessionBinding || (conversation.cliSessionId ? conversationSessionBindings.CONFIRMED : conversationSessionBindings.UNKNOWN),
    title: conversation.title || null,
    userMessageCount: Number(conversation.userMessageCount || 0),
    blockingItem: conversation.blockingItem || null,
    idleExpiresAt: conversation.idleExpiresAt || null,
    createdAt: conversation.createdAt,
    updatedAt: conversation.updatedAt,
    capabilities,
    effectiveCapabilities,
    fallbackNotice: conversation.fallbackNotice || null,
    providerSession: publicProviderSession(conversation.providerSession),
    requestedPermissionMode: conversation.requestedPermissionMode || conversation.permissionMode || 'default',
    effectivePermissionMode: conversation.effectivePermissionMode || conversation.permissionMode || 'default',
    requestedTools: Array.isArray(conversation.requestedTools) ? conversation.requestedTools : [],
    requestedToolPolicy: conversation.requestedToolPolicy || { tools: [], allowedTools: [], disallowedTools: [] },
    resumePolicy: conversation.resumePolicy || { type: 'fresh' },
    systemPromptPolicy: conversation.systemPromptPolicy || { type: 'none' },
    claudeOptions: conversation.claudeOptions || {},
    permissionSupport: conversation.permissionSupport || {},
    notices: Array.isArray(conversation.notices) ? conversation.notices : [],
    protocolVersion: conversation.protocolVersion || 1
  };
}

function adapterApprovalCapability(conversation) {
  const capabilities = conversation.effectiveCapabilities || conversation.capabilities || {};
  return capabilities.approval || {};
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
