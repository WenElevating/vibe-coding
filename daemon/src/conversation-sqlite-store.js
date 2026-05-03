'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { DatabaseSync } = require('node:sqlite');

const LIVE_STATUSES = new Set(['running', 'waiting_input', 'waiting_approval']);

class ConversationSqliteStore {
  constructor({ dbPath = defaultDbPath(), now = () => new Date() } = {}) {
    this.dbPath = dbPath;
    this.now = now;
    fs.mkdirSync(path.dirname(dbPath), { recursive: true });
    this.db = new DatabaseSync(dbPath);
    this.db.exec('PRAGMA foreign_keys = ON');
    this.migrate();
  }

  migrate() {
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version INTEGER PRIMARY KEY,
        applied_at TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS conversations (
        id TEXT PRIMARY KEY,
        workspace_id TEXT NOT NULL,
        workspace_path TEXT NOT NULL,
        adapter TEXT NOT NULL,
        permission_mode TEXT NOT NULL,
        device_id TEXT NOT NULL,
        status TEXT NOT NULL,
        cli_session_id TEXT,
        blocking_item_json TEXT,
        idle_expires_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        capabilities_json TEXT NOT NULL DEFAULT '{}'
      );
      CREATE INDEX IF NOT EXISTS idx_conversations_device_updated
        ON conversations(device_id, updated_at DESC);
      CREATE INDEX IF NOT EXISTS idx_conversations_workspace_updated
        ON conversations(workspace_id, updated_at DESC);
      CREATE TABLE IF NOT EXISTS conversation_events (
        conversation_id TEXT NOT NULL,
        seq INTEGER NOT NULL,
        type TEXT NOT NULL,
        created_at TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        PRIMARY KEY (conversation_id, seq),
        FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
      );
      CREATE INDEX IF NOT EXISTS idx_conversation_events_type_created
        ON conversation_events(type, created_at DESC);
    `);
    this.db.prepare('INSERT OR IGNORE INTO schema_migrations(version, applied_at) VALUES (?, ?)')
      .run(1, this.now().toISOString());
  }

  saveConversation(conversation) {
    const row = serializeConversation(conversation);
    this.db.prepare(`
      INSERT INTO conversations (
        id, workspace_id, workspace_path, adapter, permission_mode, device_id,
        status, cli_session_id, blocking_item_json, idle_expires_at,
        created_at, updated_at, capabilities_json
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        workspace_id = excluded.workspace_id,
        workspace_path = excluded.workspace_path,
        adapter = excluded.adapter,
        permission_mode = excluded.permission_mode,
        device_id = excluded.device_id,
        status = excluded.status,
        cli_session_id = excluded.cli_session_id,
        blocking_item_json = excluded.blocking_item_json,
        idle_expires_at = excluded.idle_expires_at,
        created_at = excluded.created_at,
        updated_at = excluded.updated_at,
        capabilities_json = excluded.capabilities_json
    `).run(
      row.id,
      row.workspace_id,
      row.workspace_path,
      row.adapter,
      row.permission_mode,
      row.device_id,
      row.status,
      row.cli_session_id,
      row.blocking_item_json,
      row.idle_expires_at,
      row.created_at,
      row.updated_at,
      row.capabilities_json
    );
  }

  loadConversations() {
    return this.db.prepare('SELECT * FROM conversations ORDER BY updated_at DESC')
      .all()
      .map(deserializeConversation);
  }

  appendEvent(event) {
    const { conversationId, seq, type, createdAt, ...payload } = event;
    this.db.prepare(`
      INSERT OR REPLACE INTO conversation_events(conversation_id, seq, type, created_at, payload_json)
      VALUES (?, ?, ?, ?, ?)
    `).run(conversationId, seq, type, createdAt, JSON.stringify(payload));
  }

  listEvents(conversationId, afterSeq = 0) {
    return this.db.prepare(`
      SELECT conversation_id, seq, type, created_at, payload_json
      FROM conversation_events
      WHERE conversation_id = ? AND seq > ?
      ORDER BY seq ASC
    `).all(conversationId, Number(afterSeq || 0)).map(deserializeEvent);
  }

  nextEventSeq(conversationId) {
    const row = this.db.prepare('SELECT COALESCE(MAX(seq), 0) + 1 AS next_seq FROM conversation_events WHERE conversation_id = ?')
      .get(conversationId);
    return row.next_seq;
  }

  close() {
    this.db.close();
  }
}

function defaultDbPath() {
  return path.join(process.cwd(), 'data', 'conversations', 'conversations.sqlite');
}

function serializeConversation(conversation) {
  return {
    id: conversation.id,
    workspace_id: conversation.workspaceId,
    workspace_path: conversation.workspacePath,
    adapter: conversation.adapter,
    permission_mode: conversation.permissionMode,
    device_id: conversation.deviceId,
    status: conversation.status,
    cli_session_id: conversation.cliSessionId || null,
    blocking_item_json: conversation.blockingItem ? JSON.stringify(conversation.blockingItem) : null,
    idle_expires_at: conversation.idleExpiresAt || null,
    created_at: conversation.createdAt,
    updated_at: conversation.updatedAt,
    capabilities_json: JSON.stringify(conversation.capabilities || {})
  };
}

function deserializeConversation(row) {
  const wasLive = LIVE_STATUSES.has(row.status);
  return {
    id: row.id,
    workspaceId: row.workspace_id,
    workspacePath: row.workspace_path,
    adapter: row.adapter,
    permissionMode: row.permission_mode,
    deviceId: row.device_id,
    status: wasLive ? 'interrupted' : row.status,
    cliSessionId: row.cli_session_id || null,
    blockingItem: wasLive ? null : parseJson(row.blocking_item_json, null),
    idleExpiresAt: wasLive ? null : row.idle_expires_at,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    capabilities: parseJson(row.capabilities_json, {}),
    handle: null
  };
}

function deserializeEvent(row) {
  return {
    seq: row.seq,
    conversationId: row.conversation_id,
    type: row.type,
    createdAt: row.created_at,
    ...parseJson(row.payload_json, {})
  };
}

function parseJson(value, fallback) {
  if (!value) return fallback;
  return JSON.parse(value);
}

module.exports = { ConversationSqliteStore, defaultDbPath };
