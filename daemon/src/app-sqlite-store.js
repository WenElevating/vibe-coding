'use strict';

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { DatabaseSync } = require('node:sqlite');

const LIVE_STATUSES = new Set(['running', 'waiting_input', 'waiting_approval']);

class AppSqliteStore {
  constructor({ dbPath = defaultAppDbPath(), now = () => new Date() } = {}) {
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
        session_binding TEXT NOT NULL DEFAULT 'unknown',
        user_message_count INTEGER NOT NULL DEFAULT 0,
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
      CREATE TABLE IF NOT EXISTS devices (
        id TEXT PRIMARY KEY,
        device_id_hash TEXT NOT NULL UNIQUE,
        label TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL,
        last_seen_at TEXT
      );
      CREATE INDEX IF NOT EXISTS idx_devices_status_last_seen
        ON devices(status, last_seen_at DESC);
      CREATE TABLE IF NOT EXISTS device_tokens (
        id TEXT PRIMARY KEY,
        device_id TEXT NOT NULL,
        token_type TEXT NOT NULL,
        token_hash TEXT NOT NULL UNIQUE,
        expires_at TEXT NOT NULL,
        revoked_at TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (device_id) REFERENCES devices(id) ON DELETE CASCADE
      );
      CREATE INDEX IF NOT EXISTS idx_device_tokens_device_type
        ON device_tokens(device_id, token_type);
      CREATE INDEX IF NOT EXISTS idx_device_tokens_expires
        ON device_tokens(expires_at);
      CREATE INDEX IF NOT EXISTS idx_device_tokens_revoked
        ON device_tokens(revoked_at);
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
      CREATE TABLE IF NOT EXISTS workspaces (
        id TEXT PRIMARY KEY,
        owner_device_id TEXT NOT NULL,
        name TEXT NOT NULL,
        path TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        deleted_at TEXT
      );
      CREATE TABLE IF NOT EXISTS workspace_device_authorizations (
        device_id TEXT NOT NULL,
        workspace_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        PRIMARY KEY (device_id, workspace_id),
        FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
      );
      CREATE INDEX IF NOT EXISTS idx_workspace_auth_device
        ON workspace_device_authorizations(device_id);
      CREATE TABLE IF NOT EXISTS exceptions (
        trace_id TEXT PRIMARY KEY,
        source TEXT NOT NULL,
        severity TEXT NOT NULL,
        message TEXT NOT NULL,
        stack TEXT,
        path TEXT,
        method TEXT,
        device_id TEXT,
        conversation_id TEXT,
        run_id TEXT,
        metadata_json TEXT NOT NULL DEFAULT '{}',
        created_at TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_exceptions_created
        ON exceptions(created_at DESC);
      CREATE INDEX IF NOT EXISTS idx_exceptions_device_created
        ON exceptions(device_id, created_at DESC);
    `);
    ensureColumn(this.db, 'conversations', 'session_binding', "TEXT NOT NULL DEFAULT 'unknown'");
    ensureColumn(this.db, 'conversations', 'user_message_count', 'INTEGER NOT NULL DEFAULT 0');
    this.ensureWorkspaceDeleteSchema();
    this.ensureWorkspaceIndexes();
    this.db.prepare('INSERT OR IGNORE INTO schema_migrations(version, applied_at) VALUES (?, ?)')
      .run(1, this.now().toISOString());
  }

  ensureWorkspaceIndexes() {
    this.db.exec(`
      CREATE UNIQUE INDEX IF NOT EXISTS idx_workspaces_owner_path_active
        ON workspaces(owner_device_id, path)
        WHERE is_deleted = 0;
      CREATE INDEX IF NOT EXISTS idx_workspace_auth_device
        ON workspace_device_authorizations(device_id);
    `);
  }

  ensureWorkspaceDeleteSchema() {
    const columns = this.db.prepare('PRAGMA table_info(workspaces)').all();
    const hasDeleted = columns.some((row) => row.name === 'is_deleted');
    const hasDeletedAt = columns.some((row) => row.name === 'deleted_at');
    const indexes = this.db.prepare('PRAGMA index_list(workspaces)').all();
    const hasOldUnique = indexes.some((row) =>
      row.name && row.name.startsWith('sqlite_autoindex_workspaces_') && row.origin === 'u'
    );
    if (hasDeleted && hasDeletedAt && !hasOldUnique) return;

    this.db.exec('PRAGMA foreign_keys = OFF');
    try {
      this.db.exec('BEGIN');
      try {
        this.db.exec(`
          CREATE TABLE workspaces_next (
            id TEXT PRIMARY KEY,
            owner_device_id TEXT NOT NULL,
            name TEXT NOT NULL,
            path TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            is_deleted INTEGER NOT NULL DEFAULT 0,
            deleted_at TEXT
          );
        `);
        const selectDeleted = hasDeleted ? 'is_deleted' : '0';
        const selectDeletedAt = hasDeletedAt ? 'deleted_at' : 'NULL';
        this.db.exec(`
          INSERT INTO workspaces_next(
            id, owner_device_id, name, path, created_at, updated_at, is_deleted, deleted_at
          )
          SELECT id, owner_device_id, name, path, created_at, updated_at, ${selectDeleted}, ${selectDeletedAt}
          FROM workspaces;
        `);
        this.db.exec('DROP TABLE workspaces');
        this.db.exec('ALTER TABLE workspaces_next RENAME TO workspaces');
        this.db.exec('COMMIT');
      } catch (error) {
        try { this.db.exec('ROLLBACK'); } catch (_) {}
        throw error;
      }
    } finally {
      this.db.exec('PRAGMA foreign_keys = ON');
    }
    const violations = this.db.prepare('PRAGMA foreign_key_check').all();
    if (violations.length > 0) throw new Error('workspace schema migration violated foreign keys');
  }

  saveConversation(conversation) {
    const row = serializeConversation(conversation);
    this.db.prepare(`
      INSERT INTO conversations (
        id, workspace_id, workspace_path, adapter, permission_mode, device_id,
        status, cli_session_id, session_binding, user_message_count,
        blocking_item_json, idle_expires_at,
        created_at, updated_at, capabilities_json
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        workspace_id = excluded.workspace_id,
        workspace_path = excluded.workspace_path,
        adapter = excluded.adapter,
        permission_mode = excluded.permission_mode,
        device_id = excluded.device_id,
        status = excluded.status,
        cli_session_id = excluded.cli_session_id,
        session_binding = excluded.session_binding,
        user_message_count = excluded.user_message_count,
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
      row.session_binding,
      row.user_message_count,
      row.blocking_item_json,
      row.idle_expires_at,
      row.created_at,
      row.updated_at,
      row.capabilities_json
    );
  }

  loadConversations() {
    const countsByConversation = new Map();
    for (const row of this.db.prepare(`
      SELECT conversation_id, COUNT(*) AS msg_count
      FROM conversation_events
      WHERE type = 'user.message'
      GROUP BY conversation_id
    `).all()) {
      countsByConversation.set(row.conversation_id, Number(row.msg_count));
    }
    return this.db.prepare('SELECT * FROM conversations ORDER BY updated_at DESC')
      .all()
      .map((row) => {
        const conversation = deserializeConversation(row);
        return this.normalizeLoadedConversation(conversation, countsByConversation.get(conversation.id) || 0);
      });
  }

  normalizeLoadedConversation(conversation, precomputedMessageCount) {
    const userMessageCount = precomputedMessageCount !== undefined
      ? precomputedMessageCount
      : Number(this.db.prepare(`
          SELECT COUNT(*) AS count FROM conversation_events
          WHERE conversation_id = ? AND type = 'user.message'
        `).get(conversation.id)?.count || 0);
    if (conversation.userMessageCount === 0 && userMessageCount > 0) {
      conversation.userMessageCount = userMessageCount;
    }
    if (!conversation.cliSessionId && conversation.userMessageCount > 0 && conversation.status === 'idle') {
      conversation.status = 'interrupted';
      conversation.sessionBinding = 'unknown';
      conversation.blockingItem = null;
      conversation.idleExpiresAt = null;
    }
    return conversation;
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

  saveWorkspaceForDevice({ deviceId, id, name, workspacePath }) {
    if (!deviceId) throw new Error('deviceId is required');
    if (!workspacePath) throw new Error('workspace path is required');
    const resolved = path.resolve(workspacePath);
    const now = this.now().toISOString();
    const displayName = name && String(name).trim() ? String(name).trim() : path.basename(resolved) || resolved;
    const existing = this.db.prepare(`
      SELECT id, name, path
      FROM workspaces
      WHERE owner_device_id = ? AND path = ? AND is_deleted = 0
    `).get(deviceId, resolved);
    if (existing) {
      this.authorizeWorkspaceForDevice(deviceId, existing.id);
      return deserializeWorkspace(existing);
    }
    const workspaceId = id || workspaceIdForDevicePath(deviceId, resolved, now);
    this.db.prepare(`
      INSERT INTO workspaces(id, owner_device_id, name, path, created_at, updated_at, is_deleted, deleted_at)
      VALUES (?, ?, ?, ?, ?, ?, 0, NULL)
    `).run(workspaceId, deviceId, displayName, resolved, now, now);
    this.authorizeWorkspaceForDevice(deviceId, workspaceId);
    return this.getWorkspaceForDevice(workspaceId, deviceId);
  }

  authorizeWorkspaceForDevice(deviceId, workspaceId) {
    if (!deviceId) throw new Error('deviceId is required');
    if (!workspaceId) throw new Error('workspaceId is required');
    this.db.prepare(`
      INSERT OR IGNORE INTO workspace_device_authorizations(device_id, workspace_id, created_at)
      VALUES (?, ?, ?)
    `).run(deviceId, workspaceId, this.now().toISOString());
  }

  listWorkspacesForDevice(deviceId) {
    const rows = this.db.prepare(`
      SELECT w.id, w.name, w.path
      FROM workspaces w
      INNER JOIN workspace_device_authorizations a ON a.workspace_id = w.id
      WHERE a.device_id = ? AND w.is_deleted = 0
      ORDER BY w.created_at ASC
    `).all(deviceId);
    return dedupeWorkspaceRowsByPath(rows).map(deserializeWorkspace);
  }

  listWorkspaces() {
    return this.db.prepare(`
      SELECT id, name, path
      FROM workspaces
      WHERE is_deleted = 0
      ORDER BY created_at ASC
    `).all().map(deserializeWorkspace);
  }

  getWorkspaceForDevice(workspaceId, deviceId) {
    const row = this.db.prepare(`
      SELECT w.id, w.name, w.path
      FROM workspaces w
      INNER JOIN workspace_device_authorizations a ON a.workspace_id = w.id
      WHERE w.id = ? AND a.device_id = ? AND w.is_deleted = 0
    `).get(workspaceId, deviceId);
    return row ? deserializeWorkspace(row) : null;
  }

  renameWorkspaceForDevice({ deviceId, workspaceId, name }) {
    if (!deviceId) throw new Error('deviceId is required');
    if (!workspaceId) throw new Error('workspaceId is required');
    const displayName = name && String(name).trim() ? String(name).trim() : '';
    if (!displayName) return null;
    const now = this.now().toISOString();
    const result = this.db.prepare(`
      UPDATE workspaces
      SET name = ?, updated_at = ?
      WHERE id = ?
        AND is_deleted = 0
        AND EXISTS (
          SELECT 1 FROM workspace_device_authorizations
          WHERE device_id = ? AND workspace_id = workspaces.id
        )
    `).run(displayName, now, workspaceId, deviceId);
    if (result.changes === 0) return null;
    return this.getWorkspaceForDevice(workspaceId, deviceId);
  }

  markWorkspaceDeletedForDevice({ deviceId, workspaceId }) {
    if (!deviceId) throw new Error('deviceId is required');
    if (!workspaceId) throw new Error('workspaceId is required');
    const now = this.now().toISOString();
    const workspace = this.getWorkspaceForDevice(workspaceId, deviceId);
    if (!workspace) return null;
    this.db.prepare(`
      UPDATE workspaces
      SET is_deleted = 1, deleted_at = ?, updated_at = ?
      WHERE id = ? AND is_deleted = 0
    `).run(now, now, workspaceId);
    return workspace;
  }

  getWorkspace(workspaceId) {
    const row = this.db.prepare('SELECT id, name, path FROM workspaces WHERE id = ? AND is_deleted = 0').get(workspaceId);
    return row ? deserializeWorkspace(row) : null;
  }

  hasAnyWorkspaces() {
    const row = this.db.prepare('SELECT 1 AS exists_workspace FROM workspaces LIMIT 1').get();
    return Boolean(row);
  }

  getDeviceByHash(deviceIdHash) {
    const row = this.db.prepare(`
      SELECT id, device_id_hash, label, status, created_at, last_seen_at
      FROM devices
      WHERE device_id_hash = ?
    `).get(deviceIdHash);
    return row ? deserializeDevice(row) : null;
  }

  getDevice(deviceId) {
    const row = this.db.prepare(`
      SELECT id, device_id_hash, label, status, created_at, last_seen_at
      FROM devices
      WHERE id = ?
    `).get(deviceId);
    return row ? deserializeDevice(row) : null;
  }

  countActiveDevices() {
    const row = this.db.prepare(`
      SELECT COUNT(*) AS count
      FROM devices
      WHERE status = 'active'
    `).get();
    return Number(row?.count || 0);
  }

  upsertDevice({ id, deviceIdHash, label, status, createdAt, lastSeenAt }) {
    const now = this.now().toISOString();
    const deviceId = id || `dev_${crypto.randomUUID()}`;
    this.db.prepare(`
      INSERT INTO devices(id, device_id_hash, label, status, created_at, last_seen_at)
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        device_id_hash = excluded.device_id_hash,
        label = excluded.label,
        status = excluded.status,
        last_seen_at = excluded.last_seen_at
    `).run(deviceId, deviceIdHash, label, status || 'active', createdAt || now, lastSeenAt || now);
    const row = this.db.prepare(`
      SELECT id, device_id_hash, label, status, created_at, last_seen_at
      FROM devices
      WHERE id = ?
    `).get(deviceId);
    return deserializeDevice(row);
  }

  saveDeviceToken({ id, deviceId, tokenType, tokenHash, expiresAt, revokedAt = null, createdAt }) {
    this.db.prepare(`
      INSERT INTO device_tokens(id, device_id, token_type, token_hash, expires_at, revoked_at, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(token_hash) DO UPDATE SET
        device_id = excluded.device_id,
        token_type = excluded.token_type,
        expires_at = excluded.expires_at,
        revoked_at = excluded.revoked_at
    `).run(id, deviceId, tokenType, tokenHash, expiresAt, revokedAt, createdAt || this.now().toISOString());
  }

  getValidRefreshTokenForDevice(deviceId) {
    const row = this.db.prepare(`
      SELECT id, device_id, token_type, token_hash, expires_at, revoked_at, created_at
      FROM device_tokens
      WHERE device_id = ? AND token_type = 'refresh' AND revoked_at IS NULL AND expires_at > ?
      ORDER BY created_at DESC
      LIMIT 1
    `).get(deviceId, this.now().toISOString());
    return row || null;
  }

  getDeviceByAccessTokenHash(tokenHash) {
    const row = this.db.prepare(`
      SELECT d.id, d.device_id_hash, d.label, d.status, d.created_at, d.last_seen_at
      FROM devices d
      INNER JOIN device_tokens t ON t.device_id = d.id
      WHERE d.status = 'active' AND t.token_type = 'access' AND t.revoked_at IS NULL AND t.expires_at > ? AND t.token_hash = ?
      LIMIT 1
    `).get(this.now().toISOString(), tokenHash);
    return row ? deserializeDevice(row) : null;
  }

  revokeToken(tokenId, revokedAt) {
    this.db.prepare(`
      UPDATE device_tokens
      SET revoked_at = ?
      WHERE id = ?
    `).run(revokedAt || this.now().toISOString(), tokenId);
  }

  revokeDevice(deviceId, revokedAt) {
    this.db.prepare(`
      UPDATE devices
      SET status = 'revoked', last_seen_at = ?
      WHERE id = ?
    `).run(revokedAt || this.now().toISOString(), deviceId);
    this.db.prepare(`
      UPDATE device_tokens
      SET revoked_at = ?
      WHERE device_id = ? AND revoked_at IS NULL
    `).run(revokedAt || this.now().toISOString(), deviceId);
  }

  recordException(input) {
    const traceId = input.traceId || `trc_${crypto.randomUUID()}`;
    const createdAt = input.createdAt || this.now().toISOString();
    this.db.prepare(`
      INSERT INTO exceptions(
        trace_id, source, severity, message, stack, path, method, device_id,
        conversation_id, run_id, metadata_json, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      traceId,
      input.source || 'daemon',
      input.severity || 'error',
      String(input.message || 'Unknown error'),
      input.stack || null,
      input.path || null,
      input.method || null,
      input.deviceId || null,
      input.conversationId || null,
      input.runId || null,
      JSON.stringify(input.metadata || {}),
      createdAt
    );
    return { traceId, createdAt };
  }

  listExceptions({ limit = 50 } = {}) {
    return this.db.prepare(`
      SELECT trace_id, source, severity, message, stack, path, method, device_id,
        conversation_id, run_id, metadata_json, created_at
      FROM exceptions
      ORDER BY created_at DESC
      LIMIT ?
    `).all(Math.max(1, Math.min(Number(limit || 50), 200))).map(deserializeException);
  }

  close() {
    this.db.close();
  }
}

function deserializeException(row) {
  return {
    traceId: row.trace_id,
    source: row.source,
    severity: row.severity,
    message: row.message,
    stack: row.stack,
    path: row.path,
    method: row.method,
    deviceId: row.device_id,
    conversationId: row.conversation_id,
    runId: row.run_id,
    metadata: parseJson(row.metadata_json, {}),
    createdAt: row.created_at
  };
}

function defaultAppDbPath() {
  return path.join(process.cwd(), 'data', 'app', 'app.sqlite');
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
    session_binding: conversation.sessionBinding || (conversation.cliSessionId ? 'confirmed' : 'unknown'),
    user_message_count: Number(conversation.userMessageCount || 0),
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
    sessionBinding: row.session_binding || (row.cli_session_id ? 'confirmed' : 'unknown'),
    userMessageCount: Number(row.user_message_count || 0),
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

function workspaceIdForDevicePath(deviceId, resolvedPath, salt = '') {
  return `workspace_${crypto.createHash('sha1').update(`${deviceId}:${resolvedPath}:${salt}`).digest('hex').slice(0, 12)}`;
}

function deserializeWorkspace(row) {
  return { id: row.id, name: row.name, path: row.path };
}

function dedupeWorkspaceRowsByPath(rows) {
  const seen = new Set();
  const deduped = [];
  for (const row of rows) {
    const key = String(row.path || '').toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    deduped.push(row);
  }
  return deduped;
}

function deserializeDevice(row) {
  return {
    id: row.id,
    deviceIdHash: row.device_id_hash,
    label: row.label,
    status: row.status,
    createdAt: row.created_at,
    lastSeenAt: row.last_seen_at,
    allowedWorkspaceIds: new Set()
  };
}

function parseJson(value, fallback) {
  if (!value) return fallback;
  return JSON.parse(value);
}

function ensureColumn(db, table, column, definition) {
  if (!/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(table)) throw new Error(`Invalid table name: ${table}`);
  if (!/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(column)) throw new Error(`Invalid column name: ${column}`);
  const rows = db.prepare(`PRAGMA table_info(${table})`).all();
  if (rows.some((row) => row.name === column)) return;
  db.exec(`ALTER TABLE ${table} ADD COLUMN ${column} ${definition}`);
}

module.exports = { AppSqliteStore, defaultAppDbPath };
