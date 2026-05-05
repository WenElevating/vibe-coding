# App DB Workspace Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist saved workspaces in the daemon application SQLite database and make mobile workspace creation/listing use daemon database state instead of widget-local cache state.

**Architecture:** Rename the daemon persistence boundary from conversation-only DB naming toward app-level DB naming, with `APP_DB_PATH` as the primary override and `CONVERSATION_DB_PATH` as a compatibility alias. Extend the SQLite store with `workspaces` and `workspace_device_authorizations`, then make `WorkspaceRegistry` read/write through that store while mobile refreshes daemon-authoritative workspaces after creation.

**Tech Stack:** Node.js CommonJS daemon, `node:sqlite` `DatabaseSync`, existing `AuthManager`, existing Flutter/Dart mobile client and widget tests, existing `npm test` and `mobile/check.bat` verification.

---

## File Structure

Create:
- `daemon/src/app-sqlite-store.js` - app-level SQLite store that owns conversations, conversation events, workspaces, and workspace authorization rows.

Modify:
- `daemon/src/conversation-sqlite-store.js` - convert to a compatibility re-export or thin subclass of the app store so old imports and tests continue to work during migration.
- `daemon/src/workspace.js` - change `WorkspaceRegistry` from in-memory-only `Map` to app-store-backed workspace access.
- `daemon/src/main.js` - wire `appDbPath`, `APP_DB_PATH`, compatibility `conversationDbPath`, and the app store into workspaces/conversations.
- `daemon/src/server.js` - keep route shapes, but rely on DB-backed registry semantics.
- `scripts/run-tests.js` - add app DB/workspace persistence tests and rename helper paths where appropriate.
- `mobile/lib/src/features/workbench/coding_workbench_page.dart` - refresh daemon workspace list after successful create before showing the success message.
- `mobile/test/coding_workbench_controller_test.dart` or `mobile/test/widget_test.dart` - add focused mobile regression coverage for stale snapshot not removing daemon-confirmed workspace state.
- `docs/superpowers/specs/2026-05-05-app-db-workspace-persistence-design.md` - no change expected unless implementation discovers a spec mismatch.

Do not modify:
- `daemon/src/auth.js` auth token format.
- CLI adapter cwd behavior.
- Workspace authorization policy beyond persisting the existing relation.

---

### Task 1: Add App DB Path and Store Skeleton

**Files:**
- Create: `daemon/src/app-sqlite-store.js`
- Modify: `daemon/src/conversation-sqlite-store.js`
- Test: `scripts/run-tests.js`

- [ ] **Step 1: Add failing app DB path test**

Add this test near the existing SQLite conversation store tests in `scripts/run-tests.js`:

```js
test('default app DB path uses app-level name', () => {
  const path = require('node:path');
  const { defaultAppDbPath } = require('../daemon/src/app-sqlite-store');

  assert.equal(
    defaultAppDbPath(),
    path.join(process.cwd(), 'data', 'app', 'app.sqlite')
  );
});
```

- [ ] **Step 2: Run test and verify it fails**

Run:

```bat
cd /d D:\AiProject\vibe-coding
npm test
```

Expected: FAIL because `daemon/src/app-sqlite-store.js` does not exist.

- [ ] **Step 3: Create `app-sqlite-store.js` by moving current SQLite store behavior**

Create `daemon/src/app-sqlite-store.js` with the current contents of `daemon/src/conversation-sqlite-store.js`, then make these exact naming changes:

```js
class AppSqliteStore {
  constructor({ dbPath = defaultAppDbPath(), now = () => new Date() } = {}) {
    this.dbPath = dbPath;
    this.now = now;
    fs.mkdirSync(path.dirname(dbPath), { recursive: true });
    this.db = new DatabaseSync(dbPath);
    this.db.exec('PRAGMA foreign_keys = ON');
    this.migrate();
  }
}

function defaultAppDbPath() {
  return path.join(process.cwd(), 'data', 'app', 'app.sqlite');
}

module.exports = { AppSqliteStore, defaultAppDbPath };
```

Keep all existing conversation methods (`saveConversation`, `loadConversations`, `appendEvent`, `listEvents`, `nextEventSeq`, `close`) unchanged inside `AppSqliteStore`.

- [ ] **Step 4: Preserve old conversation store imports**

Replace `daemon/src/conversation-sqlite-store.js` with:

```js
'use strict';

const { AppSqliteStore, defaultAppDbPath } = require('./app-sqlite-store');

class ConversationSqliteStore extends AppSqliteStore {}

function defaultDbPath() {
  return defaultAppDbPath();
}

module.exports = { ConversationSqliteStore, defaultDbPath };
```

- [ ] **Step 5: Run tests for compatibility**

Run:

```bat
cd /d D:\AiProject\vibe-coding
npm test
```

Expected: existing conversation persistence tests still pass, and the new default app DB path test passes.

- [ ] **Step 6: Commit**

```bat
cd /d D:\AiProject\vibe-coding
git add daemon/src/app-sqlite-store.js daemon/src/conversation-sqlite-store.js scripts/run-tests.js
git commit -m "Introduce app-level SQLite store"
```

---

### Task 2: Add Workspace Tables and Store Methods

**Files:**
- Modify: `daemon/src/app-sqlite-store.js`
- Test: `scripts/run-tests.js`

- [ ] **Step 1: Add failing workspace persistence tests**

Add these tests after the app DB path test in `scripts/run-tests.js`:

```js
test('app SQLite store persists workspaces and device authorizations', () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const { AppSqliteStore } = require('../daemon/src/app-sqlite-store');

  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'app-db-workspaces-'));
  const dbPath = path.join(dir, 'app.sqlite');
  const first = new AppSqliteStore({ dbPath, now: () => new Date('2026-05-05T00:00:00.000Z') });
  const workspace = first.saveWorkspaceForDevice({
    deviceId: 'device_1',
    workspacePath: path.join(dir, 'project'),
    name: 'Project'
  });
  first.close();

  const second = new AppSqliteStore({ dbPath, now: () => new Date('2026-05-05T00:00:01.000Z') });
  const listed = second.listWorkspacesForDevice('device_1');
  assert.equal(listed.length, 1);
  assert.equal(listed[0].id, workspace.id);
  assert.equal(listed[0].name, 'Project');
  assert.equal(listed[0].path, path.resolve(path.join(dir, 'project')));
  assert.deepEqual(second.listWorkspacesForDevice('device_2'), []);
  second.close();
});

test('app SQLite store scopes duplicate workspace paths by owner device', () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const { AppSqliteStore } = require('../daemon/src/app-sqlite-store');

  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'app-db-device-scope-'));
  const store = new AppSqliteStore({ dbPath: path.join(dir, 'app.sqlite') });
  const workspacePath = path.join(dir, 'shared-name');
  const first = store.saveWorkspaceForDevice({ deviceId: 'device_1', workspacePath, name: 'One' });
  const renamed = store.saveWorkspaceForDevice({ deviceId: 'device_1', workspacePath, name: 'Renamed' });
  const second = store.saveWorkspaceForDevice({ deviceId: 'device_2', workspacePath, name: 'Two' });

  assert.equal(first.id, renamed.id);
  assert.notEqual(first.id, second.id);
  assert.equal(store.listWorkspacesForDevice('device_1').length, 1);
  assert.equal(store.listWorkspacesForDevice('device_1')[0].name, 'Renamed');
  assert.equal(store.listWorkspacesForDevice('device_2').length, 1);
  assert.equal(store.listWorkspacesForDevice('device_2')[0].name, 'Two');
  store.close();
});
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bat
cd /d D:\AiProject\vibe-coding
npm test
```

Expected: FAIL because `saveWorkspaceForDevice` and `listWorkspacesForDevice` do not exist.

- [ ] **Step 3: Add workspace schema**

In `AppSqliteStore.migrate()`, add these tables inside the existing `db.exec()` block:

```sql
CREATE TABLE IF NOT EXISTS workspaces (
  id TEXT PRIMARY KEY,
  owner_device_id TEXT NOT NULL,
  name TEXT NOT NULL,
  path TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(owner_device_id, path)
);
CREATE TABLE IF NOT EXISTS workspace_device_authorizations (
  device_id TEXT NOT NULL,
  workspace_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY (device_id, workspace_id),
  FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_workspaces_owner_path
  ON workspaces(owner_device_id, path);
CREATE INDEX IF NOT EXISTS idx_workspace_auth_device
  ON workspace_device_authorizations(device_id);
```

- [ ] **Step 4: Add workspace methods**

Add these methods to `AppSqliteStore`:

```js
saveWorkspaceForDevice({ deviceId, id, name, workspacePath }) {
  if (!deviceId) throw new Error('deviceId is required');
  if (!workspacePath) throw new Error('workspace path is required');
  const resolved = path.resolve(workspacePath);
  const now = this.now().toISOString();
  const workspaceId = id || workspaceIdForDevicePath(deviceId, resolved);
  const displayName = name && String(name).trim() ? String(name).trim() : path.basename(resolved) || resolved;
  this.db.prepare(`
    INSERT INTO workspaces(id, owner_device_id, name, path, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?)
    ON CONFLICT(owner_device_id, path) DO UPDATE SET
      name = excluded.name,
      updated_at = excluded.updated_at
  `).run(workspaceId, deviceId, displayName, resolved, now, now);
  const row = this.db.prepare('SELECT id, name, path FROM workspaces WHERE owner_device_id = ? AND path = ?')
    .get(deviceId, resolved);
  this.authorizeWorkspaceForDevice(deviceId, row.id);
  return deserializeWorkspace(row);
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
  return this.db.prepare(`
    SELECT w.id, w.name, w.path
    FROM workspaces w
    INNER JOIN workspace_device_authorizations a ON a.workspace_id = w.id
    WHERE a.device_id = ?
    ORDER BY w.created_at ASC
  `).all(deviceId).map(deserializeWorkspace);
}

getWorkspaceForDevice(workspaceId, deviceId) {
  const row = this.db.prepare(`
    SELECT w.id, w.name, w.path
    FROM workspaces w
    INNER JOIN workspace_device_authorizations a ON a.workspace_id = w.id
    WHERE w.id = ? AND a.device_id = ?
  `).get(workspaceId, deviceId);
  return row ? deserializeWorkspace(row) : null;
}
```

Add helpers near existing serializers:

```js
function workspaceIdForDevicePath(deviceId, resolvedPath) {
  return `workspace_${crypto.createHash('sha1').update(`${deviceId}:${resolvedPath}`).digest('hex').slice(0, 12)}`;
}

function deserializeWorkspace(row) {
  return { id: row.id, name: row.name, path: row.path };
}
```

Also add `const crypto = require('node:crypto');` at the top of `app-sqlite-store.js`.

- [ ] **Step 5: Run tests**

Run:

```bat
cd /d D:\AiProject\vibe-coding
npm test
```

Expected: new store tests pass.

- [ ] **Step 6: Commit**

```bat
cd /d D:\AiProject\vibe-coding
git add daemon/src/app-sqlite-store.js scripts/run-tests.js
git commit -m "Persist workspaces in app SQLite store"
```

---

### Task 3: Make WorkspaceRegistry DB-Backed

**Files:**
- Modify: `daemon/src/workspace.js`
- Modify: `daemon/src/main.js`
- Test: `scripts/run-tests.js`

- [ ] **Step 1: Add failing registry persistence test**

Add this test after `workspace object authorization is enforced` in `scripts/run-tests.js`:

```js
test('workspace registry lists database-backed workspaces for authorized device', () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const { AppSqliteStore } = require('../daemon/src/app-sqlite-store');

  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'workspace-registry-db-'));
  const store = new AppSqliteStore({ dbPath: path.join(dir, 'app.sqlite') });
  const registry = new WorkspaceRegistry({ store });
  const device = { id: 'device_1', allowedWorkspaceIds: new Set() };
  const workspace = registry.add({ name: 'Saved', workspacePath: path.join(dir, 'saved') }, device);

  assert.equal(device.allowedWorkspaceIds.has(workspace.id), true);
  assert.equal(registry.listForDevice(device).some((item) => item.id === workspace.id), true);
  assert.equal(registry.getAuthorized(workspace.id, device).path, workspace.path);
  store.close();
});
```

- [ ] **Step 2: Run test and verify it fails**

Run:

```bat
cd /d D:\AiProject\vibe-coding
npm test
```

Expected: FAIL because `WorkspaceRegistry` does not accept `{ store }` and `add(..., device)`.

- [ ] **Step 3: Update `WorkspaceRegistry` constructor and add path**

Replace `WorkspaceRegistry` in `daemon/src/workspace.js` with DB-backed behavior:

```js
class WorkspaceRegistry {
  constructor({ store } = {}) {
    this.store = store || null;
    this.workspaces = new Map();
  }

  add({ id, name, workspacePath }, device = null) {
    if (!workspacePath) throw new Error('workspace path is required');
    if (this.store && device) {
      const workspace = this.store.saveWorkspaceForDevice({
        deviceId: device.id,
        id,
        name,
        workspacePath
      });
      device.allowedWorkspaceIds.add(workspace.id);
      return workspace;
    }
    const resolved = path.resolve(workspacePath);
    id = id || `workspace_${crypto.createHash('sha1').update(resolved).digest('hex').slice(0, 12)}`;
    name = name || path.basename(resolved) || resolved;
    const workspace = { id, name, path: resolved };
    this.workspaces.set(id, workspace);
    return workspace;
  }

  seedDefault({ id, name, workspacePath }, device) {
    if (!this.store) {
      const workspace = this.add({ id, name, workspacePath });
      if (device) device.allowedWorkspaceIds.add(workspace.id);
      return workspace;
    }
    const existing = this.store.listWorkspacesForDevice(device.id);
    if (existing.length > 0) return existing[0];
    return this.add({ id, name, workspacePath }, device);
  }

  listForDevice(device) {
    if (this.store) return this.store.listWorkspacesForDevice(device.id);
    return Array.from(this.workspaces.values()).filter((workspace) => device.allowedWorkspaceIds.has(workspace.id));
  }

  getAuthorized(workspaceId, device) {
    const workspace = this.store
      ? this.store.getWorkspaceForDevice(workspaceId, device.id)
      : this.workspaces.get(workspaceId);
    if (!workspace || !device.allowedWorkspaceIds.has(workspaceId)) {
      const error = new Error('workspace not found or not authorized');
      error.status = 404;
      error.code = 'WORKSPACE_NOT_FOUND';
      throw error;
    }
    return workspace;
  }
}
```

- [ ] **Step 4: Wire registry in `createApp()`**

In `daemon/src/main.js`:

1. Import app store:

```js
const { AppSqliteStore, defaultAppDbPath } = require('./app-sqlite-store');
```

2. Add parameter:

```js
appDbPath = process.env.APP_DB_PATH || conversationDbPath || process.env.CONVERSATION_DB_PATH || defaultAppDbPath(),
```

3. Create store before registry:

```js
const appSqliteStore = new AppSqliteStore({ dbPath: appDbPath });
const workspaces = new WorkspaceRegistry({ store: appSqliteStore });
const defaultDevice = { id: 'daemon-default', allowedWorkspaceIds: new Set() };
workspaces.seedDefault({ id: 'default', name: 'Current Project', workspacePath: process.cwd() }, defaultDevice);
```

4. Use the same `appSqliteStore` for conversation event store:

```js
const conversationSqliteStore = appSqliteStore;
```

5. Return `appSqliteStore` from `createApp()` alongside the compatibility `conversationSqliteStore`.

- [ ] **Step 5: Update server POST path to pass device**

In `daemon/src/server.js`, change workspace creation to:

```js
const workspace = workspaces.add(await readJson(req), device);
auth.allowWorkspace(device.id, workspace.id);
return json(res, 201, workspace);
```

- [ ] **Step 6: Run tests**

Run:

```bat
cd /d D:\AiProject\vibe-coding
npm test
```

Expected: registry and existing server tests pass.

- [ ] **Step 7: Commit**

```bat
cd /d D:\AiProject\vibe-coding
git add daemon/src/workspace.js daemon/src/main.js daemon/src/server.js scripts/run-tests.js
git commit -m "Back workspace registry with app database"
```

---

### Task 4: Verify API Persistence and DB Path Compatibility

**Files:**
- Modify: `scripts/run-tests.js`
- Modify: `daemon/src/main.js`

- [ ] **Step 1: Add registry restart persistence test**

Add this test near the workspace registry tests in `scripts/run-tests.js`:

```js
test('workspace registry persists created workspaces for the same authorized device', () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const { AppSqliteStore } = require('../daemon/src/app-sqlite-store');
  const { WorkspaceRegistry } = require('../daemon/src/workspace');

  const appDbPath = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'workspace-registry-persist-')), 'app.sqlite');
  const workspacePath = fs.mkdtempSync(path.join(os.tmpdir(), 'workspace-registry-folder-'));
  const device = { id: 'device_1' };

  const firstStore = new AppSqliteStore({ dbPath: appDbPath });
  const firstRegistry = new WorkspaceRegistry({ store: firstStore });
  const created = firstRegistry.add({ workspacePath, name: 'Persisted' }, device);
  firstStore.close();

  const secondStore = new AppSqliteStore({ dbPath: appDbPath });
  const secondRegistry = new WorkspaceRegistry({ store: secondStore });
  assert.equal(secondRegistry.listForDevice(device).some((workspace) => workspace.id === created.id), true);
  assert.deepEqual(secondRegistry.listForDevice({ id: 'device_2' }), []);
  secondStore.close();
});
```

Do not write this as an API restart test that pairs a new device after restart and expects it to see the old device's workspace. Auth tokens/devices are still in-memory in this pass, and the spec intentionally does not grant cross-device workspace visibility without explicit authorization.

- [ ] **Step 2: Add path precedence tests**

Add this test near app DB path tests:

```js
test('createApp prefers APP_DB_PATH over CONVERSATION_DB_PATH compatibility alias', () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const appDbPath = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'app-db-primary-')), 'app.sqlite');
  const conversationDbPath = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'conversation-db-alias-')), 'conversations.sqlite');

  const app = createApp({ port: 0, appDbPath, conversationDbPath, devAdapters: false });
  assert.equal(app.appSqliteStore.dbPath, appDbPath);
  app.appSqliteStore.close();
});
```

- [ ] **Step 3: Run test and fix path wiring if needed**

Run:

```bat
cd /d D:\AiProject\vibe-coding
npm test
```

Expected: tests pass. The persistence test must prove DB-backed workspace rows and authorization rows survive store/registry recreation for the same device id, while a different device id sees no workspace unless explicitly authorized.

- [ ] **Step 4: Commit**

```bat
cd /d D:\AiProject\vibe-coding
git add daemon/src/main.js scripts/run-tests.js
git commit -m "Verify app database workspace API persistence"
```

---

### Task 5: Refresh Mobile Workspace List from Daemon After Create

**Files:**
- Modify: `mobile/lib/src/features/workbench/coding_workbench_page.dart`
- Test: `mobile/test/coding_workbench_controller_test.dart`
- Test: `mobile/test/widget_test.dart` if a widget-level regression is practical with existing helpers

- [ ] **Step 1: Add a controller helper test for daemon-confirmed workspace merge**

Add this test to `mobile/test/coding_workbench_controller_test.dart`:

```dart
test('replaceWorkspacesFromDaemon keeps selected saved workspace visible', () {
  const original = WorkspaceSummary(
    id: 'workspace_1',
    name: 'Current Project',
    path: r'D:\AiProject\vibe-coding',
  );
  const created = WorkspaceSummary(
    id: 'workspace_test',
    name: 'Test',
    path: r'D:\AiProject\vibe-coding\test',
  );

  final next = replaceWorkspacesFromDaemon(
    const CodingWorkbenchState(
      workspaces: <WorkspaceSummary>[original],
      selectedWorkspace: original,
      listMode: CodingWorkbenchListMode.workspaces,
    ),
    const <WorkspaceSummary>[original, created],
    selectedWorkspaceId: created.id,
  );

  expect(next.workspaces, const <WorkspaceSummary>[original, created]);
  expect(next.selectedWorkspace, created);
  expect(next.listMode, CodingWorkbenchListMode.workspaces);
});
```

- [ ] **Step 2: Run focused mobile test and verify it fails**

Run:

```bat
cd /d D:\AiProject\vibe-coding\mobile
flutter test --no-pub test\coding_workbench_controller_test.dart
```

Expected: FAIL because `replaceWorkspacesFromDaemon` does not exist.

- [ ] **Step 3: Add controller helper**

Add this function to `mobile/lib/src/features/workbench/coding_workbench_controller.dart`:

```dart
CodingWorkbenchState replaceWorkspacesFromDaemon(
  CodingWorkbenchState state,
  List<WorkspaceSummary> workspaces, {
  String? selectedWorkspaceId,
}) {
  if (workspaces.isEmpty) return state;
  final selectedId = selectedWorkspaceId ?? state.selectedWorkspace.id;
  final selected = workspaces.firstWhere(
    (workspace) => workspace.id == selectedId,
    orElse: () => workspaces.first,
  );
  return CodingWorkbenchState(
    workspaces: List<WorkspaceSummary>.of(workspaces),
    selectedWorkspace: selected,
    listMode: state.listMode,
  );
}
```

- [ ] **Step 4: Change creation flow to refresh GET before snackbar**

In `mobile/lib/src/features/workbench/coding_workbench_page.dart`, update `_showCreateWorkspaceFromWorkspaceList()` so that after `AddWorkspaceSheet` returns `workspace`, it calls `widget.client.listWorkspaces()` before showing success:

```dart
try {
  final daemonWorkspaces = await widget.client.listWorkspaces();
  if (!mounted) return;
  setState(() {
    final next = replaceWorkspacesFromDaemon(
      CodingWorkbenchState(
        workspaces: _workspaces,
        selectedWorkspace: _selectedWorkspace,
        listMode: _listMode,
      ),
      daemonWorkspaces,
      selectedWorkspaceId: workspace.id,
    );
    _workspaces = next.workspaces;
    _selectedWorkspace = next.selectedWorkspace;
    _listMode = CodingWorkbenchListMode.workspaces;
    _workspaceConfirmedForSession = true;
    _resetConversationState();
    _error = null;
  });
  widget.onSessionListChanged(true);
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text('Workspace ready: ${workspace.name}'),
    duration: const Duration(seconds: 2),
  ));
} catch (error) {
  if (!mounted) return;
  setState(() {
    _error = 'Workspace was saved, but the list could not be refreshed: $error';
    _listMode = CodingWorkbenchListMode.workspaces;
  });
  widget.onSessionListChanged(true);
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
    content: Text('Workspace saved. Refresh workspaces to see it.'),
    duration: Duration(seconds: 3),
  ));
}
```

Do not call `_upsertWorkspace(workspace)` as the primary success path. The visible list must come from `listWorkspaces()`.

- [ ] **Step 5: Add manual retry path if not already available**

If the workspace page does not already have a refresh control, add a small retry action only for this error state. A minimal implementation is acceptable:

```dart
Future<void> _refreshWorkspacesFromDaemon() async {
  try {
    final daemonWorkspaces = await widget.client.listWorkspaces();
    if (!mounted) return;
    setState(() {
      final next = replaceWorkspacesFromDaemon(
        CodingWorkbenchState(
          workspaces: _workspaces,
          selectedWorkspace: _selectedWorkspace,
          listMode: _listMode,
        ),
        daemonWorkspaces,
      );
      _workspaces = next.workspaces;
      _selectedWorkspace = next.selectedWorkspace;
      _listMode = CodingWorkbenchListMode.workspaces;
      _error = null;
    });
  } catch (error) {
    if (mounted) setState(() => _error = error.toString());
  }
}
```

Wire it only if the current UI exposes error recovery in the workspace list; otherwise document in the final report that the warning is present but explicit retry UI remains follow-up.

- [ ] **Step 6: Run mobile checks**

Run:

```bat
cd /d D:\AiProject\vibe-coding\mobile
check.bat
```

Expected: `All checks passed.`

- [ ] **Step 7: Commit**

```bat
cd /d D:\AiProject\vibe-coding
git add mobile/lib/src/features/workbench/coding_workbench_controller.dart mobile/lib/src/features/workbench/coding_workbench_page.dart mobile/test
git commit -m "Refresh workspaces from daemon after creation"
```

---

### Task 6: Final Verification and Acceptance

**Files:**
- Read: `docs/superpowers/specs/2026-05-05-app-db-workspace-persistence-design.md`
- Read: `daemon/src/app-sqlite-store.js`
- Read: `daemon/src/workspace.js`
- Read: `mobile/lib/src/features/workbench/coding_workbench_page.dart`

- [ ] **Step 1: Verify no global path uniqueness**

Run:

```bat
cd /d D:\AiProject\vibe-coding
rg "UNIQUE\(path\)|unique.*path" daemon\src docs\superpowers\specs\2026-05-05-app-db-workspace-persistence-design.md
```

Expected: no `UNIQUE(path)` match. Any mention of path uniqueness must be device-scoped.

- [ ] **Step 2: Verify app DB naming**

Run:

```bat
cd /d D:\AiProject\vibe-coding
rg "data.*conversations.*conversations\.sqlite|CONVERSATION_DB_PATH" daemon\src scripts\run-tests.js
```

Expected: `CONVERSATION_DB_PATH` appears only as compatibility alias. Default runtime path should be `data/app/app.sqlite`.

- [ ] **Step 3: Run daemon tests**

Run:

```bat
cd /d D:\AiProject\vibe-coding
npm test
```

Expected: all daemon/script tests pass.

- [ ] **Step 4: Run mobile checks**

Run:

```bat
cd /d D:\AiProject\vibe-coding\mobile
check.bat
```

Expected: `All checks passed.`

- [ ] **Step 5: Commit any verification-only formatting changes**

If `check.bat` formats files, commit the formatting-only diff:

```bat
cd /d D:\AiProject\vibe-coding
git add mobile daemon scripts
git commit -m "Normalize app DB workspace persistence formatting"
```

If no files changed, do not create an empty commit.
