'use strict';

const path = require('node:path');
const { spawn } = require('node:child_process');

const restartDelayMs = 2000;
const terminalExitCodes = new Set([0, 130, 143]);
const repoRoot = path.join(__dirname, '..');
const daemonEntry = path.join(repoRoot, 'daemon', 'src', 'main.js');
const watchdogEnabled = process.env.DAEMON_WATCHDOG !== '0';

let child = null;
let stopping = false;

function start() {
  child = spawn(process.execPath, [daemonEntry], {
    cwd: repoRoot,
    stdio: 'inherit',
    windowsHide: false,
    env: process.env
  });

  child.on('exit', (code, signal) => {
    child = null;
    if (stopping) {
      process.exit(code ?? signalExitCode(signal) ?? 0);
      return;
    }
    if (!watchdogEnabled || terminalExitCodes.has(code ?? 0)) {
      process.exit(code ?? signalExitCode(signal) ?? 0);
      return;
    }
    const label = signal ? `signal ${signal}` : `code ${code}`;
    console.log(`[daemon] process exited with ${label}; restarting in ${restartDelayMs / 1000} seconds...`);
    setTimeout(start, restartDelayMs);
  });
}

function signalExitCode(signal) {
  if (signal === 'SIGINT') return 130;
  if (signal === 'SIGTERM') return 143;
  return null;
}

function stop(signal) {
  stopping = true;
  if (child && typeof child.kill === 'function') {
    child.kill(signal);
    return;
  }
  process.exit(signalExitCode(signal) ?? 0);
}

process.once('SIGINT', () => stop('SIGINT'));
process.once('SIGTERM', () => stop('SIGTERM'));

start();
