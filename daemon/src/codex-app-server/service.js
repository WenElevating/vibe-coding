'use strict';

const { CodexAppServerClient } = require('./client');

const DEFAULT_DISCOVERY_LIMIT = 2;
const DEFAULT_CONVERSATION_LIMIT = Math.max(1, Number(process.env.CODEX_APP_SERVER_MAX_PROCESSES) || 4);
const DEFAULT_MUTATION_LIMIT = 1;

class CodexAppServerBusyError extends Error {
  constructor(message, { pool, key } = {}) {
    super(message || 'Codex app-server process pool is busy');
    this.name = 'CodexAppServerBusyError';
    this.code = 'CODEX_APP_SERVER_BUSY';
    this.status = 503;
    this.pool = pool;
    this.key = key;
  }
}

class CodexAppServerService {
  constructor({
    lifecycle = null,
    ttlMs = 30000,
    initializeTimeoutMs = 10000,
    requestTimeoutMs = 30000,
    poolLimits = {},
    now = () => Date.now(),
    metrics = null
  } = {}) {
    this.lifecycle = lifecycle;
    this.ttlMs = Math.max(0, Number(ttlMs) || 0);
    this.initializeTimeoutMs = Math.max(1, Number(initializeTimeoutMs) || 10000);
    this.requestTimeoutMs = Math.max(1, Number(requestTimeoutMs) || 30000);
    this.poolLimits = {
      discovery: normalizeLimit(poolLimits.discovery, DEFAULT_DISCOVERY_LIMIT),
      conversation: normalizeLimit(poolLimits.conversation, DEFAULT_CONVERSATION_LIMIT),
      mutation: normalizeLimit(poolLimits.mutation, DEFAULT_MUTATION_LIMIT)
    };
    this.now = now;
    this.metrics = ensureMetrics(metrics);
    this.discovery = new Map();
    this.discoveryCreating = new Map();
    this.activeConversationCount = 0;
    this.activeMutationCounts = new Map();
  }

  async withDiscoveryClient(options, callback) {
    const resolved = normalizeOptionsAndCallback(options, callback);
    const scope = {
      ...resolved.options,
      pool: 'discovery',
      invocationKey: resolved.options.invocationKey || 'default'
    };
    const entry = await this.getDiscoveryEntry(scope);
    return resolved.callback(entry.client);
  }

  async withWorkspaceClient(workspace, callback) {
    return this.withDiscoveryClient({
      invocationKey: workspaceDiscoveryKey(workspace),
      workspaceId: workspace?.id || workspace?.workspaceId || null,
      workspacePath: workspace?.workspacePath || workspace?.path || null
    }, callback);
  }

  async withConversationClient(options, callback) {
    const scope = {
      ...options,
      pool: 'conversation'
    };
    this.activeConversationCount += 1;
    let scoped = null;
    try {
      scoped = await this.createScopedClient(scope);
      return await callback(scoped.client);
    } finally {
      this.activeConversationCount -= 1;
      if (scoped) await scoped.shutdown();
    }
  }

  async withMutationClient(options, callback) {
    const workspaceKey = mutationWorkspaceKey(options);
    const scope = {
      ...options,
      pool: 'mutation',
      workspaceKey
    };
    const activeCount = this.activeMutationCounts.get(workspaceKey) || 0;
    if (activeCount >= this.poolLimits.mutation) {
      throw new CodexAppServerBusyError('Codex app-server mutation pool is busy', {
        pool: 'mutation',
        key: workspaceKey
      });
    }
    this.activeMutationCounts.set(workspaceKey, activeCount + 1);
    let scoped = null;
    try {
      scoped = await this.createScopedClient(scope);
      return await callback(scoped.client);
    } finally {
      decrementMapCount(this.activeMutationCounts, workspaceKey);
      if (scoped) await scoped.shutdown();
    }
  }

  async getDiscoveryEntry(scope) {
    const key = scope.invocationKey || 'default';
    const cached = this.discovery.get(key);
    if (cached && this.isDiscoveryEntryHealthy(cached)) {
      this.metrics.discoveryCacheHitTotal += 1;
      cached.lastUsedAt = this.now();
      return cached;
    }
    if (cached) {
      await this.evictDiscoveryEntry(key, cached, 'expired');
    }
    this.metrics.discoveryCacheMissTotal += 1;
    if (this.discoveryCreating.has(key)) return this.discoveryCreating.get(key);
    if (this.discoveryPoolSize() >= this.poolLimits.discovery) {
      throw new CodexAppServerBusyError('Codex app-server discovery pool is busy', {
        pool: 'discovery',
        key
      });
    }
    const creating = this.createDiscoveryEntry({ ...scope, invocationKey: key })
      .finally(() => this.discoveryCreating.delete(key));
    this.discoveryCreating.set(key, creating);
    return creating;
  }

  async createDiscoveryEntry(scope) {
    const scoped = await this.createScopedClient(scope);
    const key = scope.invocationKey || 'default';
    const entry = {
      ...scoped,
      createdAt: this.now(),
      lastUsedAt: this.now()
    };
    this.discovery.set(key, entry);
    attachTransportClose(entry.handle?.transport, () => {
      const current = this.discovery.get(key);
      if (current === entry) {
        this.discovery.delete(key);
        this.metrics.processEvictionTotal.discovery.transport_closed += 1;
      }
    });
    return entry;
  }

  discoveryPoolSize() {
    return new Set([
      ...this.discovery.keys(),
      ...this.discoveryCreating.keys()
    ]).size;
  }

  isDiscoveryEntryHealthy(entry) {
    if (!entry || !entry.client || entry.client.invalidated) return false;
    if (this.ttlMs <= 0) return false;
    return this.now() - entry.createdAt <= this.ttlMs;
  }

  async evictDiscoveryEntry(key, entry, reason) {
    if (this.discovery.get(key) === entry) this.discovery.delete(key);
    incrementEvictionMetric(this.metrics, 'discovery', reason);
    await entry.shutdown();
  }

  async createScopedClient(scope = {}) {
    const pool = scope.pool || 'conversation';
    if (pool === 'conversation' && this.activeConversationCount > this.poolLimits.conversation) {
      throw new CodexAppServerBusyError('Codex app-server conversation pool is busy', {
        pool,
        key: scope.threadId || scope.workspaceId || 'default'
      });
    }
    if (pool === 'discovery' && this.poolLimits.discovery <= 0) {
      throw new CodexAppServerBusyError('Codex app-server discovery pool is busy', {
        pool,
        key: scope.invocationKey || 'default'
      });
    }
    if (!this.lifecycle || typeof this.lifecycle.spawn !== 'function') {
      const error = new Error('Codex app-server lifecycle is not configured');
      error.code = 'CODEX_APP_SERVER_LIFECYCLE_MISSING';
      error.status = 503;
      throw error;
    }
    const handle = this.lifecycle.spawn(scope);
    this.metrics.processSpawnTotal[pool] = (this.metrics.processSpawnTotal[pool] || 0) + 1;
    const client = new CodexAppServerClient({
      transport: handle.transport,
      initializeTimeoutMs: this.initializeTimeoutMs,
      requestTimeoutMs: this.requestTimeoutMs
    });
    try {
      await client.initialize();
    } catch (error) {
      if (handle && typeof handle.shutdown === 'function') {
        await handle.shutdown();
      }
      throw error;
    }
    let shutdownCalled = false;
    return {
      pool,
      scope,
      handle,
      client,
      shutdown: async () => {
        if (shutdownCalled) return;
        shutdownCalled = true;
        if (handle && typeof handle.shutdown === 'function') {
          await handle.shutdown();
        }
      }
    };
  }

  snapshotMetrics() {
    return JSON.parse(JSON.stringify(this.metrics));
  }
}

function normalizeOptionsAndCallback(options, callback) {
  if (typeof options === 'function') {
    return { options: {}, callback: options };
  }
  return { options: options || {}, callback };
}

function normalizeLimit(value, fallback) {
  if (value === undefined || value === null || value === '') return fallback;
  const numeric = Number(value);
  if (!Number.isFinite(numeric) || numeric < 0) return fallback;
  return Math.floor(numeric);
}

function mutationWorkspaceKey(options = {}) {
  return options.workspaceId ||
    options.workspace?.id ||
    options.workspace?.workspaceId ||
    options.workspacePath ||
    options.workspace?.workspacePath ||
    'default';
}

function workspaceDiscoveryKey(workspace = {}) {
  return workspace.id ||
    workspace.workspaceId ||
    workspace.workspacePath ||
    workspace.path ||
    'default';
}

function decrementMapCount(map, key) {
  const next = (map.get(key) || 0) - 1;
  if (next <= 0) map.delete(key);
  else map.set(key, next);
}

function attachTransportClose(transport, onClose) {
  if (!transport || typeof transport.on !== 'function') return;
  let called = false;
  const handler = () => {
    if (called) return;
    called = true;
    onClose();
  };
  transport.on('closed', handler);
  transport.on('close', handler);
}

function createMetrics() {
  return {
    processSpawnTotal: {
      discovery: 0,
      conversation: 0,
      mutation: 0
    },
    discoveryCacheHitTotal: 0,
    discoveryCacheMissTotal: 0,
    processEvictionTotal: {
      discovery: {
        expired: 0,
        transport_closed: 0
      },
      conversation: {},
      mutation: {}
    },
    methodLatencyMs: [],
    methodErrorTotal: {}
  };
}

function ensureMetrics(metrics) {
  if (!metrics) return createMetrics();
  if (!metrics.processSpawnTotal) metrics.processSpawnTotal = { discovery: 0, conversation: 0, mutation: 0 };
  if (typeof metrics.discoveryCacheHitTotal !== 'number') metrics.discoveryCacheHitTotal = 0;
  if (typeof metrics.discoveryCacheMissTotal !== 'number') metrics.discoveryCacheMissTotal = 0;
  if (!metrics.processEvictionTotal) {
    metrics.processEvictionTotal = {
      discovery: { expired: 0, transport_closed: 0 },
      conversation: {},
      mutation: {}
    };
  }
  if (!metrics.processEvictionTotal.discovery) metrics.processEvictionTotal.discovery = { expired: 0, transport_closed: 0 };
  if (typeof metrics.processEvictionTotal.discovery.expired !== 'number') metrics.processEvictionTotal.discovery.expired = 0;
  if (typeof metrics.processEvictionTotal.discovery.transport_closed !== 'number') metrics.processEvictionTotal.discovery.transport_closed = 0;
  if (!metrics.processEvictionTotal.conversation) metrics.processEvictionTotal.conversation = {};
  if (!metrics.processEvictionTotal.mutation) metrics.processEvictionTotal.mutation = {};
  if (!Array.isArray(metrics.methodLatencyMs)) metrics.methodLatencyMs = [];
  if (!metrics.methodErrorTotal) metrics.methodErrorTotal = {};
  return metrics;
}

function incrementEvictionMetric(metrics, pool, reason) {
  if (!metrics.processEvictionTotal[pool]) metrics.processEvictionTotal[pool] = {};
  metrics.processEvictionTotal[pool][reason] = (metrics.processEvictionTotal[pool][reason] || 0) + 1;
}

module.exports = {
  CodexAppServerBusyError,
  CodexAppServerService
};
