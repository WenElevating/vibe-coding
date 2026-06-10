'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

const { AuthManager } = require('./auth');
const { WorkspaceRegistry } = require('./workspace');
const { EventStore } = require('./event-store');
const { ConversationEventStore } = require('./conversation-event-store');
const { AppSqliteStore, defaultAppDbPath } = require('./app-sqlite-store');
const { AuditLog } = require('./audit');
const { ClaudeAdapter } = require('./claude-adapter');
const { ClaudeConversationAdapter } = require('./claude-conversation-adapter');
const { CodexConversationAdapter } = require('./codex-conversation-adapter');
const { CodexAppServerConversationAdapter } = require('./codex-app-server-conversation-adapter');
const { buildCodexAppServerAvailability } = require('./codex-app-server-availability');
const { CodexAppServerLifecycle } = require('./codex-app-server-lifecycle');
const { CodexAppServerService, DEFAULT_POOL_LIMITS } = require('./codex-app-server/service');
const { createCodexAdapter } = require('./jsonline-adapter');
const { CodexAppServerListingAdapter } = require('./codex-app-server-listing-adapter');
const { OpenCodeAdapter } = require('./opencode-adapter');
const { OpenCodeConversationAdapter } = require('./opencode-conversation-adapter');
const { OpenCodeServerLifecycle } = require('./opencode-server-lifecycle');
const { SyntheticAdapter } = require('./synthetic-adapter');
const { AdapterRegistry } = require('./adapter-registry');
const { RunManager } = require('./run-manager');
const { ConversationManager } = require('./conversation-manager');
const { AttachmentScratchStore } = require('./attachment-scratch-store');
const { conversationStatuses } = require('./conversation-protocol');
const { RunQueue } = require('./run-queue');
const { ShortcutStore } = require('./shortcuts');
const { CommandTemplateStore } = require('./command-templates');
const { SlashCommandCatalog, ClaudeSlashCommandDiscoverer } = require('./slash-command-catalog');
const { GitService } = require('./git-service');
const { WorkspaceInspector } = require('./workspace-inspector');
const { MigrationService } = require('./migrations');
const { DiagnosticsService } = require('./diagnostics');
const { DiagnosticBundleService } = require('./diagnostic-bundle');
const { versionInfo } = require('./version');
const { createServer } = require('./server');
const { createPerfConfig } = require('./perf-config');
const { PerfSqliteStore, defaultPerfDbPath } = require('./perf-sqlite-store');
const { PerfTracer } = require('./perf-tracer');
const { AsrModelAsset } = require('./asr-model-asset');
const { AppUpdateService } = require('./app-update-service');
const { NotificationHub } = require('./notification-hub');
const { createWindowsSleepInhibitor } = require('./windows-sleep-inhibitor');
const { resolveCliInvocation } = require('./cli-resolver');
const { CodexAppServerClient } = require('./codex-app-server/client');
const { normalizeCodexAppServerModelCapability } = require('./codex-app-server/models');

function loadOrCreateSecrets(dbPath) {
  const secretsPath = path.join(path.dirname(dbPath), '.daemon-secrets.json');
  try {
    const raw = fs.readFileSync(secretsPath, 'utf8');
    const parsed = JSON.parse(raw);
    if (parsed.authTokenSecret && parsed.deviceIdPepper) return parsed;
  } catch { /* file missing or corrupt — generate fresh */ }
  const secrets = {
    authTokenSecret: crypto.randomBytes(32).toString('base64url'),
    deviceIdPepper: crypto.randomBytes(32).toString('base64url'),
  };
  fs.mkdirSync(path.dirname(secretsPath), { recursive: true });
  fs.writeFileSync(secretsPath, JSON.stringify(secrets, null, 2), { mode: 0o600 });
  return secrets;
}

function createApp({
  host = process.env.DAEMON_HOST || '127.0.0.1',
  port = Number(process.env.PORT || 4317),
  mode = process.env.DAEMON_MODE || 'dev',
  claudeCommand = process.env.CLAUDE_COMMAND || 'claude',
  codexCommand = process.env.CODEX_COMMAND || 'codex',
  codexToolTimeoutSec = process.env.CODEX_TOOL_TIMEOUT_SEC,
  codexEnabled = process.env.CODEX_ENABLED === '1',
  codexAppServerEnabled = parseBooleanEnv(process.env.CODEX_APP_SERVER_ENABLED, true),
  codexAppServerTransport = process.env.CODEX_APP_SERVER_TRANSPORT || 'auto',
  codexAppServerExperimentalApi = parseBooleanEnv(process.env.CODEX_APP_SERVER_EXPERIMENTAL_API, true),
  codexAppServerRolloutPercent = process.env.CODEX_APP_SERVER_ROLLOUT_PERCENT || '100',
  codexAppServerMaxProcesses = process.env.CODEX_APP_SERVER_MAX_PROCESSES,
  codexAppServerProbe = undefined,
  codexAppServerModelLister = undefined,
  codexAppServerService = undefined,
  codexAppServerApprovalPolicy = undefined,
  opencodeCommand = process.env.OPENCODE_COMMAND || 'opencode',
  opencodeServerUrl = process.env.OPENCODE_SERVER_URL || '',
  opencodeServerLifecycle = null,
  devAdapters = process.env.DEV_ADAPTERS === '1',
  conversationAdapters = null,
  conversationDbPath = process.env.CONVERSATION_DB_PATH,
  appDbPath = process.env.APP_DB_PATH || conversationDbPath || defaultAppDbPath(),
  accessTokenTtlMs = undefined,
  refreshTokenTtlMs = undefined,
  asrModelAsset = new AsrModelAsset(),
  androidUpdateArtifactDir = process.env.ANDROID_UPDATE_ARTIFACT_DIR,
  perfEnv = process.env,
  perfDbPath = process.env.PERF_DB_PATH || defaultPerfDbPath()
} = {}) {
  const fileSecrets = loadOrCreateSecrets(appDbPath);
  const authTokenSecret = process.env.AUTH_TOKEN_SECRET || fileSecrets.authTokenSecret;
  const deviceIdPepper = process.env.DEVICE_ID_PEPPER || fileSecrets.deviceIdPepper;
  const appSqliteStore = new AppSqliteStore({ dbPath: appDbPath });
  const auth = new AuthManager({ store: appSqliteStore, authTokenSecret, deviceIdPepper, accessTokenTtlMs, refreshTokenTtlMs });
  const workspaces = new WorkspaceRegistry({ store: appSqliteStore });
  const defaultDevice = { id: 'daemon-default', allowedWorkspaceIds: new Set() };
  workspaces.seedDefault({ id: 'default', name: 'Current Project', workspacePath: process.cwd() }, defaultDevice);
  const eventStore = new EventStore();
  const conversationSqliteStore = appSqliteStore;
  const conversationEventStore = new ConversationEventStore({ persistentStore: conversationSqliteStore });
  const perfConfig = createPerfConfig({ env: perfEnv });
  const perfStore = new PerfSqliteStore({ dbPath: perfDbPath, config: perfConfig });
  const perfTracer = new PerfTracer({ enabled: perfConfig.enabled, writer: perfStore });
  conversationEventStore.perfTracer = perfTracer;
  const auditLog = new AuditLog();
  const codexAppServerRuntime = buildCodexAppServerRuntimeConfig({
    enabled: codexAppServerEnabled,
    transport: codexAppServerTransport,
    experimentalApi: codexAppServerExperimentalApi,
    rolloutPercent: codexAppServerRolloutPercent
  });
  const codexAppServerRouteEnabled = codexAppServerRuntime.availability.enabled === true;
  const codexAppServerAvailabilityState = { current: codexAppServerRuntime.availability };
  const codexAppServerMetrics = createCodexAppServerMetrics();
  const codexAppServerLifecycleMaxProcesses = resolveCodexAppServerLifecycleMaxProcesses(codexAppServerMaxProcesses);
  const codexAppServerLifecycle = codexAppServerRouteEnabled ? createCodexAppServerLifecycle({
    codexCommand,
    maxProcesses: codexAppServerLifecycleMaxProcesses,
    metrics: codexAppServerMetrics
  }) : null;
  const effectiveOpenCodeServerLifecycle = opencodeServerLifecycle || new OpenCodeServerLifecycle({
    externalUrl: opencodeServerUrl || '',
    command: opencodeCommand
  });
  const adapters = [
    new ClaudeAdapter({ command: claudeCommand }),
    createCodexAdapter({ command: codexCommand, explicitEnabled: codexEnabled }),
    new OpenCodeAdapter({ serverUrl: opencodeServerUrl, lifecycle: effectiveOpenCodeServerLifecycle })
  ];
  if (codexAppServerRouteEnabled) {
    adapters.push(new CodexAppServerListingAdapter({
      availabilityState: codexAppServerAvailabilityState,
      metrics: codexAppServerMetrics,
      probe: codexAppServerProbe === false
        ? null
        : typeof codexAppServerProbe === 'function'
        ? codexAppServerProbe
        : codexAppServerRuntime.shouldProbe
        ? createCodexAppServerProbe({
          lifecycle: createCodexAppServerLifecycle({
            codexCommand,
            maxProcesses: 1,
            metrics: codexAppServerMetrics,
            processTreeTerminator: null
          }),
          metrics: codexAppServerMetrics
        })
        : null,
      modelLister: codexAppServerModelLister === false
        ? null
        : typeof codexAppServerModelLister === 'function'
        ? codexAppServerModelLister
        : codexAppServerRuntime.shouldProbe
        ? createCodexAppServerModelLister({
          lifecycle: createCodexAppServerLifecycle({
            codexCommand,
            maxProcesses: 1,
            metrics: codexAppServerMetrics,
            processTreeTerminator: null
          })
        })
        : null
    }));
  }
  if (devAdapters) adapters.push(new SyntheticAdapter(), new SyntheticAdapter({ name: 'synthetic-text' }), new SyntheticAdapter({ name: 'synthetic-error' }), new SyntheticAdapter({ name: 'synthetic-slow', delayMs: 1000 }));
  const adapterRegistry = new AdapterRegistry(adapters);
  const shortcuts = new ShortcutStore();
  const commandTemplates = new CommandTemplateStore();
  const slashCommandCatalog = new SlashCommandCatalog({
    discoverers: {
      claude: new ClaudeSlashCommandDiscoverer({ command: claudeCommand })
    }
  });
  const gitService = new GitService();
  const workspaceInspector = new WorkspaceInspector();
  const runQueue = new RunQueue();
  const attachmentScratchStore = new AttachmentScratchStore({ root: path.join(path.dirname(appDbPath), 'attachment-scratch') });
  const effectiveCodexAppServerService = codexAppServerService !== undefined
    ? codexAppServerService
    : !codexAppServerRouteEnabled
    ? null
    : new CodexAppServerService({
      lifecycle: codexAppServerLifecycle,
      poolLimits: {
        conversation: codexAppServerMaxProcesses
      },
      metrics: codexAppServerMetrics
    });
  const config = { host, port, mode };
  const version = versionInfo({ mode });
  const migrationService = new MigrationService();
  const runs = new RunManager({ workspaces, eventStore, adapterRegistry, auditLog, runQueue });
  const conversations = new ConversationManager({
    workspaces,
    eventStore: conversationEventStore,
    auditLog,
    adapters: conversationAdapters || createConversationAdapters({
      claudeCommand,
      codexCommand,
      codexToolTimeoutSec,
      codexAppServerEnabled: codexAppServerRouteEnabled,
      codexAppServerRuntime,
      codexAppServerMaxProcesses,
      codexAppServerAvailabilityState,
      codexAppServerLifecycle,
      codexAppServerMetrics,
      opencodeCommand,
      opencodeServerLifecycle: effectiveOpenCodeServerLifecycle
    }),
    persistentStore: conversationSqliteStore,
    attachmentScratchStore,
    idleTtlMs: Number(process.env.CONVERSATION_IDLE_TTL_MS || 600000),
    perfTracer
  });
  const attachmentScratchCleanup = attachmentScratchStore.cleanupExpired({
    activeConversationIds: activeConversationIdsForScratchCleanup(conversations)
  }).catch((error) => {
    auditLog.record('attachment_scratch.startup_cleanup_error', {
      error: error.message
    });
  });
  const diagnostics = new DiagnosticsService({ config, adapterRegistry, auditLog, auth, workspaces, runs, runQueue, migrationService, versionInfo: version });
  const diagnosticBundle = new DiagnosticBundleService({ diagnostics, runs, runQueue, commandTemplates, auditLog, exceptionStore: appSqliteStore });
  const appUpdates = new AppUpdateService({ artifactDir: androidUpdateArtifactDir });
  const server = createServer({ auth, workspaces, runs, conversations, adapterRegistry, diagnostics, diagnosticBundle, shortcuts, commandTemplates, slashCommandCatalog, gitService, workspaceInspector, runQueue, eventStore, config, version, asrModelAsset, appUpdates, codexAppServerService: effectiveCodexAppServerService, codexAppServerApprovalPolicy, codexAppServerEnabled: codexAppServerRouteEnabled, auditLog, perfConfig, perfStore, perfTracer });
  const notificationHub = new NotificationHub({ auth, conversations, conversationEventStore, version, perfTracer });
  notificationHub.attach(server);
  notificationHub.start();
  return { server, auth, workspaces, eventStore, conversationEventStore, conversationSqliteStore, appSqliteStore, auditLog, adapterRegistry, shortcuts, commandTemplates, slashCommandCatalog, gitService, workspaceInspector, runQueue, migrationService, diagnostics, diagnosticBundle, runs, conversations, notificationHub, config, version, asrModelAsset, appUpdates, codexAppServerService: effectiveCodexAppServerService, opencodeServerLifecycle: effectiveOpenCodeServerLifecycle, perfConfig, perfStore, perfTracer, attachmentScratchCleanup };
}

function createConversationAdapters({ claudeCommand, codexCommand, codexToolTimeoutSec, codexAppServerEnabled = false, codexAppServerRuntime = null, codexAppServerMaxProcesses = null, codexAppServerAvailabilityState = null, codexAppServerLifecycle = null, codexAppServerMetrics = null, opencodeCommand = 'opencode', opencodeServerLifecycle = null }) {
  const effectiveOpenCodeServerLifecycle = opencodeServerLifecycle || new OpenCodeServerLifecycle({
    externalUrl: process.env.OPENCODE_SERVER_URL || '',
    command: opencodeCommand
  });
  const adapters = new Map([
    ['claude', new ClaudeConversationAdapter({ command: claudeCommand })],
    ['codex', new CodexConversationAdapter({ command: codexCommand, toolTimeoutSec: codexToolTimeoutSec })],
    ['opencode', new OpenCodeConversationAdapter({ lifecycle: effectiveOpenCodeServerLifecycle })]
  ]);
  if (codexAppServerEnabled) {
    const runtime = codexAppServerRuntime || buildCodexAppServerRuntimeConfig({ enabled: true });
    const availabilityState = codexAppServerAvailabilityState || { current: runtime.availability };
    const lifecycle = codexAppServerLifecycle || createCodexAppServerLifecycle({
      codexCommand,
      maxProcesses: resolveCodexAppServerLifecycleMaxProcesses(codexAppServerMaxProcesses),
      metrics: codexAppServerMetrics || null
    });
    adapters.set('codex-app-server', new CodexAppServerConversationAdapter({
      availability: buildCodexAppServerAvailability(availabilityState.current),
      availabilityState,
      lifecycle,
      metrics: codexAppServerMetrics || createCodexAppServerMetrics(),
      toolTimeoutSec: codexToolTimeoutSec
    }));
  }
  return adapters;
}

function createCodexAppServerMetrics() {
  return {
    probeSuccess: 0,
    probeFailure: 0,
    spawnFailure: 0,
    initializeLatencyMs: null,
    fallbackBeforeFirstRequestCount: 0,
    approvalRequestedCount: 0,
    approvalTimeoutCount: 0,
    approvalRoundTripLatencyMs: [],
    transportCloseCount: 0,
    runErrorAfterTurnStartedCount: 0,
    orphanProcessCleanupCount: 0
  };
}

function createCodexAppServerLifecycle({ codexCommand = 'codex', maxProcesses = null, metrics = null, processTreeTerminator = undefined } = {}) {
  const invocation = resolveCliInvocation(codexCommand || 'codex');
  return new CodexAppServerLifecycle({
    maxProcesses,
    command: invocation.command,
    args: [...(invocation.argsPrefix || []), 'app-server'],
    metrics,
    processTreeTerminator
  });
}

function buildCodexAppServerRuntimeConfig({ enabled = true, transport = 'auto', experimentalApi = true, rolloutPercent = 100 } = {}) {
  const normalizedTransport = String(transport || 'auto').trim().toLowerCase();
  const transportSupported = normalizedTransport === 'auto' || normalizedTransport === 'stdio';
  const rollout = normalizeRolloutPercent(rolloutPercent);
  const rolloutEnabled = rollout > 0;
  const installed = enabled;
  const protocolCompatible = installed && experimentalApi === true && transportSupported && rolloutEnabled;
  const transportHealthy = false;
  let unavailableReason = 'disabled';
  if (enabled) {
    if (normalizedTransport === 'off') {
      unavailableReason = 'transport_off';
    } else if (!transportSupported) {
      unavailableReason = 'unsupported_transport';
    } else if (experimentalApi !== true) {
      unavailableReason = 'experimental_api_disabled';
    } else if (!rolloutEnabled) {
      unavailableReason = 'rollout_disabled';
    } else {
      unavailableReason = 'probe_not_run';
    }
  }
  const shouldProbe = protocolCompatible && normalizedTransport !== 'off';
  const availability = buildCodexAppServerAvailability({
    enabled,
    installed,
    protocolCompatible,
    transportHealthy,
    unavailableReason,
    lastProbeAt: null
  });
  return {
    transport: transportSupported ? 'stdio' : normalizedTransport,
    experimentalApi: experimentalApi === true,
    rolloutPercent: rollout,
    availability: {
      enabled,
      installed: availability.installed,
      protocolCompatible: availability.protocolCompatible,
      transportHealthy: availability.transportHealthy,
      unavailableReason: availability.unavailableReason,
      lastProbeAt: availability.lastProbeAt
    },
    selectable: availability.selectable,
    effectiveCapabilities: availability.effectiveCapabilities,
    shouldProbe
  };
}

function createCodexAppServerProbe({ lifecycle, initializeTimeoutMs = 10000, shutdownGraceMs = 250, metrics = null } = {}) {
  return async function probeCodexAppServer() {
    if (!lifecycle || typeof lifecycle.spawn !== 'function') {
      return {
        installed: false,
        protocolCompatible: false,
        transportHealthy: false,
        unavailableReason: 'lifecycle_missing',
        lastProbeAt: new Date().toISOString()
      };
    }
    let handle = null;
    try {
      handle = lifecycle.spawn();
      const initializeStarted = Date.now();
      const client = new CodexAppServerClient({
        transport: handle.transport,
        initializeTimeoutMs
      });
      await client.initialize();
      if (metrics) metrics.initializeLatencyMs = Date.now() - initializeStarted;
      return {
        installed: true,
        protocolCompatible: true,
        transportHealthy: true,
        unavailableReason: null,
        lastProbeAt: new Date().toISOString()
      };
    } catch (error) {
      if (metrics && /spawn|ENOENT|not found|no such file/i.test(error.message || '')) {
        metrics.spawnFailure += 1;
      }
      return {
        installed: true,
        protocolCompatible: true,
        transportHealthy: false,
        unavailableReason: error.message || 'probe_failed',
        lastProbeAt: new Date().toISOString()
      };
    } finally {
      if (handle && typeof handle.shutdown === 'function') {
        await handle.shutdown({
          gracefulShutdownMs: shutdownGraceMs,
          hardKillGraceMs: shutdownGraceMs
        });
      }
    }
  };
}

function resolveCodexAppServerLifecycleMaxProcesses(conversationLimit = null) {
  const conversation = normalizePositiveInteger(conversationLimit, DEFAULT_POOL_LIMITS.conversation);
  return DEFAULT_POOL_LIMITS.discovery + conversation + DEFAULT_POOL_LIMITS.mutation;
}

function createCodexAppServerModelLister({ lifecycle, initializeTimeoutMs = 10000, requestTimeoutMs = 10000, shutdownGraceMs = 250 } = {}) {
  return async function listCodexAppServerModels() {
    if (!lifecycle || typeof lifecycle.spawn !== 'function') return null;
    let handle = null;
    try {
      handle = lifecycle.spawn();
      const client = new CodexAppServerClient({
        transport: handle.transport,
        initializeTimeoutMs,
        requestTimeoutMs
      });
      await client.initialize();
      const response = await client.listModels({ timeoutMs: requestTimeoutMs });
      return normalizeCodexAppServerModelCapability(response);
    } finally {
      if (handle && typeof handle.shutdown === 'function') {
        await handle.shutdown({
          gracefulShutdownMs: shutdownGraceMs,
          hardKillGraceMs: shutdownGraceMs
        });
      }
    }
  };
}

function normalizeRolloutPercent(value) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric) || numeric <= 0) return 0;
  if (numeric >= 100) return 100;
  return Math.floor(numeric);
}

function parseBooleanEnv(value, defaultValue = false) {
  if (value === undefined || value === null || value === '') return defaultValue;
  const normalized = String(value).trim().toLowerCase();
  if (['1', 'true', 'yes', 'on'].includes(normalized)) return true;
  if (['0', 'false', 'no', 'off'].includes(normalized)) return false;
  return defaultValue;
}

function normalizePositiveInteger(value, fallback) {
  if (value === undefined || value === null || value === '') return fallback;
  const numeric = Number(value);
  if (!Number.isFinite(numeric) || numeric < 1) return fallback;
  return Math.floor(numeric);
}

function activeConversationIdsForScratchCleanup(conversations) {
  const activeStatuses = new Set([
    conversationStatuses.RUNNING,
    conversationStatuses.WAITING_INPUT,
    conversationStatuses.WAITING_APPROVAL
  ]);
  return new Set(Array.from(conversations.conversations.values())
    .filter((conversation) => activeStatuses.has(conversation.status))
    .map((conversation) => conversation.id));
}

async function shutdownAppResources(app, { sleepInhibitor = null } = {}) {
  const errors = [];
  const runCleanup = async (name, cleanup) => {
    try {
      await cleanup();
    } catch (error) {
      errors.push({ name, error });
    }
  };

  if (sleepInhibitor && typeof sleepInhibitor.stop === 'function') {
    await runCleanup('sleepInhibitor.stop', () => sleepInhibitor.stop());
  }
  if (app?.server?.listening) {
    await runCleanup('server.close', () => new Promise((resolve, reject) => {
      app.server.close((error) => {
        if (error) reject(error);
        else resolve();
      });
    }));
  }
  if (app?.notificationHub && typeof app.notificationHub.close === 'function') {
    await runCleanup('notificationHub.close', () => app.notificationHub.close());
  }
  if (app?.opencodeServerLifecycle && typeof app.opencodeServerLifecycle.shutdown === 'function') {
    await runCleanup('opencodeServerLifecycle.shutdown', () => app.opencodeServerLifecycle.shutdown());
  }
  if (app?.codexAppServerService && typeof app.codexAppServerService.shutdown === 'function') {
    await runCleanup('codexAppServerService.shutdown', () => app.codexAppServerService.shutdown());
  }
  if (app?.perfStore && typeof app.perfStore.close === 'function') {
    await runCleanup('perfStore.close', () => app.perfStore.close());
  }
  if (
    app?.conversationSqliteStore &&
    app.conversationSqliteStore !== app.appSqliteStore &&
    typeof app.conversationSqliteStore.close === 'function'
  ) {
    await runCleanup('conversationSqliteStore.close', () => app.conversationSqliteStore.close());
  }
  if (app?.appSqliteStore && typeof app.appSqliteStore.close === 'function') {
    await runCleanup('appSqliteStore.close', () => app.appSqliteStore.close());
  }
  if (errors.length > 0) {
    const error = new Error(`Failed to close ${errors.map((item) => item.name).join(', ')}`);
    error.failures = errors;
    throw error;
  }
}

if (require.main === module) {
  const app = createApp();
  const sleepInhibitor = createWindowsSleepInhibitor();
  let sleepInhibitorStopped = false;
  const stopSleepInhibitor = () => {
    if (sleepInhibitorStopped) return;
    sleepInhibitorStopped = true;
    sleepInhibitor.stop();
  };
  process.once('exit', stopSleepInhibitor);
  const shutdownAndExit = (exitCode) => {
    shutdownAppResources(app, { sleepInhibitor: { stop: stopSleepInhibitor } })
      .catch((error) => {
        console.error(`daemon shutdown cleanup failed: ${error.message}`);
      })
      .finally(() => process.exit(exitCode));
  };
  process.once('SIGINT', () => shutdownAndExit(130));
  process.once('SIGTERM', () => shutdownAndExit(143));
  app.server.listen(app.config.port, app.config.host, () => {
    const lan = app.config.host === '127.0.0.1' ? 'disabled' : 'enabled';
    console.log(`daemon ${app.version.daemonVersion} listening on http://${app.config.host}:${app.config.port} (${app.config.mode}, LAN ${lan})`);
    console.log('Windows Firewall may prompt when LAN mode is enabled.');
    const sleep = sleepInhibitor.start();
    if (sleep.active) {
      console.log('Preventing Windows from sleeping while the daemon is running. Set DAEMON_PREVENT_SLEEP=0 to disable.');
    }
  });
}

module.exports = {
  createApp,
  shutdownAppResources,
  createConversationAdapters,
  createCodexAppServerProbe,
  createCodexAppServerModelLister,
  resolveCodexAppServerLifecycleMaxProcesses
};
