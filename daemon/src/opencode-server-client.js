'use strict';

const http = require('node:http');
const https = require('node:https');

const DEFAULT_SERVER_URL = 'http://127.0.0.1:4096';
const DEFAULT_TIMEOUT_MS = 5000;
const MAX_BODY_TEXT_LENGTH = 2048;
const MAX_DETAIL_STRING_LENGTH = 512;
const MAX_DETAIL_KEYS = 20;
const MAX_DETAIL_ARRAY_ITEMS = 20;
const MAX_DETAIL_DEPTH = 4;

class OpenCodeServerClient {
  constructor({ serverUrl = process.env.OPENCODE_SERVER_URL || DEFAULT_SERVER_URL, timeoutMs = DEFAULT_TIMEOUT_MS } = {}) {
    this.serverUrl = String(serverUrl || DEFAULT_SERVER_URL);
    this.timeoutMs = Math.max(1, Number(timeoutMs) || DEFAULT_TIMEOUT_MS);
  }

  health(options = {}) {
    return this._requestJson('GET', '/global/health', options);
  }

  async createSession({ directory } = {}) {
    const requestedDirectory = requiredString(directory, 'directory');
    return this._requestJson('POST', `/session?directory=${encodeURIComponent(requestedDirectory)}`);
  }

  async readSession({ sessionId } = {}) {
    const requestedSessionId = requiredString(sessionId, 'sessionId');
    return this._requestJson('GET', `/session/${encodeURIComponent(requestedSessionId)}`);
  }

  async promptAsync({ sessionId, text } = {}) {
    const requestedSessionId = requiredString(sessionId, 'sessionId');
    return this._requestJson('POST', `/session/${encodeURIComponent(requestedSessionId)}/prompt_async`, {
      body: buildPromptAsyncBody(text)
    });
  }

  async abortSession({ sessionId } = {}) {
    const requestedSessionId = requiredString(sessionId, 'sessionId');
    return this._requestJson('POST', `/session/${encodeURIComponent(requestedSessionId)}/abort`);
  }

  async replyPermission({ sessionId, permissionId, decision, scope } = {}) {
    const requestedSessionId = requiredString(sessionId, 'sessionId');
    const requestedPermissionId = requiredString(permissionId, 'permissionId');
    return this._requestJson(
      'POST',
      `/session/${encodeURIComponent(requestedSessionId)}/permissions/${encodeURIComponent(requestedPermissionId)}`,
      { body: buildPermissionReplyBody({ decision, scope }) }
    );
  }

  subscribeEvents(onEvent, onError) {
    const eventHandler = typeof onEvent === 'function' ? onEvent : () => {};
    const errorHandler = typeof onError === 'function' ? onError : () => {};
    const url = this._buildUrl('/global/event');
    const transport = transportForUrl(url);
    let closed = false;
    let response = null;
    let req = null;
    const parser = createSseParser(eventHandler, errorHandler);
    const reportError = (error) => {
      if (closed) return false;
      closed = true;
      clearTimeout(connectionTimer);
      errorHandler(error);
      return true;
    };
    const connectionTimer = setTimeout(() => {
      if (!reportError(buildTimeoutError('GET', '/global/event', this.timeoutMs))) return;
      response?.destroy();
      req?.destroy();
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
      response = res;
      if (res.statusCode < 200 || res.statusCode >= 300) {
        collectBoundedResponseText(res, { timeoutMs: this.timeoutMs, maxBytes: MAX_BODY_TEXT_LENGTH }).then((text) => {
          if (!reportError(buildHttpError('GET', '/global/event', res.statusCode, text))) return;
          response?.destroy();
          req.destroy();
        }).catch((error) => {
          reportError(buildNetworkError('GET', '/global/event', error));
        });
        return;
      }
      res.setEncoding('utf8');
      const reportStreamClosed = (reason) => {
        if (!reportError(buildSseClosedError(reason))) return;
        req.destroy();
      };
      res.on('data', (chunk) => {
        if (!closed) parser.write(String(chunk));
      });
      res.on('error', (error) => {
        if (!reportError(buildNetworkError('GET', '/global/event', error))) return;
        req.destroy();
      });
      res.on('end', () => reportStreamClosed('end'));
      res.on('close', () => reportStreamClosed('close'));
    });

    req.on('error', (error) => {
      reportError(buildNetworkError('GET', '/global/event', error));
    });
    req.end();

    return {
      close() {
        if (closed) return;
        closed = true;
        clearTimeout(connectionTimer);
        response?.destroy();
        req.destroy();
      }
    };
  }

  _requestJson(method, path, options = {}) {
    const url = this._buildUrl(path);
    const transport = transportForUrl(url);
    const body = options.body === undefined ? null : JSON.stringify(options.body);
    const signal = options.signal;
    const requestPath = `${url.pathname}${url.search}`;
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
        finish(buildAbortError(method, requestPath));
        return;
      }
      abortHandler = () => {
        const error = buildAbortError(method, requestPath);
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
        collectResponseText(res).then((text) => {
          if (res.statusCode < 200 || res.statusCode >= 300) {
            finish(buildHttpError(method, requestPath, res.statusCode, text));
            return;
          }
          if (!text) {
            finish(null, null);
            return;
          }
          const parsed = parseJson(text);
          if (!parsed.ok) {
            finish(buildBadJsonError(method, requestPath, text, parsed.error));
            return;
          }
          finish(null, parsed.value);
        }).catch((error) => {
          finish(buildNetworkError(method, requestPath, error));
        });
      });
      timer = setTimeout(() => {
        finish(buildTimeoutError(method, requestPath, this.timeoutMs));
        req.destroy();
      }, this.timeoutMs);
      req.on('error', (error) => {
        finish(buildNetworkError(method, requestPath, error));
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
  return { parts: [{ type: 'text', text: String(text || '') }] };
}

function buildPermissionReplyBody({ decision, scope } = {}) {
  if (decision === 'allow') {
    return { response: scope === 'session' ? 'always' : 'once' };
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
        dispatchSseFrame(frame, onEvent, onError);
        frameEnd = buffer.indexOf('\n\n');
      }
      if (buffer.length > MAX_BODY_TEXT_LENGTH * 4) {
        buffer = buffer.slice(-MAX_BODY_TEXT_LENGTH);
      }
    }
  };
}

function dispatchSseFrame(frame, onEvent, onError) {
  if (!frame.trim()) return;
  const dataLines = [];
  for (const line of frame.split('\n')) {
    if (!line || line.startsWith(':')) continue;
    if (!line.startsWith('data:')) continue;
    const value = line.slice(5);
    dataLines.push(value.startsWith(' ') ? value.slice(1) : value);
  }
  if (dataLines.length === 0) return;
  const data = dataLines.join('\n');
  if (!data.trim()) return;
  const parsed = parseJson(data);
  if (!parsed.ok) {
    onError(buildSseBadJsonError(data, parsed.error));
    return;
  }
  onEvent(parsed.value);
}

function collectResponseText(res) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    res.on('data', (chunk) => chunks.push(Buffer.from(chunk)));
    res.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    res.on('error', reject);
  });
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
  const body = parseResponseBodyDetails(text);
  return openCodeError(`OpenCode server ${method} ${path} failed with HTTP ${status}`, {
    status,
    code: 'OPENCODE_SERVER_HTTP_ERROR',
    details: { status, method, path, ...body }
  });
}

function buildBadJsonError(method, path, text, parseError) {
  return openCodeError(`OpenCode server ${method} ${path} returned invalid JSON`, {
    code: 'OPENCODE_SERVER_BAD_JSON',
    details: {
      method,
      path,
      bodyText: limitString(text, MAX_BODY_TEXT_LENGTH),
      parseMessage: limitString(parseError?.message || 'invalid JSON', MAX_DETAIL_STRING_LENGTH)
    }
  });
}

function buildSseBadJsonError(data, parseError) {
  return openCodeError('OpenCode server SSE event contained invalid JSON', {
    code: 'OPENCODE_SERVER_SSE_BAD_JSON',
    details: {
      data: limitString(data, MAX_DETAIL_STRING_LENGTH),
      parseMessage: limitString(parseError?.message || 'invalid JSON', MAX_DETAIL_STRING_LENGTH)
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
  return openCodeError(`OpenCode server ${method} ${path} network error: ${error?.message || 'request failed'}`, {
    code: 'OPENCODE_SERVER_NETWORK_ERROR',
    details: {
      method,
      path,
      code: limitString(error?.code || error?.name || 'NETWORK_ERROR', MAX_DETAIL_STRING_LENGTH),
      message: limitString(error?.message || 'request failed', MAX_DETAIL_STRING_LENGTH)
    }
  });
}

function parseResponseBodyDetails(text) {
  if (!text) return { body: null };
  const parsed = parseJson(text);
  if (parsed.ok) return { body: sanitizeDetails(parsed.value) };
  return { bodyText: limitString(text, MAX_BODY_TEXT_LENGTH) };
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
    const items = value.slice(0, MAX_DETAIL_ARRAY_ITEMS).map((item) => sanitizeDetails(item, depth + 1, seen));
    if (value.length > MAX_DETAIL_ARRAY_ITEMS) items.push('[Truncated]');
    seen.delete(value);
    return items;
  }
  const result = {};
  for (const key of Object.keys(value).slice(0, MAX_DETAIL_KEYS)) {
    if (key === '__proto__' || key === 'constructor' || key === 'prototype') continue;
    result[key] = sanitizeDetails(value[key], depth + 1, seen);
  }
  if (Object.keys(value).length > MAX_DETAIL_KEYS) result.truncated = true;
  seen.delete(value);
  return result;
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
