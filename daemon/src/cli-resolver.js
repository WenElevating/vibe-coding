'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

function resolveCliInvocation(command, {
  platform = process.platform,
  nodePath = process.execPath,
  which = defaultWhich,
  readTextFile = (filePath) => fs.readFileSync(filePath, 'utf8'),
  existsSync = fs.existsSync,
  spawnSyncFn = spawnSync,
  env = process.env,
  homeDir = os.homedir()
} = {}) {
  const original = { command, argsPrefix: [] };
  if (!command || typeof command !== 'string') return original;
  if (platform !== 'win32') return original;

  const cliPath = findCliPath(command, { which, existsSync, spawnSyncFn, env, homeDir });
  if (!cliPath) return original;
  if (!/\.cmd$/i.test(cliPath)) return { command: cliPath, argsPrefix: [] };

  const parsed = resolveWindowsCmdShim(cliPath, { nodePath, readTextFile });
  return parsed || original;
}

function findCliPath(command, { which, existsSync, spawnSyncFn, env, homeDir }) {
  if (isExplicitPath(command)) {
    return existsSync(command) ? command : null;
  }
  const found = which(command, { spawnSyncFn });
  if (found) return found;
  if (found === '') return null;
  return findCommonCliPath(command, { existsSync, env, homeDir });
}

function defaultWhich(command, { spawnSyncFn = spawnSync } = {}) {
  const result = spawnSyncFn('where.exe', [command], { encoding: 'utf8' });
  if (result.error || result.status !== 0) return null;
  const paths = String(result.stdout || '')
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(isLikelyPath);
  return paths.find((line) => /\.cmd$/i.test(line)) || paths[0] || '';
}

function findCommonCliPath(command, { existsSync, env, homeDir }) {
  const baseNames = cliBaseNames(command);
  const directories = [
    env?.npm_config_prefix,
    env?.NPM_CONFIG_PREFIX,
    path.join(homeDir, 'npm-global'),
    path.join(homeDir, '.npm-global', 'bin'),
    path.join(homeDir, 'node_modules', '.bin'),
    path.join(homeDir, '.yarn', 'bin'),
    path.join(homeDir, '.claude', 'local')
  ].filter(Boolean);
  for (const directory of directories) {
    for (const baseName of baseNames) {
      const candidate = path.join(directory, baseName);
      if (existsSync(candidate)) return candidate;
    }
  }
  return null;
}

function cliBaseNames(command) {
  const ext = path.extname(command);
  if (ext) return [command];
  return [`${command}.cmd`, `${command}.exe`, command];
}

function resolveWindowsCmdShim(shimPath, { nodePath, readTextFile }) {
  let text = '';
  try {
    text = readTextFile(shimPath);
  } catch {
    return null;
  }
  const target = parseNpmCmdTarget(text);
  if (!target) return null;
  const absoluteTarget = path.resolve(path.dirname(shimPath), target);
  if (/\.js$/i.test(absoluteTarget)) {
    return { command: nodePath, argsPrefix: [absoluteTarget] };
  }
  return { command: absoluteTarget, argsPrefix: [] };
}

function parseNpmCmdTarget(text) {
  const source = String(text);
  const match = source.match(/%dp0%\\([^"]+?\.js)"/i)
    || source.match(/%dp0%\\([^"]+?\.exe)"/i);
  return match ? match[1] : null;
}

function isExplicitPath(command) {
  return path.isAbsolute(command) || /[\\/]/.test(command);
}

function isLikelyPath(value) {
  return /^[a-z]:[\\/]/i.test(value) || /^\\\\/.test(value) || value.startsWith('/');
}

module.exports = {
  resolveCliInvocation,
  defaultWhich,
  parseNpmCmdTarget
};
