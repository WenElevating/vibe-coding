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

module.exports = {
  CodexAppServerClient
};
