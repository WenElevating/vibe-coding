'use strict';

class AdapterRegistry {
  constructor(adapters) {
    this.adapters = new Map(adapters.map((adapter) => [adapter.name, adapter]));
    this.capabilitiesLoad = null;
  }

  get(name) {
    const adapter = this.adapters.get(name);
    if (!adapter) {
      const error = new Error(`adapter not found: ${name}`);
      error.status = 400;
      error.code = 'ADAPTER_NOT_FOUND';
      throw error;
    }
    return adapter;
  }

  listCapabilities() {
    if (!this.capabilitiesLoad) {
      this.capabilitiesLoad = Promise.all(Array.from(this.adapters.values()).map(async (adapter) => enrich(adapter, await adapter.detectCapabilities())))
        .finally(() => {
          this.capabilitiesLoad = null;
        });
    }
    return this.capabilitiesLoad;
  }
}

async function enrich(adapter, status) {
  const modelCapability = typeof adapter.getModelCapability === 'function'
    ? await adapter.getModelCapability(status)
    : {};
  return {
    ...defaultModelCapability(),
    ...status,
    ...modelCapability,
    displayName: status.displayName || adapter.displayName || adapter.name,
    profile: status.profile || (typeof adapter.getProfile === 'function' ? adapter.getProfile() : null),
    capabilities: typeof adapter.getCapabilities === 'function' ? adapter.getCapabilities() : status.capabilities
  };
}

function defaultModelCapability() {
  return { models: [], selectedModel: null, canSelectModel: false };
}

module.exports = { AdapterRegistry };
