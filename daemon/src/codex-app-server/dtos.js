'use strict';

function normalizeThreadListResponse(payload) {
  return normalizeCollectionResponse(payload, 'threads', ['threads', 'data', 'items'], normalizeThread);
}

function normalizeThreadResponse(payload) {
  if (payload && typeof payload === 'object' && !Array.isArray(payload) && payload.thread !== undefined) {
    return {
      ...copyExtraFields(payload, new Set(['thread'])),
      thread: normalizeThread(payload.thread)
    };
  }
  return { thread: normalizeThread(payload) };
}

function normalizeTurnListResponse(payload) {
  return normalizeCollectionResponse(payload, 'turns', ['turns', 'data', 'items'], normalizeTurn);
}

function normalizeItemListResponse(payload) {
  return normalizeCollectionResponse(payload, 'items', ['items', 'data'], normalizeThreadItem);
}

function normalizeGoalResponse(payload) {
  if (payload && typeof payload === 'object' && !Array.isArray(payload) && payload.goal !== undefined) {
    return {
      ...copyExtraFields(payload, new Set(['goal'])),
      goal: normalizeGoal(payload.goal)
    };
  }
  return { goal: normalizeGoal(payload) };
}

function normalizeCollectionResponse(payload, outputKey, candidateKeys, itemNormalizer) {
  const source = payload && typeof payload === 'object' && !Array.isArray(payload) ? payload : {};
  const items = firstArray(source, candidateKeys);
  const result = {
    ...copyExtraFields(source, new Set(candidateKeys)),
    [outputKey]: items.map(itemNormalizer)
  };
  if (source.nextCursor !== undefined) result.nextCursor = source.nextCursor;
  if (source.cursor !== undefined && result.nextCursor === undefined) result.nextCursor = source.cursor;
  return result;
}

function normalizeThread(value) {
  return normalizeObject(value, ['id', 'threadId', 'title', 'workspacePath', 'archived', 'createdAt', 'updatedAt']);
}

function normalizeTurn(value) {
  return normalizeObject(value, ['id', 'turnId', 'threadId', 'status', 'createdAt', 'completedAt']);
}

function normalizeThreadItem(value) {
  return normalizeObject(value, ['id', 'itemId', 'turnId', 'threadId', 'kind', 'type', 'status', 'createdAt']);
}

function normalizeGoal(value) {
  return normalizeObject(value, ['id', 'goalId', 'threadId', 'status', 'objective', 'createdAt', 'updatedAt']);
}

function normalizeObject(value, preferredKeys) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return value;
  const result = {};
  for (const key of preferredKeys) {
    if (value[key] !== undefined) result[key] = value[key];
  }
  for (const [key, current] of Object.entries(value)) {
    if (result[key] === undefined) result[key] = current;
  }
  return result;
}

function firstArray(source, keys) {
  for (const key of keys) {
    if (Array.isArray(source[key])) return source[key];
  }
  return [];
}

function copyExtraFields(source, excludedKeys) {
  const result = {};
  for (const [key, value] of Object.entries(source || {})) {
    if (!excludedKeys.has(key) && key !== 'nextCursor' && key !== 'cursor') result[key] = value;
  }
  return result;
}

module.exports = {
  normalizeGoalResponse,
  normalizeItemListResponse,
  normalizeThreadListResponse,
  normalizeThreadResponse,
  normalizeTurnListResponse
};
