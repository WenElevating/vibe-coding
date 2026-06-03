'use strict';

const { EventEmitter } = require('node:events');
const readline = require('node:readline');

class CodexAppServerJsonlTransport extends EventEmitter {
  constructor({ stdin, stdout, stderr = null, requestTimeoutMs = 30000, idPrefix = 'codex-app' } = {}) {
    super();
    if (!stdin || typeof stdin.write !== 'function') throw new Error('stdin stream is required');
    if (!stdout || typeof stdout.on !== 'function') throw new Error('stdout stream is required');
    this.stdin = stdin;
    this.stdout = stdout;
    this.stderr = stderr;
    this.requestTimeoutMs = requestTimeoutMs;
    this.idPrefix = idPrefix;
    this.nextId = 1;
    this.pending = new Map();
    this.closed = false;
    this.rl = readline.createInterface({ input: stdout });
    this.rl.on('line', (line) => this._handleLine(line));
    this.rl.on('close', () => this._close(new Error('Codex app-server transport closed')));
    stdout.on('close', () => this._close(new Error('Codex app-server transport closed')));
    stdout.on('error', (error) => this._close(error));
    if (stderr && typeof stderr.on === 'function') {
      stderr.on('data', (chunk) => this.emit('stderr', String(chunk)));
    }
  }

  sendRequest(method, params, options = {}) {
    if (this.closed) return Promise.reject(new Error('Codex app-server transport closed'));
    if (typeof method !== 'string' || !method.trim()) {
      return Promise.reject(new Error('JSON-RPC method is required'));
    }
    const id = options.id == null ? `${this.idPrefix}-${this.nextId++}` : options.id;
    const message = { id, method };
    if (params !== undefined) message.params = params;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`${method} timed out after ${options.timeoutMs || this.requestTimeoutMs}ms`));
      }, options.timeoutMs || this.requestTimeoutMs);
      this.pending.set(id, { method, resolve, reject, timer });
      try {
        this._write(message);
      } catch (error) {
        clearTimeout(timer);
        this.pending.delete(id);
        reject(error);
      }
    });
  }

  sendNotification(method, params) {
    if (this.closed) throw new Error('Codex app-server transport closed');
    const message = { method };
    if (params !== undefined) message.params = params;
    this._write(message);
  }

  sendResult(id, result) {
    if (this.closed) throw new Error('Codex app-server transport closed');
    this._write({ id, result });
  }

  sendError(id, error) {
    if (this.closed) throw new Error('Codex app-server transport closed');
    const payload = error && typeof error === 'object'
      ? error
      : { code: -32603, message: String(error || 'Codex app-server request failed') };
    this._write({ id, error: payload });
  }

  close() {
    this._close(new Error('Codex app-server transport closed'));
    if (this.rl) this.rl.close();
  }

  _write(message) {
    this.stdin.write(`${JSON.stringify(message)}\n`);
    this.emit('sent', message);
  }

  _handleLine(line) {
    const trimmed = String(line || '').trim();
    if (!trimmed) return;
    let message;
    try {
      message = JSON.parse(trimmed);
    } catch (error) {
      this.emit('protocolError', { error, line: trimmed });
      return;
    }
    this.emit('message', message);
    if (message && message.method && message.id !== undefined) {
      this.emit('serverRequest', message);
      return;
    }
    if (message && message.method) {
      this.emit('notification', message);
      return;
    }
    if (message && message.id !== undefined) {
      this._handleResponse(message);
    }
  }

  _handleResponse(message) {
    const pending = this.pending.get(message.id);
    if (!pending) {
      this.emit('protocolWarning', { message: 'response without pending request', response: message });
      return;
    }
    this.pending.delete(message.id);
    clearTimeout(pending.timer);
    if (message.error) {
      const error = new Error(message.error.message || `${pending.method} failed`);
      error.code = message.error.code;
      error.data = message.error.data;
      pending.reject(error);
      return;
    }
    pending.resolve(message.result);
  }

  _close(error) {
    if (this.closed) return;
    this.closed = true;
    for (const pending of this.pending.values()) {
      clearTimeout(pending.timer);
      pending.reject(error);
    }
    this.pending.clear();
    this.emit('closed', error);
  }
}

module.exports = {
  CodexAppServerJsonlTransport
};
