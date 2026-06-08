'use strict';

const path = require('node:path');
const fs = require('node:fs');

function extractSessionId(value) {
  if (!value || typeof value !== 'object') return null;
  const direct = firstNonBlank([
    value.id,
    value.sessionId,
    value.sessionID,
    value.session_id
  ]);
  if (direct) return direct;
  if (typeof value.session === 'string' || typeof value.session === 'number') return safeString(value.session);
  if (value.session && typeof value.session === 'object') {
    return firstNonBlank([
      value.session.id,
      value.session.sessionId,
      value.session.sessionID,
      value.session.session_id
    ]);
  }
  return null;
}

function extractSessionDirectory(value) {
  if (!value || typeof value !== 'object') return null;
  const direct = firstNonBlank([value.directory, value.cwd]);
  if (direct) return direct;
  if (value.session && typeof value.session === 'object') {
    return firstNonBlank([value.session.directory, value.session.cwd]);
  }
  return null;
}

function validateSessionDirectory(directory, workspacePath) {
  if (!directory) return;
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
  return paths.some((value) => /^[a-zA-Z]:[\\/]/.test(String(value || '')) || /^\\\\/.test(String(value || '')) || String(value || '').includes('\\'))
    ? 'win32'
    : 'posix';
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
    throw error;
  }
}

function firstNonBlank(values) {
  for (const value of values) {
    const text = safeString(value);
    if (text) return text;
  }
  return null;
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
