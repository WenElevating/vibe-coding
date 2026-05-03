'use strict';

const { AuthManager } = require('./auth');
const { WorkspaceRegistry } = require('./workspace');
const { EventStore } = require('./event-store');
const { ConversationEventStore } = require('./conversation-event-store');
const { ConversationSqliteStore, defaultDbPath } = require('./conversation-sqlite-store');
const { AuditLog } = require('./audit');
const { ClaudeAdapter } = require('./claude-adapter');
const { ClaudeConversationAdapter } = require('./claude-conversation-adapter');
const { createCodexAdapter } = require('./jsonline-adapter');
const { OpenCodeAdapter } = require('./opencode-adapter');
const { SyntheticAdapter } = require('./synthetic-adapter');
const { AdapterRegistry } = require('./adapter-registry');
const { RunManager } = require('./run-manager');
const { ConversationManager } = require('./conversation-manager');
const { RunQueue } = require('./run-queue');
const { ShortcutStore } = require('./shortcuts');
const { CommandTemplateStore } = require('./command-templates');
const { GitService } = require('./git-service');
const { WorkspaceInspector } = require('./workspace-inspector');
const { MigrationService } = require('./migrations');
const { DiagnosticsService } = require('./diagnostics');
const { DiagnosticBundleService } = require('./diagnostic-bundle');
const { versionInfo } = require('./version');
const { createServer } = require('./server');

function createApp({
  host = process.env.DAEMON_HOST || '127.0.0.1',
  port = Number(process.env.PORT || 4317),
  mode = process.env.DAEMON_MODE || 'dev',
  claudeCommand = process.env.CLAUDE_COMMAND || 'claude',
  codexCommand = process.env.CODEX_COMMAND || 'codex',
  codexEnabled = process.env.CODEX_ENABLED === '1',
  opencodeServerUrl = process.env.OPENCODE_SERVER_URL || 'http://127.0.0.1:4096',
  devAdapters = process.env.DEV_ADAPTERS === '1' || mode === 'dev',
  conversationAdapters = null,
  conversationDbPath = process.env.CONVERSATION_DB_PATH || defaultDbPath()
} = {}) {
  const auth = new AuthManager();
  const workspaces = new WorkspaceRegistry();
  workspaces.add({ id: 'default', name: 'Current Project', workspacePath: process.cwd() });
  const eventStore = new EventStore();
  const conversationSqliteStore = new ConversationSqliteStore({ dbPath: conversationDbPath });
  const conversationEventStore = new ConversationEventStore({ persistentStore: conversationSqliteStore });
  const auditLog = new AuditLog();
  const adapters = [new ClaudeAdapter({ command: claudeCommand }), createCodexAdapter({ command: codexCommand, explicitEnabled: codexEnabled }), new OpenCodeAdapter({ serverUrl: opencodeServerUrl })];
  if (devAdapters) adapters.push(new SyntheticAdapter(), new SyntheticAdapter({ name: 'synthetic-text' }), new SyntheticAdapter({ name: 'synthetic-error' }), new SyntheticAdapter({ name: 'synthetic-slow', delayMs: 1000 }));
  const adapterRegistry = new AdapterRegistry(adapters);
  const shortcuts = new ShortcutStore();
  const commandTemplates = new CommandTemplateStore();
  const gitService = new GitService();
  const workspaceInspector = new WorkspaceInspector();
  const runQueue = new RunQueue();
  const config = { host, port, mode };
  const version = versionInfo({ mode });
  const migrationService = new MigrationService();
  const runs = new RunManager({ workspaces, eventStore, adapterRegistry, auditLog, runQueue });
  const conversations = new ConversationManager({
    workspaces,
    eventStore: conversationEventStore,
    auditLog,
    adapters: conversationAdapters || createConversationAdapters({ claudeCommand }),
    persistentStore: conversationSqliteStore,
    idleTtlMs: Number(process.env.CONVERSATION_IDLE_TTL_MS || 600000)
  });
  const diagnostics = new DiagnosticsService({ config, adapterRegistry, auditLog, auth, workspaces, runs, runQueue, migrationService, versionInfo: version });
  const diagnosticBundle = new DiagnosticBundleService({ diagnostics, runs, runQueue, commandTemplates, auditLog });
  const server = createServer({ auth, workspaces, runs, conversations, adapterRegistry, diagnostics, diagnosticBundle, shortcuts, commandTemplates, gitService, workspaceInspector, runQueue, eventStore, config, version });
  return { server, auth, workspaces, eventStore, conversationEventStore, conversationSqliteStore, auditLog, adapterRegistry, shortcuts, commandTemplates, gitService, workspaceInspector, runQueue, migrationService, diagnostics, diagnosticBundle, runs, conversations, config, version };
}

function createConversationAdapters({ claudeCommand }) {
  return new Map([
    ['claude', new ClaudeConversationAdapter({ command: claudeCommand })],
    ['codex', notImplementedConversationAdapter('Codex')],
    ['opencode', notImplementedConversationAdapter('OpenCode')]
  ]);
}

function notImplementedConversationAdapter(label) {
  return {
    capabilities: { longLivedProcess: false, waitingInput: false, waitingApproval: false, resume: false, partialOutput: true },
    async startConversation() {
      const error = new Error(`${label} conversation adapter is not implemented yet`);
      error.status = 501;
      throw error;
    }
  };
}

if (require.main === module) {
  const app = createApp();
  app.server.listen(app.config.port, app.config.host, () => {
    const lan = app.config.host === '127.0.0.1' ? 'disabled' : 'enabled';
    console.log(`daemon ${app.version.daemonVersion} listening on http://${app.config.host}:${app.config.port} (${app.config.mode}, LAN ${lan})`);
    console.log('Windows Firewall may prompt when LAN mode is enabled.');
  });
}

module.exports = { createApp };
