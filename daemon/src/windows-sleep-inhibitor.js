'use strict';

const { spawn } = require('node:child_process');

function createWindowsSleepInhibitor({
  platform = process.platform,
  pid = process.pid,
  env = process.env,
  spawnFn = spawn,
  logger = console
} = {}) {
  let child = null;

  function clearChild(current, error = null) {
    if (child !== current) return;
    child = null;
    if (error && typeof logger?.warn === 'function') {
      logger.warn(`Windows sleep inhibitor process failed: ${error.message}`);
    }
  }

  return {
    start() {
      if (env.DAEMON_PREVENT_SLEEP === '0') {
        return { active: false, reason: 'disabled' };
      }
      if (platform !== 'win32') {
        return { active: false, reason: 'unsupported_platform' };
      }
      if (child) {
        return { active: true, reason: 'already_started' };
      }

      try {
        child = spawnFn('powershell.exe', [
          '-NoLogo',
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          windowsPowerRequestScript(pid)
        ], {
          windowsHide: true,
          stdio: 'ignore'
        });
        if (typeof child?.once === 'function') {
          const current = child;
          child.once('error', (error) => clearChild(current, error));
          child.once('exit', () => clearChild(current));
          child.once('close', () => clearChild(current));
        }
        if (typeof child?.unref === 'function') child.unref();
        return { active: true, reason: 'started' };
      } catch (error) {
        child = null;
        if (typeof logger?.warn === 'function') {
          logger.warn(`Unable to prevent Windows sleep while daemon is running: ${error.message}`);
        }
        return { active: false, reason: 'spawn_failed', error };
      }
    },

    stop() {
      const current = child;
      child = null;
      if (!current || typeof current.kill !== 'function' || current.killed) return;
      try {
        current.kill();
      } catch (error) {
        if (typeof logger?.warn === 'function') {
          logger.warn(`Unable to stop Windows sleep inhibitor: ${error.message}`);
        }
      }
    }
  };
}

function windowsPowerRequestScript(parentPid) {
  const safeParentPid = Number.isInteger(Number(parentPid)) && Number(parentPid) > 0
    ? Number(parentPid)
    : 0;
  return `
$ErrorActionPreference = 'SilentlyContinue'
$parentPid = ${safeParentPid}
$signature = @"
using System;
using System.Runtime.InteropServices;
public static class VibeCodingPower {
  [DllImport("kernel32.dll", SetLastError = true)]
  public static extern uint SetThreadExecutionState(uint esFlags);
}
"@
Add-Type -TypeDefinition $signature
$preventSleepFlags = [uint32]2147483649
$clearFlags = [uint32]2147483648
try {
  while (Get-Process -Id $parentPid -ErrorAction SilentlyContinue) {
    [VibeCodingPower]::SetThreadExecutionState($preventSleepFlags) | Out-Null
    Start-Sleep -Seconds 30
  }
} finally {
  [VibeCodingPower]::SetThreadExecutionState($clearFlags) | Out-Null
}
`;
}

module.exports = { createWindowsSleepInhibitor, windowsPowerRequestScript };
