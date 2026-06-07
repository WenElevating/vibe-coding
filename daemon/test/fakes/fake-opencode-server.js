'use strict';

const http = require('node:http');
const { EventEmitter } = require('node:events');

class FakeOpenCodeServer extends EventEmitter {
  constructor() {
    super();
    this.sessions = new Map();
    this.events = [];
    this.permissionReplies = [];
    this.promptBodies = [];
    this.server = http.createServer((req, res) => this.handle(req, res));
    this.sseClients = new Set();
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
      req.on('close', () => this.sseClients.delete(res));
      return;
    }
    if (req.method === 'POST' && url.pathname === '/session') {
      await readBody(req);
      const id = `sess_${this.nextSessionNumber++}`;
      const directory = url.searchParams.get('directory') || process.cwd();
      const session = { id, sessionID: id, directory };
      this.sessions.set(id, session);
      return sendJson(res, 200, session);
    }
    const promptMatch = url.pathname.match(/^\/session\/([^/]+)\/prompt_async$/);
    if (req.method === 'POST' && promptMatch) {
      const sessionId = decodeURIComponent(promptMatch[1]);
      if (!this.sessions.has(sessionId)) return sendJson(res, 404, { error: { code: 'SESSION_NOT_FOUND' } });
      const body = await readJson(req);
      this.promptBodies.push({ sessionId, body });
      return sendJson(res, 200, { ok: true });
    }
    const abortMatch = url.pathname.match(/^\/session\/([^/]+)\/abort$/);
    if (req.method === 'POST' && abortMatch) {
      await readBody(req);
      return sendJson(res, 200, true);
    }
    const permissionMatch = url.pathname.match(/^\/session\/([^/]+)\/permissions\/([^/]+)$/);
    if (req.method === 'POST' && permissionMatch) {
      const body = await readJson(req);
      this.permissionReplies.push({
        sessionId: decodeURIComponent(permissionMatch[1]),
        permissionId: decodeURIComponent(permissionMatch[2]),
        body
      });
      return sendJson(res, 200, { ok: true });
    }
    return sendJson(res, 404, { error: { code: 'NOT_FOUND' } });
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
