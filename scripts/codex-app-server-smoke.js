'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const readline = require('node:readline');
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

let nextId = 1;
const messages = [];
const stderrChunks = [];
const approvals = [];
const pending = new Map();
let child;
let initializedAt = null;
let completedAt = null;
let childPid = null;
let childExit = null;
let descendantsBeforeCleanup = [];
let descendantsAfterCleanup = [];

function redact(value) {
  if (typeof value === 'string') {
    return value
      .replaceAll(os.homedir(), '<USER_HOME>')
      .replaceAll(repoRoot, '<WORKSPACE>')
      .replaceAll(cwd, '<WORKSPACE>');
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
  if (name === 'sequential-turns') {
    return `Reply with exactly: app-server sequential smoke ${index + 1}`;
  }
  if (name === 'large-output') {
    return 'Run a local shell command that prints exactly 1200 short numbered lines, then reply with exactly: app-server large output ok';
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

async function runScenario(threadId) {
  if (scenario === 'sequential-turns') return runSequentialTurnsScenario(threadId);
  if (scenario === 'cancellation') return runCancellationScenario(threadId);
  if (scenario === 'large-output') return runLargeOutputScenario(threadId);
  return runBasicScenario(threadId);
}

async function run() {
  fs.mkdirSync(samplesDir, { recursive: true });
  const command = codexJs ? nodeBin : codexBin;
  const args = codexJs ? [codexJs, 'app-server'] : ['app-server'];
  child = spawn(command, args, {
    cwd,
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

  initializedAt = new Date();
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

  const modelList = await request('model/list', { limit: 20, includeHidden: false }, 30000);
  const threadListBefore = await request('thread/list', { limit: 5, useStateDbOnly: true }, 30000);
  const threadStart = await request('thread/start', {
    cwd,
    approvalPolicy: 'never',
    sandbox: 'read-only',
    serviceName: 'vibe_coding_smoke',
  }, 30000);
  const threadId = threadStart.thread && threadStart.thread.id;
  if (!threadId) throw new Error('thread/start did not return thread.id');

  const scenarioResult = await runScenario(threadId);
  const threadListAfter = await request('thread/list', { limit: 5, useStateDbOnly: true }, 30000);
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
    childPid,
    childExit,
    processTree: {
      descendantsBeforeCleanup,
      descendantsAfterCleanup,
      orphanedDescendantsAfterCleanup: descendantsAfterCleanup.filter((processInfo) => processInfo.aliveAfterCleanup),
    },
    cwd,
    initializedAt: initializedAt.toISOString(),
    completedAt: completedAt.toISOString(),
    initialize,
    modelListSummary: {
      count: Array.isArray(modelList.data) ? modelList.data.length : null,
      defaultModel: Array.isArray(modelList.data)
        ? (modelList.data.find((item) => item.isDefault) || modelList.data[0] || {}).id || null
        : null,
    },
    threadListBeforeSummary: {
      count: Array.isArray(threadListBefore.data) ? threadListBefore.data.length : null,
    },
    threadStart,
    ...scenarioResult,
    approvals,
    threadListAfterSummary: {
      count: Array.isArray(threadListAfter.data) ? threadListAfter.data.length : null,
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
  });
