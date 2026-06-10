'use strict';

const { canonicalizeForHash } = require('./canonical-json');

const protocolVersion = 1;
const maxClientFrameBytes = 64 * 1024;

const notificationTopics = Object.freeze({
  CONVERSATION_EVENTS: 'conversation.events'
});

const notificationErrorCodes = Object.freeze({
  AUTH_REQUIRED: 'AUTH_REQUIRED',
  TOKEN_EXPIRED: 'TOKEN_EXPIRED',
  FORBIDDEN: 'FORBIDDEN',
  UNKNOWN_TOPIC: 'UNKNOWN_TOPIC',
  INVALID_MESSAGE: 'INVALID_MESSAGE',
  REPLAY_TRUNCATED: 'REPLAY_TRUNCATED',
  BACKPRESSURE: 'BACKPRESSURE',
  INTERNAL_ERROR: 'INTERNAL_ERROR'
});

function parseClientFrame(raw) {
  const text = clientFrameText(raw);
  if (Buffer.byteLength(text, 'utf8') > maxClientFrameBytes) {
    throw protocolError(notificationErrorCodes.INVALID_MESSAGE, 'WebSocket frame is too large.');
  }
  let message;
  try {
    message = JSON.parse(text);
  } catch {
    throw protocolError(notificationErrorCodes.INVALID_MESSAGE, 'WebSocket frame must be valid JSON.');
  }
  if (!message || typeof message !== 'object' || Array.isArray(message) || typeof message.type !== 'string') {
    throw protocolError(notificationErrorCodes.INVALID_MESSAGE, 'WebSocket frame must contain a type.');
  }
  if (message.type === 'subscribe') return parseSubscribe(message);
  if (message.type === 'unsubscribe') return parseScopedRequest(message, 'unsubscribe');
  if (message.type === 'ack') return parseAck(message);
  if (message.type === 'ping') return { type: 'ping', id: stringOrNull(message.id) };
  throw protocolError(notificationErrorCodes.INVALID_MESSAGE, `Unsupported WebSocket frame type: ${message.type}`);
}

function clientFrameText(raw) {
  if (typeof raw === 'string') return raw;
  if (Buffer.isBuffer(raw)) return raw.toString('utf8');
  if (raw instanceof ArrayBuffer) return Buffer.from(raw).toString('utf8');
  if (ArrayBuffer.isView(raw)) return Buffer.from(raw.buffer, raw.byteOffset, raw.byteLength).toString('utf8');
  return String(raw);
}

function parseSubscribe(message) {
  const frame = parseScopedRequest(message, 'subscribe');
  const afterSeq = parseOptionalSequence(message.afterSeq, 'afterSeq');
  return { ...frame, afterSeq };
}

function parseScopedRequest(message, expectedType) {
  if (message.type !== expectedType) {
    throw protocolError(notificationErrorCodes.INVALID_MESSAGE, `Expected ${expectedType} frame.`);
  }
  if (typeof message.topic !== 'string' || message.topic.length === 0) {
    throw protocolError(notificationErrorCodes.INVALID_MESSAGE, 'topic is required.');
  }
  const scope = normalizeScope(message.scope);
  validateTopicScope(message.topic, scope);
  return {
    type: expectedType,
    id: stringOrNull(message.id),
    topic: message.topic,
    scope
  };
}

function parseAck(message) {
  const frame = parseScopedRequest(message, 'ack');
  const seq = parseRequiredSequence(message.seq, 'ack seq');
  return { ...frame, seq };
}

function parseOptionalSequence(value, fieldName) {
  if (value === undefined) return 0;
  return parseRequiredSequence(value, fieldName);
}

function parseRequiredSequence(value, fieldName) {
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 0) {
    throw protocolError(notificationErrorCodes.INVALID_MESSAGE, `${fieldName} must be a non-negative integer.`);
  }
  return value;
}

function normalizeScope(scope) {
  if (!scope || typeof scope !== 'object' || Array.isArray(scope)) return {};
  return Object.fromEntries(Object.keys(scope).sort().map((key) => [key, scope[key]]));
}

function validateTopicScope(topic, scope) {
  if (topic === notificationTopics.CONVERSATION_EVENTS) {
    const keys = Object.keys(scope);
    if (
      keys.length !== 1 ||
      keys[0] !== 'conversationId' ||
      typeof scope.conversationId !== 'string' ||
      scope.conversationId.length === 0
    ) {
      throw protocolError(notificationErrorCodes.INVALID_MESSAGE, 'conversation.events requires scope.conversationId.');
    }
    return;
  }
  throw protocolError(notificationErrorCodes.UNKNOWN_TOPIC, `Unknown notification topic: ${topic}`);
}

function canonicalScope(scope) {
  return canonicalizeForHash(normalizeScope(scope));
}

function subscriptionKey(topic, scope) {
  return `${topic}|${canonicalScope(scope)}`;
}

function createHelloFrame({
  connectionId,
  heartbeatIntervalMs,
  authExpiresAt = null,
  daemonVersion,
  topics,
  maxReplayEvents
}) {
  return {
    type: 'hello',
    connectionId,
    protocolVersion,
    heartbeatIntervalMs,
    authExpiresAt,
    daemonVersion,
    capabilities: { topics, maxReplayEvents }
  };
}

function createSubscribedFrame({ id, topic, scope, afterSeq }) {
  return { type: 'subscribed', id: stringOrNull(id), topic, scope: normalizeScope(scope), afterSeq };
}

function createEventFrame({ topic, scope, event }) {
  return { type: 'event', topic, scope: normalizeScope(scope), seq: event.seq, payload: event };
}

function createErrorFrame({ id = null, topic = null, scope = null, code, message }) {
  return {
    type: 'error',
    ...(id ? { id } : {}),
    ...(topic ? { topic } : {}),
    ...(scope ? { scope: normalizeScope(scope) } : {}),
    code,
    message
  };
}

function protocolError(code, message) {
  const error = new Error(message);
  error.code = code;
  return error;
}

function stringOrNull(value) {
  return typeof value === 'string' && value.length > 0 ? value : null;
}

module.exports = {
  protocolVersion,
  notificationTopics,
  notificationErrorCodes,
  parseClientFrame,
  canonicalScope,
  subscriptionKey,
  createHelloFrame,
  createSubscribedFrame,
  createEventFrame,
  createErrorFrame,
  protocolError
};
