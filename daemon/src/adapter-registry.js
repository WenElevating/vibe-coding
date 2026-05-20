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
  const rawCapabilities = {
    ...(typeof adapter.getCapabilities === 'function' ? adapter.getCapabilities() : {}),
    ...(status.capabilities || {})
  };
  const attachments = normalizeAttachmentCapabilities(rawCapabilities?.attachments);
  const rawModels = selectRawModels(modelCapability, status);
  const models = normalizeModels(rawModels, attachments);
  const selectedModel = normalizeSelectedModelId(modelCapability.selectedModel) || normalizeSelectedModelId(status.selectedModel);
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
    models: models.map((model) => modelCapabilityHashInput(model, attachments)),
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

function selectRawModels(modelCapability, status) {
  if (Array.isArray(modelCapability.models) && modelCapability.models.length > 0) return modelCapability.models;
  return status.models;
}

function normalizeSelectedModelId(value) {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return trimmed || null;
}

function modelCapabilityHashInput(model, adapterAttachments) {
  const input = {
    id: model.id
  };
  if (Array.isArray(model.inputModalities)) {
    input.inputModalities = model.inputModalities;
  }
  const defaultProjection = applyModelAttachmentCapabilities({
    id: model.id,
    inputModalities: model.inputModalities
  }, adapterAttachments);
  if (!sameAttachments(model.attachments, defaultProjection.attachments)) {
    input.attachments = model.attachments;
  }
  return input;
}

function sameAttachments(left, right) {
  return left?.image === right?.image &&
    left?.pdf === right?.pdf &&
    left?.textDocument === right?.textDocument;
}

module.exports = { AdapterRegistry };
