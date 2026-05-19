'use strict';

const {
  normalizeAttachmentCapabilities,
  applyModelAttachmentCapabilities
} = require('./attachment-capabilities');
const { capabilityVersionForNormalizedInput } = require('./attachment-hashes');

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
  const modelCapability = await loadModelCapability(adapter, status);
  const rawCapabilities = typeof adapter.getCapabilities === 'function'
    ? adapter.getCapabilities()
    : status.capabilities;
  const attachments = normalizeAttachmentCapabilities(rawCapabilities?.attachments);
  const models = normalizeModels(modelCapability.models, attachments);
  const selectedModel = typeof modelCapability.selectedModel === 'string'
    ? modelCapability.selectedModel
    : null;
  const enriched = {
    ...defaultModelCapability(),
    ...status,
    ...modelCapability,
    models,
    selectedModel,
    displayName: status.displayName || adapter.displayName || adapter.name,
    profile: status.profile || (typeof adapter.getProfile === 'function' ? adapter.getProfile() : null),
    capabilities: {
      ...(rawCapabilities || {}),
      attachments
    }
  };
  enriched.capabilityVersion = capabilityVersionForNormalizedInput({
    adapterId: adapter.name,
    attachments,
    cliPath: status.cliPath || status.path || adapter.cliPath || adapter.name || status.command,
    cliVersion: status.cliVersion || status.version || null,
    models: models.map((model) => ({
      id: model.id,
      inputModalities: model.inputModalities
    })),
    selectedModelId: selectedModel
  });
  return enriched;
}

async function loadModelCapability(adapter, status) {
  if (typeof adapter.getModelCapability !== 'function') return {};
  try {
    return await adapter.getModelCapability(status);
  } catch (_error) {
    return {};
  }
}

function defaultModelCapability() {
  return { models: [], selectedModel: null, canSelectModel: false };
}

function normalizeModels(models, attachments) {
  return (Array.isArray(models) ? models : [])
    .filter((model) => model && typeof model.id === 'string' && model.id.trim())
    .map((model) => applyModelAttachmentCapabilities({
      ...model,
      id: model.id.trim()
    }, attachments))
    .sort((a, b) => a.id.localeCompare(b.id));
}

module.exports = { AdapterRegistry };
