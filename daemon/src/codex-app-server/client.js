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

  startAccountLogin(options = {}) {
    return this.sendRequest('account/login/start', compactObject({
      provider: options.provider
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
      serverId: options.serverId
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

module.exports = {
  CodexAppServerClient,
  compactObject
};
