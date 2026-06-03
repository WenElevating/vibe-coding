'use strict';

const { spawn } = require('node:child_process');
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
    spawnAppServer = null
  } = {}) {
    this.maxProcesses = Math.max(1, Number(maxProcesses) || 1);
    this.gracefulShutdownMs = Math.max(1, Number(gracefulShutdownMs) || 5000);
    this.requestTimeoutMs = Math.max(1, Number(requestTimeoutMs) || 30000);
    this.hardKillGraceMs = Math.max(1, Number(this.gracefulShutdownMs) || 5000);
    this.command = command;
    this.args = args;
    this.cwd = cwd;
    this.env = env;
    this.spawnAppServer = spawnAppServer || (() => spawn(this.command, this.args, {
      cwd: this.cwd,
      env: this.env,
      stdio: ['pipe', 'pipe', 'pipe'],
      windowsHide: true
    }));
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
      requestTimeoutMs: this.requestTimeoutMs
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
  constructor({ child, lifecycle, gracefulShutdownMs, hardKillGraceMs, requestTimeoutMs }) {
    if (!child || !child.stdin || !child.stdout) throw new Error('app-server child process must expose stdio streams');
    this.child = child;
    this.lifecycle = lifecycle;
    this.pid = child.pid || null;
    this.exited = false;
    this.exit = null;
    this.gracefulShutdownMs = gracefulShutdownMs;
    this.hardKillGraceMs = hardKillGraceMs;
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
        this.exited = true;
        this.exit = { code, signal };
        this.lifecycle.handles.delete(this);
        resolve(this.exit);
      };
      let hardKillTimer = null;
      const graceTimer = setTimeout(() => {
        if (!this.exited && typeof this.child.kill === 'function') {
          this.child.kill('SIGKILL');
          hardKillTimer = setTimeout(() => {
            if (!this.exited) done(null, 'SIGKILL_TIMEOUT');
          }, this.hardKillGraceMs);
        }
      }, this.gracefulShutdownMs);
      this.child.once('exit', done);
      if (typeof this.child.kill === 'function') {
        this.child.kill('SIGTERM');
      } else {
        done(null, 'missing-kill');
      }
    });
  }
}

module.exports = {
  CodexAppServerLifecycle,
  CodexAppServerProcessHandle
};
