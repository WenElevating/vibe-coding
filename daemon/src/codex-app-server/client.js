'use strict';

const {
  buildCodexAppServerThreadResumeRequest,
  buildCodexAppServerThreadStartRequest,
  buildCodexAppServerTurnInterruptRequest,
  buildCodexAppServerTurnStartRequest
} = require('../codex-app-server-bridge');
const { buildCodexAppServerApprovalResponse } = require('../codex-app-server-approval');

const DEFAULT_CLIENT_INFO = Object.freeze({
  name: 'vibe-coding-daemon',
  title: 'vibe-coding daemon',
  version: '0.1.0'
});

class CodexAppServerClient {
  constructor({ transport, initializeTimeoutMs = 10000, requestTimeoutMs = 30000, clientInfo = DEFAULT_CLIENT_INFO } = {}) {
    if (!transport || typeof transport.sendRequest !== 'function') {
      throw new Error('CodexAppServerClient requires a transport with sendRequest');
    }
    if (typeof transport.sendNotification !== 'function') {
      throw new Error('CodexAppServerClient requires a transport with sendNotification');
    }
    this.transport = transport;
    this.initializeTimeoutMs = Math.max(1, Number(initializeTimeoutMs) || 10000);
    this.requestTimeoutMs = Math.max(1, Number(requestTimeoutMs) || 30000);
    this.clientInfo = clientInfo;
    this.initialized = false;
    this.invalidated = false;
    this.closeError = null;
    this.initializePromise = null;
    if (typeof transport.on === 'function') {
      transport.on('closed', (error) => {
        this.invalidated = true;
        this.initialized = false;
        this.closeError = error instanceof Error ? error : new Error('Codex app-server transport closed');
      });
    }
  }

  initialize() {
    if (this.invalidated) return Promise.reject(this.invalidatedError());
    if (this.initialized) return Promise.resolve();
    if (!this.initializePromise) {
      this.initializePromise = this._initialize().catch((error) => {
        this.invalidated = true;
        throw error;
      });
    }
    return this.initializePromise;
  }

  async _initialize() {
    await this.transport.sendRequest('initialize', {
      clientInfo: this.clientInfo,
      capabilities: {
        experimentalApi: true,
        requestAttestation: false
      }
    }, { timeoutMs: this.initializeTimeoutMs });
    this.transport.sendNotification('initialized', {});
    this.initialized = true;
  }

  listModels(options = {}) {
    return this.sendRequest('model/list', {}, options);
  }

  listThreads(options = {}) {
    return this.sendRequest('thread/list', compactObject({
      cwd: options.cwd ?? options.workspacePath,
      limit: options.limit,
      cursor: options.cursor,
      archived: options.archived
    }), options);
  }

  listLoadedThreads(options = {}) {
    return this.sendRequest('thread/loaded/list', {}, options);
  }

  readConfig(options = {}) {
    return this.sendRequest('config/read', {}, options);
  }

  readConfigRequirements(options = {}) {
    return this.sendRequest('configRequirements/read', {}, options);
  }

  listMcpServerStatus(options = {}) {
    return this.sendRequest('mcpServerStatus/list', compactObject({
      cursor: options.cursor
    }), options);
  }

  readMcpServerResource(options = {}) {
    return this.sendRequest('mcpServer/resource/read', compactObject({
      server: options.server ?? options.serverId,
      uri: options.uri
    }), options);
  }

  listSkills(options = {}) {
    return this.sendRequest('skills/list', compactObject({
      cwds: options.cwds,
      forceReload: options.forceReload
    }), options);
  }

  listPlugins(options = {}) {
    return this.sendRequest('plugin/list', compactObject({
      cwds: options.cwds,
      marketplaceKinds: options.marketplaceKinds
    }), options);
  }

  readPlugin(options = {}) {
    return this.sendRequest('plugin/read', compactObject({
      pluginName: options.pluginName ?? options.pluginId,
      marketplacePath: options.marketplacePath,
      remoteMarketplaceName: options.remoteMarketplaceName
    }), options);
  }

  readPluginSkill(options = {}) {
    return this.sendRequest('plugin/skill/read', compactObject({
      remoteMarketplaceName: options.remoteMarketplaceName,
      remotePluginId: options.remotePluginId ?? options.pluginId,
      skillName: options.skillName ?? options.skillId
    }), options);
  }

  listPluginShares(options = {}) {
    return this.sendRequest('plugin/share/list', {}, options);
  }

  listApps(options = {}) {
    return this.sendRequest('app/list', compactObject({
      cursor: options.cursor
    }), options);
  }

  listHooks(options = {}) {
    return this.sendRequest('hooks/list', {}, options);
  }

  listCollaborationModes(options = {}) {
    return this.sendRequest('collaborationMode/list', {}, options);
  }

  listExperimentalFeatures(options = {}) {
    return this.sendRequest('experimentalFeature/list', {}, options);
  }

  detectExternalAgentConfig(options = {}) {
    return this.sendRequest('externalAgentConfig/detect', {}, options);
  }

  listPermissionProfiles(options = {}) {
    return this.sendRequest('permissionProfile/list', {}, options);
  }

  readModelProviderCapabilities(options = {}) {
    return this.sendRequest('modelProvider/capabilities/read', {}, options);
  }

  readWindowsSandboxReadiness(options = {}) {
    return this.sendRequest('windowsSandbox/readiness', {}, options);
  }

  readAccount(options = {}) {
    return this.sendRequest('account/read', {}, options);
  }

  readAccountRateLimits(options = {}) {
    return this.sendRequest('account/rateLimits/read', {}, options);
  }

  getFileMetadata(options = {}) {
    return this.sendRequest('fs/getMetadata', compactObject({
      path: options.path
    }), options);
  }

  readDirectory(options = {}) {
    return this.sendRequest('fs/readDirectory', compactObject({
      path: options.path
    }), options);
  }

  readFile(options = {}) {
    return this.sendRequest('fs/readFile', compactObject({
      path: options.path
    }), options);
  }

  watchFileSystem(options = {}) {
    return this.sendRequest('fs/watch', compactObject({
      path: options.path,
      watchId: options.watchId
    }), options);
  }

  unwatchFileSystem(options = {}) {
    return this.sendRequest('fs/unwatch', compactObject({
      watchId: options.watchId
    }), options);
  }

  copyFile(options = {}) {
    return this.sendRequest('fs/copy', compactObject({
      sourcePath: options.sourcePath,
      destinationPath: options.destinationPath
    }), options);
  }

  createDirectory(options = {}) {
    return this.sendRequest('fs/createDirectory', compactObject({
      path: options.path
    }), options);
  }

  removeFile(options = {}) {
    return this.sendRequest('fs/remove', compactObject({
      path: options.path
    }), options);
  }

  writeFile(options = {}) {
    return this.sendRequest('fs/writeFile', compactObject({
      path: options.path,
      dataBase64: options.dataBase64 ?? encodeFileContent(options.content)
    }), options);
  }

  spawnProcess(options = {}) {
    return this.sendRequest('process/spawn', compactObject({
      command: options.command,
      cwd: options.cwd,
      processHandle: options.processHandle
    }), options);
  }

  killProcess(options = {}) {
    return this.sendRequest('process/kill', compactObject({
      processHandle: options.processHandle ?? options.processId
    }), options);
  }

  executeCommand(options = {}) {
    return this.sendRequest('command/exec', compactObject({
      command: options.command,
      cwd: options.cwd,
      processId: options.processId
    }), options);
  }

  writeConfigValue(options = {}) {
    return this.sendRequest('config/value/write', compactObject({
      keyPath: options.keyPath ?? options.key,
      mergeStrategy: options.mergeStrategy ?? 'replace',
      value: options.value
    }), options);
  }

  writeConfigBatch(options = {}) {
    return this.sendRequest('config/batchWrite', compactObject({
      edits: options.edits ?? configEditsFromValues(options.values)
    }), options);
  }

  reloadMcpServerConfig(options = {}) {
    return this.sendRequest('config/mcpServer/reload', null, options || {});
  }

  addEnvironment(options = {}) {
    return this.sendRequest('environment/add', compactObject({
      environmentId: options.environmentId ?? options.name,
      execServerUrl: options.execServerUrl ?? options.value
    }), options);
  }

  installPlugin(options = {}) {
    return this.sendRequest('plugin/install', compactObject({
      pluginName: options.pluginName ?? options.pluginId,
      marketplacePath: options.marketplacePath,
      remoteMarketplaceName: options.remoteMarketplaceName
    }), options);
  }

  uninstallPlugin(options = {}) {
    return this.sendRequest('plugin/uninstall', compactObject({
      pluginId: options.pluginId
    }), options);
  }

  addMarketplace(options = {}) {
    return this.sendRequest('marketplace/add', compactObject({
      source: options.source ?? options.url,
      refName: options.refName,
      sparsePaths: options.sparsePaths
    }), options);
  }

  removeMarketplace(options = {}) {
    return this.sendRequest('marketplace/remove', compactObject({
      marketplaceName: options.marketplaceName ?? options.marketplaceId
    }), options);
  }

  upgradeMarketplace(options = {}) {
    return this.sendRequest('marketplace/upgrade', compactObject({
      marketplaceName: options.marketplaceName ?? options.marketplaceId
    }), options);
  }

  writeSkillsConfig(options = {}) {
    const config = options.config && typeof options.config === 'object' && !Array.isArray(options.config)
      ? options.config
      : options;
    return this.sendRequest('skills/config/write', compactObject({
      enabled: config.enabled,
      name: config.name,
      path: config.path
    }), options);
  }

  setSkillsExtraRoots(options = {}) {
    return this.sendRequest('skills/extraRoots/set', compactObject({
      extraRoots: options.extraRoots ?? options.roots
    }), options);
  }

  readRemoteControlStatus(options = {}) {
    return this.sendRequest('remoteControl/status/read', {}, options);
  }

  listRemoteControlClients(options = {}) {
    return this.sendRequest('remoteControl/client/list', compactObject({
      environmentId: options.environmentId,
      cursor: options.cursor,
      limit: options.limit,
      order: options.order
    }), options);
  }

  enableRemoteControl(options = {}) {
    return this.sendRequest('remoteControl/enable', {}, options);
  }

  disableRemoteControl(options = {}) {
    return this.sendRequest('remoteControl/disable', {}, options);
  }

  startRemoteControlPairing(options = {}) {
    return this.sendRequest('remoteControl/pairing/start', compactObject({
      manualCode: options.manualCode
    }), options);
  }

  revokeRemoteControlClient(options = {}) {
    return this.sendRequest('remoteControl/client/revoke', compactObject({
      clientId: options.clientId,
      environmentId: options.environmentId
    }), options);
  }

  startAccountLogin(options = {}) {
    return this.sendRequest('account/login/start', compactDefinedObject({
      type: options.type,
      apiKey: options.apiKey,
      codexStreamlinedLogin: options.codexStreamlinedLogin,
      accessToken: options.accessToken,
      chatgptAccountId: options.chatgptAccountId,
      chatgptPlanType: options.chatgptPlanType
    }), options);
  }

  cancelAccountLogin(options = {}) {
    return this.sendRequest('account/login/cancel', compactObject({
      loginId: options.loginId
    }), options);
  }

  logoutAccount(options = {}) {
    return this.sendRequest('account/logout', {}, options);
  }

  sendAddCreditsNudgeEmail(options = {}) {
    return this.sendRequest('account/sendAddCreditsNudgeEmail', compactObject({
      creditType: options.creditType
    }), options);
  }

  startMcpServerOauthLogin(options = {}) {
    return this.sendRequest('mcpServer/oauth/login', compactObject({
      name: options.name,
      scopes: options.scopes,
      timeoutSecs: options.timeoutSecs
    }), options);
  }

  readThread(options = {}) {
    return this.sendRequest('thread/read', compactObject({
      threadId: options.threadId
    }), options);
  }

  searchThreads(options = {}) {
    return this.sendRequest('thread/search', compactObject({
      searchTerm: options.searchTerm ?? options.query,
      limit: options.limit,
      cursor: options.cursor
    }), options);
  }

  fuzzyFileSearch(options = {}) {
    return this.sendRequest('fuzzyFileSearch', compactObject({
      query: options.query,
      roots: normalizeRoots(options)
    }), options);
  }

  startFuzzyFileSearchSession(options = {}) {
    return this.sendRequest('fuzzyFileSearch/sessionStart', compactObject({
      sessionId: options.sessionId,
      roots: normalizeRoots(options)
    }), options);
  }

  updateFuzzyFileSearchSession(options = {}) {
    return this.sendRequest('fuzzyFileSearch/sessionUpdate', compactObject({
      sessionId: options.sessionId,
      query: options.query
    }), options);
  }

  stopFuzzyFileSearchSession(options = {}) {
    return this.sendRequest('fuzzyFileSearch/sessionStop', compactObject({
      sessionId: options.sessionId
    }), options);
  }

  startReview(options = {}) {
    return this.sendRequest('review/start', compactDefinedObject({
      threadId: options.threadId,
      target: options.target,
      delivery: options.delivery
    }), options);
  }

  generateAttestation(options = {}) {
    return this.sendRequest('attestation/generate', compactObject({
      workspacePath: options.workspacePath,
      challenge: options.challenge
    }), options);
  }

  listRealtimeVoices(options = {}) {
    return this.sendRequest('thread/realtime/listVoices', {}, options);
  }

  listThreadTurns(options = {}) {
    return this.sendRequest('thread/turns/list', compactObject({
      threadId: options.threadId,
      limit: options.limit,
      cursor: options.cursor
    }), options);
  }

  listThreadTurnItems(options = {}) {
    return this.sendRequest('thread/turns/items/list', compactObject({
      threadId: options.threadId,
      turnId: options.turnId,
      limit: options.limit,
      cursor: options.cursor
    }), options);
  }

  getThreadGoal(options = {}) {
    return this.sendRequest('thread/goal/get', compactObject({
      threadId: options.threadId
    }), options);
  }

  forkThread(options = {}) {
    return this.sendRequest('thread/fork', compactObject({
      threadId: options.threadId,
      cwd: options.cwd ?? options.workspacePath
    }), options);
  }

  archiveThread(options = {}) {
    return this.sendRequest('thread/archive', compactObject({
      threadId: options.threadId
    }), options);
  }

  unarchiveThread(options = {}) {
    return this.sendRequest('thread/unarchive', compactObject({
      threadId: options.threadId
    }), options);
  }

  rollbackThread(options = {}) {
    return this.sendRequest('thread/rollback', compactObject({
      threadId: options.threadId,
      numTurns: options.numTurns
    }), options);
  }

  updateThreadMetadata(options = {}) {
    const metadata = options.metadata && typeof options.metadata === 'object' && !Array.isArray(options.metadata)
      ? options.metadata
      : {};
    return this.sendRequest('thread/metadata/update', compactDefinedObject({
      threadId: options.threadId,
      gitInfo: options.gitInfo ?? metadata.gitInfo
    }), options);
  }

  setThreadName(options = {}) {
    return this.sendRequest('thread/name/set', compactObject({
      threadId: options.threadId,
      name: options.name
    }), options);
  }

  updateThreadSettings(options = {}) {
    const settings = options.settings && typeof options.settings === 'object' && !Array.isArray(options.settings)
      ? options.settings
      : options;
    return this.sendRequest('thread/settings/update', compactDefinedObject({
      threadId: options.threadId,
      approvalPolicy: settings.approvalPolicy,
      approvalsReviewer: settings.approvalsReviewer,
      collaborationMode: settings.collaborationMode,
      cwd: settings.cwd,
      effort: settings.effort,
      model: settings.model,
      permissions: settings.permissions,
      personality: settings.personality,
      sandboxPolicy: settings.sandboxPolicy,
      serviceTier: settings.serviceTier,
      summary: settings.summary
    }), options);
  }

  setThreadMemoryMode(options = {}) {
    return this.sendRequest('thread/memoryMode/set', compactObject({
      threadId: options.threadId,
      mode: options.mode ?? options.memoryMode
    }), options);
  }

  setThreadGoal(options = {}) {
    const goal = options.goal && typeof options.goal === 'object' && !Array.isArray(options.goal)
      ? options.goal
      : {};
    return this.sendRequest('thread/goal/set', compactDefinedObject({
      threadId: options.threadId,
      objective: options.objective ?? goal.objective,
      status: options.status ?? goal.status,
      tokenBudget: options.tokenBudget ?? goal.tokenBudget
    }), options);
  }

  clearThreadGoal(options = {}) {
    return this.sendRequest('thread/goal/clear', compactObject({
      threadId: options.threadId
    }), options);
  }

  startThread(options = {}) {
    const request = buildCodexAppServerThreadStartRequest(options);
    return this.sendRequest(request.method, request.params, options);
  }

  resumeThread(options = {}) {
    const request = buildCodexAppServerThreadResumeRequest(options);
    return this.sendRequest(request.method, request.params, options);
  }

  startTurn(options = {}) {
    const request = buildCodexAppServerTurnStartRequest(options);
    return this.sendRequest(request.method, request.params, options);
  }

  interruptTurn(options = {}) {
    const request = buildCodexAppServerTurnInterruptRequest(options);
    return this.sendRequest(request.method, request.params, options);
  }

  respondApproval(context, response) {
    const rpcResponse = buildCodexAppServerApprovalResponse(context, response);
    this.transport.sendResult(rpcResponse.id, rpcResponse.result);
    return rpcResponse;
  }

  sendRequest(method, params, options = {}) {
    if (this.invalidated) return Promise.reject(this.invalidatedError());
    return this.transport.sendRequest(method, params, {
      timeoutMs: options.timeoutMs || this.requestTimeoutMs
    });
  }

  invalidatedError() {
    if (this.closeError) return new Error(`Codex app-server client invalidated: ${this.closeError.message}`);
    return new Error('Codex app-server client invalidated');
  }
}

function compactObject(value) {
  const result = {};
  for (const [key, current] of Object.entries(value || {})) {
    if (current !== undefined && current !== null) result[key] = current;
  }
  return result;
}

function encodeFileContent(value) {
  if (typeof value !== 'string') return undefined;
  return Buffer.from(value, 'utf8').toString('base64');
}

function normalizeRoots(options = {}) {
  if (Array.isArray(options.roots)) return options.roots;
  if (typeof options.workspacePath === 'string') return [options.workspacePath];
  return undefined;
}

function configEditsFromValues(values) {
  if (!values || typeof values !== 'object' || Array.isArray(values)) return undefined;
  return Object.entries(values).map(([keyPath, value]) => ({
    keyPath,
    mergeStrategy: 'replace',
    value
  }));
}

function compactDefinedObject(value) {
  const result = {};
  for (const [key, current] of Object.entries(value || {})) {
    if (current !== undefined) result[key] = current;
  }
  return result;
}

module.exports = {
  CodexAppServerClient,
  compactObject
};
