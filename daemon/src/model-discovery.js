'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const MODEL_CATALOG_MAX_BYTES = 1024 * 1024;

const MODEL_SOURCES = {
  CODEX_CONFIG: 'codex_config',
  CODEX_CATALOG: 'codex_catalog',
  CLAUDE_ENV: 'claude_env',
  CLAUDE_CONFIG: 'claude_config',
  CLI_DEFAULT: 'cli_default',
  UNKNOWN: 'unknown'
};

const CLAUDE_ENV_MODEL_KEYS = [
  'ANTHROPIC_DEFAULT_OPUS_MODEL',
  'ANTHROPIC_DEFAULT_SONNET_MODEL',
  'ANTHROPIC_DEFAULT_HAIKU_MODEL'
];

const TOP_LEVEL_CONFIG_KEYS = new Set(['model', 'model_provider', 'model_catalog_json']);
const ALLOWED_SECTION_PATHS = new Set(['shell_environment_policy.set']);
const DANGEROUS_CONFIG_KEYS = new Set(['__proto__', 'prototype', 'constructor']);

function discoverConfiguredModels(options = {}) {
  try {
    const env = options.env || process.env;
    if (isDiscoveryDisabled(env)) return emptyDiscovery();

    if (options.adapter === 'codex') return discoverCodexModels(options, env);
    if (options.adapter === 'claude') return discoverClaudeModels(options, env);
    return emptyDiscovery();
  } catch (_error) {
    return emptyDiscovery();
  }
}

function parseTomlScalarConfig(text) {
  const config = {};
  let section = [];
  if (typeof text !== 'string') return config;

  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;

    const sectionMatch = line.match(/^\[([A-Za-z0-9_.-]+)\]$/);
    if (sectionMatch) {
      const nextSection = sectionMatch[1].split('.');
      section = isAllowedSection(nextSection) ? nextSection : null;
      continue;
    }

    const assignment = line.match(/^([A-Za-z0-9_-]+)\s*=\s*("(?:\\["\\nrt]|[^"\\\n])*"|'[^'\n]*')\s*(?:#.*)?$/);
    if (!assignment || section === null) continue;

    const valueText = assignment[2];
    if (valueText.startsWith('"""') || valueText.startsWith("'''")) continue;

    const value = parseQuotedScalar(valueText);
    if (typeof value !== 'string') continue;
    setConfigValue(config, section, assignment[1], value);
  }

  return config;
}

function discoverCodexModels(options, env) {
  const homeDir = options.homeDir || os.homedir();
  const workspacePath = options.workspacePath || process.cwd();
  const userConfigPath = options.userConfigPath || path.join(homeDir, '.codex', 'config.toml');
  const projectConfigPath = options.projectConfigPath || path.join(workspacePath, '.codex', 'config.toml');
  const userConfig = readTomlConfig(userConfigPath);
  const projectConfig = readTomlConfig(projectConfigPath);
  const config = { ...userConfig, ...projectConfig };
  const models = [];

  if (isNonEmptyString(config.model)) {
    addModel(models, config.model, MODEL_SOURCES.CODEX_CONFIG, true);
  }

  for (const model of readCatalogModels(config.model_catalog_json, workspacePath)) {
    addModel(models, model.id, MODEL_SOURCES.CODEX_CATALOG, model.id === config.model, model.label);
  }

  markSelected(models, config.model);
  return {
    models,
    selectedModel: selectedModelFrom(models),
    canSelectModel: false
  };
}

function discoverClaudeModels(options, env) {
  const homeDir = options.homeDir || os.homedir();
  const workspacePath = options.workspacePath || process.cwd();
  const userSettings = readClaudeSettings(
    options.claudeSettingsPath || path.join(homeDir, '.claude', 'settings.json')
  );
  const projectSettings = readClaudeSettings(
    options.claudeProjectSettingsPath || path.join(workspacePath, '.claude', 'settings.json')
  );
  const models = [];

  addClaudeSettingsModels(models, userSettings, MODEL_SOURCES.CLAUDE_CONFIG);
  addClaudeSettingsModels(models, projectSettings, MODEL_SOURCES.CLAUDE_CONFIG);

  const projectConfigPath = options.projectConfigPath || path.join(workspacePath, '.codex', 'config.toml');
  const projectConfig = readTomlConfig(projectConfigPath);
  const shellEnv = projectConfig.shell_environment_policy && projectConfig.shell_environment_policy.set;
  if (shellEnv) {
    for (const key of CLAUDE_ENV_MODEL_KEYS) {
      addModel(models, shellEnv[key], MODEL_SOURCES.CLAUDE_CONFIG, false);
    }
  }

  for (const key of CLAUDE_ENV_MODEL_KEYS) {
    addModel(models, env[key], MODEL_SOURCES.CLAUDE_ENV, false);
  }

  if (models.length === 0) {
    addModel(models, userSettings.model || projectSettings.model, MODEL_SOURCES.CLI_DEFAULT, true);
  }

  markSelected(models, preferredClaudeModel(userSettings, projectSettings, shellEnv, env) || (models[0] && models[0].id));
  return {
    models,
    selectedModel: selectedModelFrom(models),
    canSelectModel: false
  };
}

function readClaudeSettings(settingsPath) {
  try {
    const text = readTextFileIfSafe(settingsPath);
    if (text === null) return emptyClaudeSettings();
    const parsed = JSON.parse(text);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) return emptyClaudeSettings();
    const settingsEnv = parsed.env && typeof parsed.env === 'object' && !Array.isArray(parsed.env)
      ? parsed.env
      : {};
    return {
      model: isNonEmptyString(parsed.model) ? parsed.model : null,
      models: modelsFromEnv(settingsEnv)
    };
  } catch (_error) {
    return emptyClaudeSettings();
  }
}

function emptyClaudeSettings() {
  return { model: null, models: [] };
}

function modelsFromEnv(env) {
  const models = [];
  for (const key of CLAUDE_ENV_MODEL_KEYS) {
    if (isNonEmptyString(env && env[key]) && !models.includes(env[key])) models.push(env[key]);
  }
  return models;
}

function addClaudeSettingsModels(models, settings, source) {
  for (const model of settings.models) {
    addModel(models, model, source, false);
  }
}

function preferredClaudeModel(userSettings, projectSettings, projectEnv, systemEnv) {
  return preferredFromSettings(userSettings) ||
    preferredFromSettings(projectSettings) ||
    firstEnvModel(projectEnv) ||
    firstEnvModel(systemEnv);
}

function preferredFromSettings(settings) {
  if (settings.model && settings.models.includes(settings.model)) return settings.model;
  return settings.models[0] || null;
}

function firstEnvModel(env) {
  for (const key of CLAUDE_ENV_MODEL_KEYS) {
    if (isNonEmptyString(env && env[key])) return env[key];
  }
  return null;
}

function readTomlConfig(filePath) {
  const text = readTextFileIfSafe(filePath);
  if (text === null) return {};
  return parseTomlScalarConfig(text);
}

function readCatalogModels(catalogPath, workspacePath) {
  try {
    if (!isNonEmptyString(catalogPath)) return [];
    const resolvedPath = path.isAbsolute(catalogPath) ? catalogPath : path.resolve(workspacePath, catalogPath);
    const stat = fs.statSync(resolvedPath);
    if (!stat.isFile() || stat.size > MODEL_CATALOG_MAX_BYTES) return [];
    const parsed = JSON.parse(fs.readFileSync(resolvedPath, 'utf8'));
    const rawModels = Array.isArray(parsed) ? parsed : parsed && parsed.models;
    if (!Array.isArray(rawModels)) return [];
    return rawModels
      .map((entry) => normalizeCatalogModel(entry))
      .filter(Boolean);
  } catch (_error) {
    return [];
  }
}

function normalizeCatalogModel(entry) {
  if (typeof entry === 'string') return { id: entry, label: entry };
  if (!entry || typeof entry !== 'object') return null;
  const id = entry.id || entry.model || entry.name;
  if (!isNonEmptyString(id)) return null;
  return {
    id,
    label: isNonEmptyString(entry.label) ? entry.label : id
  };
}

function readTextFileIfSafe(filePath) {
  try {
    const stat = fs.statSync(filePath);
    if (!stat.isFile()) return null;
    return fs.readFileSync(filePath, 'utf8');
  } catch (_error) {
    return null;
  }
}

function parseQuotedScalar(valueText) {
  if (valueText.startsWith('"') && valueText.endsWith('"')) {
    try {
      return JSON.parse(valueText);
    } catch (_error) {
      return null;
    }
  }
  if (valueText.startsWith("'") && valueText.endsWith("'")) {
    return valueText.slice(1, -1);
  }
  return null;
}

function setConfigValue(config, section, key, value) {
  if (!isAllowedConfigKey(section, key)) return;
  let target = config;
  for (const part of section) {
    if (!Object.prototype.hasOwnProperty.call(target, part) || typeof target[part] !== 'object' || Array.isArray(target[part])) {
      target[part] = {};
    }
    target = target[part];
  }
  target[key] = value;
}

function isAllowedSection(section) {
  if (!Array.isArray(section)) return false;
  if (section.some(isDangerousConfigKey)) return false;
  if (section.length === 0) return true;
  return ALLOWED_SECTION_PATHS.has(section.join('.'));
}

function isAllowedConfigKey(section, key) {
  if (isDangerousConfigKey(key)) return false;
  if (!Array.isArray(section)) return false;
  if (section.length === 0) return TOP_LEVEL_CONFIG_KEYS.has(key);
  return isAllowedSection(section);
}

function isDangerousConfigKey(key) {
  return DANGEROUS_CONFIG_KEYS.has(key);
}

function addModel(models, id, source, selected = false, label = id) {
  if (!isNonEmptyString(id)) return;
  if (models.some((model) => model.id === id)) return;
  models.push({ id, label: isNonEmptyString(label) ? label : id, source, selected: Boolean(selected) });
}

function markSelected(models, selectedId) {
  let selectedFound = false;
  for (const model of models) {
    model.selected = Boolean(selectedId && model.id === selectedId);
    selectedFound = selectedFound || model.selected;
  }
  if (!selectedFound && models.length > 0) models[0].selected = true;
}

function selectedModelFrom(models) {
  const selected = models.find((model) => model.selected);
  return selected ? selected.id : null;
}

function isDiscoveryDisabled(env) {
  const value = env && env.VIBE_DISABLE_MODEL_DISCOVERY;
  if (typeof value !== 'string') return false;
  const normalized = value.toLowerCase();
  return normalized === '1' || normalized === 'true' || normalized === 'yes';
}

function isNonEmptyString(value) {
  return typeof value === 'string' && value.trim().length > 0;
}

function emptyDiscovery() {
  return { models: [], selectedModel: null, canSelectModel: false };
}

module.exports = {
  MODEL_CATALOG_MAX_BYTES,
  MODEL_SOURCES,
  discoverConfiguredModels,
  parseTomlScalarConfig
};
