'use strict';

const { CodexAppServerClient } = require('./client');

const DEFAULT_DISCOVERY_LIMIT = 2;
const DEFAULT_CONVERSATION_LIMIT = Math.max(1, Number(process.env.CODEX_APP_SERVER_MAX_PROCESSES) || 4);
const DEFAULT_MUTATION_LIMIT = 1;
const DEFAULT_POOL_LIMITS = Object.freeze({
  discovery: DEFAULT_DISCOVERY_LIMIT,
  conversation: DEFAULT_CONVERSATION_LIMIT,
  mutation: DEFAULT_MUTATION_LIMIT
});

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
    return resolved.callback(wrapClientWithMetrics(entry.client, this.metrics, 'discovery', this.now));
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
      return await callback(wrapClientWithMetrics(scoped.client, this.metrics, 'conversation', this.now));
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
      return await callback(wrapClientWithMetrics(scoped.client, this.metrics, 'mutation', this.now));
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
    return sanitizeMetrics(this.metrics);
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

function wrapClientWithMetrics(client, metrics, pool, now) {
  if (!client || client.__codexAppServerMetricsWrapped) return client;
  const proxy = new Proxy(client, {
    get(target, property, receiver) {
      const value = Reflect.get(target, property, receiver);
      if (typeof value !== 'function') return value;
      return async (...args) => {
        const method = inferClientMethod(property, args);
        if (method === 'initialize') return value.apply(target, args);
        const startedAt = now();
        try {
          const result = await value.apply(target, args);
          recordMethodLatency(metrics, method, pool, now() - startedAt);
          return result;
        } catch (error) {
          recordMethodLatency(metrics, method, pool, now() - startedAt);
          recordMethodError(metrics, method, pool);
          throw error;
        }
      };
    }
  });
  Object.defineProperty(proxy, '__codexAppServerMetricsWrapped', {
    value: true,
    enumerable: false
  });
  return proxy;
}

function inferClientMethod(property, args) {
  if (property === 'sendRequest' && typeof args[0] === 'string') return sanitizeMethodName(args[0]);
  return sanitizeMethodName(CLIENT_METHOD_TO_APP_SERVER_METHOD[property] || property);
}

function recordMethodLatency(metrics, method, pool, latencyMs) {
  metrics.methodLatencyMs.push({
    name: 'codex_app_server_method_latency_ms',
    method,
    pool,
    value: Math.max(0, Number(latencyMs) || 0)
  });
}

function recordMethodError(metrics, method, pool) {
  const sanitizedPool = sanitizeLabelValue(pool);
  const sanitizedMethod = sanitizeMethodName(method);
  if (!metrics.methodErrorTotal[sanitizedPool]) metrics.methodErrorTotal[sanitizedPool] = {};
  metrics.methodErrorTotal[sanitizedPool][sanitizedMethod] = (metrics.methodErrorTotal[sanitizedPool][sanitizedMethod] || 0) + 1;
}

function sanitizeMetrics(metrics) {
  const snapshot = JSON.parse(JSON.stringify(metrics));
  sanitizeMetricLatencyEntries(snapshot);
  sanitizeProcessMetricMaps(snapshot);
  normalizeMetricErrorTotals(snapshot);
  const metricSamples = exportMetricSamples(snapshot);
  return {
    ...snapshot,
    exported: metricSamples,
    metricSamples,
    metricNames: Array.from(new Set(metricSamples.map((sample) => sample.name))).sort()
  };
}

function sanitizeMetricLatencyEntries(metrics) {
  metrics.methodLatencyMs = (metrics.methodLatencyMs || []).map((latency) => ({
    name: 'codex_app_server_method_latency_ms',
    method: sanitizeMethodName(latency?.method),
    pool: sanitizeLabelValue(latency?.pool),
    value: Math.max(0, Number(latency?.value) || 0)
  }));
}

function sanitizeProcessMetricMaps(metrics) {
  metrics.processSpawnTotal = sanitizePoolValueMap(metrics.processSpawnTotal);
  metrics.processEvictionTotal = sanitizePoolReasonMap(metrics.processEvictionTotal);
}

function sanitizePoolValueMap(value) {
  const sanitized = {};
  for (const [pool, count] of Object.entries(value || {})) {
    sanitized[sanitizeLabelValue(pool)] = Number(count) || 0;
  }
  return sanitized;
}

function sanitizePoolReasonMap(value) {
  const sanitized = {};
  for (const [pool, reasons] of Object.entries(value || {})) {
    const safePool = sanitizeLabelValue(pool);
    sanitized[safePool] = {};
    for (const [reason, count] of Object.entries(reasons || {})) {
      sanitized[safePool][sanitizeLabelValue(reason)] = Number(count) || 0;
    }
  }
  return sanitized;
}

function normalizeMetricErrorTotals(metrics) {
  const normalized = {};
  for (const [poolOrKey, value] of Object.entries(metrics.methodErrorTotal || {})) {
    if (value && typeof value === 'object' && !Array.isArray(value)) {
      const pool = sanitizeLabelValue(poolOrKey);
      if (!normalized[pool]) normalized[pool] = {};
      for (const [method, count] of Object.entries(value)) {
        normalized[pool][sanitizeMethodName(method)] = Number(count) || 0;
      }
      continue;
    }
    const [pool, method] = splitMetricKey(poolOrKey);
    if (!normalized[pool]) normalized[pool] = {};
    normalized[pool][method] = (normalized[pool][method] || 0) + (Number(value) || 0);
  }
  metrics.methodErrorTotal = normalized;
}

function exportMetricSamples(metrics) {
  const samples = [];
  for (const [pool, value] of Object.entries(metrics.processSpawnTotal || {})) {
    samples.push(metricSample('codex_app_server_process_spawn_total', { pool }, value));
  }
  samples.push(metricSample('codex_app_server_discovery_cache_hit_total', {}, metrics.discoveryCacheHitTotal || 0));
  samples.push(metricSample('codex_app_server_discovery_cache_miss_total', {}, metrics.discoveryCacheMissTotal || 0));
  for (const [pool, reasons] of Object.entries(metrics.processEvictionTotal || {})) {
    for (const [reason, value] of Object.entries(reasons || {})) {
      samples.push(metricSample('codex_app_server_process_eviction_total', { pool, reason }, value));
    }
  }
  for (const latency of metrics.methodLatencyMs || []) {
    samples.push(metricSample('codex_app_server_method_latency_ms', {
      method: sanitizeMethodName(latency.method),
      pool: sanitizeLabelValue(latency.pool)
    }, latency.value));
  }
  for (const [pool, methods] of Object.entries(metrics.methodErrorTotal || {})) {
    if (methods && typeof methods === 'object' && !Array.isArray(methods)) {
      for (const [method, value] of Object.entries(methods)) {
        samples.push(metricSample('codex_app_server_method_error_total', { method, pool }, value));
      }
      continue;
    }
    const [legacyPool, method] = splitMetricKey(pool);
    samples.push(metricSample('codex_app_server_method_error_total', { method, pool: legacyPool }, methods));
  }
  return samples;
}

function metricSample(name, labels, value) {
  return {
    name,
    labels: Object.fromEntries(Object.entries(labels).map(([key, item]) => [
      key,
      key === 'method' ? sanitizeMethodName(item) : sanitizeLabelValue(item)
    ])),
    value: Number(value) || 0
  };
}

function splitMetricKey(key) {
  const delimiter = String(key || '').indexOf(':');
  if (delimiter < 0) return ['unknown', sanitizeMethodName(key)];
  return [
    sanitizeLabelValue(String(key).slice(0, delimiter)),
    sanitizeMethodName(String(key).slice(delimiter + 1))
  ];
}

function sanitizeMethodName(value) {
  const normalized = String(value || 'unknown');
  return /^[a-zA-Z0-9/_-]{1,120}$/.test(normalized) ? normalized : 'unknown';
}

function sanitizeLabelValue(value) {
  const normalized = String(value || 'unknown');
  return /^[a-zA-Z0-9_-]{1,80}$/.test(normalized) ? normalized : 'unknown';
}

const CLIENT_METHOD_TO_APP_SERVER_METHOD = Object.freeze({
  listModels: 'model/list',
  listThreads: 'thread/list',
  listLoadedThreads: 'thread/loaded/list',
  readConfig: 'config/read',
  readConfigRequirements: 'configRequirements/read',
  listMcpServerStatus: 'mcpServerStatus/list',
  readMcpServerResource: 'mcpServer/resource/read',
  listSkills: 'skills/list',
  listPlugins: 'plugin/list',
  readPlugin: 'plugin/read',
  readPluginSkill: 'plugin/skill/read',
  listPluginShares: 'plugin/share/list',
  listApps: 'app/list',
  listHooks: 'hooks/list',
  listCollaborationModes: 'collaborationMode/list',
  listExperimentalFeatures: 'experimentalFeature/list',
  detectExternalAgentConfig: 'externalAgentConfig/detect',
  listPermissionProfiles: 'permissionProfile/list',
  readModelProviderCapabilities: 'modelProvider/capabilities/read',
  readWindowsSandboxReadiness: 'windowsSandbox/readiness',
  readAccount: 'account/read',
  readAccountRateLimits: 'account/rateLimits/read',
  getFileMetadata: 'fs/getMetadata',
  readDirectory: 'fs/readDirectory',
  readFile: 'fs/readFile',
  watchFileSystem: 'fs/watch',
  unwatchFileSystem: 'fs/unwatch',
  copyFile: 'fs/copy',
  createDirectory: 'fs/createDirectory',
  removeFile: 'fs/remove',
  writeFile: 'fs/writeFile',
  spawnProcess: 'process/spawn',
  killProcess: 'process/kill',
  executeCommand: 'command/exec',
  writeConfigValue: 'config/value/write',
  writeConfigBatch: 'config/batchWrite',
  reloadMcpServerConfig: 'config/mcpServer/reload',
  addEnvironment: 'environment/add',
  installPlugin: 'plugin/install',
  uninstallPlugin: 'plugin/uninstall',
  addMarketplace: 'marketplace/add',
  removeMarketplace: 'marketplace/remove',
  upgradeMarketplace: 'marketplace/upgrade',
  writeSkillsConfig: 'skills/config/write',
  setSkillsExtraRoots: 'skills/extraRoots/set',
  readRemoteControlStatus: 'remoteControl/status/read',
  listRemoteControlClients: 'remoteControl/client/list',
  enableRemoteControl: 'remoteControl/enable',
  disableRemoteControl: 'remoteControl/disable',
  startRemoteControlPairing: 'remoteControl/pairing/start',
  revokeRemoteControlClient: 'remoteControl/client/revoke',
  startAccountLogin: 'account/login/start',
  cancelAccountLogin: 'account/login/cancel',
  logoutAccount: 'account/logout',
  sendAddCreditsNudgeEmail: 'account/sendAddCreditsNudgeEmail',
  startMcpServerOauthLogin: 'mcpServer/oauth/login',
  readThread: 'thread/read',
  searchThreads: 'thread/search',
  fuzzyFileSearch: 'fuzzyFileSearch',
  startFuzzyFileSearchSession: 'fuzzyFileSearch/sessionStart',
  updateFuzzyFileSearchSession: 'fuzzyFileSearch/sessionUpdate',
  stopFuzzyFileSearchSession: 'fuzzyFileSearch/sessionStop',
  startReview: 'review/start',
  generateAttestation: 'attestation/generate',
  listRealtimeVoices: 'thread/realtime/listVoices',
  listThreadTurns: 'thread/turns/list',
  listThreadTurnItems: 'thread/turns/items/list',
  getThreadGoal: 'thread/goal/get',
  forkThread: 'thread/fork',
  archiveThread: 'thread/archive',
  unarchiveThread: 'thread/unarchive',
  rollbackThread: 'thread/rollback',
  updateThreadMetadata: 'thread/metadata/update',
  setThreadName: 'thread/name/set',
  updateThreadSettings: 'thread/settings/update',
  setThreadMemoryMode: 'thread/memoryMode/set',
  setThreadGoal: 'thread/goal/set',
  clearThreadGoal: 'thread/goal/clear',
  startThread: 'thread/start',
  resumeThread: 'thread/resume',
  startTurn: 'turn/start',
  interruptTurn: 'turn/interrupt'
});

module.exports = {
  CodexAppServerBusyError,
  DEFAULT_POOL_LIMITS,
  CodexAppServerService
};
