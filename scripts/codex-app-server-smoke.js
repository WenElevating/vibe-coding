'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const readline = require('node:readline');
const http = require('node:http');
const { spawn, spawnSync } = require('node:child_process');

const repoRoot = path.resolve(__dirname, '..');
const fixtureRoot = path.join(repoRoot, 'docs', 'superpowers', 'fixtures', 'codex-app-server');
const samplesDir = path.join(fixtureRoot, 'samples');
const codexBin = process.env.CODEX_BIN || (process.platform === 'win32' ? 'D:\\nodejs\\codex.cmd' : 'codex');
const codexJs = process.env.CODEX_JS || (process.platform === 'win32'
  ? 'D:\\nodejs\\node_modules\\@openai\\codex\\bin\\codex.js'
  : null);
const nodeBin = process.env.NODE_BIN || process.execPath;
const cwd = process.env.CODEX_SMOKE_CWD || repoRoot;
const timeoutMs = Number(process.env.CODEX_APP_SERVER_SMOKE_TIMEOUT_MS || 120000);
const dateStamp = new Date().toISOString().slice(0, 10);
const scenario = process.env.CODEX_APP_SERVER_SMOKE_SCENARIO || 'basic-turn';
const usesMockModelServer = scenario === 'command-approval' ||
  scenario === 'resume-rejoin' ||
  scenario === 'image-input' ||
  scenario === 'permissions-approval';
const isolatedProjectTrust = scenario === 'project-trust';
const usesIsolatedCodexHome = isolatedProjectTrust || usesMockModelServer;
const scenarioCodexHome = usesIsolatedCodexHome
  ? fs.mkdtempSync(path.join(os.tmpdir(), 'codex-app-server-home-'))
  : null;
const scenarioWorkspace = usesIsolatedCodexHome
  ? fs.mkdtempSync(path.join(os.tmpdir(), 'codex-app-server-workspace-'))
  : cwd;

let nextId = 1;
const messages = [];
const stderrChunks = [];
const approvals = [];
const modelRequests = [];
const pending = new Map();
let child;
let mockModelServer = null;
let mockModelServerUrl = null;
let initializedAt = null;
let completedAt = null;
let childPid = null;
let childExit = null;
let descendantsBeforeCleanup = [];
let descendantsAfterCleanup = [];

function redact(value) {
  if (typeof value === 'string') {
    let redacted = value
      .replace(/[A-Za-z]:\\\\users\\\\[^\\\s'")]+/ig, '<USER_PATH>')
      .replace(/[A-Za-z]:\\users\\[^\\\s'"]+/ig, '<USER_PATH>')
      .replaceAll(os.homedir(), '<USER_HOME>')
      .replaceAll(repoRoot, '<WORKSPACE>')
      .replaceAll(cwd, '<WORKSPACE>')
      .replaceAll(scenarioWorkspace, '<SMOKE_WORKSPACE>');
    if (scenarioCodexHome) redacted = redacted.replaceAll(scenarioCodexHome, '<SMOKE_CODEX_HOME>');
    return redacted;
  }
  if (Array.isArray(value)) {
    return value.map(redact);
  }
  if (value && typeof value === 'object') {
    const out = {};
    for (const [key, item] of Object.entries(value)) {
      if (/token|secret|cookie|authorization|apiKey/i.test(key)) {
        out[key] = '<REDACTED_SECRET>';
      } else if (key === 'env' || key === 'environment') {
        out[key] = '<REDACTED_ENV>';
      } else {
        out[key] = redact(item);
      }
    }
    return out;
  }
  return value;
}

function record(direction, message) {
  messages.push({
    at: new Date().toISOString(),
    direction,
    message: redact(message),
  });
}

function send(message) {
  record('client_to_server', message);
  child.stdin.write(`${JSON.stringify(message)}\n`);
}

function request(method, params, timeout = timeoutMs) {
  const id = nextId++;
  const message = { method, id };
  if (params !== undefined) message.params = params;
  send(message);
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      pending.delete(id);
      reject(new Error(`${method} timed out after ${timeout}ms`));
    }, timeout);
    pending.set(id, {
      method,
      resolve: (value) => {
        clearTimeout(timer);
        resolve(value);
      },
      reject: (error) => {
        clearTimeout(timer);
        reject(error);
      },
    });
  });
}

function notification(method, params) {
  const message = { method };
  if (params !== undefined) message.params = params;
  send(message);
}

function handleServerRequest(message) {
  const method = message.method || 'unknown';
  if (method === 'item/commandExecution/requestApproval') {
    const decision = process.env.CODEX_APP_SERVER_SMOKE_APPROVAL_DECISION || 'accept';
    const requestedAt = new Date();
    const approval = redact({
      method,
      id: message.id,
      decision,
      params: message.params,
      requestedAt: requestedAt.toISOString(),
      respondedAt: null,
      responseLatencyMs: null,
      resolvedAt: null,
      resolvedLatencyMs: null,
    });
    approvals.push(approval);
    const response = {
      id: message.id,
      result: { decision },
    };
    const respondedAt = new Date();
    approval.respondedAt = respondedAt.toISOString();
    approval.responseLatencyMs = respondedAt.getTime() - requestedAt.getTime();
    record('client_to_server_request_response', response);
    child.stdin.write(`${JSON.stringify(response)}\n`);
    return;
  }
  if (method === 'item/fileChange/requestApproval') {
    const decision = process.env.CODEX_APP_SERVER_SMOKE_FILE_DECISION || 'decline';
    approvals.push(redact({
      method,
      id: message.id,
      decision,
      params: message.params,
    }));
    const response = {
      id: message.id,
      result: { decision },
    };
    record('client_to_server_request_response', response);
    child.stdin.write(`${JSON.stringify(response)}\n`);
    return;
  }
  if (method === 'item/permissions/requestApproval') {
    approvals.push(redact({
      method,
      id: message.id,
      decision: 'deny',
      params: message.params,
    }));
    const response = {
      id: message.id,
      result: {
        permissions: {},
        scope: 'turn',
      },
    };
    record('client_to_server_request_response', response);
    child.stdin.write(`${JSON.stringify(response)}\n`);
    return;
  }
  const failClosed = {
    id: message.id,
    error: {
      code: -32601,
      message: `Smoke runner does not support server request ${method}`,
    },
  };
  record('client_fail_closed_server_request', failClosed);
  child.stdin.write(`${JSON.stringify(failClosed)}\n`);
}

function handleMessage(message) {
  record('server_to_client', message);
  if (message.method === 'serverRequest/resolved' && message.params) {
    const requestId = message.params.requestId ?? message.params.request_id;
    const approval = approvals.find((item) => item.id === requestId);
    if (approval && !approval.resolvedAt) {
      const resolvedAt = new Date();
      approval.resolvedAt = resolvedAt.toISOString();
      approval.resolvedLatencyMs = approval.requestedAt
        ? resolvedAt.getTime() - new Date(approval.requestedAt).getTime()
        : null;
    }
  }
  if (message.method && message.id !== undefined) {
    handleServerRequest(message);
    return;
  }
  if (message.id !== undefined) {
    const entry = pending.get(message.id);
    if (!entry) return;
    pending.delete(message.id);
    if (message.error) {
      entry.reject(new Error(`${entry.method} failed: ${message.error.message || JSON.stringify(message.error)}`));
    } else {
      entry.resolve(message.result);
    }
    return;
  }
}

function waitForNotification(method, predicate = () => true, timeout = timeoutMs) {
  const start = Date.now();
  return new Promise((resolve, reject) => {
    const interval = setInterval(() => {
      const found = messages.find((entry) => {
        const message = entry.message;
        return entry.direction === 'server_to_client' && message.method === method && predicate(message);
      });
      if (found) {
        clearInterval(interval);
        resolve(found.message);
      } else if (Date.now() - start > timeout) {
        clearInterval(interval);
        reject(new Error(`Notification ${method} timed out after ${timeout}ms`));
      }
    }, 100);
  });
}

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function sse(events) {
  return events.map((event) => {
    const type = event.type;
    if (Object.keys(event).length === 1) return `event: ${type}\n\n`;
    return `event: ${type}\ndata: ${JSON.stringify(event)}\n\n`;
  }).join('');
}

function evResponseCreated(id) {
  return {
    type: 'response.created',
    response: { id },
  };
}

function evCompleted(id) {
  return {
    type: 'response.completed',
    response: {
      id,
      usage: {
        input_tokens: 0,
        input_tokens_details: null,
        output_tokens: 0,
        output_tokens_details: null,
        total_tokens: 0,
      },
    },
  };
}

function evFunctionCall(callId, name, argumentsJson) {
  return {
    type: 'response.output_item.done',
    item: {
      type: 'function_call',
      call_id: callId,
      name,
      arguments: argumentsJson,
    },
  };
}

function evAssistantMessage(id, text) {
  return {
    type: 'response.output_item.done',
    item: {
      type: 'message',
      role: 'assistant',
      id,
      content: [{ type: 'output_text', text }],
    },
  };
}

function shellCommandForApproval(index) {
  if (process.platform === 'win32') {
    return `cmd.exe /d /c echo app-server-approval-smoke-${index + 1}`;
  }
  return `echo app-server-approval-smoke-${index + 1}`;
}

function shellCommandSse(index) {
  const responseId = `resp-approval-shell-${index + 1}`;
  const args = JSON.stringify({
    command: shellCommandForApproval(index),
    workdir: scenarioWorkspace,
    timeout_ms: 5000,
  });
  return sse([
    evResponseCreated(responseId),
    evFunctionCall(`call-approval-${index + 1}`, 'shell_command', args),
    evCompleted(responseId),
  ]);
}

function requestPermissionsSse(index) {
  const responseId = `resp-permissions-${index + 1}`;
  const args = JSON.stringify({
    reason: 'Select a workspace root',
    permissions: {
      file_system: {
        write: ['.', '../shared'],
      },
    },
  });
  return sse([
    evResponseCreated(responseId),
    evFunctionCall(`call-permissions-${index + 1}`, 'request_permissions', args),
    evCompleted(responseId),
  ]);
}

function finalAssistantSse(index) {
  const responseId = `resp-approval-final-${index + 1}`;
  return sse([
    evResponseCreated(responseId),
    evAssistantMessage(`msg-approval-${index + 1}`, `approval turn ${index + 1} done`),
    evCompleted(responseId),
  ]);
}

function directAssistantSse(index) {
  const responseId = `resp-direct-${scenario}-${index + 1}`;
  return sse([
    evResponseCreated(responseId),
    evAssistantMessage(`msg-direct-${scenario}-${index + 1}`, `${scenario} turn ${index + 1} done`),
    evCompleted(responseId),
  ]);
}

function requestIncludesFunctionOutput(body) {
  const input = Array.isArray(body?.input) ? body.input : [];
  const last = input[input.length - 1];
  return Boolean(last && last.type === 'function_call_output');
}

function summarizeModelInput(input) {
  if (!Array.isArray(input)) return null;
  return input.map((item) => {
    if (!item || typeof item !== 'object') return { type: null };
    const summary = { type: item.type || null };
    if (Array.isArray(item.content)) {
      summary.contentTypes = item.content.map((content) => content?.type || null);
    }
    return summary;
  });
}

function startMockModelServer() {
  let turnIndex = 0;
  const server = http.createServer((req, res) => {
    if (req.method !== 'POST' || !/\/v1\/responses$/.test(req.url || '')) {
      res.writeHead(404, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ error: 'not found' }));
      return;
    }
    const chunks = [];
    req.on('data', (chunk) => chunks.push(chunk));
    req.on('end', () => {
      let body = null;
      try {
        body = JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}');
      } catch (error) {
        body = { parseError: error.message };
      }
      modelRequests.push(redact({
        at: new Date().toISOString(),
        url: req.url,
        includesFunctionOutput: requestIncludesFunctionOutput(body),
        inputItemTypes: Array.isArray(body?.input) ? body.input.map((item) => item?.type || null) : null,
        inputSummary: summarizeModelInput(body?.input),
      }));
      const isFollowup = requestIncludesFunctionOutput(body);
      const currentIndex = isFollowup ? Math.max(0, turnIndex - 1) : turnIndex++;
      let bodyText = directAssistantSse(currentIndex);
      if (scenario === 'command-approval') {
        bodyText = isFollowup ? finalAssistantSse(currentIndex) : shellCommandSse(currentIndex);
      } else if (scenario === 'permissions-approval') {
        bodyText = isFollowup ? directAssistantSse(currentIndex) : requestPermissionsSse(currentIndex);
      }
      res.writeHead(200, {
        'content-type': 'text/event-stream',
        'cache-control': 'no-cache',
        connection: 'close',
      });
      res.end(bodyText);
    });
  });
  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const address = server.address();
      mockModelServer = server;
      mockModelServerUrl = `http://127.0.0.1:${address.port}`;
      resolve(mockModelServerUrl);
    });
  });
}

function stopMockModelServer() {
  if (!mockModelServer) return Promise.resolve();
  return new Promise((resolve) => {
    mockModelServer.close(() => resolve());
  });
}

function writeMockModelConfig(serverUrl) {
  if (!scenarioCodexHome) throw new Error('mock model config requires isolated CODEX_HOME');
  fs.mkdirSync(scenarioCodexHome, { recursive: true });
  const approvalPolicy = scenario === 'permissions-approval' ? 'untrusted' : 'on-request';
  const configToml = [
    'model = "mock-model"',
    `approval_policy = "${approvalPolicy}"`,
    'sandbox_mode = "read-only"',
    'model_provider = "mock_provider"',
    '',
    '[model_providers.mock_provider]',
    'name = "Mock provider for app-server smoke"',
    `base_url = "${serverUrl}/v1"`,
    'wire_api = "responses"',
    'request_max_retries = 0',
    'stream_max_retries = 0',
    '',
    ...(scenario === 'permissions-approval' ? [
      '[features]',
      'request_permissions_tool = true',
      '',
    ] : []),
  ].join('\n');
  fs.writeFileSync(path.join(scenarioCodexHome, 'config.toml'), configToml, 'utf8');
}

function listDescendantProcesses(rootPid) {
  if (!rootPid) return [];
  if (process.platform !== 'win32') return [];
  const script = [
    '$ErrorActionPreference = "Stop"',
    '$items = Get-CimInstance Win32_Process | Select-Object ProcessId,ParentProcessId,Name,CommandLine',
    '$items | ConvertTo-Json -Compress'
  ].join('; ');
  const result = spawnSync('powershell', ['-NoProfile', '-Command', script], {
    encoding: 'utf8',
    windowsHide: true,
    timeout: 10000,
  });
  if (result.status !== 0 || !result.stdout.trim()) {
    return [];
  }
  let processes;
  try {
    processes = JSON.parse(result.stdout);
  } catch {
    return [];
  }
  const all = Array.isArray(processes) ? processes : [processes];
  const byParent = new Map();
  for (const processInfo of all) {
    const parent = Number(processInfo.ParentProcessId);
    if (!byParent.has(parent)) byParent.set(parent, []);
    byParent.get(parent).push(processInfo);
  }
  const descendants = [];
  const queue = [...(byParent.get(Number(rootPid)) || [])];
  while (queue.length > 0) {
    const current = queue.shift();
    descendants.push({
      pid: Number(current.ProcessId),
      parentPid: Number(current.ParentProcessId),
      name: current.Name || null,
      commandLine: current.CommandLine || null,
    });
    queue.push(...(byParent.get(Number(current.ProcessId)) || []));
  }
  return redact(descendants);
}

function pidExists(pid) {
  if (!pid) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function terminateProcessTree(pid, { force = false } = {}) {
  if (!pid || process.platform !== 'win32') return false;
  const args = ['/PID', String(pid), '/T'];
  if (force) args.push('/F');
  const result = spawnSync('taskkill', args, {
    windowsHide: true,
    stdio: 'ignore',
  });
  return result.status === 0;
}

function terminateCapturedDescendants(processes) {
  if (process.platform !== 'win32' || !Array.isArray(processes)) return;
  for (const processInfo of [...processes].reverse()) {
    terminateProcessTree(processInfo.pid, { force: true });
  }
}

function stopChild(timeout = 5000) {
  if (!child || childExit) return Promise.resolve(childExit);
  return new Promise((resolve) => {
    const timer = setTimeout(() => {
      if (child && !child.killed) {
        if (!terminateProcessTree(childPid, { force: true })) {
          child.kill('SIGKILL');
        }
      }
      resolve(childExit || { code: null, signal: 'timeout-kill' });
    }, timeout);
    child.once('exit', (code, signal) => {
      clearTimeout(timer);
      childExit = { code, signal };
      resolve(childExit);
    });
    if (!terminateProcessTree(childPid, { force: false })) {
      child.kill();
    }
  });
}

function turnPromptForScenario(name, index = 0) {
  if (name === 'command-approval') {
    return 'Run this exact shell command, then reply with exactly app-server approval ok: echo app-server-approval-smoke';
  }
  if (name === 'permissions-approval') {
    return 'Request write access to a temporary workspace root, then reply with exactly: app-server permissions approval ok';
  }
  if (name === 'sequential-turns') {
    return `Reply with exactly: app-server sequential smoke ${index + 1}`;
  }
  if (name === 'large-output') {
    return 'Run a local shell command that prints exactly 1200 short numbered lines, then reply with exactly: app-server large output ok';
  }
  if (name === 'resume-rejoin') {
    return `Reply with exactly: app-server resume rejoin smoke ${index + 1}`;
  }
  if (name === 'cancellation') {
    return 'Begin a long answer counting from 1 to 100000 with one number per line. Do not summarize.';
  }
  return 'Reply with exactly: app-server smoke ok';
}

async function startTurnAndWait(threadId, name, index = 0) {
  const turnStart = await request('turn/start', {
    threadId,
    input: [{
      type: 'text',
      text: turnPromptForScenario(name, index),
      text_elements: [],
    }],
    approvalPolicy: name === 'command-approval' ? 'on-request' : 'never',
    sandboxPolicy: { type: 'readOnly', networkAccess: false },
  }, 30000);
  const turnId = turnStart.turn && turnStart.turn.id;
  if (!turnId) throw new Error('turn/start did not return turn.id');
  const turnCompleted = await waitForNotification('turn/completed', (message) => {
    return message.params && message.params.turn && message.params.turn.id === turnId;
  }, timeoutMs);
  return { turnStart, turnCompleted };
}

async function runBasicScenario(threadId) {
  if (scenario === 'command-approval') {
    const turns = [];
    for (let index = 0; index < 3; index += 1) {
      turns.push(await startTurnAndWait(threadId, 'command-approval', index));
    }
    return { turns };
  }
  if (scenario === 'permissions-approval') {
    const result = {
      turns: [await startTurnAndWait(threadId, 'permissions-approval', 0)]
    };
    if (!approvals.some((approval) => approval.method === 'item/permissions/requestApproval')) {
      throw new Error('permissions-approval smoke completed without item/permissions/requestApproval');
    }
    return {
      ...result
    };
  }
  return {
    turns: [await startTurnAndWait(threadId, scenario, 0)]
  };
}

async function runSequentialTurnsScenario(threadId) {
  const turns = [];
  for (let index = 0; index < 10; index += 1) {
    turns.push(await startTurnAndWait(threadId, 'sequential-turns', index));
  }
  return { turns };
}

async function runCancellationScenario(threadId) {
  const command = process.platform === 'win32'
    ? 'powershell -NoProfile -Command "Start-Sleep -Seconds 20"'
    : 'sleep 20';
  const shellCommand = await request('thread/shellCommand', { threadId, command }, 10000);
  const turnStarted = await waitForNotification('turn/started', (message) => {
    return message.params && message.params.threadId === threadId;
  }, 10000);
  const turnId = turnStarted.params.turn && turnStarted.params.turn.id;
  if (!turnId) throw new Error('turn/started did not include turn.id');
  await wait(Number(process.env.CODEX_APP_SERVER_SMOKE_INTERRUPT_DELAY_MS || 500));
  const interrupt = await request('turn/interrupt', { threadId, turnId }, 10000);
  const turnCompleted = await waitForNotification('turn/completed', (message) => {
    return message.params && message.params.turn && message.params.turn.id === turnId;
  }, timeoutMs);
  return {
    turns: [{ shellCommand, turnStarted, interrupt, turnCompleted }]
  };
}

async function runLargeOutputScenario(threadId) {
  const js = 'for (let i = 1; i <= 1200; i++) console.log(`app-server-large-output-${i}`)';
  const command = `${JSON.stringify(process.execPath)} -e ${JSON.stringify(js)}`;
  const shellCommand = await request('thread/shellCommand', { threadId, command }, 10000);
  const turnCompleted = await waitForNotification('turn/completed', (message) => {
    return message.params && message.params.threadId === threadId;
  }, timeoutMs);
  return {
    turns: [{ shellCommand, turnCompleted }]
  };
}

async function runImageInputScenario(threadId) {
  const imagePath = path.join(scenarioWorkspace, 'app-server-smoke-image.png');
  const transparentPng = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
  fs.writeFileSync(imagePath, Buffer.from(transparentPng, 'base64'));
  const turnStart = await request('turn/start', {
    threadId,
    input: [
      {
        type: 'text',
        text: 'Reply with exactly: app-server image input ok',
        text_elements: [],
      },
      {
        type: 'localImage',
        path: imagePath,
      }
    ],
    approvalPolicy: 'never',
    sandboxPolicy: { type: 'readOnly', networkAccess: false },
  }, 30000);
  const turnId = turnStart.turn && turnStart.turn.id;
  if (!turnId) throw new Error('turn/start did not return turn.id');
  const turnCompleted = await waitForNotification('turn/completed', (message) => {
    return message.params && message.params.turn && message.params.turn.id === turnId;
  }, timeoutMs);
  return {
    turns: [{ turnStart, turnCompleted }],
    imageInput: {
      imagePath: redact(imagePath),
      localImageSent: true,
    }
  };
}

async function initializeConnection() {
  initializedAt = initializedAt || new Date();
  const initialize = await request('initialize', {
    clientInfo: {
      name: 'vibe_coding_smoke',
      title: 'vibe-coding smoke',
      version: '0.1.0',
    },
    capabilities: {
      experimentalApi: true,
      requestAttestation: false,
    },
  }, 10000);
  notification('initialized', {});
  return initialize;
}

function startChildProcess() {
  const command = codexJs ? nodeBin : codexBin;
  const args = codexJs ? [codexJs, 'app-server'] : ['app-server'];
  child = spawn(command, args, {
    cwd: scenarioWorkspace,
    env: usesIsolatedCodexHome ? { ...process.env, CODEX_HOME: scenarioCodexHome } : process.env,
    stdio: ['pipe', 'pipe', 'pipe'],
    windowsHide: true,
  });
  childPid = child.pid || null;

  child.stderr.setEncoding('utf8');
  child.stderr.on('data', (chunk) => {
    stderrChunks.push(redact(chunk));
  });

  const rl = readline.createInterface({ input: child.stdout });
  rl.on('line', (line) => {
    if (!line.trim()) return;
    try {
      handleMessage(JSON.parse(line));
    } catch (error) {
      record('server_parse_error', { line, error: error.message });
    }
  });

  child.once('exit', (code, signal) => {
    childExit = { code, signal };
    for (const [id, entry] of pending.entries()) {
      entry.reject(new Error(`app-server exited before ${entry.method} response: code=${code} signal=${signal}`));
      pending.delete(id);
    }
  });
}

async function restartChildProcess() {
  const previousChild = {
    pid: childPid,
    descendantsBeforeCleanup: listDescendantProcesses(childPid),
  };
  previousChild.exit = await stopChild();
  terminateCapturedDescendants(previousChild.descendantsBeforeCleanup);
  await wait(1000);
  previousChild.descendantsAfterCleanup = previousChild.descendantsBeforeCleanup.map((processInfo) => ({
    ...processInfo,
    aliveAfterCleanup: pidExists(processInfo.pid),
  }));
  child = null;
  childExit = null;
  childPid = null;
  startChildProcess();
  previousChild.reinitialized = await initializeConnection();
  return previousChild;
}

async function runResumeRejoinScenario(threadId) {
  const firstTurn = await startTurnAndWait(threadId, 'resume-rejoin', 0);
  const restart = await restartChildProcess();
  const resume = await request('thread/resume', {
    threadId,
    cwd: scenarioWorkspace,
    approvalPolicy: 'never',
    sandbox: 'read-only',
    serviceName: 'vibe_coding_smoke_resume',
  }, 30000);
  const secondTurn = await startTurnAndWait(threadId, 'resume-rejoin', 1);
  return {
    turns: [firstTurn, secondTurn],
    resumeRejoin: {
      threadId,
      restart,
      resume,
    }
  };
}

function readConfigToml() {
  if (!scenarioCodexHome) return null;
  const configPath = path.join(scenarioCodexHome, 'config.toml');
  try {
    return fs.readFileSync(configPath, 'utf8');
  } catch (error) {
    if (error.code === 'ENOENT') return null;
    throw error;
  }
}

async function runProjectTrustScenario() {
  const beforeConfig = readConfigToml();
  const readOnlyThreadStart = await request('thread/start', {
    cwd: scenarioWorkspace,
    approvalPolicy: 'never',
    sandbox: 'read-only',
    serviceName: 'vibe_coding_smoke_project_trust',
  }, 30000);
  const afterReadOnlyConfig = readConfigToml();
  const workspaceWriteThreadStart = await request('thread/start', {
    cwd: scenarioWorkspace,
    approvalPolicy: 'never',
    sandbox: 'workspace-write',
    serviceName: 'vibe_coding_smoke_project_trust',
  }, 30000);
  const afterWorkspaceWriteConfig = readConfigToml();
  return {
    turns: [],
    projectTrust: redact({
      codexHome: scenarioCodexHome,
      workspace: scenarioWorkspace,
      beforeConfig,
      readOnlyThreadStart,
      afterReadOnlyConfig,
      workspaceWriteThreadStart,
      afterWorkspaceWriteConfig,
      readOnlyPersistedTrust: typeof afterReadOnlyConfig === 'string' && afterReadOnlyConfig.includes('trust_level = "trusted"'),
      workspaceWritePersistedTrust: typeof afterWorkspaceWriteConfig === 'string' && afterWorkspaceWriteConfig.includes('trust_level = "trusted"'),
      workspaceMentionedAfterReadOnly: typeof afterReadOnlyConfig === 'string' && afterReadOnlyConfig.toLowerCase().includes(scenarioWorkspace.toLowerCase()),
      workspaceMentionedAfterWorkspaceWrite: typeof afterWorkspaceWriteConfig === 'string' && afterWorkspaceWriteConfig.toLowerCase().includes(scenarioWorkspace.toLowerCase()),
    })
  };
}

async function runScenario(threadId) {
  if (scenario === 'sequential-turns') return runSequentialTurnsScenario(threadId);
  if (scenario === 'cancellation') return runCancellationScenario(threadId);
  if (scenario === 'large-output') return runLargeOutputScenario(threadId);
  if (scenario === 'resume-rejoin') return runResumeRejoinScenario(threadId);
  if (scenario === 'image-input') return runImageInputScenario(threadId);
  return runBasicScenario(threadId);
}

async function run() {
  fs.mkdirSync(samplesDir, { recursive: true });
  if (usesMockModelServer) {
    const serverUrl = await startMockModelServer();
    writeMockModelConfig(serverUrl);
  }
  startChildProcess();

  const initialize = await initializeConnection();

  let modelList = null;
  let threadListBefore = null;
  let threadStart = null;
  let threadListAfter = null;
  let scenarioResult;
  if (scenario === 'project-trust') {
    scenarioResult = await runProjectTrustScenario();
  } else {
    modelList = await request('model/list', { limit: 20, includeHidden: false }, 30000);
    threadListBefore = await request('thread/list', { limit: 5, useStateDbOnly: true }, 30000);
    threadStart = await request('thread/start', {
      cwd: scenarioWorkspace,
      approvalPolicy: 'never',
      sandbox: 'read-only',
      serviceName: 'vibe_coding_smoke',
    }, 30000);
    const threadId = threadStart.thread && threadStart.thread.id;
    if (!threadId) throw new Error('thread/start did not return thread.id');
    scenarioResult = await runScenario(threadId);
    threadListAfter = await request('thread/list', { limit: 5, useStateDbOnly: true }, 30000);
  }
  descendantsBeforeCleanup = listDescendantProcesses(childPid);
  await stopChild();
  terminateCapturedDescendants(descendantsBeforeCleanup);
  await wait(1000);
  descendantsAfterCleanup = descendantsBeforeCleanup.map((processInfo) => ({
    ...processInfo,
    aliveAfterCleanup: pidExists(processInfo.pid),
  }));
  completedAt = new Date();

  const sample = {
    schemaVersion: 1,
    transport: 'stdio',
    scenario,
    codexBin,
    codexJs,
    mockModelServerUrl,
    childPid,
    childExit,
    processTree: {
      descendantsBeforeCleanup,
      descendantsAfterCleanup,
      orphanedDescendantsAfterCleanup: descendantsAfterCleanup.filter((processInfo) => processInfo.aliveAfterCleanup),
    },
    cwd: scenarioWorkspace,
    codexHome: scenarioCodexHome,
    initializedAt: initializedAt.toISOString(),
    completedAt: completedAt.toISOString(),
    initialize,
    modelListSummary: {
      count: Array.isArray(modelList?.data) ? modelList.data.length : null,
      defaultModel: Array.isArray(modelList?.data)
        ? (modelList.data.find((item) => item.isDefault) || modelList.data[0] || {}).id || null
        : null,
    },
    threadListBeforeSummary: {
      count: Array.isArray(threadListBefore?.data) ? threadListBefore.data.length : null,
    },
    threadStart,
    ...scenarioResult,
    approvals,
    approvalSummary: {
      count: approvals.length,
      availableDecisions: approvals.map((approval) => approval.params?.availableDecisions || approval.params?.available_decisions || null),
      responseLatencyMs: approvals.map((approval) => approval.responseLatencyMs),
      resolvedLatencyMs: approvals.map((approval) => approval.resolvedLatencyMs),
      sawAcceptForSession: approvals.some((approval) => {
        const decisions = approval.params?.availableDecisions || approval.params?.available_decisions || [];
        return Array.isArray(decisions) && decisions.includes('acceptForSession');
      }),
    },
    modelRequests,
    threadListAfterSummary: {
      count: Array.isArray(threadListAfter?.data) ? threadListAfter.data.length : null,
    },
    messages,
    stderr: stderrChunks.join('').slice(-12000),
  };

  const samplePath = path.join(samplesDir, `${dateStamp}-stdio-${scenario}.json`);
  fs.writeFileSync(samplePath, `${JSON.stringify(redact(sample), null, 2)}\n`, 'utf8');
  console.log(`wrote ${path.relative(repoRoot, samplePath)}`);
}

run()
  .catch((error) => {
    const failedPath = path.join(samplesDir, `${dateStamp}-stdio-${scenario}-failed.json`);
    fs.mkdirSync(samplesDir, { recursive: true });
    fs.writeFileSync(failedPath, `${JSON.stringify(redact({
      schemaVersion: 1,
      transport: 'stdio',
      scenario,
      codexBin,
      codexJs,
      childPid,
      childExit,
      processTree: {
        descendantsBeforeCleanup,
        descendantsAfterCleanup,
      },
      cwd,
      error: error.message,
      approvals,
      messages,
      stderr: stderrChunks.join('').slice(-12000),
    }), null, 2)}\n`, 'utf8');
    console.error(error.stack || error.message);
    console.error(`wrote ${path.relative(repoRoot, failedPath)}`);
    process.exitCode = 1;
  })
  .finally(() => {
    if (child && !child.killed && !childExit) child.kill();
    stopMockModelServer();
  });
