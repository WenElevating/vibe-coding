'use strict';

const http = require('node:http');
const https = require('node:https');

const DEFAULT_SERVER_URL = 'http://127.0.0.1:4096';
const DEFAULT_TIMEOUT_MS = 5000;
const MAX_BODY_TEXT_LENGTH = 2048;
const MAX_JSON_RESPONSE_TEXT_LENGTH = 256 * 1024;
const MAX_SSE_EVENT_TEXT_LENGTH = 256 * 1024;
const MAX_DETAIL_STRING_LENGTH = 512;
const MAX_PROVIDER_CODE_LENGTH = 128;
const MAX_DETAIL_KEYS = 20;
const MAX_DETAIL_ARRAY_ITEMS = 20;
const MAX_DETAIL_DEPTH = 4;

class OpenCodeServerClient {
  constructor({ serverUrl = process.env.OPENCODE_SERVER_URL || DEFAULT_SERVER_URL, timeoutMs = DEFAULT_TIMEOUT_MS } = {}) {
    this.serverUrl = String(serverUrl || DEFAULT_SERVER_URL);
    this.timeoutMs = Math.max(1, Number(timeoutMs) || DEFAULT_TIMEOUT_MS);
    this.eventStream = null;
  }

  health(options = {}) {
    return this._requestJson('GET', '/global/health', options);
  }

  async createSession({ directory } = {}) {
    const requestedDirectory = requiredString(directory, 'directory');
    return this._requestJson('POST', `/session?directory=${encodeURIComponent(requestedDirectory)}`, {
      route: '/session'
    });
  }

  async readSession({ sessionId } = {}) {
    const requestedSessionId = requiredString(sessionId, 'sessionId');
    return this._requestJson('GET', `/session/${encodeURIComponent(requestedSessionId)}`, {
      route: '/session/:sessionId'
    });
  }

  async promptAsync({ sessionId, text } = {}) {
    const requestedSessionId = requiredString(sessionId, 'sessionId');
    return this._requestJson('POST', `/session/${encodeURIComponent(requestedSessionId)}/prompt_async`, {
      route: '/session/:sessionId/prompt_async',
      body: buildPromptAsyncBody(text)
    });
  }

  async abortSession({ sessionId } = {}) {
    const requestedSessionId = requiredString(sessionId, 'sessionId');
    return this._requestJson('POST', `/session/${encodeURIComponent(requestedSessionId)}/abort`, {
      route: '/session/:sessionId/abort'
    });
  }

  async replyPermission({ sessionId, permissionId, decision, scope } = {}) {
    const requestedSessionId = requiredString(sessionId, 'sessionId');
    const requestedPermissionId = requiredString(permissionId, 'permissionId');
    return this._requestJson(
      'POST',
      `/session/${encodeURIComponent(requestedSessionId)}/permissions/${encodeURIComponent(requestedPermissionId)}`,
      {
        route: '/session/:sessionId/permissions/:permissionId',
        body: buildPermissionReplyBody({ decision, scope })
      }
    );
  }

  subscribeEvents(onEvent, onError) {
    const stream = this._ensureEventStream();
    const subscriber = {
      eventHandler: typeof onEvent === 'function' ? onEvent : () => {},
      errorHandler: typeof onError === 'function' ? onError : () => {},
      closed: false
    };
    stream.subscribers.add(subscriber);
    return {
      opened: stream.opened,
      close() {
        if (subscriber.closed) return;
        subscriber.closed = true;
        stream.subscribers.delete(subscriber);
        if (stream.subscribers.size === 0) stream.close();
      }
    };
  }

  _ensureEventStream() {
    if (!this.eventStream || this.eventStream.closed) {
      this.eventStream = this._openEventStream();
    }
    return this.eventStream;
  }

  _openEventStream() {
    const url = this._buildUrl('/global/event');
    const transport = transportForUrl(url);
    let response = null;
    let req = null;
    let connectionTimer = null;
    let openedSettled = false;
    let resolveOpened = null;
    const opened = new Promise((resolve) => {
      resolveOpened = resolve;
    });
    const settleOpened = (result) => {
      if (openedSettled) return;
      openedSettled = true;
      resolveOpened(result);
    };
    const stream = {
      subscribers: new Set(),
      closed: false,
      opened,
      close: () => {
        closeStream();
      }
    };
    const closeStream = ({ error = null } = {}) => {
      if (stream.closed) return false;
      stream.closed = true;
      if (this.eventStream === stream) this.eventStream = null;
      if (connectionTimer) clearTimeout(connectionTimer);
      connectionTimer = null;
      settleOpened(error ? { ok: false, error } : { ok: false, closed: true });
      const subscribers = Array.from(stream.subscribers);
      stream.subscribers.clear();
      for (const subscriber of subscribers) {
        if (subscriber.closed) continue;
        subscriber.closed = true;
        if (error) notifySubscriberError(subscriber, error);
      }
      response?.destroy();
      req?.destroy();
      return true;
    };
    const notifySubscriberError = (subscriber, error) => {
      try {
        subscriber.errorHandler(error);
      } catch (_) {
        // Subscriber callbacks are app-owned; transport cleanup must stay isolated.
      }
    };
    const closeSubscriberWithError = (subscriber, error) => {
      if (subscriber.closed) return;
      subscriber.closed = true;
      stream.subscribers.delete(subscriber);
      notifySubscriberError(subscriber, error);
      if (stream.subscribers.size === 0) closeStream();
    };
    const reportError = (error) => closeStream({ error });
    const dispatchEvent = (event) => {
      if (stream.closed) return;
      for (const subscriber of Array.from(stream.subscribers)) {
        if (subscriber.closed) continue;
        try {
          subscriber.eventHandler(event);
        } catch (error) {
          closeSubscriberWithError(subscriber, buildSseSubscriberHandlerError(error));
        }
      }
    };
    const parser = createSseParser(dispatchEvent, reportError);
    connectionTimer = setTimeout(() => {
      reportError(buildTimeoutError('GET', '/global/event', this.timeoutMs));
    }, this.timeoutMs);

    req = transport.request({
      protocol: url.protocol,
      hostname: url.hostname,
      port: url.port || defaultPortForProtocol(url.protocol),
      path: `${url.pathname}${url.search}`,
      method: 'GET',
      headers: { accept: 'text/event-stream' }
    }, (res) => {
      clearTimeout(connectionTimer);
      connectionTimer = null;
      response = res;
      if (res.statusCode < 200 || res.statusCode >= 300) {
        collectBoundedResponseText(res, { timeoutMs: this.timeoutMs, maxBytes: MAX_BODY_TEXT_LENGTH }).then((text) => {
          reportError(buildHttpError('GET', '/global/event', res.statusCode, text));
        }).catch((error) => {
          reportError(buildNetworkError('GET', '/global/event', error));
        });
        return;
      }
      if (!isEventStreamContentType(res.headers?.['content-type'])) {
        collectBoundedResponseText(res, { timeoutMs: this.timeoutMs, maxBytes: MAX_BODY_TEXT_LENGTH }).then(() => {
          reportError(buildSseBadContentTypeError());
        }).catch((error) => {
          reportError(buildNetworkError('GET', '/global/event', error));
        });
        return;
      }
      settleOpened({ ok: true });
      res.setEncoding('utf8');
      const reportStreamClosed = (reason) => {
        reportError(buildSseClosedError(reason));
      };
      res.on('data', (chunk) => {
        if (!stream.closed) parser.write(String(chunk));
      });
      res.on('error', (error) => {
        reportError(buildNetworkError('GET', '/global/event', error));
      });
      res.on('end', () => reportStreamClosed('end'));
      res.on('close', () => reportStreamClosed('close'));
    });

    req.on('error', (error) => {
      reportError(buildNetworkError('GET', '/global/event', error));
    });
    req.end();
    return stream;
  }

  _requestJson(method, path, options = {}) {
    const url = this._buildUrl(path);
    const transport = transportForUrl(url);
    const body = options.body === undefined ? null : JSON.stringify(options.body);
    const signal = options.signal;
    const requestPath = `${url.pathname}${url.search}`;
    const publicPath = publicPathForUrl(url, options.route);
    const headers = { accept: 'application/json' };
    if (body !== null) {
      headers['content-type'] = 'application/json';
      headers['content-length'] = Buffer.byteLength(body);
    }

    return new Promise((resolve, reject) => {
      let settled = false;
      let req = null;
      let response = null;
      let timer = null;
      let abortHandler = null;
      const cleanup = () => {
        if (timer) {
          clearTimeout(timer);
          timer = null;
        }
        if (abortHandler && signal && typeof signal.removeEventListener === 'function') {
          signal.removeEventListener('abort', abortHandler);
        }
        abortHandler = null;
      };
      const finish = (error, value) => {
        if (settled) return;
        settled = true;
        cleanup();
        if (error) reject(error);
        else resolve(value);
      };
      if (signal?.aborted) {
        finish(buildAbortError(method, publicPath));
        return;
      }
      abortHandler = () => {
        const error = buildAbortError(method, publicPath);
        finish(error);
        response?.destroy(error);
        req?.destroy(error);
      };
      if (signal && typeof signal.addEventListener === 'function') {
        signal.addEventListener('abort', abortHandler, { once: true });
      }
      req = transport.request({
        protocol: url.protocol,
        hostname: url.hostname,
        port: url.port || defaultPortForProtocol(url.protocol),
        path: requestPath,
        method,
        headers
      }, (res) => {
        response = res;
        collectBoundedResponseText(res, {
          timeoutMs: this.timeoutMs,
          maxBytes: MAX_JSON_RESPONSE_TEXT_LENGTH
        }).then((text) => {
          if (res.statusCode < 200 || res.statusCode >= 300) {
            finish(buildHttpError(method, publicPath, res.statusCode, text));
            return;
          }
          if (!text) {
            finish(null, null);
            return;
          }
          const parsed = parseJson(text);
          if (!parsed.ok) {
            finish(buildBadJsonError(method, publicPath, text, parsed.error));
            return;
          }
          finish(null, parsed.value);
        }).catch((error) => {
          finish(buildNetworkError(method, publicPath, error));
        });
      });
      timer = setTimeout(() => {
        finish(buildTimeoutError(method, publicPath, this.timeoutMs));
        req.destroy();
      }, this.timeoutMs);
      req.on('error', (error) => {
        finish(buildNetworkError(method, publicPath, error));
      });
      if (body !== null) req.write(body);
      req.end();
    });
  }

  _buildUrl(path) {
    return new URL(path, this.serverUrl);
  }
}

function buildPromptAsyncBody(text) {
  return { parts: [{ type: 'text', text: String(text ?? '') }] };
}

function buildPermissionReplyBody({ decision, scope } = {}) {
  const normalizedDecision = String(decision || '').trim();
  if (!['allow', 'deny', 'cancel'].includes(normalizedDecision)) {
    throw openCodeError('OpenCode server permission reply requires decision to be allow, deny, or cancel', {
      code: 'OPENCODE_SERVER_INVALID_REQUEST',
      details: { field: 'decision', reason: 'unsupported' }
    });
  }
  if (normalizedDecision === 'allow') {
    const normalizedScope = String(scope || 'once').trim() || 'once';
    if (!['once', 'session'].includes(normalizedScope)) {
      throw openCodeError('OpenCode server permission reply scope must be once or session', {
        code: 'OPENCODE_SERVER_INVALID_REQUEST',
        details: { field: 'scope', reason: 'unsupported' }
      });
    }
    return { response: normalizedScope === 'session' ? 'always' : 'once' };
  }
  return { response: 'reject' };
}

function requiredString(value, field) {
  const text = String(value ?? '');
  if (text.trim()) return text;
  throw openCodeError(`OpenCode server request requires ${field}`, {
    code: 'OPENCODE_SERVER_INVALID_REQUEST',
    details: { field, reason: 'required' }
  });
}

function createSseParser(onEvent, onError) {
  let buffer = '';
  return {
    write(chunk) {
      buffer += chunk;
      buffer = buffer.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
      let frameEnd = buffer.indexOf('\n\n');
      while (frameEnd !== -1) {
        const frame = buffer.slice(0, frameEnd);
        buffer = buffer.slice(frameEnd + 2);
        if (dispatchSseFrame(frame, onEvent, onError) === false) {
          buffer = '';
          return;
        }
        frameEnd = buffer.indexOf('\n\n');
      }
      if (buffer.length > MAX_SSE_EVENT_TEXT_LENGTH) {
        const chars = buffer.length;
        buffer = '';
        onError(buildSseEventTooLargeError(chars));
        return;
      }
    }
  };
}

function dispatchSseFrame(frame, onEvent, onError) {
  if (!frame.trim()) return true;
  const dataLines = [];
  let dataLength = 0;
  for (const line of frame.split('\n')) {
    if (!line || line.startsWith(':')) continue;
    if (!line.startsWith('data:')) continue;
    const value = line.slice(5);
    const normalizedValue = value.startsWith(' ') ? value.slice(1) : value;
    dataLength += normalizedValue.length + (dataLines.length > 0 ? 1 : 0);
    if (dataLength > MAX_SSE_EVENT_TEXT_LENGTH) {
      onError(buildSseEventTooLargeError(dataLength));
      return false;
    }
    dataLines.push(normalizedValue);
  }
  if (dataLines.length === 0) return true;
  const data = dataLines.join('\n');
  if (!data.trim()) return true;
  const parsed = parseJson(data);
  if (!parsed.ok) {
    onError(buildSseBadJsonError(data, parsed.error));
    return false;
  }
  onEvent(parsed.value);
  return true;
}

function collectBoundedResponseText(res, { timeoutMs, maxBytes }) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let bytes = 0;
    let settled = false;
    const finish = (error, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      res.off('data', onData);
      res.off('end', onEnd);
      res.off('error', onError);
      if (error) reject(error);
      else resolve(value);
    };
    const currentText = () => Buffer.concat(chunks).toString('utf8');
    const onData = (chunk) => {
      const buffer = Buffer.from(chunk);
      const remaining = maxBytes - bytes;
      if (remaining > 0) chunks.push(buffer.length > remaining ? buffer.subarray(0, remaining) : buffer);
      bytes += buffer.length;
      if (bytes >= maxBytes) {
        finish(null, currentText());
        res.destroy();
      }
    };
    const onEnd = () => finish(null, currentText());
    const onError = (error) => finish(error);
    const timer = setTimeout(() => {
      finish(null, currentText());
      res.destroy();
    }, Math.max(1, Number(timeoutMs) || DEFAULT_TIMEOUT_MS));

    res.on('data', onData);
    res.on('end', onEnd);
    res.on('error', onError);
  });
}

function parseJson(text) {
  try {
    return { ok: true, value: JSON.parse(text) };
  } catch (error) {
    return { ok: false, error };
  }
}

function buildHttpError(method, path, status, text) {
  const provider = parseResponseBodyDetails(text);
  return openCodeError(`OpenCode server ${method} ${path} failed with HTTP ${status}`, {
    status,
    code: 'OPENCODE_SERVER_HTTP_ERROR',
    details: { status, method, path, ...provider }
  });
}

function buildBadJsonError(method, path, _text, _parseError) {
  return openCodeError(`OpenCode server ${method} ${path} returned invalid JSON`, {
    code: 'OPENCODE_SERVER_BAD_JSON',
    details: {
      method,
      path,
      reason: 'invalid_json'
    }
  });
}

function buildSseBadJsonError(_data, _parseError) {
  return openCodeError('OpenCode server SSE event contained invalid JSON', {
    code: 'OPENCODE_SERVER_SSE_BAD_JSON',
    details: {
      method: 'GET',
      path: '/global/event',
      reason: 'invalid_json'
    }
  });
}

function buildSseBadContentTypeError() {
  return openCodeError('OpenCode server SSE endpoint did not return an event stream', {
    code: 'OPENCODE_SERVER_SSE_BAD_CONTENT_TYPE',
    details: {
      method: 'GET',
      path: '/global/event',
      reason: 'invalid_content_type'
    }
  });
}

function buildSseEventTooLargeError(chars) {
  return openCodeError('OpenCode server SSE event exceeded the size limit', {
    code: 'OPENCODE_SERVER_SSE_EVENT_TOO_LARGE',
    details: {
      method: 'GET',
      path: '/global/event',
      reason: 'event_too_large',
      chars,
      maxChars: MAX_SSE_EVENT_TEXT_LENGTH
    }
  });
}

function buildSseClosedError(reason) {
  return openCodeError('OpenCode server SSE stream closed', {
    code: 'OPENCODE_SERVER_SSE_CLOSED',
    details: {
      method: 'GET',
      path: '/global/event',
      reason: limitString(reason || 'closed', MAX_DETAIL_STRING_LENGTH)
    }
  });
}

function buildSseSubscriberHandlerError(error) {
  return openCodeError('OpenCode server SSE subscriber handler failed', {
    code: 'OPENCODE_SERVER_SSE_SUBSCRIBER_FAILED',
    details: {
      method: 'GET',
      path: '/global/event',
      reason: 'subscriber_handler_failed',
      handlerCode: firstSafeProviderCode([
        safeErrorField(error, 'code'),
        safeErrorField(error, 'name')
      ]) || 'HANDLER_ERROR'
    }
  });
}

function buildTimeoutError(method, path, timeoutMs) {
  return openCodeError(`OpenCode server ${method} ${path} timed out after ${timeoutMs}ms`, {
    code: 'OPENCODE_SERVER_TIMEOUT',
    details: { method, path, timeoutMs }
  });
}

function buildAbortError(method, path) {
  return openCodeError(`OpenCode server ${method} ${path} request was aborted`, {
    code: 'OPENCODE_SERVER_ABORTED',
    details: { method, path }
  });
}

function buildNetworkError(method, path, error) {
  return openCodeError(`OpenCode server ${method} ${path} network error`, {
    code: 'OPENCODE_SERVER_NETWORK_ERROR',
    details: {
      method,
      path,
      code: firstSafeProviderCode([
        safeErrorField(error, 'code'),
        safeErrorField(error, 'name')
      ]) || 'NETWORK_ERROR',
      reason: 'request_failed'
    }
  });
}

function parseResponseBodyDetails(text) {
  if (!text) return {};
  const parsed = parseJson(text);
  if (!parsed.ok || !parsed.value || typeof parsed.value !== 'object') return {};
  const result = {};
  const providerCode = firstSafeProviderCode([
    parsed.value.error?.code,
    parsed.value.code,
    parsed.value.errorCode
  ]);
  const providerStatus = firstSafeProviderCode([
    parsed.value.error?.status,
    parsed.value.status
  ]);
  if (providerCode) result.providerCode = providerCode;
  if (providerStatus) result.providerStatus = providerStatus;
  return result;
}

function firstSafeProviderCode(values) {
  for (const value of values) {
    const code = safeProviderCode(value);
    if (code) return code;
  }
  return null;
}

function safeProviderCode(value) {
  if (typeof value === 'number' && Number.isSafeInteger(value)) return String(value);
  if (typeof value !== 'string') return null;
  const text = value.trim();
  if (!text || text.length > MAX_PROVIDER_CODE_LENGTH) return null;
  if (!/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(text)) return null;
  return text;
}

function isEventStreamContentType(value) {
  const text = String(value || '').split(';')[0].trim().toLowerCase();
  return text === 'text/event-stream';
}

function publicPathForUrl(url, route) {
  const label = String(route || url.pathname || '/').split('?')[0] || '/';
  return limitString(label, MAX_DETAIL_STRING_LENGTH);
}

function openCodeError(message, { status, code, details }) {
  const error = new Error(message);
  if (status !== undefined) error.status = status;
  error.code = code;
  error.details = sanitizeDetails(details);
  return error;
}

function sanitizeDetails(value, depth = 0, seen = new Set()) {
  if (value === null || value === undefined) return value;
  if (typeof value === 'string') return limitString(value, MAX_DETAIL_STRING_LENGTH);
  if (typeof value === 'number' || typeof value === 'boolean') return value;
  if (typeof value === 'bigint') return limitString(String(value), MAX_DETAIL_STRING_LENGTH);
  if (typeof value !== 'object') return limitString(String(value), MAX_DETAIL_STRING_LENGTH);
  if (depth >= MAX_DETAIL_DEPTH) return '[Truncated]';
  if (seen.has(value)) return '[Circular]';
  seen.add(value);
  if (Array.isArray(value)) {
    const items = [];
    for (let index = 0; index < Math.min(value.length, MAX_DETAIL_ARRAY_ITEMS); index += 1) {
      items.push(sanitizeDetails(safeOwnDataValue(value, String(index)), depth + 1, seen));
    }
    if (value.length > MAX_DETAIL_ARRAY_ITEMS) items.push('[Truncated]');
    seen.delete(value);
    return items;
  }
  const result = {};
  const keys = safeEnumerableKeys(value);
  for (const key of keys.slice(0, MAX_DETAIL_KEYS)) {
    if (key === '__proto__' || key === 'constructor' || key === 'prototype') continue;
    const fieldValue = safeOwnDataValue(value, key);
    if (fieldValue !== undefined) result[key] = sanitizeDetails(fieldValue, depth + 1, seen);
  }
  if (keys.length > MAX_DETAIL_KEYS) result.truncated = true;
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

function safeOwnDataValue(value, key) {
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
    const value = safeOwnDataValue(current, key);
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

function limitString(value, maxLength) {
  const text = String(value || '');
  if (text.length <= maxLength) return text;
  const suffix = '...[truncated]';
  return `${text.slice(0, Math.max(0, maxLength - suffix.length))}${suffix}`;
}

function transportForUrl(url) {
  if (url.protocol === 'https:') return https;
  if (url.protocol === 'http:') return http;
  throw new Error(`unsupported OpenCode server protocol: ${url.protocol}`);
}

function defaultPortForProtocol(protocol) {
  return protocol === 'https:' ? 443 : 80;
}

module.exports = {
  OpenCodeServerClient,
  buildPromptAsyncBody
};
