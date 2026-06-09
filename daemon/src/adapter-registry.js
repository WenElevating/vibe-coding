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
      this.capabilitiesLoad = Promise.all(Array.from(this.adapters.values()).map(async (adapter) => enrich(adapter, await loadAdapterStatus(adapter))))
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

async function loadAdapterStatus(adapter) {
  try {
    return await adapter.detectCapabilities();
  } catch (error) {
    const message = publicAdapterDetectionFailureMessage(error);
    return {
      adapter: adapter.name,
      available: false,
      status: 'unavailable',
      error: message,
      actionable: message
    };
  }
}

function publicAdapterDetectionFailureMessage(error) {
  const message = safePublicMessage(safeErrorField(error, 'message'));
  const code = safeTokenString(safeErrorField(error, 'code'));
  const name = safeTokenString(safeErrorField(error, 'name'));
  const detail = message || code || (name && name !== 'Error' ? name : null);
  return detail
    ? `Adapter capability detection failed: ${detail}`
    : 'Adapter capability detection failed.';
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

function safePublicMessage(value, maxLength = 128) {
  if (typeof value !== 'string' && typeof value !== 'number') return null;
  const text = String(value).trim();
  if (!text || text.length > maxLength) return null;
  if (/[\\/\r\n]/.test(text)) return null;
  if (/[:?&][A-Za-z0-9_.-]*(?:token|secret|password|api[_-]?key|authorization)[A-Za-z0-9_.-]*=/i.test(text)) return null;
  if (/(?:token|secret|password|api[_-]?key|authorization|bearer)\s*[:=]/i.test(text)) return null;
  if (/\b[A-Za-z][A-Za-z0-9_.-]*=/.test(text)) return null;
  if (!/^[A-Za-z0-9 _.,:;()'"+-]+$/.test(text)) return null;
  return text;
}

function safeTokenString(value, maxLength = 128) {
  if (typeof value !== 'string' && typeof value !== 'number') return null;
  const text = String(value).trim();
  if (!text || text.length > maxLength) return null;
  return /^[A-Za-z0-9_.-]+$/.test(text) ? text : null;
}

function safeErrorField(error, key) {
  if (!error || (typeof error !== 'object' && typeof error !== 'function')) return undefined;
  let current = error;
  while (current) {
    const value = safeDataPropertyValue(current, key);
    if (value !== undefined) return value;
    try {
      const descriptor = Object.getOwnPropertyDescriptor(current, key);
      if (descriptor && !Object.prototype.hasOwnProperty.call(descriptor, 'value')) return undefined;
      current = Object.getPrototypeOf(current);
    } catch (_) {
      return undefined;
    }
  }
  return undefined;
}

function safeDataPropertyValue(value, key) {
  if (!value || (typeof value !== 'object' && typeof value !== 'function')) return undefined;
  try {
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    if (!descriptor || !Object.prototype.hasOwnProperty.call(descriptor, 'value')) return undefined;
    return descriptor.value;
  } catch (_) {
    return undefined;
  }
}

module.exports = { AdapterRegistry };
