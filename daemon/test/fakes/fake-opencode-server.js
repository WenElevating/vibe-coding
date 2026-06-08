'use strict';

const http = require('node:http');
const { EventEmitter } = require('node:events');

class FakeOpenCodeServer extends EventEmitter {
  constructor() {
    super();
    this.sessions = new Map();
    this.events = [];
    this.permissionReplies = [];
    this.permissionReplyFailures = new Map();
    this.promptFailures = new Map();
    this.promptBodies = [];
    this.createRequests = [];
    this.readSessionIds = [];
    this.abortSessionIds = [];
    this.server = http.createServer((req, res) => this.handle(req, res));
    this.sseClients = new Set();
    this.sseOpenCount = 0;
    this.sseCloseCount = 0;
    this.nextSessionNumber = 1;
  }

  get url() {
    const address = this.server.address();
    return `http://127.0.0.1:${address.port}`;
  }

  listen() {
    return new Promise((resolve) => this.server.listen(0, '127.0.0.1', resolve));
  }

  close() {
    for (const res of this.sseClients) res.end();
    this.sseClients.clear();
    return new Promise((resolve) => this.server.close(resolve));
  }

  emitEvent(event) {
    this.events.push(event);
    const payload = `data: ${JSON.stringify(event)}\n\n`;
    for (const res of this.sseClients) res.write(payload);
  }

  failPermissionReply(permissionId, { status = 500, body = null } = {}) {
    this.permissionReplyFailures.set(String(permissionId), {
      status,
      body: body || { error: { code: 'PERMISSION_REPLY_FAILED' } }
    });
  }

  failPrompt(sessionId, { status = 500, body = null, waitForSseClient = false } = {}) {
    this.promptFailures.set(String(sessionId), {
      status,
      body: body || { error: { code: 'PROMPT_FAILED' } },
      waitForSseClient: waitForSseClient === true
    });
  }

  async handle(req, res) {
    const url = new URL(req.url, 'http://127.0.0.1');
    if (req.method === 'GET' && url.pathname === '/global/health') {
      return sendJson(res, 200, { ok: true, version: 'fake-opencode' });
    }
    if (req.method === 'GET' && url.pathname === '/doc') {
      return sendJson(res, 200, { openapi: '3.0.0', paths: { '/global/event': {} } });
    }
    if (req.method === 'GET' && url.pathname === '/global/event') {
      res.writeHead(200, {
        'content-type': 'text/event-stream',
        'cache-control': 'no-cache',
        connection: 'keep-alive'
      });
      res.flushHeaders?.();
      this.sseClients.add(res);
      this.sseOpenCount += 1;
      this.emit('sseClient');
      req.on('close', () => {
        if (this.sseClients.delete(res)) this.sseCloseCount += 1;
      });
      return;
    }
    if (req.method === 'POST' && url.pathname === '/session') {
      await readBody(req);
      const id = `sess_${this.nextSessionNumber++}`;
      const directory = url.searchParams.get('directory') || process.cwd();
      const session = { id, sessionID: id, directory };
      this.createRequests.push({ directory });
      this.sessions.set(id, session);
      return sendJson(res, 200, session);
    }
    const readMatch = url.pathname.match(/^\/session\/([^/]+)$/);
    if (req.method === 'GET' && readMatch) {
      const sessionId = decodeURIComponent(readMatch[1]);
      this.readSessionIds.push(sessionId);
      if (!this.sessions.has(sessionId)) return sendJson(res, 404, { error: { code: 'SESSION_NOT_FOUND' } });
      return sendJson(res, 200, this.sessions.get(sessionId));
    }
    const promptMatch = url.pathname.match(/^\/session\/([^/]+)\/prompt_async$/);
    if (req.method === 'POST' && promptMatch) {
      const sessionId = decodeURIComponent(promptMatch[1]);
      if (!this.sessions.has(sessionId)) return sendJson(res, 404, { error: { code: 'SESSION_NOT_FOUND' } });
      const body = await readJson(req);
      this.promptBodies.push({ sessionId, body });
      const failure = this.promptFailures.get(sessionId);
      if (failure) {
        if (failure.waitForSseClient) await this.waitForSseClient();
        return sendJson(res, failure.status, failure.body);
      }
      return sendJson(res, 200, { ok: true });
    }
    const abortMatch = url.pathname.match(/^\/session\/([^/]+)\/abort$/);
    if (req.method === 'POST' && abortMatch) {
      const sessionId = decodeURIComponent(abortMatch[1]);
      this.abortSessionIds.push(sessionId);
      await readBody(req);
      return sendJson(res, 200, true);
    }
    const permissionMatch = url.pathname.match(/^\/session\/([^/]+)\/permissions\/([^/]+)$/);
    if (req.method === 'POST' && permissionMatch) {
      const permissionId = decodeURIComponent(permissionMatch[2]);
      const body = await readJson(req);
      this.permissionReplies.push({
        sessionId: decodeURIComponent(permissionMatch[1]),
        permissionId,
        body
      });
      const failure = this.permissionReplyFailures.get(permissionId);
      if (failure) return sendJson(res, failure.status, failure.body);
      return sendJson(res, 200, { ok: true });
    }
    return sendJson(res, 404, { error: { code: 'NOT_FOUND' } });
  }

  waitForSseClient(timeoutMs = 500) {
    if (this.sseClients.size > 0) return Promise.resolve();
    return new Promise((resolve) => {
      const timer = setTimeout(resolve, timeoutMs);
      this.once('sseClient', () => {
        clearTimeout(timer);
        resolve();
      });
    });
  }
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', (chunk) => chunks.push(chunk));
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

async function readJson(req) {
  const text = await readBody(req);
  return text ? JSON.parse(text) : {};
}

function sendJson(res, status, body) {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    'content-type': 'application/json',
    'content-length': Buffer.byteLength(payload)
  });
  res.end(payload);
}

module.exports = { FakeOpenCodeServer };
