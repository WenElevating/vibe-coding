'use strict';

const path = require('node:path');
const { URL } = require('node:url');
const { conversationEventTypes } = require('./conversation-protocol');

const RAW_PAYLOAD_MAX_CHARS = 4096;
const RAW_LIMITS = Object.freeze({
  maxDepth: 4,
  maxArrayLength: 20,
  maxObjectKeys: 16,
  maxStringLength: 512
});
const PROVIDER_FIELD_MAX_CHARS = RAW_LIMITS.maxStringLength;
const CRITICAL_PREFIXES = ['message.', 'permission.', 'session.status', 'session.idle', 'session.error', 'session.diff', 'file.edited'];
const POLLUTION_KEYS = new Set(['__proto__', 'prototype', 'constructor']);

function mapOpenCodeEvent(raw, options = {}) {
  if (!safeObject(raw)) return null;
  const normalizedOptions = normalizeOptions(options);
  const providerRawType = firstSafeString(raw, ['type', 'event', 'kind']);
  if (!providerRawType) return unknownNotice(raw, 'opencode_unknown_event');
  const rawType = boundedRedactedProviderString(providerRawType);
  const sessionId = normalizeId(raw, ['sessionID', 'sessionId', 'session_id', 'session'], ['id', 'sessionID', 'sessionId', 'session_id']);
  if (isCritical(providerRawType) && !sessionId) {
    return {
      type: conversationEventTypes.PROTOCOL_WARNING,
      warning: 'opencode_critical_event_missing_session_id',
      dispatchable: false,
      rawType,
      raw: sanitizeRaw(raw)
    };
  }
  if (rawType === 'session.idle') {
    return { type: conversationEventTypes.CONVERSATION_COMPLETED, sessionId, rawType };
  }
  if (rawType === 'session.created' || rawType === 'session.updated') {
    return mapSessionNotice(raw, sessionId, rawType);
  }
  if (rawType === 'session.error') {
    const error = safeOwnObject(raw, 'error');
    const details = error || safeOwnObject(raw, 'details');
    const message = redactBoundedString(firstSafeStringValue([
      ownValue(raw, 'message'),
      error ? ownValue(error, 'message') : undefined
    ]) || 'OpenCode session error');
    const code = redactBoundedString(firstSafeStringValue([
      ownValue(raw, 'code'),
      error ? ownValue(error, 'code') : undefined
    ]) || 'OPENCODE_SESSION_ERROR');
    return {
      type: conversationEventTypes.RUN_ERROR,
      sessionId,
      message,
      code,
      details: details ? sanitizeRaw(details, { redactPathFields: true, redactPathStrings: true }) : null,
      rawType
    };
  }
  if (rawType === 'session.status') {
    const status = boundedProviderString(ownValue(raw, 'status'));
    if (status && normalizedOptions.terminalSessionStatuses.includes(status)) {
      return { type: conversationEventTypes.CONVERSATION_COMPLETED, sessionId, status, rawType };
    }
    return {
      type: conversationEventTypes.SYSTEM_NOTICE,
      noticeKind: 'opencode_session_status',
      visible: false,
      sessionId,
      status,
      rawType
    };
  }
  if (rawType === 'message.part.delta') {
    const part = safeOwnObject(raw, 'part');
    const ids = messagePartIds(raw, null, part);
    const text = firstSafeStringValue([
      ownValue(raw, 'delta'),
      ownValue(raw, 'text'),
      part ? ownValue(part, 'text') : undefined,
      part ? ownValue(part, 'delta') : undefined
    ]);
    const partKindValues = [
      part ? ownValue(part, 'type') : undefined,
      part ? ownValue(part, 'kind') : undefined,
      ownValue(raw, 'partType'),
      ownValue(raw, 'kind')
    ];
    const partKind = firstSafeStringValue(partKindValues);
    if (!text) return hiddenNotice(raw, sessionId, rawType);
    if (partKindValues.some((value) => /thinking|reasoning/i.test(safeStringValue(value)))) {
      return { type: conversationEventTypes.ASSISTANT_THINKING, sessionId, ...ids, text, rawType };
    }
    if (isToolPartKind(partKind)) {
      return {
        type: conversationEventTypes.TOOL_DELTA,
        sessionId,
        ...ids,
        toolUseId: toolUseId(raw, part, ids.partId),
        toolName: toolName(raw, part),
        text,
        rawType
      };
    }
    return { type: conversationEventTypes.ASSISTANT_PARTIAL, sessionId, ...ids, text, rawType };
  }
  if (rawType === 'message.updated' || rawType === 'message.part.updated') {
    return mapMessageUpdated(raw, sessionId, rawType, normalizedOptions.workspacePath);
  }
  if (rawType === 'message.part.removed' || rawType === 'message.removed') {
    const message = safeOwnObject(raw, 'message');
    const part = safeOwnObject(raw, 'part');
    const noticeKind = rawType === 'message.part.removed'
      ? 'opencode_message_part_removed'
      : 'opencode_message_removed';
    return knownHiddenNotice(raw, noticeKind, sessionId, rawType, messagePartIds(raw, message, part));
  }
  if (rawType === 'permission.asked') {
    return mapPermissionAsked(raw, sessionId, rawType, normalizedOptions.workspacePath);
  }
  if (rawType === 'permission.replied') {
    const approvalId = normalizeId(raw, ['permissionID', 'permissionId', 'permission_id', 'id']);
    if (!approvalId) return missingPermissionIdWarning(raw, sessionId, rawType);
    return {
      type: conversationEventTypes.APPROVAL_RESOLVED,
      sessionId,
      approvalId,
      decision: firstBoundedProviderStringValue([
        ownValue(raw, 'decision'),
        ownValue(raw, 'reply'),
        ownValue(raw, 'status')
      ]) || 'resolved',
      rawType
    };
  }
  if (rawType === 'session.diff') {
    return mapDiff(raw, sessionId, rawType, normalizedOptions.workspacePath);
  }
  if (rawType === 'file.edited') {
    return mapFileEdited(raw, sessionId, rawType, normalizedOptions.workspacePath);
  }
  if (rawType === 'file.watcher.updated') {
    return knownHiddenNotice(raw, 'opencode_file_watcher_updated', sessionId, rawType);
  }
  if (rawType === 'project.updated') {
    return knownHiddenNotice(raw, 'opencode_project_updated', sessionId, rawType, {
      project: sanitizeOptionalObject(safeOwnObject(raw, 'project'))
    });
  }
  return unknownNotice(raw, 'opencode_unknown_event', sessionId, rawType);
}

function normalizeOptions(options) {
  const source = safeObject(options) ? options : {};
  const terminalStatuses = ownValue(source, 'terminalSessionStatuses');
  return {
    workspacePath: safeStringValue(ownValue(source, 'workspacePath')) || null,
    terminalSessionStatuses: Array.isArray(terminalStatuses)
      ? terminalStatuses.filter((status) => typeof status === 'string')
      : []
  };
}

function mapSessionNotice(raw, sessionId, rawType) {
  const session = safeOwnObject(raw, 'session');
  const noticeKind = rawType === 'session.created'
    ? 'opencode_session_created'
    : 'opencode_session_updated';
  return knownHiddenNotice(raw, noticeKind, sessionId, rawType, {
    session: sanitizeOptionalObject(session)
  });
}

function mapMessageUpdated(raw, sessionId, rawType, workspacePath) {
  const message = safeOwnObject(raw, 'message');
  const part = safeOwnObject(raw, 'part');
  const ids = messagePartIds(raw, message, part);
  const role = messageRole(raw, message, part);
  const partKind = messagePartKind(raw, message, part);
  const text = messageText(raw, message, part);
  if (isToolPartKind(partKind) || role === 'tool') {
    return mapToolMessageUpdated(raw, sessionId, rawType, part, ids, partKind, workspacePath);
  }
  if (text && isAssistantMessage(role, partKind)) {
    return {
      type: conversationEventTypes.ASSISTANT_MESSAGE,
      sessionId,
      ...ids,
      text,
      rawType
    };
  }
  return knownHiddenNotice(raw, 'opencode_message_update', sessionId, rawType, ids);
}

function mapToolMessageUpdated(raw, sessionId, rawType, part, ids, partKind, workspacePath) {
  const status = toolStatus(raw, part);
  const normalizedToolName = toolName(raw, part);
  const normalizedToolUseId = toolUseId(raw, part, ids.partId);
  const text = messageText(raw, null, part);
  const common = {
    sessionId,
    ...ids,
    toolUseId: normalizedToolUseId,
    toolName: normalizedToolName,
    rawType
  };
  if (isToolCompleted(partKind, status)) {
    return {
      type: conversationEventTypes.TOOL_COMPLETED,
      ...common,
      text: text || toolOutput(raw, part) || 'OpenCode tool call completed.',
      status: status || null,
      isError: toolIsError(raw, part, status)
    };
  }
  return {
    type: conversationEventTypes.TOOL_STARTED,
    ...common,
    input: toolInput(raw, part, workspacePath),
    summary: toolSummary(raw, part, normalizedToolName, workspacePath)
  };
}

function mapPermissionAsked(raw, sessionId, rawType, workspacePath) {
  const inputObject = safeOwnObject(raw, 'input');
  const fileObject = safeOwnObject(raw, 'file');
  const approvalId = normalizeId(raw, ['permissionID', 'permissionId', 'permission_id', 'id']);
  const toolUseId = normalizeId(raw, [
    'toolCallID',
    'toolCallId',
    'tool_call_id',
    'toolUseID',
    'toolUseId',
    'tool_use_id',
    'callID',
    'callId',
    'call_id'
  ]);
  const command = redactBoundedString(firstSafeStringValue([
    ownValue(raw, 'command'),
    inputObject ? ownValue(inputObject, 'command') : undefined
  ]));
  if (!approvalId) return missingPermissionIdWarning(raw, sessionId, rawType);
  const rawFilePath = firstSafeStringValue([
    ownValue(raw, 'path'),
    ownValue(raw, 'filePath'),
    ownValue(raw, 'file_path'),
    fileObject ? ownValue(fileObject, 'path') : undefined,
    fileObject ? ownValue(fileObject, 'filePath') : undefined,
    fileObject ? ownValue(fileObject, 'file_path') : undefined,
    inputObject ? ownValue(inputObject, 'path') : undefined,
    inputObject ? ownValue(inputObject, 'filePath') : undefined,
    inputObject ? ownValue(inputObject, 'file_path') : undefined
  ]);
  const filePath = rawFilePath ? workspaceBoundPath(rawFilePath, workspacePath) : '';
  const toolName = redactBoundedString(firstSafeStringValue([
    ownValue(raw, 'tool'),
    ownValue(raw, 'toolName'),
    ownValue(raw, 'name')
  ]));
  const approvalOptions = {
    kind: command ? 'command' : filePath ? 'file_change' : 'generic',
    supportsSessionScope: true,
    supportsCancel: false,
    denyBehavior: 'interrupt'
  };
  if (command) approvalOptions.command = command;
  const cwd = redactBoundedString(ownValue(raw, 'cwd'));
  const reason = redactBoundedString(firstSafeStringValue([ownValue(raw, 'reason'), ownValue(raw, 'description')]));
  if (cwd) approvalOptions.cwd = cwd;
  if (reason) approvalOptions.reason = reason;
  return {
    type: conversationEventTypes.APPROVAL_REQUESTED,
    sessionId,
    approvalId,
    toolUseId,
    toolName,
    input: permissionInput(inputObject, command, filePath, workspacePath),
    summary: permissionSummary(command, filePath, toolName),
    approvalOptions,
    rawType
  };
}

function permissionInput(inputObject, command, filePath, workspacePath) {
  const input = Object.create(null);
  if (command) input.command = command;
  if (filePath) input.path = filePath;
  copyMappedInputFields(input, inputObject, workspacePath);
  return input;
}

function copyMappedInputFields(input, inputObject, workspacePath) {
  if (!safeObject(inputObject)) return;
  let inspected = 0;
  let retainedKeys = Object.keys(input).length;
  try {
    for (const key in inputObject) {
      if (inspected >= RAW_LIMITS.maxObjectKeys || retainedKeys >= RAW_LIMITS.maxObjectKeys) break;
      inspected += 1;
      if (POLLUTION_KEYS.has(key) || shouldSkipPermissionInputKey(input, key)) continue;
      const descriptor = ownDescriptor(inputObject, key);
      if (!descriptor || descriptor.enumerable !== true || !Object.prototype.hasOwnProperty.call(descriptor, 'value')) continue;
      input[key] = sanitizeMappedInputValue(key, descriptor.value, workspacePath);
      retainedKeys += 1;
    }
  } catch (_) {
    // Ignore provider-controlled iterator failures; mapped input is diagnostic only.
  }
}

function shouldSkipPermissionInputKey(input, key) {
  if (Object.prototype.hasOwnProperty.call(input, key)) return true;
  const normalized = String(key || '').toLowerCase();
  return Object.prototype.hasOwnProperty.call(input, 'path') && (
    normalized === 'filepath' ||
    normalized === 'file_path'
  );
}

function sanitizeMappedInputValue(key, value, workspacePath) {
  if (isPathLikeKey(key)) {
    const text = safeStringValue(value);
    if (text) return sanitizeMappedPathLikeString(text, workspacePath);
  }
  return sanitizeValue(value, {
    limits: RAW_LIMITS,
    seen: new WeakSet(),
    depth: 0,
    redactPathFields: true,
    redactPathStrings: true
  });
}

function sanitizeMappedPathLikeString(value, workspacePath) {
  const text = limitString(safeStringValue(value), RAW_LIMITS.maxStringLength).trim();
  if (!text) return '';
  const redacted = redactBoundedString(text);
  if (redacted !== text) return limitString(redacted, RAW_LIMITS.maxStringLength);
  return workspaceBoundPath(text, workspacePath);
}

function permissionSummary(command, filePath, toolName) {
  if (command) return command;
  if (filePath) return limitString(`OpenCode file change: ${filePath}`, RAW_LIMITS.maxStringLength);
  return toolName ? `OpenCode permission requested: ${toolName}` : 'OpenCode permission requested';
}

function mapDiff(raw, sessionId, rawType, workspacePath) {
  const files = ownValue(raw, 'files');
  const usableFiles = usableDiffFiles(files);
  if (usableFiles.length === 0) {
    const notice = knownHiddenNotice(raw, 'opencode_session_diff', sessionId, rawType, { visible: true });
    notice.raw = sanitizeRaw(raw, { redactPathFields: true, redactPathStrings: true });
    return notice;
  }
  const normalizedFiles = usableFiles.map((file) => normalizeDiffFile(file, workspacePath));
  return {
    type: conversationEventTypes.DIFF_SUMMARY,
    sessionId,
    files: sanitizeValue(normalizedFiles, { limits: RAW_LIMITS, seen: new WeakSet(), depth: 0, redactPathFields: false, redactPathStrings: false }),
    summary: redactBoundedString(ownValue(raw, 'summary')) || `${usableFiles.length} file${usableFiles.length === 1 ? '' : 's'} changed`,
    rawType,
    raw: sanitizeRaw(raw, { redactPathFields: true, redactPathStrings: true })
  };
}

function normalizeDiffFile(file, workspacePath) {
  const rawPath = firstSafeStringValue([
    ownValue(file, 'path'),
    ownValue(file, 'filePath'),
    ownValue(file, 'file_path')
  ]);
  const result = Object.create(null);
  result.path = workspaceBoundPath(rawPath, workspacePath);
  copyDiffString(result, file, 'diff');
  copyDiffString(result, file, 'patch');
  const hunks = ownValue(file, 'hunks');
  if (Array.isArray(hunks) && hunks.length > 0) {
    result.hunks = sanitizeValue(hunks, { limits: RAW_LIMITS, seen: new WeakSet(), depth: 0, redactPathFields: true, redactPathStrings: true });
  }
  for (const key of ['additions', 'deletions', 'added', 'deleted', 'binary']) {
    const value = ownValue(file, key);
    if (value !== undefined) result[key] = sanitizeValue(value, { limits: RAW_LIMITS, seen: new WeakSet(), depth: 0, redactPathFields: false, redactPathStrings: true });
  }
  return result;
}

function copyDiffString(target, source, key) {
  const value = safeStringValue(ownValue(source, key));
  if (value) target[key] = redactBoundedString(value);
}

function usableDiffFiles(files) {
  if (!Array.isArray(files)) return [];
  const result = [];
  const count = Math.min(files.length, RAW_LIMITS.maxArrayLength);
  for (let index = 0; index < count; index += 1) {
    const file = ownValue(files, String(index));
    if (safeObject(file) && hasUsableDiffFile(file)) result.push(file);
  }
  return result;
}

function hasUsableDiffFile(file) {
  const filePath = firstSafeStringValue([
    ownValue(file, 'path'),
    ownValue(file, 'filePath'),
    ownValue(file, 'file_path')
  ]);
  if (!filePath) return false;
  if (firstSafeStringValue([ownValue(file, 'diff'), ownValue(file, 'patch')])) return true;
  const hunks = ownValue(file, 'hunks');
  if (Array.isArray(hunks) && hunks.length > 0) return true;
  return [
    ownValue(file, 'additions'),
    ownValue(file, 'deletions'),
    ownValue(file, 'added'),
    ownValue(file, 'deleted')
  ].some((value) => Number.isFinite(value));
}

function mapFileEdited(raw, sessionId, rawType, workspacePath) {
  const fileObject = safeOwnObject(raw, 'file');
  const rawPath = firstSafeStringValue([
    ownValue(raw, 'path'),
    ownValue(raw, 'filePath'),
    ownValue(raw, 'file_path'),
    fileObject ? ownValue(fileObject, 'path') : undefined,
    fileObject ? ownValue(fileObject, 'filePath') : undefined,
    fileObject ? ownValue(fileObject, 'file_path') : undefined
  ]);
  if (!rawPath) return hiddenNotice(raw, sessionId, rawType);
  const filePath = workspaceBoundPath(rawPath, workspacePath);
  return {
    type: conversationEventTypes.SYSTEM_NOTICE,
    text: limitString(`OpenCode edited ${filePath}`, RAW_LIMITS.maxStringLength),
    noticeKind: 'opencode_file_edited',
    visible: true,
    sessionId,
    path: filePath,
    rawType,
    raw: sanitizeRaw(raw, { redactPathFields: true, redactPathStrings: true })
  };
}

function missingPermissionIdWarning(raw, sessionId, rawType) {
  return {
    type: conversationEventTypes.PROTOCOL_WARNING,
    warning: 'opencode_permission_event_missing_permission_id',
    sessionId,
    rawType,
    raw: sanitizeRaw(raw, { redactPathFields: true, redactPathStrings: true })
  };
}

function messagePartIds(raw, message, part) {
  const ids = {};
  const messageId = firstBoundedProviderStringValue([
    ownValue(raw, 'messageID'),
    ownValue(raw, 'messageId'),
    ownValue(raw, 'message_id'),
    message ? ownValue(message, 'id') : undefined,
    message ? ownValue(message, 'messageID') : undefined,
    message ? ownValue(message, 'messageId') : undefined,
    message ? ownValue(message, 'message_id') : undefined
  ]);
  const partId = firstBoundedProviderStringValue([
    ownValue(raw, 'partID'),
    ownValue(raw, 'partId'),
    ownValue(raw, 'part_id'),
    part ? ownValue(part, 'id') : undefined,
    part ? ownValue(part, 'partID') : undefined,
    part ? ownValue(part, 'partId') : undefined,
    part ? ownValue(part, 'part_id') : undefined
  ]);
  if (messageId) ids.messageId = messageId;
  if (partId) ids.partId = partId;
  return ids;
}

function messageRole(raw, message, part) {
  return firstSafeStringValue([
    ownValue(raw, 'role'),
    message ? ownValue(message, 'role') : undefined,
    part ? ownValue(part, 'role') : undefined
  ]).toLowerCase();
}

function messagePartKind(raw, message, part) {
  return firstSafeStringValue([
    part ? ownValue(part, 'type') : undefined,
    part ? ownValue(part, 'kind') : undefined,
    ownValue(raw, 'partType'),
    message ? ownValue(message, 'partType') : undefined,
    message ? ownValue(message, 'kind') : undefined,
    ownValue(raw, 'kind')
  ]).toLowerCase();
}

function messageText(raw, message, part) {
  return firstSafeStringValue([
    message ? ownValue(message, 'text') : undefined,
    message ? ownValue(message, 'content') : undefined,
    part ? ownValue(part, 'text') : undefined,
    part ? ownValue(part, 'content') : undefined,
    part ? ownValue(part, 'delta') : undefined,
    ownValue(raw, 'text'),
    ownValue(raw, 'delta')
  ]);
}

function isAssistantMessage(role, partKind) {
  if (role === 'user' || role === 'tool') return false;
  if (role === 'assistant') return true;
  return ['text', 'markdown', 'assistant', 'assistant_text'].includes(partKind);
}

function isToolPartKind(partKind) {
  return /(^|[._-])(tool|command)([._-]|$)/i.test(partKind || '') ||
    ['tool', 'tool_call', 'tool_use', 'tool_result', 'command', 'command_execution'].includes(partKind);
}

function toolUseId(raw, part, fallbackPartId) {
  return firstBoundedProviderStringValue([
    part ? ownValue(part, 'toolCallID') : undefined,
    part ? ownValue(part, 'toolCallId') : undefined,
    part ? ownValue(part, 'tool_call_id') : undefined,
    part ? ownValue(part, 'toolUseID') : undefined,
    part ? ownValue(part, 'toolUseId') : undefined,
    part ? ownValue(part, 'tool_use_id') : undefined,
    ownValue(raw, 'toolCallID'),
    ownValue(raw, 'toolCallId'),
    ownValue(raw, 'tool_call_id'),
    ownValue(raw, 'toolUseID'),
    ownValue(raw, 'toolUseId'),
    ownValue(raw, 'tool_use_id'),
    fallbackPartId
  ]) || null;
}

function toolName(raw, part) {
  return redactBoundedString(firstSafeStringValue([
    part ? ownValue(part, 'tool') : undefined,
    part ? ownValue(part, 'toolName') : undefined,
    part ? ownValue(part, 'name') : undefined,
    ownValue(raw, 'tool'),
    ownValue(raw, 'toolName'),
    ownValue(raw, 'name')
  ])) || 'tool';
}

function toolStatus(raw, part) {
  return firstBoundedProviderStringValue([
    part ? ownValue(part, 'status') : undefined,
    ownValue(raw, 'status')
  ]).toLowerCase();
}

function isToolCompleted(partKind, status) {
  if (partKind === 'tool_result') return true;
  return ['complete', 'completed', 'done', 'success', 'succeeded', 'failed', 'error', 'cancelled', 'canceled'].includes(status);
}

function toolIsError(raw, part, status) {
  if (ownValue(raw, 'isError') === true || ownValue(raw, 'is_error') === true) return true;
  if (part && (ownValue(part, 'isError') === true || ownValue(part, 'is_error') === true)) return true;
  return ['failed', 'error', 'cancelled', 'canceled'].includes(status);
}

function toolOutput(raw, part) {
  return firstSafeStringValue([
    part ? ownValue(part, 'output') : undefined,
    part ? ownValue(part, 'result') : undefined,
    ownValue(raw, 'output'),
    ownValue(raw, 'result')
  ]);
}

function toolInput(raw, part, workspacePath = null) {
  const input = Object.create(null);
  const inputObject = part ? safeOwnObject(part, 'input') : safeOwnObject(raw, 'input');
  const command = redactBoundedString(firstSafeStringValue([
    part ? ownValue(part, 'command') : undefined,
    ownValue(raw, 'command'),
    inputObject ? ownValue(inputObject, 'command') : undefined
  ]));
  const rawFilePath = firstSafeStringValue([
    part ? ownValue(part, 'path') : undefined,
    part ? ownValue(part, 'filePath') : undefined,
    part ? ownValue(part, 'file_path') : undefined,
    ownValue(raw, 'path'),
    ownValue(raw, 'filePath'),
    ownValue(raw, 'file_path'),
    inputObject ? ownValue(inputObject, 'path') : undefined,
    inputObject ? ownValue(inputObject, 'filePath') : undefined,
    inputObject ? ownValue(inputObject, 'file_path') : undefined
  ]);
  if (command) input.command = command;
  if (rawFilePath) input.path = workspaceBoundPath(rawFilePath, workspacePath);
  copyMappedInputFields(input, inputObject, workspacePath);
  return input;
}

function toolSummary(raw, part, normalizedToolName, workspacePath = null) {
  const input = toolInput(raw, part, workspacePath);
  if (safeStringValue(ownValue(input, 'command'))) return ownValue(input, 'command');
  return normalizedToolName || 'tool';
}

function knownHiddenNotice(raw, noticeKind, sessionId, rawType, extra = {}) {
  const event = {
    type: conversationEventTypes.SYSTEM_NOTICE,
    text: `OpenCode event: ${rawType || 'unknown'}`,
    noticeKind,
    visible: false,
    ...(sessionId ? { sessionId } : {}),
    ...(rawType ? { rawType } : {}),
    raw: sanitizeRaw(raw, { redactPathFields: true, redactPathStrings: true })
  };
  for (const [key, value] of Object.entries(extra || {})) {
    if (value !== undefined && value !== null) event[key] = value;
  }
  return event;
}

function sanitizeOptionalObject(value) {
  return safeObject(value) ? sanitizeRaw(value, { redactPathFields: true, redactPathStrings: true }) : undefined;
}

function hiddenNotice(raw, sessionId, rawType) {
  return {
    type: conversationEventTypes.SYSTEM_NOTICE,
    text: `OpenCode event: ${rawType || 'unknown'}`,
    noticeKind: 'opencode_hidden_event',
    visible: false,
    ...(sessionId ? { sessionId } : {}),
    ...(rawType ? { rawType } : {}),
    raw: sanitizeRaw(raw)
  };
}

function unknownNotice(raw, noticeKind, sessionId = null, rawType = null) {
  return {
    type: conversationEventTypes.SYSTEM_NOTICE,
    text: `OpenCode event: ${rawType || 'unknown'}`,
    noticeKind,
    visible: false,
    ...(sessionId ? { sessionId } : {}),
    ...(rawType ? { rawType } : {}),
    raw: sanitizeRaw(raw)
  };
}

function normalizeId(raw, keys, nestedKeys = ['id']) {
  for (const key of keys) {
    const value = ownValue(raw, key);
    const direct = normalizeIdValue(value);
    if (direct) return direct;
    if (safeObject(value)) {
      for (const nestedKey of nestedKeys) {
        const nested = normalizeIdValue(ownValue(value, nestedKey));
        if (nested) return nested;
      }
    }
  }
  return null;
}

function normalizeIdValue(value) {
  if (typeof value === 'string' && value.trim()) return boundedProviderString(value.trim());
  return null;
}

function isCritical(rawType) {
  return CRITICAL_PREFIXES.some((prefix) => rawType.startsWith(prefix));
}

function sanitizeRaw(raw, { redactPathFields = true, redactPathStrings = true } = {}) {
  const sanitized = sanitizeValue(raw, {
    limits: RAW_LIMITS,
    seen: new WeakSet(),
    depth: 0,
    redactPathFields,
    redactPathStrings
  });
  return enforceSerializedRawCap(sanitized);
}

function sanitizeValue(value, context) {
  if (value === null || ['boolean', 'number'].includes(typeof value)) {
    if (typeof value === 'number' && !Number.isFinite(value)) return String(value);
    return value;
  }
  if (typeof value === 'string') {
    const bounded = limitString(value, context.limits.maxStringLength);
    const text = context.redactPathStrings ? redactAbsolutePaths(bounded) : bounded;
    return limitString(text, context.limits.maxStringLength);
  }
  if (typeof value === 'bigint') return value.toString();
  if (['undefined', 'function', 'symbol'].includes(typeof value)) return `[${typeof value}]`;
  if (!safeObject(value) && !Array.isArray(value)) return String(value);
  if (context.seen.has(value)) return '[Circular]';
  if (context.depth >= context.limits.maxDepth) return '[MaxDepth]';
  context.seen.add(value);
  try {
    if (Array.isArray(value)) return sanitizeArray(value, context);
    return sanitizeObject(value, context);
  } finally {
    context.seen.delete(value);
  }
}

function sanitizeArray(value, context) {
  const result = [];
  const count = Math.min(value.length, context.limits.maxArrayLength);
  for (let index = 0; index < count; index += 1) {
    result.push(sanitizeValue(ownValue(value, String(index)), { ...context, depth: context.depth + 1 }));
  }
  return result;
}

function sanitizeObject(value, context) {
  const result = Object.create(null);
  let inspected = 0;
  try {
    for (const key in value) {
      if (inspected >= context.limits.maxObjectKeys) {
        result.truncated = true;
        break;
      }
      inspected += 1;
      if (POLLUTION_KEYS.has(key)) continue;
      const descriptor = ownDescriptor(value, key);
      if (!descriptor || descriptor.enumerable !== true) continue;
      if (context.redactPathFields && isPathLikeKey(key)) {
        result[key] = '[Redacted path]';
        continue;
      }
      result[key] = Object.prototype.hasOwnProperty.call(descriptor, 'value')
        ? sanitizeValue(descriptor.value, { ...context, depth: context.depth + 1 })
        : '[Getter]';
    }
  } catch (_) {
    result.truncated = true;
  }
  return result;
}

function enforceSerializedRawCap(raw) {
  try {
    const serialized = JSON.stringify(raw);
    if (typeof serialized === 'string' && serialized.length <= RAW_PAYLOAD_MAX_CHARS) return raw;
    const retained = Object.create(null);
    retained.truncated = true;
    const rawType = safeStringValue(ownValue(raw, 'type'));
    if (rawType) retained.type = boundedRedactedProviderString(rawType);
    return retained;
  } catch (_) {
    return { truncated: true };
  }
}

function isPathLikeKey(key) {
  const normalized = String(key || '').toLowerCase();
  return normalized === 'cwd' ||
    normalized === 'directory' ||
    normalized.endsWith('directory') ||
    normalized === 'path' ||
    normalized.endsWith('path') ||
    normalized.endsWith('_path');
}

function workspaceBoundPath(filePath, workspacePath) {
  const rawPath = String(filePath || '').trim();
  if (!rawPath) return '';
  const fileUrlPath = normalizeFileUrlPath(rawPath);
  if (fileUrlPath === '') return '[Redacted path]';
  const displayPath = fileUrlPath || rawPath;
  const flavor = pathFlavor(displayPath, workspacePath);
  const pathApi = flavor === 'win32' ? path.win32 : path.posix;
  if (!workspacePath || !String(workspacePath).trim()) return safeRelativeDisplayPath(displayPath, pathApi);
  const workspaceRoot = pathApi.resolve(String(workspacePath));
  const candidate = pathApi.isAbsolute(displayPath)
    ? pathApi.normalize(displayPath)
    : pathApi.resolve(workspaceRoot, displayPath);
  const comparableRoot = caseComparablePath(workspaceRoot, flavor);
  const comparableCandidate = caseComparablePath(candidate, flavor);
  if (
    comparableCandidate === comparableRoot ||
    comparableCandidate.startsWith(`${comparableRoot}${pathApi.sep}`)
  ) {
    const relative = pathApi.relative(workspaceRoot, candidate);
    return safeRelativeDisplayPath(relative || pathApi.basename(candidate), pathApi);
  }
  return boundedDisplayPath(pathApi.basename(candidate) || pathApi.basename(displayPath));
}

function normalizeFileUrlPath(value) {
  const text = String(value || '').trim();
  if (!/^file:\/\//i.test(text)) return null;
  try {
    const url = new URL(text);
    if (url.protocol.toLowerCase() !== 'file:') return null;
    const pathname = decodeFileUrlPathname(url.pathname || '');
    if (url.hostname) return `\\\\${url.hostname}${pathname.replace(/\//g, '\\')}`;
    if (/^\/[a-zA-Z]:[\\/]/.test(pathname)) return pathname.slice(1).replace(/\//g, '\\');
    return pathname || '';
  } catch (_) {
    return '';
  }
}

function decodeFileUrlPathname(value) {
  try {
    return decodeURIComponent(value);
  } catch (_) {
    return value;
  }
}

function safeRelativeDisplayPath(filePath, pathApi = path) {
  const rawPath = String(filePath || '').trim();
  if (!rawPath) return '';
  if (pathApi.isAbsolute(rawPath)) return boundedDisplayPath(pathApi.basename(rawPath));
  const normalized = normalizePathSeparators(pathApi.normalize(rawPath)).replace(/^\.\//, '');
  const parts = normalized.split('/').filter(Boolean);
  if (parts.includes('..')) return boundedDisplayPath(pathApi.basename(normalized));
  return boundedDisplayPath(normalized || pathApi.basename(rawPath));
}

function boundedDisplayPath(value) {
  return limitString(String(value || ''), RAW_LIMITS.maxStringLength);
}

function caseComparablePath(filePath, flavor) {
  return flavor === 'win32' ? filePath.toLowerCase() : filePath;
}

function pathFlavor(...paths) {
  return paths.some((value) => {
    const text = String(value || '');
    return /^[a-zA-Z]:[\\/]/.test(text) || /^\\\\/.test(text) || text.includes('\\');
  })
    ? 'win32'
    : 'posix';
}

function normalizePathSeparators(filePath) {
  return String(filePath || '').replace(/\\/g, '/');
}

function firstSafeString(object, keys) {
  return firstSafeStringValue(keys.map((key) => ownValue(object, key)));
}

function firstSafeStringValue(values) {
  for (const value of values) {
    const text = safeStringValue(value);
    if (text) return text;
  }
  return '';
}

function firstBoundedProviderStringValue(values) {
  for (const value of values) {
    const text = safeStringValue(value);
    if (text) return boundedProviderString(text);
  }
  return '';
}

function safeOwnObject(object, key) {
  const value = ownValue(object, key);
  return safeObject(value) ? value : null;
}

function ownValue(object, key) {
  if (!safeObject(object) && !Array.isArray(object)) return undefined;
  const descriptor = ownDescriptor(object, key);
  if (!descriptor || !Object.prototype.hasOwnProperty.call(descriptor, 'value')) return undefined;
  return descriptor.value;
}

function ownDescriptor(object, key) {
  if (!safeObject(object) && !Array.isArray(object)) return undefined;
  try {
    return Object.getOwnPropertyDescriptor(object, key);
  } catch (_) {
    return undefined;
  }
}

function limitString(value, maxLength) {
  if (value.length <= maxLength) return value;
  const marker = '...[truncated]';
  return `${value.slice(0, Math.max(0, maxLength - marker.length))}${marker}`;
}

function boundedProviderString(value) {
  return redactBoundedString(value, PROVIDER_FIELD_MAX_CHARS);
}

function boundedRedactedProviderString(value) {
  return boundedProviderString(value);
}

function redactBoundedString(value, maxLength = RAW_LIMITS.maxStringLength) {
  const bounded = limitString(safeStringValue(value), maxLength);
  if (!bounded) return '';
  return limitString(redactAbsolutePaths(bounded), maxLength);
}

function redactAbsolutePaths(value) {
  if (typeof value !== 'string' || !value) return value;
  return redactPosixAbsolutePaths(redactWindowsAbsolutePaths(redactFileUrls(value)));
}

function redactFileUrls(value) {
  let result = '';
  let index = 0;
  while (index < value.length) {
    const fileUrlStart = findFileUrlStart(value, index);
    if (fileUrlStart === -1) {
      result += value.slice(index);
      break;
    }
    result += value.slice(index, fileUrlStart);
    result += '[Redacted path]';
    index = findFileUrlEnd(value, fileUrlStart);
  }
  return result;
}

function findFileUrlStart(value, startIndex) {
  const lower = value.toLowerCase();
  for (let index = startIndex; index < value.length; index += 1) {
    if (!lower.startsWith('file://', index)) continue;
    if (index > 0 && !isPathBoundary(value[index - 1])) continue;
    return index;
  }
  return -1;
}

function findFileUrlEnd(value, fileUrlStart) {
  const prefixEnd = fileUrlStart + 'file://'.length;
  let pathStart = prefixEnd;
  while (pathStart < value.length && value[pathStart] === '/') pathStart += 1;
  if (isWindowsDrivePathStart(value, pathStart)) return findWindowsPathEnd(value, pathStart);
  if (isWindowsDrivePathStart(value, prefixEnd)) return findWindowsPathEnd(value, prefixEnd);
  if (value[prefixEnd] === '/') return findPosixPathEnd(value, prefixEnd);
  let index = prefixEnd;
  while (index < value.length && !isWindowsPathTerminator(value[index])) {
    if (/\s/.test(value[index])) {
      const nextIndex = nextNonWhitespaceIndex(value, index);
      if (
        nextIndex >= value.length ||
        isWindowsPathTerminator(value[nextIndex]) ||
        value[nextIndex] === '-'
      ) {
        return index;
      }
    }
    index += 1;
  }
  return index;
}

function redactWindowsAbsolutePaths(value) {
  let result = '';
  let index = 0;
  while (index < value.length) {
    const pathStart = findWindowsPathStart(value, index);
    if (pathStart === -1) {
      result += value.slice(index);
      break;
    }
    result += value.slice(index, pathStart);
    result += '[Redacted path]';
    index = findWindowsPathEnd(value, pathStart);
  }
  return result;
}

function findWindowsPathStart(value, startIndex) {
  for (let index = startIndex; index < value.length; index += 1) {
    if (!isWindowsDrivePathStart(value, index) && !isUncPathStart(value, index)) continue;
    if (index > 0 && !isPathBoundary(value[index - 1])) continue;
    return index;
  }
  return -1;
}

function findWindowsPathEnd(value, pathStart) {
  let index = pathStart;
  let segmentStart = pathStart;
  let ambiguousFinalSegmentTokens = 0;
  const preserveExtensionlessArgs = previousCommandAcceptsPathArguments(value, pathStart);
  while (index < value.length && !isWindowsPathTerminator(value[index])) {
    if (isPathSeparator(value[index])) {
      segmentStart = index + 1;
      ambiguousFinalSegmentTokens = 0;
      index += 1;
      continue;
    }
    if (/\s/.test(value[index])) {
      const segment = value.slice(segmentStart, index);
      const nextIndex = nextNonWhitespaceIndex(value, index);
      if (
        nextIndex >= value.length ||
        isWindowsPathTerminator(value[nextIndex]) ||
        value[nextIndex] === '-'
      ) {
        return index;
      }
      const nextTokenEnd = tokenEndIndex(value, nextIndex);
      if (tokenLooksLikeWindowsPathContinuation(value, nextIndex, nextTokenEnd)) {
        index += 1;
        continue;
      }
      if (tokenLooksLikeUrl(value, nextIndex, nextTokenEnd)) return index;
      if (value[nextIndex] === '/') return index;
      if (hasFileExtensionSegment(segment)) return index;
      if (
        preserveExtensionlessArgs &&
        nextTokenLooksLikeExtensionlessArgument(value, nextIndex)
      ) {
        return index;
      }
      if (tokenHasFileExtension(value, nextIndex, nextTokenEnd)) {
        if (ambiguousFinalSegmentTokens > 0) return index;
        ambiguousFinalSegmentTokens += 1;
        index += 1;
        continue;
      }
      ambiguousFinalSegmentTokens += 1;
    }
    index += 1;
  }
  return index;
}

function isWindowsDrivePathStart(value, index) {
  return index <= value.length - 3 &&
    isAsciiLetter(value.charCodeAt(index)) &&
    value[index + 1] === ':' &&
    isPathSeparator(value[index + 2]);
}

function isUncPathStart(value, index) {
  return index <= value.length - 5 &&
    value[index - 1] !== ':' &&
    isPathSeparator(value[index]) &&
    isPathSeparator(value[index + 1]) &&
    !isPathSeparator(value[index + 2]);
}

function redactPosixAbsolutePaths(value) {
  let result = '';
  let index = 0;
  while (index < value.length) {
    const pathStart = findPosixPathStart(value, index);
    if (pathStart === -1) {
      result += value.slice(index);
      break;
    }
    result += value.slice(index, pathStart);
    result += '[Redacted path]';
    index = findPosixPathEnd(value, pathStart);
  }
  return result;
}

function findPosixPathStart(value, startIndex) {
  for (let index = startIndex; index < value.length; index += 1) {
    if (value[index] !== '/') continue;
    if (value[index + 1] === '/') continue;
    if (index > 0 && (value[index - 1] === ':' || !isPathBoundary(value[index - 1]))) continue;
    const end = tokenEndIndex(value, index);
    if (!isPosixAbsolutePathLike(value.slice(index, end))) continue;
    return index;
  }
  return -1;
}

function findPosixPathEnd(value, pathStart) {
  let index = pathStart;
  let segmentStart = pathStart + 1;
  let ambiguousFinalSegmentTokens = 0;
  while (index < value.length && !isWindowsPathTerminator(value[index])) {
    if (value[index] === '/') {
      segmentStart = index + 1;
      ambiguousFinalSegmentTokens = 0;
      index += 1;
      continue;
    }
    if (/\s/.test(value[index])) {
      const segment = value.slice(segmentStart, index);
      const nextIndex = nextNonWhitespaceIndex(value, index);
      if (
        nextIndex >= value.length ||
        isWindowsPathTerminator(value[nextIndex]) ||
        value[nextIndex] === '-'
      ) {
        return index;
      }
      const nextTokenEnd = tokenEndIndex(value, nextIndex);
      if (tokenLooksLikeUrl(value, nextIndex, nextTokenEnd)) return index;
      if (tokenContainsPathSeparator(value, nextIndex, nextTokenEnd)) {
        index += 1;
        continue;
      }
      if (hasFileExtensionSegment(segment)) return index;
      if (tokenHasFileExtension(value, nextIndex, nextTokenEnd)) {
        if (ambiguousFinalSegmentTokens > 0) return index;
        ambiguousFinalSegmentTokens += 1;
        index += 1;
        continue;
      }
      ambiguousFinalSegmentTokens += 1;
    }
    index += 1;
  }
  return index;
}

function isPosixAbsolutePathLike(value) {
  if (!value || value === '/' || value[0] !== '/') return false;
  if (value.indexOf('/', 1) !== -1) return true;
  const segment = value.slice(1);
  if (hasFileExtensionSegment(segment)) return true;
  return [
    'bin',
    'dev',
    'etc',
    'home',
    'mnt',
    'opt',
    'private',
    'proc',
    'root',
    'sbin',
    'sys',
    'tmp',
    'usr',
    'var',
    'workspace'
  ].includes(segment.toLowerCase());
}

function tokenHasFileExtension(value, start, end) {
  return hasFileExtensionSegment(value.slice(start, end));
}

function tokenLooksLikeUrl(value, start, end) {
  return value.slice(start, end).includes('://');
}

function nextTokenLooksLikeExtensionlessArgument(value, index) {
  const end = tokenEndIndex(value, index);
  const token = value.slice(index, end);
  return !!token && !tokenContainsPathSeparator(value, index, end);
}

function previousCommandAcceptsPathArguments(value, pathStart) {
  const tokens = commandTokensBeforePath(value, pathStart);
  if (tokens.length === 0 || !interpreterCommandNames().includes(normalizeCommandName(tokens[0]))) return false;
  return interpreterPrefixAllowsPathArgument(tokens.slice(1));
}

function interpreterCommandNames() {
  return [
    'bun',
    'deno',
    'node',
    'perl',
    'php',
    'pwsh',
    'powershell',
    'py',
    'python',
    'python2',
    'python3',
    'ruby',
    'sh'
  ];
}

function normalizeCommandName(token) {
  return path.win32.basename(token.toLowerCase()).replace(/\.(?:exe|cmd|bat|ps1)$/i, '');
}

function interpreterPrefixAllowsPathArgument(tokens) {
  let skipNextOptionValue = false;
  for (const rawToken of tokens) {
    const token = rawToken.toLowerCase();
    if (!token) continue;
    if (skipNextOptionValue) {
      skipNextOptionValue = false;
      continue;
    }
    if (!token.startsWith('-')) return false;
    const optionName = token.replace(/^--?/, '').split(/[=:]/)[0];
    if (['c', 'command', 'm', 'module'].includes(optionName) && !/[=:]/.test(token)) {
      skipNextOptionValue = true;
    }
  }
  return true;
}

function commandTokensBeforePath(value, pathStart) {
  const start = commandSegmentStart(value, pathStart);
  const tokens = [];
  let token = '';
  let quote = '';
  for (let index = start; index < pathStart; index += 1) {
    const char = value[index];
    if (quote) {
      if (char === quote) {
        quote = '';
      } else {
        token += char;
      }
      continue;
    }
    if (char === '"' || char === "'" || char === '`') {
      quote = char;
      continue;
    }
    if (/\s/.test(char) || isWindowsPathTerminator(char)) {
      if (token) {
        tokens.push(token);
        token = '';
      }
      continue;
    }
    token += char;
  }
  if (token) tokens.push(token);
  return tokens;
}

function commandSegmentStart(value, index) {
  let start = index;
  while (start > 0 && !isWindowsPathTerminator(value[start - 1])) start -= 1;
  return start;
}

function tokenLooksLikeWindowsPathContinuation(value, start, end) {
  if (isWindowsDrivePathStart(value, start) || isUncPathStart(value, start)) return true;
  for (let current = start; current < end && current < value.length; current += 1) {
    if (value[current] === '\\') return true;
  }
  return false;
}

function tokenEndIndex(value, index) {
  let current = index;
  while (current < value.length && !/\s/.test(value[current]) && !isWindowsPathTerminator(value[current])) {
    current += 1;
  }
  return current;
}

function tokenContainsPathSeparator(value, start, end) {
  for (let current = start; current < end && current < value.length; current += 1) {
    if (isPathSeparator(value[current])) return true;
  }
  return false;
}

function nextNonWhitespaceIndex(value, index) {
  let next = index;
  while (next < value.length && /\s/.test(value[next])) next += 1;
  return next;
}

function isAsciiLetter(charCode) {
  return (charCode >= 65 && charCode <= 90) || (charCode >= 97 && charCode <= 122);
}

function isPathSeparator(value) {
  return value === '\\' || value === '/';
}

function isPathBoundary(value) {
  return /\s/.test(value) || ['"', "'", '`', '(', '=', ':', '{', '[', '_', '.'].includes(value);
}

function hasFileExtensionSegment(segment) {
  return /\.[A-Za-z0-9]{1,16}$/.test(segment);
}

function isWindowsPathTerminator(value) {
  return ['"', "'", '`', '<', '>', '|', '&', '\r', '\n', ')', ']', '}', ',', ';'].includes(value);
}

function safeObject(value) {
  return !!value && typeof value === 'object' && !Array.isArray(value);
}

function safeStringValue(value) {
  return typeof value === 'string' ? value : '';
}

module.exports = { mapOpenCodeEvent };
