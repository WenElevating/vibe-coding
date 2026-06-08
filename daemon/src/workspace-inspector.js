'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const DEFAULT_IGNORES = new Set(['.git', 'node_modules', 'build', 'dist', '.dart_tool', '.omx', '.gradle']);
const TEXT_EXTENSIONS = new Set(['.dart', '.js', '.ts', '.tsx', '.jsx', '.json', '.md', '.yaml', '.yml', '.txt', '.html', '.css', '.cpp', '.h', '.kt', '.java', '.swift']);

class WorkspaceInspector {
  constructor({ spawnSyncFn = spawnSync, maxFileBytes = 200000, maxTreeEntries = 800 } = {}) {
    this.spawnSyncFn = spawnSyncFn;
    this.maxFileBytes = maxFileBytes;
    this.maxTreeEntries = maxTreeEntries;
  }

  overview(workspace) {
    const files = this._walkFiles(workspace.path, { maxEntries: this.maxTreeEntries });
    let codeLines = 0;
    let symbolCount = 0;
    for (const file of files) {
      if (!isTextPath(file.absolutePath)) continue;
      const text = safeReadText(file.absolutePath, 120000);
      if (text == null) continue;
      codeLines += text.split(/\r?\n/).filter((line) => line.trim()).length;
      symbolCount += (text.match(/\b(function|class|Future<|void|const|final)\b/g) || []).length;
    }
    return {
      workspaceId: workspace.id,
      name: workspace.name,
      path: workspace.path,
      fileCount: files.length,
      codeLineCount: codeLines,
      symbolCount,
      analysisScore: Math.max(50, Math.min(99, 100 - Math.floor(files.length / 100))),
      recentFiles: files.slice(0, 10).map((file) => ({ path: file.relativePath, modifiedAt: file.modifiedAt }))
    };
  }

  tree(workspace, { relativePath = '', maxDepth = 8 } = {}) {
    const root = safeResolve(workspace.path, relativePath);
    const stat = fs.statSync(root);
    if (!stat.isDirectory()) throw httpError(400, 'path is not a directory', 'NOT_DIRECTORY');
    return { workspaceId: workspace.id, root: normalizePath(relativePath), entries: this._treeEntries(workspace.path, root, 0, Number(maxDepth) || 8, { count: 0 }) };
  }

  content(workspace, relativePath) {
    if (!relativePath) throw httpError(400, 'path query is required', 'PATH_REQUIRED');
    const absolutePath = safeResolve(workspace.path, relativePath);
    const stat = fs.statSync(absolutePath);
    if (!stat.isFile()) throw httpError(400, 'path is not a file', 'NOT_FILE');
    if (stat.size > this.maxFileBytes) {
      return { workspaceId: workspace.id, path: normalizePath(relativePath), binary: false, tooLarge: true, size: stat.size, content: '' };
    }
    const buffer = fs.readFileSync(absolutePath);
    const binary = isProbablyBinary(buffer) && !isTextPath(absolutePath);
    return {
      workspaceId: workspace.id,
      path: normalizePath(relativePath),
      binary,
      tooLarge: false,
      size: stat.size,
      language: languageForPath(relativePath),
      content: binary ? '' : buffer.toString('utf8')
    };
  }

  commits(workspace, { limit = 20 } = {}) {
    const count = Math.max(1, Math.min(Number(limit) || 20, 100));
    const result = this.spawnSyncFn('git', ['log', `--max-count=${count}`, '--pretty=format:%H%x1f%h%x1f%s%x1f%an%x1f%ad', '--date=iso'], { cwd: workspace.path, encoding: 'utf8' });
    if (result.status !== 0) throw httpError(400, result.stderr || 'workspace is not a git repository', 'GIT_NOT_REPOSITORY');
    return { workspaceId: workspace.id, commits: String(result.stdout || '').split(/\r?\n/).filter(Boolean).map(parseCommitLine) };
  }

  diagnostics(workspace) {
    const diagnostics = [];
    for (const file of this._walkFiles(workspace.path, { maxEntries: this.maxTreeEntries })) {
      if (!isTextPath(file.absolutePath)) continue;
      const text = safeReadText(file.absolutePath, 80000);
      if (text == null) continue;
      text.split(/\r?\n/).forEach((line, index) => {
        if (line.includes('TODO') || line.includes('FIXME')) {
          diagnostics.push({ path: file.relativePath, line: index + 1, column: Math.max(1, line.indexOf('TODO') + 1 || line.indexOf('FIXME') + 1), severity: 'info', message: line.trim() });
        }
      });
    }
    return { workspaceId: workspace.id, available: true, diagnostics };
  }

  async extensions(adapterRegistry) {
    const adapters = await adapterRegistry.listCapabilities();
    return {
      extensions: adapters.map((adapter) => ({
        id: adapter.adapter,
        name: displayName(adapter.adapter),
        version: adapter.version || '',
        installed: Boolean(adapter.available),
        status: adapter.status || 'unknown',
        description: adapter.actionable || adapter.error || `${displayName(adapter.adapter)} integration`
      }))
    };
  }

  _treeEntries(workspaceRoot, currentPath, depth, maxDepth, counter) {
    if (depth >= maxDepth || counter.count >= this.maxTreeEntries) return [];
    return fs.readdirSync(currentPath, { withFileTypes: true })
      .filter((entry) => !DEFAULT_IGNORES.has(entry.name))
      .sort((a, b) => Number(b.isDirectory()) - Number(a.isDirectory()) || a.name.localeCompare(b.name))
      .slice(0, this.maxTreeEntries - counter.count)
      .map((entry) => {
        counter.count += 1;
        const absolutePath = path.join(currentPath, entry.name);
        const relativePath = normalizePath(path.relative(workspaceRoot, absolutePath));
        return { name: entry.name, path: relativePath, type: entry.isDirectory() ? 'directory' : 'file', children: entry.isDirectory() ? this._treeEntries(workspaceRoot, absolutePath, depth + 1, maxDepth, counter) : [] };
      });
  }

  _walkFiles(root, { maxEntries }) {
    const files = [];
    const visit = (dir) => {
      if (files.length >= maxEntries) return;
      for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        if (DEFAULT_IGNORES.has(entry.name)) continue;
        const absolutePath = path.join(dir, entry.name);
        if (entry.isDirectory()) visit(absolutePath);
        else if (entry.isFile()) {
          const stat = fs.statSync(absolutePath);
          files.push({ absolutePath, relativePath: normalizePath(path.relative(root, absolutePath)), modifiedAt: stat.mtime.toISOString() });
        }
        if (files.length >= maxEntries) return;
      }
    };
    visit(root);
    return files.sort((a, b) => String(b.modifiedAt).localeCompare(String(a.modifiedAt)));
  }
}

function safeResolve(root, relativePath) {
  const normalizedRoot = path.resolve(root);
  const resolved = path.resolve(normalizedRoot, relativePath || '.');
  if (!isPathWithinRoot(resolved, normalizedRoot)) throw httpError(400, 'path escapes workspace', 'PATH_OUTSIDE_WORKSPACE');
  if (!fs.existsSync(resolved)) throw httpError(404, 'path not found', 'PATH_NOT_FOUND');
  const realRoot = realpath(normalizedRoot);
  const realResolved = realpath(resolved);
  if (!isPathWithinRoot(realResolved, realRoot)) throw httpError(400, 'path escapes workspace', 'PATH_OUTSIDE_WORKSPACE');
  return resolved;
}

function realpath(value) {
  const nativeRealpath = fs.realpathSync.native || fs.realpathSync;
  return nativeRealpath(value);
}

function isPathWithinRoot(target, root) {
  const comparableTarget = normalizePathForGuard(target);
  const comparableRoot = normalizePathForGuard(root);
  return comparableTarget === comparableRoot || comparableTarget.startsWith(comparableRoot + path.sep);
}

function normalizePathForGuard(value) {
  const normalized = path.normalize(value);
  return process.platform === 'win32' ? normalized.toLowerCase() : normalized;
}

function safeReadText(filePath, maxBytes) {
  try {
    const stat = fs.statSync(filePath);
    if (stat.size > maxBytes) return null;
    const buffer = fs.readFileSync(filePath);
    if (isProbablyBinary(buffer) && !isTextPath(filePath)) return null;
    return buffer.toString('utf8');
  } catch {
    return null;
  }
}

function isProbablyBinary(buffer) {
  return buffer.subarray(0, Math.min(buffer.length, 512)).includes(0);
}

function isTextPath(filePath) {
  return TEXT_EXTENSIONS.has(path.extname(filePath).toLowerCase());
}

function languageForPath(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  return ({ '.dart': 'Dart', '.js': 'JavaScript', '.ts': 'TypeScript', '.json': 'JSON', '.md': 'Markdown', '.cpp': 'C++', '.h': 'C++' })[ext] || ext.replace('.', '').toUpperCase();
}

function parseCommitLine(line) {
  const [hash, shortHash, subject, author, date] = line.split('\x1f');
  return { hash, shortHash, subject, author, date };
}

function normalizePath(value) {
  return String(value || '').replace(/\\/g, '/');
}

function displayName(id) {
  return String(id).split('-').map((part) => part ? part[0].toUpperCase() + part.slice(1) : part).join(' ');
}

function httpError(status, message, code) {
  const error = new Error(message);
  error.status = status;
  error.code = code;
  return error;
}

module.exports = { WorkspaceInspector, safeResolve };
