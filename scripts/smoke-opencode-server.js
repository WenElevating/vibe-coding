'use strict';

const http = require('node:http');
const https = require('node:https');
const path = require('node:path');

const DEFAULT_SERVER_URL = process.env.OPENCODE_SERVER_URL || 'http://127.0.0.1:4096';
const DEFAULT_TIMEOUT_MS = 5000;
const DEFAULT_SMOKE_PROMPT = 'Reply with the single word OK.';
const GATE_NAMES = [
  'health',
  'doc',
  'sessionCreateDirectory',
  'promptAsyncBody',
  'abort',
  'permissionResponseBody',
  'globalEventSse',
  'sessionIdFieldNames',
  'sessionReadReconcile',
  'sessionStatusTerminalValues',
  'historyReplay'
];

function parseOpenCodeSseFrames(text) {
  const frames = [];
  let dataLines = [];
  for (const rawLine of String(text || '').split(/\r?\n/)) {
    const line = rawLine.trimEnd();
    if (line === '') {
      pushFrame(frames, dataLines);
      dataLines = [];
      continue;
    }
    if (line.startsWith('data:')) dataLines.push(line.slice(5).trimStart());
  }
  pushFrame(frames, dataLines);
  return frames;
}

function pushFrame(frames, dataLines) {
  if (!dataLines.length) return;
  const text = dataLines.join('\n').trim();
  if (!text) return;
  try {
    frames.push(JSON.parse(text));
  } catch (error) {
    frames.push({ type: 'parse.error', message: error.message, raw: text.slice(0, 4096) });
  }
}

async function runOpenCodeServerSmoke({
  serverUrl = DEFAULT_SERVER_URL,
  workspace = process.cwd(),
  allowPromptDispatch = false,
  timeoutMs = DEFAULT_TIMEOUT_MS,
  prompt = DEFAULT_SMOKE_PROMPT
} = {}) {
  const normalizedServerUrl = normalizeServerUrl(serverUrl);
  const gates = Object.fromEntries(GATE_NAMES.map((name) => [name, 'not_run']));
  const evidence = {};
  let session = null;
  let sessionId = null;

  await runGate('health', gates, evidence, async () => {
    const response = await requestJson(normalizedServerUrl, 'GET', '/global/health', { timeoutMs });
    evidence.health = { statusCode: response.statusCode, bodyKeys: Object.keys(response.body || {}) };
    assertOkResponse(response, 'health');
  });

  await runGate('doc', gates, evidence, async () => {
    const response = await requestJson(normalizedServerUrl, 'GET', '/doc', { timeoutMs });
    evidence.doc = { statusCode: response.statusCode, pathCount: Object.keys(response.body?.paths || {}).length };
    assertOkResponse(response, 'doc');
  });

  await runGate('globalEventSse', gates, evidence, async () => {
    const response = await openSse(normalizedServerUrl, '/global/event', { timeoutMs });
    evidence.globalEventSse = {
      statusCode: response.statusCode,
      contentType: response.contentType
    };
    if (!String(response.contentType || '').toLowerCase().includes('text/event-stream')) {
      throw new Error('global event route did not return text/event-stream');
    }
    response.close();
  });

  await runGate('sessionCreateDirectory', gates, evidence, async () => {
    const response = await requestJson(
      normalizedServerUrl,
      'POST',
      `/session?directory=${encodeURIComponent(path.resolve(workspace))}`,
      { timeoutMs, body: {} }
    );
    assertOkResponse(response, 'session create');
    session = response.body;
    sessionId = extractSessionId(session);
    evidence.sessionCreateDirectory = {
      statusCode: response.statusCode,
      hasSessionId: !!sessionId,
      directoryMatches: path.resolve(extractSessionDirectory(session) || '') === path.resolve(workspace)
    };
    if (!sessionId) throw new Error('session create did not return an id/sessionID');
    if (!evidence.sessionCreateDirectory.directoryMatches) {
      throw new Error('session create did not preserve requested directory');
    }
  });

  await runGate('sessionIdFieldNames', gates, evidence, async () => {
    if (!session) throw new Error('session create did not run');
    const fields = Object.keys(session).filter((key) => /^(id|session_?id)$/i.test(key));
    evidence.sessionIdFieldNames = { fields };
    if (!fields.length || !sessionId) throw new Error('session id field was not found');
  });

  await runGate('sessionReadReconcile', gates, evidence, async () => {
    if (!sessionId) throw new Error('session create did not return a session id');
    const response = await requestJson(
      normalizedServerUrl,
      'GET',
      `/session/${encodeURIComponent(sessionId)}`,
      { timeoutMs }
    );
    assertOkResponse(response, 'session read');
    const readSessionId = extractSessionId(response.body);
    evidence.sessionReadReconcile = {
      statusCode: response.statusCode,
      idMatches: readSessionId === sessionId,
      directoryMatches: path.resolve(extractSessionDirectory(response.body) || '') === path.resolve(workspace)
    };
    if (readSessionId !== sessionId) throw new Error('session read returned a different session id');
    if (!evidence.sessionReadReconcile.directoryMatches) {
      throw new Error('session read returned a different directory');
    }
  });

  if (allowPromptDispatch) {
    await runGate('promptAsyncBody', gates, evidence, async () => {
      if (!sessionId) throw new Error('session create did not return a session id');
      const response = await requestJson(
        normalizedServerUrl,
        'POST',
        `/session/${encodeURIComponent(sessionId)}/prompt_async`,
        {
          timeoutMs,
          body: { parts: [{ type: 'text', text: String(prompt) }] }
        }
      );
      evidence.promptAsyncBody = { statusCode: response.statusCode };
      assertOkResponse(response, 'prompt_async');
    });
  }

  await runGate('abort', gates, evidence, async () => {
    if (!sessionId) throw new Error('session create did not return a session id');
    const response = await requestJson(
      normalizedServerUrl,
      'POST',
      `/session/${encodeURIComponent(sessionId)}/abort`,
      { timeoutMs, body: {} }
    );
    evidence.abort = { statusCode: response.statusCode };
    assertOkResponse(response, 'abort');
  });

  gates.permissionResponseBody = 'not_run';
  gates.sessionStatusTerminalValues = 'not_run';
  gates.historyReplay = 'blocked';

  return {
    schemaVersion: 1,
    adapter: 'opencode',
    status: summarizeGateStatus(gates),
    verifiedAt: new Date().toISOString(),
    serverUrl: publicServerUrl(normalizedServerUrl),
    workspace: path.resolve(workspace),
    promptDispatchEnabled: allowPromptDispatch === true,
    gates,
    evidence,
    samples: []
  };
}

function summarizeGateStatus(gates) {
  const results = Object.values(gates);
  if (results.includes('fail')) return 'fail';
  if (results.includes('not_run')) return 'not_run';
  if (results.includes('blocked')) return 'blocked';
  return 'pass';
}

async function runGate(name, gates, evidence, action) {
  try {
    await action();
    gates[name] = 'pass';
  } catch (error) {
    gates[name] = 'fail';
    evidence[name] = {
      ...(evidence[name] || {}),
      error: error.message || String(error)
    };
  }
}

function normalizeServerUrl(value) {
  const text = String(value || '').trim();
  if (!text) throw new Error('server URL is required');
  return text.endsWith('/') ? text.slice(0, -1) : text;
}

function publicServerUrl(value) {
  try {
    const url = new URL(value);
    url.username = '';
    url.password = '';
    url.search = '';
    url.hash = '';
    return url.toString().replace(/\/$/, '');
  } catch {
    return 'invalid';
  }
}

function requestJson(serverUrl, method, route, { timeoutMs, body } = {}) {
  const payload = body === undefined ? null : JSON.stringify(body);
  return requestRaw(serverUrl, method, route, {
    timeoutMs,
    body: payload,
    headers: payload === null
      ? { accept: 'application/json' }
      : {
        accept: 'application/json',
        'content-type': 'application/json',
        'content-length': Buffer.byteLength(payload)
      }
  }).then((response) => ({
    ...response,
    body: response.text ? parseJson(response.text) : null
  }));
}

function requestRaw(serverUrl, method, route, { timeoutMs, body = null, headers = {} } = {}) {
  const url = new URL(route, `${serverUrl}/`);
  const transport = url.protocol === 'https:' ? https : http;
  return new Promise((resolve, reject) => {
    let settled = false;
    const req = transport.request({
      protocol: url.protocol,
      hostname: url.hostname,
      port: url.port,
      path: `${url.pathname}${url.search}`,
      method,
      headers
    }, (res) => {
      const chunks = [];
      res.on('data', (chunk) => chunks.push(chunk));
      res.on('end', () => finish(null, {
        statusCode: res.statusCode,
        headers: res.headers,
        text: Buffer.concat(chunks).toString('utf8')
      }));
      res.on('error', finish);
    });
    const timer = setTimeout(() => {
      req.destroy(new Error(`${method} ${route} timed out after ${timeoutMs}ms`));
    }, timeoutMs);
    const finish = (error, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (error) reject(error);
      else resolve(value);
    };
    req.on('error', finish);
    if (body !== null) req.write(body);
    req.end();
  });
}

function openSse(serverUrl, route, { timeoutMs } = {}) {
  const url = new URL(route, `${serverUrl}/`);
  const transport = url.protocol === 'https:' ? https : http;
  return new Promise((resolve, reject) => {
    let settled = false;
    const req = transport.request({
      protocol: url.protocol,
      hostname: url.hostname,
      port: url.port,
      path: `${url.pathname}${url.search}`,
      method: 'GET',
      headers: { accept: 'text/event-stream' }
    }, (res) => {
      finish(null, {
        statusCode: res.statusCode,
        contentType: res.headers['content-type'] || '',
        close() {
          res.destroy();
          req.destroy();
        }
      });
    });
    const timer = setTimeout(() => {
      req.destroy(new Error(`${route} timed out after ${timeoutMs}ms`));
    }, timeoutMs);
    const finish = (error, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (error) reject(error);
      else resolve(value);
    };
    req.on('error', finish);
    req.end();
  });
}

function assertOkResponse(response, label) {
  if (response.statusCode >= 200 && response.statusCode < 300) return;
  throw new Error(`${label} returned HTTP ${response.statusCode}`);
}

function parseJson(text) {
  try {
    return JSON.parse(text);
  } catch (error) {
    throw new Error(`response was not JSON: ${error.message}`);
  }
}

function extractSessionId(value) {
  if (!value || typeof value !== 'object') return null;
  return value.id || value.sessionID || value.sessionId || value.session_id || value.session?.id || null;
}

function extractSessionDirectory(value) {
  if (!value || typeof value !== 'object') return null;
  return value.directory || value.cwd || value.path || value.session?.directory || null;
}

function parseCliArgs(argv) {
  const options = {};
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === '--allow-prompt-dispatch') {
      options.allowPromptDispatch = true;
    } else if (arg === '--server-url') {
      options.serverUrl = argv[++index];
    } else if (arg === '--workspace') {
      options.workspace = argv[++index];
    } else if (arg === '--timeout-ms') {
      options.timeoutMs = Number(argv[++index]);
    } else if (arg === '--prompt') {
      options.prompt = argv[++index];
    } else if (arg === '--help' || arg === '-h') {
      options.help = true;
    } else {
      throw new Error(`unknown argument: ${arg}`);
    }
  }
  return options;
}

function usage() {
  return [
    'Usage: node scripts/smoke-opencode-server.js [--server-url URL] [--workspace PATH] [--timeout-ms MS] [--allow-prompt-dispatch]',
    '',
    'Runs non-model-consuming OpenCode server route checks by default.',
    'Use --allow-prompt-dispatch only when a live prompt request is acceptable.'
  ].join('\n');
}

module.exports = {
  parseOpenCodeSseFrames,
  runOpenCodeServerSmoke
};

if (require.main === module) {
  (async () => {
    const options = parseCliArgs(process.argv.slice(2));
    if (options.help) {
      console.log(usage());
      return;
    }
    const result = await runOpenCodeServerSmoke(options);
    console.log(JSON.stringify(result, null, 2));
    if (result.status === 'fail') process.exitCode = 1;
  })().catch((error) => {
    console.error(error.message || String(error));
    process.exitCode = 1;
  });
}
