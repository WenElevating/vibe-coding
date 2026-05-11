# Workspace Management CRUD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add complete workspace management for the current device: searchable workspace list, create, rename, logical delete, and active-CLI delete confirmation.

**Architecture:** Keep daemon persistence/API changes behind `AppSqliteStore`, `WorkspaceRegistry`, and `server.js`. Keep Flutter changes narrow: `DaemonClient` gets workspace update/delete calls, `WorkspaceListPage` owns local search and long-press UI, and `CodingWorkbenchPage` owns daemon mutations and refreshed route state.

**Tech Stack:** Node.js CommonJS daemon, `node:sqlite` `DatabaseSync`, Flutter/Dart, generated Flutter localizations from ARB, existing `scripts/run-tests.js` and Flutter widget tests.

---

## File Map

- Modify `daemon/src/app-sqlite-store.js`: add workspace logical-delete schema, atomic table rebuild for removing `UNIQUE(owner_device_id, path)`, CRUD methods, and active-row list filters.
- Modify `daemon/src/workspace.js`: expose `renameForDevice`, `deleteForDevice`, and active workspace lookup through the registry boundary.
- Modify `daemon/src/run-manager.js`: add workspace-scoped active run detection and cancellation helper.
- Modify `daemon/src/conversation-manager.js`: add workspace-scoped active conversation detection and cancellation helper.
- Modify `daemon/src/server.js`: add `PATCH /api/workspaces/:id` and `DELETE /api/workspaces/:id`.
- Modify `scripts/run-tests.js`: add daemon regression tests for create/rename/delete and active CLI delete semantics.
- Modify `mobile/lib/src/services/daemon_client.dart`: add `_patch`, `_delete`, `renameWorkspace`, and `deleteWorkspace`.
- Modify `mobile/lib/src/features/workbench/coding_workbench_page.dart`: wire rename/delete callbacks and update workspace route state after mutations.
- Modify `mobile/lib/src/features/workspace_picker/workspace_picker_sheet.dart`: make workspace search a real input; add long-press action sheet, rename surface, delete confirmation surface hooks.
- Modify `mobile/lib/l10n/app_en.arb` and `mobile/lib/l10n/app_zh.arb`: add workspace CRUD labels and error/empty-state copy.
- Modify `mobile/test/widget_test.dart`: add widget tests for search, empty states, long press, rename, and delete confirmation.

## Task 1: Daemon Store CRUD Semantics

**Files:**
- Modify: `daemon/src/app-sqlite-store.js`
- Test: `scripts/run-tests.js`

- [ ] **Step 1: Add failing store tests**

Add these tests after `app SQLite store scopes duplicate workspace paths by owner device` in `scripts/run-tests.js`:

```js
test('app SQLite store logically deletes workspaces and re-adds same path as new id', () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const { AppSqliteStore } = require('../daemon/src/app-sqlite-store');

  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'app-db-workspace-delete-'));
  const store = new AppSqliteStore({
    dbPath: path.join(dir, 'app.sqlite'),
    now: (() => {
      const dates = [
        new Date('2026-05-11T00:00:00.000Z'),
        new Date('2026-05-11T00:00:01.000Z'),
        new Date('2026-05-11T00:00:02.000Z')
      ];
      return () => dates.shift() || new Date('2026-05-11T00:00:03.000Z');
    })()
  });
  const workspacePath = path.join(dir, 'project');
  const first = store.saveWorkspaceForDevice({ deviceId: 'device_1', workspacePath, name: 'First' });

  const deleted = store.markWorkspaceDeletedForDevice({ deviceId: 'device_1', workspaceId: first.id });
  const afterDelete = store.listWorkspacesForDevice('device_1');
  const second = store.saveWorkspaceForDevice({ deviceId: 'device_1', workspacePath, name: 'Second' });

  assert.equal(deleted.id, first.id);
  assert.deepEqual(afterDelete, []);
  assert.notEqual(second.id, first.id);
  assert.equal(second.name, 'Second');
  assert.equal(second.path, path.resolve(workspacePath));
  assert.deepEqual(store.listWorkspacesForDevice('device_1').map((item) => item.id), [second.id]);
  assert.equal(store.getWorkspaceForDevice(first.id, 'device_1'), null);
  store.close();
});

test('app SQLite store renames active workspaces and rejects deleted workspaces', () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const { AppSqliteStore } = require('../daemon/src/app-sqlite-store');

  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'app-db-workspace-rename-'));
  const store = new AppSqliteStore({ dbPath: path.join(dir, 'app.sqlite') });
  const workspace = store.saveWorkspaceForDevice({ deviceId: 'device_1', workspacePath: path.join(dir, 'project'), name: 'Before' });

  const renamed = store.renameWorkspaceForDevice({ deviceId: 'device_1', workspaceId: workspace.id, name: 'After' });
  store.markWorkspaceDeletedForDevice({ deviceId: 'device_1', workspaceId: workspace.id });

  assert.equal(renamed.id, workspace.id);
  assert.equal(renamed.name, 'After');
  assert.equal(renamed.path, workspace.path);
  assert.equal(store.renameWorkspaceForDevice({ deviceId: 'device_1', workspaceId: workspace.id, name: 'Hidden' }), null);
  assert.equal(store.renameWorkspaceForDevice({ deviceId: 'device_1', workspaceId: workspace.id, name: '   ' }), null);
  store.close();
});
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```powershell
npm test
```

Expected: FAIL because `markWorkspaceDeletedForDevice` and `renameWorkspaceForDevice` do not exist.

- [ ] **Step 3: Implement schema and store methods**

In `daemon/src/app-sqlite-store.js`, replace the `CREATE TABLE IF NOT EXISTS workspaces` block with a version that includes the new columns and no table-level unique constraint:

```js
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
```

Replace the existing `idx_workspaces_owner_path` creation with:

```js
      CREATE UNIQUE INDEX IF NOT EXISTS idx_workspaces_owner_path_active
        ON workspaces(owner_device_id, path)
        WHERE is_deleted = 0;
```

Add this call near the end of `migrate()`, after `ensureColumn(...)` calls:

```js
    this.ensureWorkspaceDeleteSchema();
```

Add these methods inside `class AppSqliteStore`, after `migrate()`:

```js
  ensureWorkspaceDeleteSchema() {
    const columns = this.db.prepare('PRAGMA table_info(workspaces)').all();
    const hasDeleted = columns.some((row) => row.name === 'is_deleted');
    const hasDeletedAt = columns.some((row) => row.name === 'deleted_at');
    const indexes = this.db.prepare('PRAGMA index_list(workspaces)').all();
    const hasOldUnique = indexes.some((row) => row.name && row.name.startsWith('sqlite_autoindex_workspaces_'));
    if (hasDeleted && hasDeletedAt && !hasOldUnique) return;

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
      this.db.exec(`
        CREATE UNIQUE INDEX IF NOT EXISTS idx_workspaces_owner_path_active
          ON workspaces(owner_device_id, path)
          WHERE is_deleted = 0;
        CREATE INDEX IF NOT EXISTS idx_workspace_auth_device
          ON workspace_device_authorizations(device_id);
      `);
      this.db.exec('COMMIT');
    } catch (error) {
      this.db.exec('ROLLBACK');
      throw error;
    }
  }
```

Replace `saveWorkspaceForDevice` with:

```js
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
```

Update `listWorkspacesForDevice`, `listWorkspaces`, `getWorkspaceForDevice`, and `getWorkspace` queries so each filters `w.is_deleted = 0` or `is_deleted = 0`.

Add methods after `getWorkspaceForDevice`:

```js
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
```

Replace `workspaceIdForDevicePath` with:

```js
function workspaceIdForDevicePath(deviceId, resolvedPath, salt = '') {
  return `workspace_${crypto.createHash('sha1').update(`${deviceId}:${resolvedPath}:${salt}`).digest('hex').slice(0, 12)}`;
}
```

- [ ] **Step 4: Run daemon tests**

Run:

```powershell
npm test
```

Expected: PASS for the new store tests and no existing workspace persistence regressions.

- [ ] **Step 5: Commit**

Run:

```powershell
git add daemon/src/app-sqlite-store.js scripts/run-tests.js
git commit -m "Add workspace logical delete persistence"
```

## Task 2: Daemon Workspace API and Active CLI Shutdown

**Files:**
- Modify: `daemon/src/workspace.js`
- Modify: `daemon/src/run-manager.js`
- Modify: `daemon/src/conversation-manager.js`
- Modify: `daemon/src/server.js`
- Test: `scripts/run-tests.js`

- [ ] **Step 1: Add failing API tests**

Add these tests near the other HTTP API tests in `scripts/run-tests.js`:

```js
test('workspace API renames and logically deletes workspaces', async () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const appDbPath = tempConversationDbPath('app-db-workspace-api-');
  const app = createApp({ port: 0, appDbPath, devAdapters: false });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  const workspacePath = fs.mkdtempSync(path.join(os.tmpdir(), 'workspace-api-project-'));
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'test' });
    const token = paired.body.token;
    const created = await request(port, 'POST', '/api/workspaces', { workspacePath, name: 'Before' }, token);
    const renamed = await request(port, 'PATCH', `/api/workspaces/${created.body.id}`, { name: 'After' }, token);
    const deleted = await request(port, 'DELETE', `/api/workspaces/${created.body.id}`, {}, token);
    const listed = await request(port, 'GET', '/api/workspaces', null, token);
    const recreated = await request(port, 'POST', '/api/workspaces', { workspacePath, name: 'Fresh' }, token);

    assert.equal(renamed.status, 200);
    assert.equal(renamed.body.name, 'After');
    assert.equal(renamed.body.path, path.resolve(workspacePath));
    assert.equal(deleted.status, 200);
    assert.deepEqual(listed.body.workspaces.map((workspace) => workspace.id), []);
    assert.notEqual(recreated.body.id, created.body.id);
    assert.equal(recreated.body.name, 'Fresh');
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
    app.appSqliteStore.close();
  }
});

test('workspace API rejects deleted workspace rename and path mutation', async () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const app = createApp({ port: 0, appDbPath: tempConversationDbPath('app-db-workspace-api-guard-'), devAdapters: false });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'test' });
    const token = paired.body.token;
    const created = await request(port, 'POST', '/api/workspaces', { workspacePath: fs.mkdtempSync(path.join(os.tmpdir(), 'workspace-api-guard-')), name: 'Before' }, token);
    const pathUpdate = await request(port, 'PATCH', `/api/workspaces/${created.body.id}`, { name: 'After', workspacePath: 'D:/other' }, token);
    await request(port, 'DELETE', `/api/workspaces/${created.body.id}`, {}, token);
    const renameDeleted = await request(port, 'PATCH', `/api/workspaces/${created.body.id}`, { name: 'Hidden' }, token);

    assert.equal(pathUpdate.status, 400);
    assert.equal(renameDeleted.status, 404);
    assert.equal(renameDeleted.body.error.code, 'WORKSPACE_NOT_FOUND');
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
    app.appSqliteStore.close();
  }
});

test('workspace delete requires confirmation for active conversations and is idempotent after they end', async () => {
  const app = createApp({ port: 0, appDbPath: tempConversationDbPath('app-db-workspace-active-'), devAdapters: false });
  const workspace = app.workspaces.add({ workspacePath: process.cwd(), name: 'Active' }, { id: 'device_1', allowedWorkspaceIds: new Set() });
  const device = { id: 'device_1', allowedWorkspaceIds: new Set([workspace.id]) };
  const fakeHandle = { cancelled: 0, async cancel() { this.cancelled += 1; } };
  const conversation = {
    id: 'conv_active',
    workspaceId: workspace.id,
    workspacePath: workspace.path,
    adapter: 'codex',
    permissionMode: 'default',
    deviceId: device.id,
    status: 'running',
    cliSessionId: 'session_1',
    sessionBinding: 'confirmed',
    userMessageCount: 1,
    blockingItem: null,
    idleExpiresAt: null,
    createdAt: '2026-05-11T00:00:00.000Z',
    updatedAt: '2026-05-11T00:00:00.000Z',
    capabilities: {},
    handle: fakeHandle
  };
  app.conversations.conversations.set(conversation.id, conversation);
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', { code: pairing.body.code, label: 'test', deviceId: 'device_1' });
    const token = paired.body.token;
    app.workspaces.authorizeDeviceForWorkspace(app.auth.authenticate(`Bearer ${token}`), workspace.id);

    const rejected = await request(port, 'DELETE', `/api/workspaces/${workspace.id}`, {}, token);
    conversation.status = 'idle';
    const confirmed = await request(port, 'DELETE', `/api/workspaces/${workspace.id}`, { closeActive: true }, token);

    assert.equal(rejected.status, 409);
    assert.equal(rejected.body.error.code, 'WORKSPACE_HAS_ACTIVE_CLI');
    assert.equal(confirmed.status, 200);
    assert.equal(fakeHandle.cancelled, 0);
    assert.deepEqual(confirmed.body.workspaces, []);
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
    app.appSqliteStore.close();
  }
});
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```powershell
npm test
```

Expected: FAIL because `PATCH`/`DELETE /api/workspaces/:id` do not exist and workspace managers lack helper methods.

- [ ] **Step 3: Implement registry methods**

Add to `WorkspaceRegistry` in `daemon/src/workspace.js`:

```js
  renameForDevice(workspaceId, payload, device) {
    if (!payload || typeof payload !== 'object') throw badRequest('payload must be an object');
    if (Object.prototype.hasOwnProperty.call(payload, 'workspacePath') || Object.prototype.hasOwnProperty.call(payload, 'path')) {
      throw badRequest('workspace path cannot be updated');
    }
    const name = typeof payload.name === 'string' ? payload.name.trim() : '';
    if (!name) throw badRequest('workspace name is required');
    if (this.store) {
      const workspace = this.store.renameWorkspaceForDevice({ deviceId: device.id, workspaceId, name });
      if (!workspace) throw workspaceNotFound();
      return workspace;
    }
    const workspace = this.getAuthorized(workspaceId, device);
    workspace.name = name;
    return workspace;
  }

  deleteForDevice(workspaceId, device) {
    if (this.store) {
      const workspace = this.store.markWorkspaceDeletedForDevice({ deviceId: device.id, workspaceId });
      if (!workspace) throw workspaceNotFound();
      device.allowedWorkspaceIds.delete(workspaceId);
      return workspace;
    }
    const workspace = this.getAuthorized(workspaceId, device);
    this.workspaces.delete(workspaceId);
    device.allowedWorkspaceIds.delete(workspaceId);
    return workspace;
  }
```

Add helper functions before `module.exports`:

```js
function badRequest(message) {
  const error = new Error(message);
  error.status = 400;
  error.code = 'BAD_REQUEST';
  return error;
}

function workspaceNotFound() {
  const error = new Error('workspace not found or not authorized');
  error.status = 404;
  error.code = 'WORKSPACE_NOT_FOUND';
  return error;
}
```

- [ ] **Step 4: Implement active workspace helpers**

Add to `RunManager` in `daemon/src/run-manager.js`:

```js
  activeWorkspaceRuns(workspaceId, device) {
    return Array.from(this.runs.values())
      .filter((run) => run.workspaceId === workspaceId)
      .filter((run) => run.deviceId === device.id)
      .filter((run) => run.status === 'running' || run.status === 'queued');
  }

  cancelWorkspaceRuns(workspaceId, device) {
    const active = this.activeWorkspaceRuns(workspaceId, device);
    for (const run of active) this.cancelRun(run.id, device);
    return active.map(publicRun);
  }
```

Add to `ConversationManager` in `daemon/src/conversation-manager.js`:

```js
  activeWorkspaceConversations(workspaceId, device) {
    return Array.from(this.conversations.values())
      .filter((conversation) => conversation.workspaceId === workspaceId)
      .filter((conversation) => this.canAccessConversation(conversation, device))
      .filter((conversation) => [
        conversationStatuses.RUNNING,
        conversationStatuses.WAITING_INPUT,
        conversationStatuses.WAITING_APPROVAL
      ].includes(conversation.status));
  }

  async cancelWorkspaceConversations(workspaceId, device) {
    const active = this.activeWorkspaceConversations(workspaceId, device);
    const cancelled = [];
    for (const conversation of active) {
      cancelled.push(await this.cancelConversation(conversation.id, device));
    }
    return cancelled;
  }
```

- [ ] **Step 5: Implement API routes**

In `daemon/src/server.js`, after the existing `POST /api/workspaces` route, add:

```js
      const workspaceMutation = url.pathname.match(/^\/api\/workspaces\/([^/]+)$/);
      if (workspaceMutation && method === 'PATCH') {
        return json(res, 200, workspaces.renameForDevice(workspaceMutation[1], await readJson(req), device));
      }
      if (workspaceMutation && method === 'DELETE') {
        const body = await readJson(req);
        const activeRuns = runs.activeWorkspaceRuns(workspaceMutation[1], device);
        const activeConversations = conversations.activeWorkspaceConversations(workspaceMutation[1], device);
        if ((activeRuns.length > 0 || activeConversations.length > 0) && body.closeActive !== true) {
          const error = new Error('Workspace has active CLI work.');
          error.status = 409;
          error.code = 'WORKSPACE_HAS_ACTIVE_CLI';
          error.recoverable = true;
          error.userAction = 'Confirm deletion to close active CLI work and remove this workspace from the device.';
          throw error;
        }
        if (body.closeActive === true) {
          runs.cancelWorkspaceRuns(workspaceMutation[1], device);
          await conversations.cancelWorkspaceConversations(workspaceMutation[1], device);
        }
        const workspace = workspaces.deleteForDevice(workspaceMutation[1], device);
        return json(res, 200, { workspaceId: workspace.id, workspace, workspaces: workspaces.listForDevice(device) });
      }
```

- [ ] **Step 6: Run daemon tests**

Run:

```powershell
npm test
```

Expected: PASS.

- [ ] **Step 7: Commit**

Run:

```powershell
git add daemon/src/workspace.js daemon/src/run-manager.js daemon/src/conversation-manager.js daemon/src/server.js scripts/run-tests.js
git commit -m "Add workspace management API"
```

## Task 3: Flutter Client Workspace Methods

**Files:**
- Modify: `mobile/lib/src/services/daemon_client.dart`
- Test: `mobile/test/daemon_client_test.dart`

- [ ] **Step 1: Add failing DaemonClient tests**

In `mobile/test/daemon_client_test.dart`, add tests near the existing client request tests:

```dart
test('renameWorkspace sends PATCH and decodes workspace', () async {
  final httpClient = RecordingHttpClient((request) async {
    expect(request.method, 'PATCH');
    expect(request.url.path, '/api/workspaces/workspace_1');
    expect(await request.finalize().bytesToString(), '{"name":"Renamed"}');
    return jsonResponse(200, <String, Object?>{
      'id': 'workspace_1',
      'name': 'Renamed',
      'path': r'D:\project',
    });
  });
  final client = DaemonClient(
    baseUri: Uri.parse('http://127.0.0.1:4317'),
    tokenStore: MemoryTokenStore(),
    httpClient: httpClient,
  );

  final workspace = await client.renameWorkspace('workspace_1', ' Renamed ');

  expect(workspace.id, 'workspace_1');
  expect(workspace.name, 'Renamed');
});

test('deleteWorkspace sends closeActive confirmation and decodes refreshed list', () async {
  final httpClient = RecordingHttpClient((request) async {
    expect(request.method, 'DELETE');
    expect(request.url.path, '/api/workspaces/workspace_1');
    expect(await request.finalize().bytesToString(), '{"closeActive":true}');
    return jsonResponse(200, <String, Object?>{
      'workspaceId': 'workspace_1',
      'workspaces': <Object?>[
        <String, Object?>{'id': 'workspace_2', 'name': 'Next', 'path': r'D:\next'},
      ],
    });
  });
  final client = DaemonClient(
    baseUri: Uri.parse('http://127.0.0.1:4317'),
    tokenStore: MemoryTokenStore(),
    httpClient: httpClient,
  );

  final workspaces = await client.deleteWorkspace('workspace_1', closeActive: true);

  expect(workspaces.single.id, 'workspace_2');
});
```

If `RecordingHttpClient` or `jsonResponse` have different names in the existing test file, use the existing helper shape and keep the assertions above.

- [ ] **Step 2: Run focused test to verify failure**

Run:

```powershell
cd mobile
flutter test test\daemon_client_test.dart -r expanded
```

Expected: FAIL because `renameWorkspace` and `deleteWorkspace` do not exist.

- [ ] **Step 3: Add client methods**

In `DaemonClient`, after `createWorkspace`, add:

```dart
  Future<WorkspaceSummary> renameWorkspace(
      String workspaceId, String name) async {
    final trimmed = name.trim();
    final response = await _patch('/api/workspaces/$workspaceId',
        <String, Object?>{'name': trimmed});
    return WorkspaceSummary.fromJson(response);
  }

  Future<List<WorkspaceSummary>> deleteWorkspace(String workspaceId,
      {bool closeActive = false}) async {
    final response = await _delete('/api/workspaces/$workspaceId',
        <String, Object?>{'closeActive': closeActive});
    final items = response['workspaces'] as List<Object?>;
    return items
        .cast<Map<String, Object?>>()
        .map(WorkspaceSummary.fromJson)
        .toList();
  }
```

Add `_patch` and `_delete` near `_post`:

```dart
  Future<Map<String, Object?>> _patch(
      String path, Map<String, Object?> body) async {
    final response = await _httpClient.patch(
      baseUri.resolve(path),
      headers: _headers(authorize: true),
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  Future<Map<String, Object?>> _delete(
      String path, Map<String, Object?> body) async {
    final request = http.Request('DELETE', baseUri.resolve(path))
      ..headers.addAll(_headers(authorize: true))
      ..body = jsonEncode(body);
    final streamed = await _httpClient.send(request);
    final response = await http.Response.fromStream(streamed);
    return _decode(response);
  }
```

- [ ] **Step 4: Run focused test**

Run:

```powershell
cd mobile
flutter test test\daemon_client_test.dart -r expanded
```

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```powershell
git add mobile/lib/src/services/daemon_client.dart mobile/test/daemon_client_test.dart
git commit -m "Add mobile workspace mutation client"
```

## Task 4: Workspace List UI Search and Long-Press Actions

**Files:**
- Modify: `mobile/lib/src/features/workspace_picker/workspace_picker_sheet.dart`
- Modify: `mobile/lib/src/features/workbench/coding_workbench_page.dart`
- Modify: `mobile/lib/l10n/app_en.arb`
- Modify: `mobile/lib/l10n/app_zh.arb`
- Test: `mobile/test/widget_test.dart`

- [ ] **Step 1: Add failing widget tests**

In `mobile/test/widget_test.dart`, add a fake mutation client near other fake clients:

```dart
class _WorkspaceMutationClient extends DaemonClient {
  _WorkspaceMutationClient()
      : super(
            baseUri: Uri.parse('http://127.0.0.1:4317'),
            tokenStore: MemoryTokenStore());

  String? renamedWorkspaceId;
  String? renamedName;
  String? deletedWorkspaceId;
  bool? deletedCloseActive;
  bool failDeleteWithActiveCli = false;

  @override
  Future<WorkspaceSummary> renameWorkspace(String workspaceId, String name) async {
    renamedWorkspaceId = workspaceId;
    renamedName = name;
    return WorkspaceSummary(id: workspaceId, name: name.trim(), path: r'D:\AiProject\vibe-coding');
  }

  @override
  Future<List<WorkspaceSummary>> deleteWorkspace(String workspaceId, {bool closeActive = false}) async {
    deletedWorkspaceId = workspaceId;
    deletedCloseActive = closeActive;
    if (failDeleteWithActiveCli && closeActive == false) {
      throw const DaemonClientException(409, <String, Object?>{
        'error': <String, Object?>{
          'code': 'WORKSPACE_HAS_ACTIVE_CLI',
          'message': 'Workspace has active CLI work.',
          'userAction': 'Confirm deletion to close active CLI work and remove this workspace from the device.',
        }
      });
    }
    return const <WorkspaceSummary>[];
  }
}
```

Add tests after the existing workspace list tests:

```dart
testWidgets('workspace list search filters by name and path', (WidgetTester tester) async {
  final selected = <WorkspaceSummary>[];
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en', 'US'),
    supportedLocales: appSupportedLocales,
    localizationsDelegates: appLocalizationsDelegates,
    theme: theme.buildAppTheme(),
    home: Scaffold(
      body: WorkspaceListPage(
        workspaces: const <WorkspaceSummary>[
          WorkspaceSummary(id: 'workspace_1', name: 'Vibe Coding', path: r'D:\AIProject\vibe-coding'),
          WorkspaceSummary(id: 'workspace_2', name: 'CLI Proxy', path: r'D:\AIProject\cli-proxy'),
        ],
        onSelected: selected.add,
        onAddWorkspace: () {},
        onRenameWorkspace: (_, __) {},
        onDeleteWorkspace: (_) {},
      ),
    ),
  ));

  await tester.enterText(find.byKey(const ValueKey('workspace-search-field')), 'proxy');
  await tester.pump();

  expect(find.text('CLI Proxy'), findsOneWidget);
  expect(find.text('Vibe Coding'), findsNothing);
});

testWidgets('workspace row long press exposes rename and delete actions', (WidgetTester tester) async {
  WorkspaceSummary? renameTarget;
  WorkspaceSummary? deleteTarget;
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en', 'US'),
    supportedLocales: appSupportedLocales,
    localizationsDelegates: appLocalizationsDelegates,
    theme: theme.buildAppTheme(),
    home: Scaffold(
      body: WorkspaceListPage(
        workspaces: const <WorkspaceSummary>[
          WorkspaceSummary(id: 'workspace_1', name: 'Vibe Coding', path: r'D:\AIProject\vibe-coding'),
        ],
        onSelected: (_) {},
        onAddWorkspace: () {},
        onRenameWorkspace: (workspace, _) => renameTarget = workspace,
        onDeleteWorkspace: (workspace) => deleteTarget = workspace,
      ),
    ),
  ));

  await tester.longPress(find.text('Vibe Coding'));
  await tester.pumpAndSettle();

  expect(find.text('Rename'), findsOneWidget);
  expect(find.text('Delete'), findsOneWidget);

  await tester.tap(find.text('Rename'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('workspace-rename-field')), 'Renamed');
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();

  expect(renameTarget?.id, 'workspace_1');
  expect(deleteTarget, isNull);
});
```

- [ ] **Step 2: Run focused widget tests to verify failure**

Run:

```powershell
cd mobile
flutter test test\widget_test.dart -r expanded --name "workspace list search|workspace row long press"
```

Expected: FAIL because the widget constructor and UI controls do not exist.

- [ ] **Step 3: Add localization keys**

Add to `mobile/lib/l10n/app_en.arb`:

```json
  "workspaceSearchPlaceholder": "Search workspaces by name or path...",
  "workspaceNoMatchesTitle": "No matching workspaces",
  "workspaceNoMatchesBody": "Try a different name or path.",
  "workspaceEmptyTitle": "No workspaces yet",
  "workspaceEmptyBody": "Add a workspace to choose where CLI commands run.",
  "workspaceRenameAction": "Rename",
  "workspaceDeleteAction": "Delete",
  "workspaceRenameTitle": "Rename workspace",
  "workspaceRenameSaveAction": "Save",
  "workspaceRenameEmptyError": "Workspace name is required.",
  "workspaceDeleteTitle": "Delete workspace",
  "workspaceDeleteBody": "This removes the workspace from this app. It does not delete files on disk.",
  "workspaceDeleteActiveBody": "This workspace has active CLI work. Deleting it will close that CLI work and remove the workspace from this app.",
  "workspaceDeleteConfirmAction": "Delete",
  "workspaceCancelAction": "Cancel"
```

Add equivalent Chinese keys to `mobile/lib/l10n/app_zh.arb`:

```json
  "workspaceSearchPlaceholder": "搜索工作区名称或路径...",
  "workspaceNoMatchesTitle": "没有匹配的工作区",
  "workspaceNoMatchesBody": "换一个名称或路径试试。",
  "workspaceEmptyTitle": "还没有工作区",
  "workspaceEmptyBody": "添加工作区后，CLI 命令会在对应目录运行。",
  "workspaceRenameAction": "重命名",
  "workspaceDeleteAction": "删除",
  "workspaceRenameTitle": "重命名工作区",
  "workspaceRenameSaveAction": "保存",
  "workspaceRenameEmptyError": "工作区名称不能为空。",
  "workspaceDeleteTitle": "删除工作区",
  "workspaceDeleteBody": "这只会从应用中移除工作区，不会删除磁盘文件。",
  "workspaceDeleteActiveBody": "这个工作区有活跃 CLI。删除会关闭该 CLI，并从应用中移除工作区。",
  "workspaceDeleteConfirmAction": "删除",
  "workspaceCancelAction": "取消"
```

Run:

```powershell
cd mobile
flutter gen-l10n
```

Expected: generated localization getters compile.

- [ ] **Step 4: Implement WorkspaceListPage UI**

Change the `WorkspaceListPage` constructor to include callbacks:

```dart
required this.onRenameWorkspace,
required this.onDeleteWorkspace,
```

with fields:

```dart
final void Function(WorkspaceSummary workspace, String name) onRenameWorkspace;
final ValueChanged<WorkspaceSummary> onDeleteWorkspace;
```

Convert `WorkspaceListPage` to `StatefulWidget` with a `_search` controller and local filtering:

```dart
final query = _search.text.trim().toLowerCase();
final visibleWorkspaces = dedupeWorkspacesByPath(widget.workspaces)
    .where((workspace) {
      if (query.isEmpty) return true;
      return workspace.name.toLowerCase().contains(query) ||
          workspace.path.toLowerCase().contains(query);
    })
    .toList(growable: false);
```

Replace `const SessionSearchBox()` with:

```dart
_WorkspaceSearchField(controller: _search)
```

Add `_WorkspaceSearchField`, `_WorkspaceEmptyState`, `_showWorkspaceActions`, and `_showRenameWorkspaceSheet` in `workspace_picker_sheet.dart`. Use `TextField` key `ValueKey('workspace-search-field')` and rename field key `ValueKey('workspace-rename-field')`.

Update `_WorkspaceChoiceRow` to accept `onLongPress` and pass it to `InkWell`:

```dart
final VoidCallback? onLongPress;
...
onLongPress: onLongPress,
```

When building rows:

```dart
_WorkspaceChoiceRow(
  workspace: workspace,
  selected: false,
  allowSelectedTap: true,
  onTap: () => widget.onSelected(workspace),
  onLongPress: () => _showWorkspaceActions(workspace),
)
```

- [ ] **Step 5: Wire CodingWorkbenchPage callbacks**

Update `_buildWorkspaceList()` in `coding_workbench_page.dart`:

```dart
  Widget _buildWorkspaceList() => WorkspaceListPage(
      workspaces: _workspaces,
      onSelected: _openWorkspaceSessions,
      onAddWorkspace: _showCreateWorkspaceFromWorkspaceList,
      onRenameWorkspace: _renameWorkspaceFromList,
      onDeleteWorkspace: _deleteWorkspaceFromList);
```

Add helpers:

```dart
  Future<void> _renameWorkspaceFromList(
      WorkspaceSummary workspace, String name) async {
    try {
      final renamed = await widget.client.renameWorkspace(workspace.id, name);
      if (!mounted) return;
      setState(() => _replaceWorkspaceInRouteState(renamed));
    } catch (error) {
      if (!mounted) return;
      await _showWorkspaceCreationDialog(
        title: 'Workspace rename failed',
        message: error.toString(),
      );
    }
  }

  Future<void> _deleteWorkspaceFromList(WorkspaceSummary workspace) async {
    try {
      final workspaces = await widget.client.deleteWorkspace(workspace.id);
      if (!mounted) return;
      setState(() => _routeState = WorkspaceListRouteState(workspaces: workspaces));
    } on DaemonClientException catch (error) {
      if (_isActiveWorkspaceDeleteConflict(error)) {
        final confirmed = await _showDeleteActiveWorkspaceDialog(workspace);
        if (confirmed != true) return;
        final workspaces =
            await widget.client.deleteWorkspace(workspace.id, closeActive: true);
        if (!mounted) return;
        setState(() => _routeState = WorkspaceListRouteState(workspaces: workspaces));
        return;
      }
      if (!mounted) return;
      await _showWorkspaceCreationDialog(
        title: 'Workspace deletion failed',
        message: error.toString(),
      );
    } catch (error) {
      if (!mounted) return;
      await _showWorkspaceCreationDialog(
        title: 'Workspace deletion failed',
        message: error.toString(),
      );
    }
  }
```

Implement `_replaceWorkspaceInRouteState`, `_isActiveWorkspaceDeleteConflict`, and `_showDeleteActiveWorkspaceDialog` using the existing route state classes and themed dialog style already used by `_showWorkspaceCreationDialog`.

- [ ] **Step 6: Run focused widget tests**

Run:

```powershell
cd mobile
flutter test test\widget_test.dart -r expanded --name "workspace list search|workspace row long press"
```

Expected: PASS.

- [ ] **Step 7: Run analyzer**

Run:

```powershell
cd mobile
flutter analyze
```

Expected: PASS.

- [ ] **Step 8: Commit**

Run:

```powershell
git add mobile/lib/src/features/workspace_picker/workspace_picker_sheet.dart mobile/lib/src/features/workbench/coding_workbench_page.dart mobile/lib/l10n/app_en.arb mobile/lib/l10n/app_zh.arb mobile/test/widget_test.dart
git commit -m "Add workspace management interactions"
```

## Task 5: Full Verification and Final Integration

**Files:**
- Review only unless verification finds defects.

- [ ] **Step 1: Run daemon verification**

Run:

```powershell
npm run lint
npm test
```

Expected: both PASS.

- [ ] **Step 2: Run Flutter verification**

Run:

```powershell
cd mobile
flutter analyze
flutter test test\daemon_client_test.dart test\widget_test.dart test\create_workspace_workflow_test.dart -r expanded
```

Expected: PASS.

- [ ] **Step 3: Check generated file and status noise**

Run:

```powershell
git status --short
git diff --name-status
```

Expected: only intentional source/test/localization changes are present. If Flutter generated plugin files appear but have no content diff, do not stage them.

- [ ] **Step 4: Commit any verification fixes**

If verification required fixes:

```powershell
git add daemon/src/app-sqlite-store.js daemon/src/workspace.js daemon/src/run-manager.js daemon/src/conversation-manager.js daemon/src/server.js scripts/run-tests.js mobile/lib/src/services/daemon_client.dart mobile/lib/src/features/workbench/coding_workbench_page.dart mobile/lib/src/features/workspace_picker/workspace_picker_sheet.dart mobile/lib/l10n/app_en.arb mobile/lib/l10n/app_zh.arb mobile/test/daemon_client_test.dart mobile/test/widget_test.dart
git commit -m "Stabilize workspace CRUD verification"
```

If no fixes were needed, do not create an empty commit.
