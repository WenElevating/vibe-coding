'use strict';

const net = require('node:net');
const { spawn, spawnSync } = require('node:child_process');
const { resolveCliInvocation } = require('./cli-resolver');
const { OpenCodeServerClient } = require('./opencode-server-client');

const MAX_DETAIL_STRING_LENGTH = 512;
const MAX_DETAIL_KEYS = 20;
const MAX_DETAIL_ARRAY_ITEMS = 20;
const MAX_DETAIL_DEPTH = 4;
const DEFAULT_STARTUP_ATTEMPTS = 3;
const DEFAULT_STARTUP_TIMEOUT_MS = 5000;
const DEFAULT_HEALTH_POLL_INTERVAL_MS = 100;
const DEFAULT_RETRY_DELAY_MS = 250;
const DEFAULT_GRACEFUL_SHUTDOWN_MS = 500;
const DEFAULT_HARD_KILL_GRACE_MS = 1000;

class OpenCodeServerLifecycle {
  constructor({
    externalUrl = process.env.OPENCODE_SERVER_URL || '',
    command = 'opencode',
    spawnFn = spawn,
    spawnSyncFn = spawnSync,
    clientFactory = (serverUrl) => new OpenCodeServerClient({ serverUrl }),
    findAvailablePort = findAvailableLoopbackPort,
    delayFn = delay,
    startupAttempts = DEFAULT_STARTUP_ATTEMPTS,
    startupTimeoutMs = DEFAULT_STARTUP_TIMEOUT_MS,
    healthPollIntervalMs = DEFAULT_HEALTH_POLL_INTERVAL_MS,
    retryDelayMs = DEFAULT_RETRY_DELAY_MS,
    gracefulShutdownMs = DEFAULT_GRACEFUL_SHUTDOWN_MS,
    hardKillGraceMs = DEFAULT_HARD_KILL_GRACE_MS,
    processTreeTerminator = undefined,
    cliResolverOptions = {}
  } = {}) {
    this.externalUrl = normalizeExternalUrl(externalUrl);
    this.command = command || 'opencode';
    this.spawnFn = spawnFn;
    this.spawnSyncFn = spawnSyncFn;
    this.clientFactory = clientFactory;
    this.findAvailablePort = findAvailablePort;
    this.delayFn = delayFn;
    this.startupAttempts = Math.min(DEFAULT_STARTUP_ATTEMPTS, normalizeNumber(startupAttempts, DEFAULT_STARTUP_ATTEMPTS, 1));
    this.startupTimeoutMs = normalizeNumber(startupTimeoutMs, DEFAULT_STARTUP_TIMEOUT_MS, 1);
    this.healthPollIntervalMs = normalizeNumber(healthPollIntervalMs, DEFAULT_HEALTH_POLL_INTERVAL_MS, 1);
    this.retryDelayMs = normalizeNumber(retryDelayMs, DEFAULT_RETRY_DELAY_MS, 0);
    this.gracefulShutdownMs = normalizeNumber(gracefulShutdownMs, DEFAULT_GRACEFUL_SHUTDOWN_MS, 1);
    this.hardKillGraceMs = normalizeNumber(hardKillGraceMs, DEFAULT_HARD_KILL_GRACE_MS, 1);
    this.cliResolverOptions = cliResolverOptions || {};
    const customSpawn = spawnFn !== spawn;
    this.processTreeTerminator = processTreeTerminator === undefined
      ? customSpawn
        ? null
        : (pid, options = {}) => defaultProcessTreeTerminator(pid, {
          ...options,
          spawnSyncFn: this.spawnSyncFn
        })
      : processTreeTerminator;
    this.current = null;
    this.managedChild = null;
    this.startingChild = null;
    this.startPromise = null;
    this.childStates = new WeakMap();
    this.shutdownChildPromises = new WeakMap();
    this.generation = 0;
    this.generationWaiters = new Set();
    this.lastError = null;
    this.lastStatus = 'idle';
  }

  async ensureStarted() {
    if (this.current) return this.current;
    if (this.startPromise) return this.startPromise;
    const generation = this.generation;
    const startPromise = this._ensureStarted(generation).finally(() => {
      if (this.startPromise === startPromise) this.startPromise = null;
    });
    this.startPromise = startPromise;
    return startPromise;
  }

  async shutdown() {
    this.generation += 1;
    this._notifyGenerationChanged();
    this.startPromise = null;
    if (this.current?.mode === 'external') {
      this.current = null;
      this.lastStatus = 'idle';
      return;
    }
    const child = this.managedChild || this.startingChild;
    this.current = null;
    this.managedChild = null;
    this.startingChild = null;
    if (!child) {
      if (!this.current && !this.startPromise) this.lastStatus = 'idle';
      return;
    }
    this.lastStatus = 'stopping';
    await this._shutdownChild(child);
    if (!this.current && !this.startPromise) this.lastStatus = 'idle';
  }

  getDiagnostics() {
    return {
      status: this.lastStatus,
      lastError: this.lastError
        ? { code: this.lastError.code, message: this.lastError.message, details: this.lastError.details }
        : null
    };
  }

  _createGenerationChangeSignal(startGeneration) {
    if (startGeneration !== this.generation) {
      return {
        promise: Promise.resolve({ type: 'stopped' }),
        cancel() {}
      };
    }
    let waiter = null;
    const promise = new Promise((resolve) => {
      waiter = () => resolve({ type: 'stopped' });
      this.generationWaiters.add(waiter);
    }).finally(() => {
      if (waiter) this.generationWaiters.delete(waiter);
    });
    return {
      promise,
      cancel: () => {
        if (waiter) this.generationWaiters.delete(waiter);
      }
    };
  }

  _notifyGenerationChanged() {
    const waiters = Array.from(this.generationWaiters);
    this.generationWaiters.clear();
    for (const waiter of waiters) waiter();
  }

  async _waitForGenerationDelay(ms, generation) {
    const waitDelay = createCancelableDelay(this.delayFn, ms);
    const stopSignal = this._createGenerationChangeSignal(generation);
    try {
      await Promise.race([
        waitDelay.promise,
        stopSignal.promise
      ]);
      throwIfStopped(generation, this.generation, 'startup');
    } finally {
      waitDelay.cancel();
      stopSignal.cancel();
    }
  }

  async _ensureStarted(generation) {
    if (this.externalUrl) return this._ensureExternalStarted(generation);
    return this._ensureManagedStarted(generation);
  }

  async _ensureExternalStarted(generation) {
    const client = this.clientFactory(this.externalUrl);
    const abortController = new AbortController();
    try {
      throwIfStopped(generation, this.generation, 'startup');
      this.lastStatus = 'health_check';
      const healthPromise = Promise.resolve()
        .then(() => client.health({ signal: abortController.signal }))
        .then(
          () => ({ type: 'healthy' }),
          (error) => ({ type: 'health_error', error })
        );
      const stopSignal = this._createGenerationChangeSignal(generation);
      const stopPromise = stopSignal.promise.then((result) => {
        abortController.abort();
        return result;
      });
      let healthResult = null;
      try {
        healthResult = await Promise.race([healthPromise, stopPromise]);
      } finally {
        if (generation !== this.generation) abortController.abort();
        stopSignal.cancel();
      }
      throwIfStopped(generation, this.generation, 'startup');
      if (healthResult.type === 'health_error') throw healthResult.error;
      this.current = {
        mode: 'external',
        serverUrl: this.externalUrl,
        client,
        owned: false
      };
      this.lastStatus = 'started';
      this.lastError = null;
      return this.current;
    } catch (error) {
      if (error?.code === 'OPENCODE_SERVER_STOPPED') {
        if (!this.current && !this.startPromise) {
          this.lastError = error;
          this.lastStatus = 'idle';
        }
        throw error;
      }
      const wrapped = createLifecycleError(`OpenCode server is unavailable at ${this.externalUrl}`, {
        code: 'OPENCODE_SERVER_UNAVAILABLE',
        details: {
          serverUrl: this.externalUrl,
          cause: errorDetails(error)
        },
        cause: error
      });
      this.lastError = wrapped;
      this.lastStatus = 'failed';
      throw wrapped;
    }
  }

  async _ensureManagedStarted(generation) {
    let lastError = null;
    for (let attempt = 1; attempt <= this.startupAttempts; attempt += 1) {
      throwIfStopped(generation, this.generation, 'startup');
      let child = null;
      try {
        const port = await this._findPort();
        throwIfStopped(generation, this.generation, 'startup');
        const serverUrl = `http://127.0.0.1:${port}`;
        const client = this.clientFactory(serverUrl);
        const invocation = this._resolveInvocation();
        const args = [...(invocation.argsPrefix || []), 'serve', '--hostname', '127.0.0.1', '--port', String(port)];
        throwIfStopped(generation, this.generation, 'startup');
        child = this.spawnFn(invocation.command, args, {
          stdio: ['ignore', 'ignore', 'ignore'],
          windowsHide: true
        });
        if (!child || typeof child.once !== 'function') {
          throw createLifecycleError('OpenCode server spawn did not return a child process handle', {
            code: 'OPENCODE_SERVER_SPAWN_FAILED',
            details: { attempt }
          });
        }
        this.startingChild = child;
        const childState = this._trackChild(child);
        this.lastStatus = 'health_check';
        await this._waitForManagedHealth({ client, serverUrl, childState, attempt, generation });
        throwIfStopped(generation, this.generation, 'startup');
        if (this.startingChild === child) this.startingChild = null;
        this.managedChild = child;
        this.current = {
          mode: 'managed',
          serverUrl,
          client,
          owned: true
        };
        this.lastStatus = 'started';
        this.lastError = null;
        return this.current;
      } catch (error) {
        lastError = ensureLifecycleError(error, 'OPENCODE_SERVER_SPAWN_FAILED');
        if (lastError.code !== 'OPENCODE_SERVER_STOPPED' || (!this.current && !this.startPromise)) {
          this.lastError = lastError;
        }
        if (child) await this._shutdownChild(child);
        if (this.startingChild === child) this.startingChild = null;
        if (lastError.code === 'OPENCODE_SERVER_STOPPED') {
          if (!this.current && !this.startPromise) this.lastStatus = 'idle';
          throw lastError;
        }
        this.lastStatus = 'retrying';
        if (attempt < this.startupAttempts) {
          try {
            await this._waitForGenerationDelay(this.retryDelayMs, generation);
          } catch (retryError) {
            const retryLifecycleError = ensureLifecycleError(retryError, 'OPENCODE_SERVER_SPAWN_FAILED');
            if (retryLifecycleError.code === 'OPENCODE_SERVER_STOPPED' && !this.current && !this.startPromise) {
              this.lastError = retryLifecycleError;
              this.lastStatus = 'idle';
            }
            throw retryLifecycleError;
          }
        }
      }
    }
    const wrapped = createLifecycleError('OpenCode managed server failed to start', {
      code: lastError?.code === 'OPENCODE_SERVER_PORT_UNAVAILABLE'
        ? 'OPENCODE_SERVER_PORT_UNAVAILABLE'
        : 'OPENCODE_SERVER_SPAWN_FAILED',
      details: {
        attempts: this.startupAttempts,
        cause: errorDetails(lastError)
      },
      cause: lastError
    });
    this.lastError = wrapped;
    this.lastStatus = 'failed';
    throw wrapped;
  }

  async _findPort() {
    try {
      const port = await this.findAvailablePort();
      if (!isUsablePort(port)) throw new Error(`invalid loopback port: ${port}`);
      return Number(port);
    } catch (error) {
      throw createLifecycleError('OpenCode managed server could not allocate a loopback port', {
        code: 'OPENCODE_SERVER_PORT_UNAVAILABLE',
        details: { cause: errorDetails(error) },
        cause: error
      });
    }
  }

  _resolveInvocation() {
    return resolveCliInvocation(this.command, {
      ...this.cliResolverOptions,
      spawnSyncFn: this.spawnSyncFn
    });
  }

  async _waitForManagedHealth({ client, serverUrl, childState, attempt, generation }) {
    const deadline = Date.now() + this.startupTimeoutMs;
    let lastHealthError = null;
    while (true) {
      throwIfStopped(generation, this.generation, 'startup');
      if (childState.exited) {
        throw createLifecycleError('OpenCode managed server exited before becoming healthy', {
          code: 'OPENCODE_SERVER_SPAWN_FAILED',
          details: { attempt, serverUrl, exit: childState.exit }
        });
      }
      const remainingMs = deadline - Date.now();
      if (remainingMs <= 0) break;
      const timeoutDelay = createCancelableDelay(this.delayFn, remainingMs);
      const abortController = new AbortController();
      const healthPromise = Promise.resolve()
        .then(() => client.health({ signal: abortController.signal }))
        .then(
          () => ({ type: 'healthy' }),
          (error) => ({ type: 'health_error', error })
        );
      const stopSignal = this._createGenerationChangeSignal(generation);
      const abortHealth = () => abortController.abort();
      let result = null;
      try {
        result = await Promise.race([
          healthPromise,
          stopSignal.promise.then((value) => {
            abortHealth();
            return value;
          }),
          childState.promise.then(() => {
            abortHealth();
            return { type: 'child_exit' };
          }),
          timeoutDelay.promise.then(() => {
            abortHealth();
            return { type: 'timeout' };
          })
        ]);
      } finally {
        if (!result || (result.type !== 'healthy' && result.type !== 'health_error')) abortHealth();
        stopSignal.cancel();
        timeoutDelay.cancel();
      }
      throwIfStopped(generation, this.generation, 'startup');
      if (result.type === 'healthy') return;
      if (result.type === 'child_exit') {
        throw createLifecycleError('OpenCode managed server exited before becoming healthy', {
          code: 'OPENCODE_SERVER_SPAWN_FAILED',
          details: { attempt, serverUrl, exit: childState.exit }
        });
      }
      if (result.type === 'timeout') break;
      lastHealthError = result.error;
      const pollDelayMs = Math.min(this.healthPollIntervalMs, deadline - Date.now());
      if (pollDelayMs > 0) {
        const pollDelay = createCancelableDelay(this.delayFn, pollDelayMs);
        const pollStopSignal = this._createGenerationChangeSignal(generation);
        let delayResult = null;
        try {
          delayResult = await Promise.race([
            pollDelay.promise.then(() => ({ type: 'delay' })),
            childState.promise.then(() => ({ type: 'child_exit' })),
            pollStopSignal.promise
          ]);
        } finally {
          pollStopSignal.cancel();
          pollDelay.cancel();
        }
        throwIfStopped(generation, this.generation, 'startup');
        if (delayResult.type === 'child_exit') {
          throw createLifecycleError('OpenCode managed server exited before becoming healthy', {
            code: 'OPENCODE_SERVER_SPAWN_FAILED',
            details: { attempt, serverUrl, exit: childState.exit }
          });
        }
      }
    }
    throw createLifecycleError('OpenCode managed server did not become healthy before startup timeout', {
      code: 'OPENCODE_SERVER_SPAWN_FAILED',
      details: {
        attempt,
        serverUrl,
        timeoutMs: this.startupTimeoutMs,
        cause: errorDetails(lastHealthError)
      },
      cause: lastHealthError
    });
  }

  _trackChild(child) {
    const existing = this.childStates.get(child);
    if (existing) return existing;
    const state = {
      exited: false,
      exit: null,
      promise: null
    };
    state.promise = new Promise((resolve) => {
      const finish = (exit) => {
        if (state.exited) return;
        state.exited = true;
        state.exit = sanitizeDetails(exit);
        if (this.managedChild === child) {
          this.managedChild = null;
          this.current = null;
          this.lastStatus = 'exited';
        }
        if (this.startingChild === child) this.startingChild = null;
        resolve(state.exit);
      };
      child.once('exit', (code, signal) => finish({ code, signal }));
      child.once('error', (error) => finish({ error: errorDetails(error) }));
    });
    this.childStates.set(child, state);
    return state;
  }

  async _shutdownChild(child) {
    const existing = this.shutdownChildPromises.get(child);
    if (existing) return existing;
    const shutdownPromise = this._shutdownChildOnce(child).finally(() => {
      this.shutdownChildPromises.delete(child);
    });
    this.shutdownChildPromises.set(child, shutdownPromise);
    return shutdownPromise;
  }

  async _shutdownChildOnce(child) {
    const childState = this._trackChild(child);
    if (childState.exited) return childState.exit;
    tryProcessTreeTerminate(this.processTreeTerminator, child.pid, { force: false, signal: 'SIGTERM' });
    tryKillChild(child, 'SIGTERM');
    await waitForChildExit(childState, this.gracefulShutdownMs, this.delayFn);
    if (!childState.exited) {
      const terminated = tryProcessTreeTerminate(this.processTreeTerminator, child.pid, { force: true, signal: 'SIGKILL' });
      if (!terminated) tryKillChild(child, 'SIGKILL');
      await waitForChildExit(childState, this.hardKillGraceMs, this.delayFn);
    }
    return childState.exit;
  }
}

function delay(ms) {
  let timer = null;
  let settled = false;
  const promise = new Promise((resolve) => {
    timer = setTimeout(() => {
      settled = true;
      timer = null;
      resolve();
    }, Math.max(0, Number(ms) || 0));
  });
  promise.cancel = () => {
    if (settled || timer === null) return;
    clearTimeout(timer);
    timer = null;
    settled = true;
  };
  return promise;
}

function createCancelableDelay(delayFn, ms) {
  const delayPromise = delayFn(ms);
  return {
    promise: Promise.resolve(delayPromise),
    cancel: () => cancelPromiseDelay(delayPromise)
  };
}

function cancelPromiseDelay(delayPromise) {
  const cancel = delayPromise?.cancel || delayPromise?.clear;
  if (typeof cancel !== 'function') return;
  try {
    cancel.call(delayPromise);
  } catch (_) {
    // Best-effort cleanup: cancellation must not replace the original race result.
  }
}

function findAvailableLoopbackPort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    let settled = false;
    const finish = (error, port) => {
      if (settled) return;
      settled = true;
      if (error) reject(error);
      else resolve(port);
    };
    server.on('error', (error) => finish(error));
    server.listen(0, '127.0.0.1', () => {
      const address = server.address();
      const port = address && typeof address === 'object' ? address.port : 0;
      server.close((error) => {
        if (error) finish(error);
        else if (isUsablePort(port)) finish(null, port);
        else finish(new Error(`invalid loopback port: ${port}`));
      });
    });
    server.unref?.();
  });
}

function defaultProcessTreeTerminator(pid, { force = false, platform = process.platform, spawnSyncFn = spawnSync } = {}) {
  if (platform !== 'win32' || !pid) return false;
  const args = ['/PID', String(pid), '/T'];
  if (force) args.push('/F');
  const result = spawnSyncFn('taskkill', args, {
    windowsHide: true,
    stdio: 'ignore'
  });
  return result?.status === 0;
}

function tryProcessTreeTerminate(processTreeTerminator, pid, options) {
  if (!processTreeTerminator || !pid) return false;
  try {
    return processTreeTerminator(pid, options) === true;
  } catch (_) {
    return false;
  }
}

function tryKillChild(child, signal) {
  if (typeof child?.kill !== 'function') return false;
  try {
    return child.kill(signal) === true;
  } catch (_) {
    return false;
  }
}

function waitForChildExit(childState, timeoutMs, delayFn) {
  if (childState.exited) return Promise.resolve(childState.exit);
  const timeoutDelay = createCancelableDelay(delayFn, timeoutMs);
  return Promise.race([
    childState.promise,
    timeoutDelay.promise
  ]).finally(() => {
    timeoutDelay.cancel();
  });
}

function isUsablePort(port) {
  const numericPort = Number(port);
  return Number.isInteger(numericPort) && numericPort > 0 && numericPort <= 65535;
}

function normalizeNumber(value, fallback, min) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.max(min, Math.floor(number));
}

function normalizeExternalUrl(value) {
  const text = String(value || '').trim();
  return text || null;
}

function throwIfStopped(startGeneration, currentGeneration, phase) {
  if (startGeneration === currentGeneration) return;
  throw createLifecycleError('OpenCode server lifecycle operation was stopped', {
    code: 'OPENCODE_SERVER_STOPPED',
    details: { phase }
  });
}

function createLifecycleError(message, { code, details = {}, cause } = {}) {
  const error = new Error(limitString(message, MAX_DETAIL_STRING_LENGTH), cause ? { cause } : undefined);
  error.code = code;
  error.details = sanitizeDetails(details);
  return error;
}

function ensureLifecycleError(error, fallbackCode) {
  if (error?.code && String(error.code).startsWith('OPENCODE_SERVER_')) return error;
  return createLifecycleError(error?.message || 'OpenCode managed server failed', {
    code: fallbackCode,
    details: { cause: errorDetails(error) },
    cause: error
  });
}

function errorDetails(error) {
  return sanitizeDetails({
    code: error?.code || error?.name || 'ERROR',
    message: error?.message || String(error || 'unknown error'),
    details: error?.details
  });
}

function sanitizeDetails(value, depth = 0, seen = new Set()) {
  if (value === null || value === undefined) return value;
  if (typeof value === 'string') return limitString(value, MAX_DETAIL_STRING_LENGTH);
  if (typeof value === 'number' || typeof value === 'boolean') return value;
  if (typeof value === 'bigint') return limitString(String(value), MAX_DETAIL_STRING_LENGTH);
  if (typeof value !== 'object') return limitString(String(value), MAX_DETAIL_STRING_LENGTH);
  if (depth >= MAX_DETAIL_DEPTH) return '[Truncated]';
  if (seen.has(value)) return '[Circular]';
  seen.add(value);
  if (Array.isArray(value)) {
    const items = value.slice(0, MAX_DETAIL_ARRAY_ITEMS).map((item) => sanitizeDetails(item, depth + 1, seen));
    if (value.length > MAX_DETAIL_ARRAY_ITEMS) items.push('[Truncated]');
    seen.delete(value);
    return items;
  }
  const result = {};
  for (const key of Object.keys(value).slice(0, MAX_DETAIL_KEYS)) {
    if (key === '__proto__' || key === 'constructor' || key === 'prototype') continue;
    result[key] = sanitizeDetails(value[key], depth + 1, seen);
  }
  if (Object.keys(value).length > MAX_DETAIL_KEYS) result.truncated = true;
  seen.delete(value);
  return result;
}

function limitString(value, maxLength) {
  const text = String(value || '');
  if (text.length <= maxLength) return text;
  const suffix = '...[truncated]';
  return `${text.slice(0, Math.max(0, maxLength - suffix.length))}${suffix}`;
}

module.exports = {
  OpenCodeServerLifecycle,
  delay,
  defaultProcessTreeTerminator,
  findAvailableLoopbackPort
};
