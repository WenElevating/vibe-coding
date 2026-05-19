'use strict';

const fs = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');

const messageScratchDirNamePattern = /^msg_\d+_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

class AttachmentScratchStore {
  constructor({ root, ttlMs = 86_400_000, now = () => new Date() }) {
    this.root = path.resolve(root);
    this.ttlMs = ttlMs;
    this.now = now;
  }

  async createMessageScratch({ conversationId, clientMessageId, scratchLifetime }) {
    await fs.mkdir(this.root, { recursive: true });
    const dir = path.join(this.root, `msg_${Date.now()}_${crypto.randomUUID()}`);
    const resolved = path.resolve(dir);
    if (!isUnderRoot(resolved, this.root)) throw new Error('scratch path escaped root');
    await fs.mkdir(resolved, { recursive: false });
    const scratch = new MessageScratch({
      root: this.root,
      dir: resolved,
      baseMetadata: {
        conversationId,
        clientMessageId,
        scratchLifetime,
        createdAt: this.now().toISOString()
      }
    });
    await scratch.writeMetadata({});
    return scratch;
  }

  async cleanupExpired({ activeConversationIds = new Set() } = {}) {
    const entries = await fs.readdir(this.root, { withFileTypes: true }).catch(() => []);
    const cutoff = this.now().getTime() - this.ttlMs;
    for (const entry of entries) {
      if (!entry.isDirectory()) continue;
      const dir = path.resolve(path.join(this.root, entry.name));
      if (!isUnderRoot(dir, this.root)) continue;
      const metadata = await readJson(path.join(dir, 'metadata.json'));
      if (metadata?.conversationId && activeConversationIds.has(metadata.conversationId)) continue;
      const createdAt = Date.parse(metadata?.createdAt || '');
      if (!Number.isFinite(createdAt) || createdAt < cutoff) {
        await fs.rm(dir, { recursive: true, force: true });
      }
    }
  }
}

class MessageScratch {
  #root;
  #dir;
  #baseMetadata;

  constructor({ root, dir, baseMetadata }) {
    const resolvedRoot = path.resolve(root);
    const resolvedDir = path.resolve(dir);
    if (!isChildUnderRoot(resolvedDir, resolvedRoot)) throw new Error('scratch path escaped root');
    if (!isMessageScratchDirName(path.basename(resolvedDir))) throw new Error('scratch path escaped root');
    this.#root = resolvedRoot;
    this.#dir = resolvedDir;
    this.#baseMetadata = Object.freeze({ ...baseMetadata });
  }

  get root() {
    return this.#root;
  }

  get dir() {
    return this.#dir;
  }

  async writeFile(fileName, bytes) {
    const target = path.resolve(path.join(this.#dir, fileName));
    if (!isUnderRoot(target, this.#dir)) throw new Error('scratch file path escaped message directory');
    await fs.writeFile(target, bytes);
    return target;
  }

  async writeMetadata(metadata) {
    await fs.writeFile(
      path.join(this.#dir, 'metadata.json'),
      `${JSON.stringify({ ...metadata, ...this.#baseMetadata }, null, 2)}\n`,
      'utf8'
    );
  }

  async cleanup() {
    if (!isChildUnderRoot(this.#dir, this.#root)) throw new Error('scratch cleanup path escaped root');
    await fs.rm(this.#dir, { recursive: true, force: true });
  }
}

async function readJson(filePath) {
  try {
    return JSON.parse(await fs.readFile(filePath, 'utf8'));
  } catch {
    return null;
  }
}

function isUnderRoot(target, root) {
  const relative = path.relative(path.resolve(root), path.resolve(target));
  return relative === '' || (!relative.startsWith('..') && !path.isAbsolute(relative));
}

function isChildUnderRoot(target, root) {
  const relative = path.relative(path.resolve(root), path.resolve(target));
  return relative !== '' && !relative.startsWith('..') && !path.isAbsolute(relative);
}

function isMessageScratchDirName(name) {
  return messageScratchDirNamePattern.test(name);
}

module.exports = { AttachmentScratchStore, MessageScratch, isUnderRoot };
