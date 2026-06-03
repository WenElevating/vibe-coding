'use strict';

const { buildCodexAppServerAvailability } = require('./codex-app-server-availability');

class CodexAppServerConversationAdapter {
  constructor({
    availability = null,
    lifecycle = null,
    toolTimeoutSec = null
  } = {}) {
    this.name = 'codex-app-server';
    this.toolTimeoutSec = toolTimeoutSec;
    this.lifecycle = lifecycle;
    this.availability = availability || buildCodexAppServerAvailability({ enabled: false });
    this.capabilities = this.availability.effectiveCapabilities || {};
  }

  detectCapabilities() {
    return {
      adapter: this.name,
      available: this.availability.selectable === true,
      status: this.availability.selectable === true ? 'available' : 'unavailable',
      ...this.availability,
      capabilities: this.availability.effectiveCapabilities || {}
    };
  }

  getCapabilities() {
    return this.availability.effectiveCapabilities || {};
  }

  async startConversation() {
    if (!this.availability || this.availability.selectable !== true) {
      const reason = this.availability?.unavailableReason || 'unavailable';
      const error = new Error(`Codex app-server adapter is not selectable: ${reason}`);
      error.status = 503;
      error.code = 'CODEX_APP_SERVER_UNAVAILABLE';
      throw error;
    }
    if (!this.lifecycle || typeof this.lifecycle.spawn !== 'function') {
      const error = new Error('Codex app-server lifecycle is not configured');
      error.status = 503;
      error.code = 'CODEX_APP_SERVER_LIFECYCLE_MISSING';
      throw error;
    }
    const processHandle = this.lifecycle.spawn();
    return new CodexAppServerConversationHandle({ processHandle });
  }
}

class CodexAppServerConversationHandle {
  constructor({ processHandle }) {
    this.processHandle = processHandle;
  }

  async sendUserMessage() {
    const error = new Error('Codex app-server conversation execution is not implemented yet');
    error.status = 501;
    error.code = 'CODEX_APP_SERVER_NOT_IMPLEMENTED';
    throw error;
  }

  async dispose() {
    if (this.processHandle && typeof this.processHandle.shutdown === 'function') {
      await this.processHandle.shutdown();
    }
  }
}

module.exports = {
  CodexAppServerConversationAdapter,
  CodexAppServerConversationHandle
};
