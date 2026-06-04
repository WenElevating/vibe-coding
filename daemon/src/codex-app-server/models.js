'use strict';

function normalizeCodexAppServerModelCapability(response) {
  const rawModels = Array.isArray(response?.data) ? response.data : [];
  const models = [];
  for (const raw of rawModels) {
    const model = normalizeCodexAppServerModel(raw);
    if (!model || models.some((item) => item.id === model.id)) continue;
    models.push(model);
  }
  const selected = models.find((model) => model.selected) || models[0] || null;
  if (selected) {
    for (const model of models) model.selected = model.id === selected.id;
  }
  return {
    models,
    selectedModel: selected?.id || null,
    canSelectModel: true
  };
}

function normalizeCodexAppServerModel(raw) {
  if (!raw || typeof raw !== 'object' || raw.hidden === true) return null;
  const id = String(raw.id || raw.model || raw.name || '').trim();
  if (!id) return null;
  const label = String(raw.displayName || raw.display_name || raw.label || id).trim() || id;
  const model = {
    id,
    label,
    source: 'app_server',
    selected: raw.isDefault === true || raw.default === true
  };
  const inputModalities = Array.isArray(raw.inputModalities)
    ? raw.inputModalities
    : Array.isArray(raw.input_modalities)
    ? raw.input_modalities
    : null;
  if (inputModalities) model.inputModalities = inputModalities;
  return model;
}

module.exports = {
  normalizeCodexAppServerModel,
  normalizeCodexAppServerModelCapability
};
