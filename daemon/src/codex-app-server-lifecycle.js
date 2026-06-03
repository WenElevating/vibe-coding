'use strict';

const { spawn, spawnSync } = require('node:child_process');
const { CodexAppServerJsonlTransport } = require('./codex-app-server-transport');

class CodexAppServerLifecycle {
  constructor({
    maxProcesses = 1,
    gracefulShutdownMs = 5000,
    requestTimeoutMs = 30000,
    command = process.platform === 'win32' ? 'D:\\nodejs\\node.exe' : 'codex',
    args = process.platform === 'win32'
      ? ['D:\\nodejs\\node_modules\\@openai\\codex\\bin\\codex.js', 'app-server']
      : ['app-server'],
    cwd = process.cwd(),
    env = process.env,
    spawnAppServer = null,
    processTreeTerminator = undefined,
    metrics = null
  } = {}) {
    this.maxProcesses = Math.max(1, Number(maxProcesses) || 1);
    this.gracefulShutdownMs = Math.max(1, Number(gracefulShutdownMs) || 5000);
    this.requestTimeoutMs = Math.max(1, Number(requestTimeoutMs) || 30000);
    this.hardKillGraceMs = Math.max(1, Number(this.gracefulShutdownMs) || 5000);
    this.command = command;
    this.args = args;
    this.cwd = cwd;
    this.env = env;
    const customSpawn = typeof spawnAppServer === 'function';
    this.spawnAppServer = spawnAppServer || (() => spawn(this.command, this.args, {
      cwd: this.cwd,
      env: this.env,
      stdio: ['pipe', 'pipe', 'pipe'],
      windowsHide: true
    }));
    this.processTreeTerminator = processTreeTerminator === undefined
      ? (customSpawn ? null : defaultProcessTreeTerminator)
      : processTreeTerminator;
    this.metrics = metrics || {
      orphanProcessCleanupCount: 0
    };
    this.handles = new Set();
  }

  spawn() {
    this._pruneClosed();
    if (this.handles.size >= this.maxProcesses) {
      throw new Error('maximum Codex app-server process limit reached');
    }
    const child = this.spawnAppServer();
    const handle = new CodexAppServerProcessHandle({
      child,
      lifecycle: this,
      gracefulShutdownMs: this.gracefulShutdownMs,
      hardKillGraceMs: this.hardKillGraceMs,
      requestTimeoutMs: this.requestTimeoutMs,
      processTreeTerminator: this.processTreeTerminator
    });
    this.handles.add(handle);
    child.once('exit', () => {
      handle.exited = true;
      this.handles.delete(handle);
    });
    return handle;
  }

  _pruneClosed() {
    for (const handle of this.handles) {
      if (handle.exited) this.handles.delete(handle);
    }
  }
}

class CodexAppServerProcessHandle {
  constructor({ child, lifecycle, gracefulShutdownMs, hardKillGraceMs, requestTimeoutMs, processTreeTerminator = null }) {
    if (!child || !child.stdin || !child.stdout) throw new Error('app-server child process must expose stdio streams');
    this.child = child;
    this.lifecycle = lifecycle;
    this.pid = child.pid || null;
    this.exited = false;
    this.exit = null;
    this.gracefulShutdownMs = gracefulShutdownMs;
    this.hardKillGraceMs = hardKillGraceMs;
    this.processTreeTerminator = processTreeTerminator;
    this.processTreePids = [];
    this.forceTerminateSent = false;
    this.transport = new CodexAppServerJsonlTransport({
      stdin: child.stdin,
      stdout: child.stdout,
      stderr: child.stderr,
      requestTimeoutMs
    });
    child.once('exit', (code, signal) => {
      this.exited = true;
      this.exit = { code, signal };
      this.transport.close();
    });
  }

  shutdown() {
    if (this.exited) return Promise.resolve(this.exit);
    return new Promise((resolve) => {
      const done = (code, signal) => {
        clearTimeout(graceTimer);
        clearTimeout(hardKillTimer);
        if (this.processTreeTerminator && this.pid && !this.forceTerminateSent) {
          this.terminate('SIGKILL');
        }
        this.exited = true;
        this.exit = { code, signal };
        this.lifecycle.handles.delete(this);
        resolve(this.exit);
      };
      let hardKillTimer = null;
      const graceTimer = setTimeout(() => {
        if (!this.exited) {
          this.terminate('SIGKILL');
          hardKillTimer = setTimeout(() => {
            if (!this.exited) done(null, 'SIGKILL_TIMEOUT');
          }, this.hardKillGraceMs);
        }
      }, this.gracefulShutdownMs);
      this.child.once('exit', done);
      if (!this.terminate('SIGTERM')) {
        done(null, 'missing-kill');
      }
    });
  }

  terminate(signal) {
    const force = signal === 'SIGKILL';
    if (force) this.forceTerminateSent = true;
    if (this.processTreeTerminator && this.pid) {
      if (this.processTreePids.length === 0) {
        this.processTreePids = collectWindowsProcessTreePids(this.pid);
      }
      const result = this.processTreeTerminator(this.pid, {
        force,
        signal,
        processTreePids: this.processTreePids
      });
      if (result === true) {
        if (force || this.processTreePids.length > 1) {
          this.lifecycle.metrics.orphanProcessCleanupCount += 1;
        }
        return true;
      }
    }
    if (typeof this.child.kill === 'function') {
      return this.child.kill(signal);
    }
    return false;
  }
}

function defaultProcessTreeTerminator(pid, { force = false, processTreePids = [] } = {}) {
  if (process.platform !== 'win32') return false;
  if (force && Array.isArray(processTreePids) && processTreePids.length > 0) {
    let killedAny = false;
    for (const processId of [...processTreePids].reverse()) {
      const args = ['/PID', String(processId), '/T', '/F'];
      const result = spawnSync('taskkill', args, { windowsHide: true, stdio: 'ignore' });
      killedAny = killedAny || result.status === 0;
    }
    return killedAny;
  }
  const args = ['/PID', String(pid), '/T'];
  if (force) args.push('/F');
  const result = spawnSync('taskkill', args, { windowsHide: true, stdio: 'ignore' });
  return result.status === 0;
}

function collectWindowsProcessTreePids(rootPid) {
  if (!rootPid || process.platform !== 'win32') return [];
  const script = [
    '$ErrorActionPreference = "Stop"',
    '$items = Get-CimInstance Win32_Process | Select-Object ProcessId,ParentProcessId',
    '$items | ConvertTo-Json -Compress'
  ].join('; ');
  const result = spawnSync('powershell', ['-NoProfile', '-Command', script], {
    encoding: 'utf8',
    windowsHide: true,
    timeout: 10000
  });
  if (result.status !== 0 || !result.stdout.trim()) return [Number(rootPid)];
  let processes;
  try {
    processes = JSON.parse(result.stdout);
  } catch {
    return [Number(rootPid)];
  }
  const all = Array.isArray(processes) ? processes : [processes];
  const byParent = new Map();
  for (const processInfo of all) {
    const parent = Number(processInfo.ParentProcessId);
    if (!byParent.has(parent)) byParent.set(parent, []);
    byParent.get(parent).push(Number(processInfo.ProcessId));
  }
  const pids = [Number(rootPid)];
  const queue = [...(byParent.get(Number(rootPid)) || [])];
  while (queue.length > 0) {
    const current = queue.shift();
    pids.push(current);
    queue.push(...(byParent.get(current) || []));
  }
  return pids;
}

module.exports = {
  CodexAppServerLifecycle,
  CodexAppServerProcessHandle,
  defaultProcessTreeTerminator,
  collectWindowsProcessTreePids
};
