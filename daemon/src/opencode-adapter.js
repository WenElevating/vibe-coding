'use strict';

const http = require('node:http');
const { eventTypes } = require('./protocol');

class OpenCodeAdapter {
  constructor({ serverUrl = process.env.OPENCODE_SERVER_URL || 'http://127.0.0.1:4096', fetchJson = defaultFetchJson } = {}) {
    this.name = 'opencode';
    this.serverUrl = serverUrl;
    this.fetchJson = fetchJson;
    this.capability = null;
  }

  detectCapabilities() {
    return this.fetchJson(`${this.serverUrl}/doc`)
      .then(() => {
        this.capability = capability(true, 'available', null, this.serverUrl);
        return this.capability;
      })
      .catch((error) => {
        this.capability = capability(false, 'needs_configuration', `OpenCode server unreachable at ${this.serverUrl}. Start opencode serve or update OPENCODE_SERVER_URL. ${error.message || error}`, this.serverUrl);
        return this.capability;
      });
  }

  async ensureAvailable() {
    const current = this.capability || await this.detectCapabilities();
    if (!current.available) {
      const error = new Error(current.error);
      error.status = 503;
      error.code = 'ADAPTER_UNAVAILABLE';
      error.actionable = current.actionable;
      error.details = current;
      throw error;
    }
  }

  async startRun({ prompt, sessionId, resume = false, onEvent }) {
    await this.ensureAvailable();
    if (resume && !sessionId) {
      const error = new Error('OpenCode resume requires a captured server session id');
      error.status = 409;
      error.code = 'OPENCODE_SESSION_REQUIRED';
      throw error;
    }
    const activeSessionId = sessionId || await this.createSession();
    onEvent({ type: eventTypes.RAW_OUTPUT, text: '', sessionId: activeSessionId, reason: 'opencode_session_active' });
    await this.sendPrompt(activeSessionId, prompt);
    onEvent({ type: eventTypes.RUN_COMPLETED, exitCode: 0, sessionId: activeSessionId });
    return { kill: () => this.abortSession(activeSessionId).catch(() => {}) };
  }

  async createSession() {
    const response = await this.fetchJson(`${this.serverUrl}/session`, { method: 'POST', body: '{}' });
    return parseSessionId(response.body) || parseSessionId(response) || parseSessionId(response.json) || response.body?.id || response.id;
  }

  async sendPrompt(sessionId, prompt) {
    await this.fetchJson(`${this.serverUrl}/session/${encodeURIComponent(sessionId)}/prompt_async`, {
      method: 'POST',
      body: JSON.stringify({ prompt })
    });
  }

  async abortSession(sessionId) {
    await this.fetchJson(`${this.serverUrl}/session/${encodeURIComponent(sessionId)}/abort`, { method: 'POST', body: '{}' });
  }
}

function capability(available, status, error, serverUrl) {
  return { adapter: 'opencode', available, status, serverUrl, error, actionable: error };
}

function defaultFetchJson(url, options = {}) {
  return new Promise((resolve, reject) => {
    const parsed = new URL(url);
    const req = http.request({
      hostname: parsed.hostname,
      port: parsed.port,
      path: `${parsed.pathname}${parsed.search}`,
      method: options.method || 'GET',
      headers: options.body ? { 'content-type': 'application/json', 'content-length': Buffer.byteLength(options.body) } : undefined
    }, (res) => {
      const chunks = [];
      res.on('data', (chunk) => chunks.push(chunk));
      res.on('end', () => {
        const text = Buffer.concat(chunks).toString('utf8');
        const payload = { status: res.statusCode, body: text, json: parseJson(text) };
        if (res.statusCode >= 200 && res.statusCode < 500) resolve(payload);
        else reject(new Error(`HTTP ${res.statusCode}`));
      });
    });
    req.setTimeout(1500, () => req.destroy(new Error('timeout')));
    req.on('error', reject);
    if (options.body) req.write(options.body);
    req.end();
  });
}

function parseJson(text) {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

function parseSessionId(value) {
  if (!value) return null;
  if (typeof value === 'string') {
    const parsed = parseJson(value);
    return parsed ? parseSessionId(parsed) : value.trim() || null;
  }
  if (typeof value === 'object') {
    return value.id || value.sessionId || value.session_id || value.session?.id || null;
  }
  return null;
}

module.exports = { OpenCodeAdapter };
