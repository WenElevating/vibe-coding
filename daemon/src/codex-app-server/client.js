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
      workspacePath: options.workspacePath,
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
      serverId: options.serverId,
      uri: options.uri
    }), options);
  }

  listSkills(options = {}) {
    return this.sendRequest('skills/list', compactObject({
      cursor: options.cursor
    }), options);
  }

  listPlugins(options = {}) {
    return this.sendRequest('plugin/list', compactObject({
      cursor: options.cursor
    }), options);
  }

  readPlugin(options = {}) {
    return this.sendRequest('plugin/read', compactObject({
      pluginId: options.pluginId
    }), options);
  }

  readPluginSkill(options = {}) {
    return this.sendRequest('plugin/skill/read', compactObject({
      pluginId: options.pluginId,
      skillId: options.skillId
    }), options);
  }

  listPluginShares(options = {}) {
    return this.sendRequest('plugin/share/list', compactObject({
      cursor: options.cursor
    }), options);
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
      path: options.path,
      encoding: options.encoding
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
      args: options.args,
      cwd: options.cwd,
      workspacePath: options.workspacePath
    }), options);
  }

  killProcess(options = {}) {
    return this.sendRequest('process/kill', compactObject({
      processId: options.processId
    }), options);
  }

  executeCommand(options = {}) {
    return this.sendRequest('command/exec', compactObject({
      command: options.command,
      cwd: options.cwd,
      workspacePath: options.workspacePath
    }), options);
  }

  writeConfigValue(options = {}) {
    return this.sendRequest('config/value/write', compactObject({
      key: options.key,
      value: options.value
    }), options);
  }

  writeConfigBatch(options = {}) {
    return this.sendRequest('config/batchWrite', compactObject({
      values: options.values
    }), options);
  }

  reloadMcpServerConfig(options = {}) {
    return this.sendRequest('config/mcpServer/reload', compactObject({
      serverId: options.serverId
    }), options);
  }

  addEnvironment(options = {}) {
    return this.sendRequest('environment/add', compactObject({
      name: options.name,
      value: options.value
    }), options);
  }

  installPlugin(options = {}) {
    return this.sendRequest('plugin/install', compactObject({
      pluginId: options.pluginId
    }), options);
  }

  uninstallPlugin(options = {}) {
    return this.sendRequest('plugin/uninstall', compactObject({
      pluginId: options.pluginId
    }), options);
  }

  addMarketplace(options = {}) {
    return this.sendRequest('marketplace/add', compactObject({
      marketplaceId: options.marketplaceId,
      url: options.url
    }), options);
  }

  removeMarketplace(options = {}) {
    return this.sendRequest('marketplace/remove', compactObject({
      marketplaceId: options.marketplaceId
    }), options);
  }

  upgradeMarketplace(options = {}) {
    return this.sendRequest('marketplace/upgrade', compactObject({
      marketplaceId: options.marketplaceId
    }), options);
  }

  writeSkillsConfig(options = {}) {
    return this.sendRequest('skills/config/write', compactObject({
      config: options.config
    }), options);
  }

  setSkillsExtraRoots(options = {}) {
    return this.sendRequest('skills/extraRoots/set', compactObject({
      roots: options.roots
    }), options);
  }

  readRemoteControlStatus(options = {}) {
    return this.sendRequest('remoteControl/status/read', {}, options);
  }

  listRemoteControlClients(options = {}) {
    return this.sendRequest('remoteControl/client/list', compactObject({
      cursor: options.cursor
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
      timeoutSecs: options.timeoutSecs
    }), options);
  }

  revokeRemoteControlClient(options = {}) {
    return this.sendRequest('remoteControl/client/revoke', compactObject({
      clientId: options.clientId
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
    return this.sendRequest('account/sendAddCreditsNudgeEmail', {}, options);
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
      query: options.query,
      workspacePath: options.workspacePath,
      limit: options.limit,
      cursor: options.cursor
    }), options);
  }

  fuzzyFileSearch(options = {}) {
    return this.sendRequest('fuzzyFileSearch', compactObject({
      query: options.query,
      workspacePath: options.workspacePath,
      limit: options.limit
    }), options);
  }

  startFuzzyFileSearchSession(options = {}) {
    return this.sendRequest('fuzzyFileSearch/sessionStart', compactObject({
      query: options.query,
      workspacePath: options.workspacePath,
      limit: options.limit
    }), options);
  }

  updateFuzzyFileSearchSession(options = {}) {
    return this.sendRequest('fuzzyFileSearch/sessionUpdate', compactObject({
      sessionId: options.sessionId,
      query: options.query,
      workspacePath: options.workspacePath,
      limit: options.limit
    }), options);
  }

  stopFuzzyFileSearchSession(options = {}) {
    return this.sendRequest('fuzzyFileSearch/sessionStop', compactObject({
      sessionId: options.sessionId,
      workspacePath: options.workspacePath
    }), options);
  }

  startReview(options = {}) {
    return this.sendRequest('review/start', compactObject({
      workspacePath: options.workspacePath,
      maxItems: options.maxItems
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
      workspacePath: options.workspacePath,
      fromTurnId: options.fromTurnId
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
      turnId: options.turnId,
      itemId: options.itemId
    }), options);
  }

  updateThreadMetadata(options = {}) {
    return this.sendRequest('thread/metadata/update', compactObject({
      threadId: options.threadId,
      metadata: options.metadata
    }), options);
  }

  setThreadName(options = {}) {
    return this.sendRequest('thread/name/set', compactObject({
      threadId: options.threadId,
      name: options.name
    }), options);
  }

  updateThreadSettings(options = {}) {
    return this.sendRequest('thread/settings/update', compactObject({
      threadId: options.threadId,
      settings: options.settings
    }), options);
  }

  setThreadMemoryMode(options = {}) {
    return this.sendRequest('thread/memoryMode/set', compactObject({
      threadId: options.threadId,
      memoryMode: options.memoryMode
    }), options);
  }

  setThreadGoal(options = {}) {
    return this.sendRequest('thread/goal/set', compactObject({
      threadId: options.threadId,
      goal: options.goal
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
