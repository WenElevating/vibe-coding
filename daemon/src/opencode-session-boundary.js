'use strict';

const path = require('node:path');
const fs = require('node:fs');

function extractSessionId(value) {
  if (!value || typeof value !== 'object') return null;
  const direct = firstNonBlank([
    safeOwnValue(value, 'id'),
    safeOwnValue(value, 'sessionId'),
    safeOwnValue(value, 'sessionID'),
    safeOwnValue(value, 'session_id')
  ]);
  if (direct) return direct;
  const session = safeOwnValue(value, 'session');
  if (typeof session === 'string' || typeof session === 'number') return safeString(session);
  if (session && typeof session === 'object') {
    return firstNonBlank([
      safeOwnValue(session, 'id'),
      safeOwnValue(session, 'sessionId'),
      safeOwnValue(session, 'sessionID'),
      safeOwnValue(session, 'session_id')
    ]);
  }
  return null;
}

function extractSessionDirectory(value) {
  if (!value || typeof value !== 'object') return null;
  const direct = firstNonBlank([
    safeOwnValue(value, 'directory'),
    safeOwnValue(value, 'cwd'),
    safeOwnValue(value, 'path')
  ]);
  if (direct) return direct;
  const session = safeOwnValue(value, 'session');
  if (session && typeof session === 'object') {
    return firstNonBlank([
      safeOwnValue(session, 'directory'),
      safeOwnValue(session, 'cwd'),
      safeOwnValue(session, 'path')
    ]);
  }
  return null;
}

function validateSessionDirectory(directory, workspacePath) {
  if (!directory) {
    throw sessionBoundaryError();
  }
  if (!pathContainsOrEquals(workspacePath, directory)) {
    throw sessionBoundaryError();
  }
  const realWorkspace = tryRealpath(workspacePath);
  const realDirectory = tryRealpath(directory);
  if (realWorkspace && realDirectory && !pathContainsOrEquals(realWorkspace, realDirectory)) {
    throw sessionBoundaryError();
  }
}

function pathContainsOrEquals(rootPath, candidatePath) {
  const flavor = pathFlavor(rootPath, candidatePath);
  const pathApi = flavor === 'win32' ? path.win32 : path.posix;
  const root = normalizeForPathFlavor(rootPath, pathApi, flavor);
  const candidate = normalizeForPathFlavor(candidatePath, pathApi, flavor);
  if (!root || !candidate) return false;
  const normalizedRoot = flavor === 'win32' ? root.toLowerCase() : root;
  const normalizedCandidate = flavor === 'win32' ? candidate.toLowerCase() : candidate;
  if (normalizedCandidate === normalizedRoot) return true;
  const rootWithSeparator = normalizedRoot.endsWith(pathApi.sep) ? normalizedRoot : `${normalizedRoot}${pathApi.sep}`;
  return normalizedCandidate.startsWith(rootWithSeparator);
}

function sessionBoundaryError() {
  const error = new Error('OpenCode session directory is outside the authorized workspace.');
  error.status = 409;
  error.code = 'OPENCODE_SESSION_DIRECTORY_MISMATCH';
  error.details = { reason: 'directory_mismatch' };
  return error;
}

function pathFlavor(...paths) {
  const texts = paths.map((value) => String(value || '')).filter(Boolean);
  if (texts.some((text) => /^[a-zA-Z]:[\\/]/.test(text) || /^\\\\/.test(text))) return 'win32';
  if (texts.length > 0 && texts.every((text) => text.startsWith('/'))) return 'posix';
  return texts.some((text) => text.includes('\\')) ? 'win32' : 'posix';
}

function normalizeForPathFlavor(value, pathApi, flavor) {
  const text = safeString(value);
  if (!text || !pathApi.isAbsolute(text)) return null;
  const normalized = pathApi.normalize(text);
  if (flavor !== 'win32') return normalized;
  return normalized.replace(/[\\/]+$/, '');
}

function tryRealpath(value) {
  try {
    const nativeRealpath = fs.realpathSync.native || fs.realpathSync;
    return nativeRealpath(value);
  } catch (error) {
    if (error?.code === 'ENOENT' || error?.code === 'ENOTDIR') return null;
    throw sessionBoundaryError();
  }
}

function firstNonBlank(values) {
  for (const value of values) {
    const text = safeString(value);
    if (text) return text;
  }
  return null;
}

function safeOwnValue(value, key) {
  if (!value || typeof value !== 'object') return undefined;
  try {
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    if (!descriptor || !Object.prototype.hasOwnProperty.call(descriptor, 'value')) return undefined;
    return descriptor.value;
  } catch (_) {
    return undefined;
  }
}

function safeString(value) {
  if (typeof value !== 'string' && typeof value !== 'number') return '';
  return String(value).trim();
}

module.exports = {
  extractSessionId,
  extractSessionDirectory,
  validateSessionDirectory,
  pathContainsOrEquals
};
