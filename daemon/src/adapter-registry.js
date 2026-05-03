'use strict';

class AdapterRegistry {
  constructor(adapters) {
    this.adapters = new Map(adapters.map((adapter) => [adapter.name, adapter]));
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
    return Promise.all(Array.from(this.adapters.values()).map(async (adapter) => enrich(adapter, await adapter.detectCapabilities())));
  }
}

function enrich(adapter, status) {
  return {
    ...status,
    displayName: adapter.displayName || adapter.name,
    profile: typeof adapter.getProfile === 'function' ? adapter.getProfile() : null,
    capabilities: typeof adapter.getCapabilities === 'function' ? adapter.getCapabilities() : status.capabilities
  };
}

module.exports = { AdapterRegistry };
