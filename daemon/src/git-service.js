'use strict';

const { spawnSync } = require('node:child_process');
const { errorCodes } = require('./protocol');

class GitService {
  constructor({ spawnSyncFn = spawnSync, maxDiffBytes = 200000 } = {}) {
    this.spawnSyncFn = spawnSyncFn;
    this.maxDiffBytes = maxDiffBytes;
  }

  status(workspace) {
    const result = this.spawnSyncFn('git', ['status', '--short'], { cwd: workspace.path, encoding: 'utf8' });
    if (result.status !== 0) throw gitError(errorCodes.GIT_NOT_REPOSITORY, result.stderr || 'workspace is not a git repository');
    return {
      workspaceId: workspace.id,
      clean: !String(result.stdout || '').trim(),
      files: String(result.stdout || '').split(/\r?\n/).filter(Boolean).map(parseStatusLine)
    };
  }

  diff(workspace, { maxBytes = this.maxDiffBytes } = {}) {
    const result = this.spawnSyncFn('git', ['diff', '--stat', '--numstat'], { cwd: workspace.path, encoding: 'utf8', maxBuffer: maxBytes });
    if (result.error && result.error.code === 'ENOBUFS') throw gitError(errorCodes.GIT_DIFF_TOO_LARGE, 'git diff is too large');
    if (result.status !== 0) throw gitError(errorCodes.GIT_NOT_REPOSITORY, result.stderr || 'workspace is not a git repository');
    const raw = String(result.stdout || '');
    return { workspaceId: workspace.id, summaries: parseNumstat(raw), rawPreview: raw.slice(0, 4000) };
  }
}

function parseStatusLine(line) {
  return { status: line.slice(0, 2).trim(), path: line.slice(3).trim() };
}

function parseNumstat(output) {
  return output.split(/\r?\n/).map((line) => {
    const match = line.match(/^(\d+|-)\t(\d+|-)\t(.+)$/);
    if (!match) return null;
    const [, additions, deletions, filePath] = match;
    return {
      filePath,
      additions: additions === '-' ? 0 : Number(additions),
      deletions: deletions === '-' ? 0 : Number(deletions),
      binary: additions === '-' || deletions === '-'
    };
  }).filter(Boolean);
}

function gitError(code, message) {
  const error = new Error(message);
  error.status = code === errorCodes.GIT_DIFF_TOO_LARGE ? 413 : 400;
  error.code = code;
  error.recoverable = true;
  return error;
}

module.exports = { GitService, parseStatusLine, parseNumstat };
