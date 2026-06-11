# Workspace Management and Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add safe workspace rename/delete management and a working workspace-list search field.

**Architecture:** The daemon owns workspace persistence mutations through `WorkspaceRegistry` and `AppSQLiteStore`. Flutter keeps UI rendering in widgets, state and commands in focused route/controller helpers, and daemon access in `DaemonClient` plus a small workspace repository boundary. Search is local view-model state and never calls the daemon.

**Tech Stack:** Node.js CommonJS daemon, SQLite app store, Flutter/Dart, Flutter `ChangeNotifier`/controller patterns, generated Flutter localizations, existing dark theme tokens.

---

## Source Spec

- `docs/superpowers/specs/2026-05-10-workspace-management-search-design.md`

## File Structure

- Modify: `daemon/src/app-sqlite-store.js` for `renameWorkspaceForDevice` and `deleteWorkspaceForDevice` persistence methods.
- Modify: `daemon/src/workspace.js` for registry-level rename/delete, authorization checks, in-memory behavior, and idempotent rename.
- Modify: `daemon/src/server.js` for `PATCH /api/workspaces/:workspaceId` and `DELETE /api/workspaces/:workspaceId`.
- Modify: `scripts/run-tests.js` for daemon regression tests around idempotency, deletion, authorization, and response status.
- Modify: `mobile/lib/src/services/daemon_client.dart` for `renameWorkspace` and `deleteWorkspace`.
- Create: `mobile/lib/src/features/workspace_picker/workspace_management_controller.dart` for local search/filter and mutation state.
- Modify: `mobile/lib/src/features/workspace_picker/workspace_picker_sheet.dart` for search input, overflow actions, dialogs, and callbacks.
- Modify: `mobile/lib/src/features/workbench/coding_workbench_page.dart` for wiring rename/delete callbacks and current-route delete behavior.
- Modify: `mobile/lib/l10n/app_en.arb` and `mobile/lib/l10n/app_zh.arb` for labels, hints, confirmations, and errors.
- Modify: `mobile/lib/l10n/app_localizations.dart`, `mobile/lib/l10n/app_localizations_en.dart`, and `mobile/lib/l10n/app_localizations_zh.dart` after running Flutter localization generation.
- Modify: `mobile/test/coding_workbench_controller_test.dart` for search/filter state tests and current-route delete policy tests.
- Create: `mobile/test/workspace_management_controller_test.dart` for focused search/filter and local mutation tests.

Do not run `git commit` during implementation unless the user explicitly asks.

---

### Task 1: Daemon Store Mutations

**Files:**
- Modify: `daemon/src/app-sqlite-store.js`
- Test: `scripts/run-tests.js`

- [ ] **Step 1: Add failing store tests**

Add tests near existing workspace store tests in `scripts/run-tests.js`:

```js
test('app SQLite store renames workspace idempotently without touching path or updated_at', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'app-db-workspace-rename-'));
  const dbPath = path.join(dir, 'app.sqlite');
  const store = new AppSQLiteStore({ dbPath, now: fixedNow('2026-05-10T00:00:00.000Z') });
  try {
    const created = store.saveWorkspaceForDevice({
      deviceId: 'device_1',
      name: 'Original',
      workspacePath: dir
    });
    const originalRow = store.db.prepare('SELECT updated_at FROM workspaces WHERE id = ?').get(created.id);

    const renamed = store.renameWorkspaceForDevice({
      deviceId: 'device_1',
      workspaceId: created.id,
      name: 'Renamed'
    });
    assert.equal(renamed.name, 'Renamed');
    assert.equal(renamed.path, created.path);

    const same = store.renameWorkspaceForDevice({
      deviceId: 'device_1',
      workspaceId: created.id,
      name: 'Renamed'
    });
    const sameRow = store.db.prepare('SELECT updated_at FROM workspaces WHERE id = ?').get(created.id);
    assert.equal(same.name, 'Renamed');
    assert.equal(sameRow.updated_at, originalRow.updated_at);
  } finally {
    store.close();
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('app SQLite store deletes workspace row and explicit authorizations only', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'app-db-workspace-delete-'));
  const dbPath = path.join(dir, 'app.sqlite');
  const store = new AppSQLiteStore({ dbPath });
  try {
    const workspace = store.saveWorkspaceForDevice({
      deviceId: 'device_1',
      name: 'Delete Me',
      workspacePath: dir
    });
    store.deleteWorkspaceForDevice({ deviceId: 'device_1', workspaceId: workspace.id });

    assert.equal(store.getWorkspace(workspace.id), null);
    assert.equal(store.getWorkspaceForDevice(workspace.id, 'device_1'), null);
    assert.ok(fs.existsSync(dir));
  } finally {
    store.close();
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npm test`

Expected: FAIL with `renameWorkspaceForDevice is not a function` or `deleteWorkspaceForDevice is not a function`.

- [ ] **Step 3: Implement store methods**

Add methods to `AppSQLiteStore` after `saveWorkspaceForDevice`:

```js
  renameWorkspaceForDevice({ deviceId, workspaceId, name }) {
    if (!deviceId) throw new Error('deviceId is required');
    if (!workspaceId) throw new Error('workspaceId is required');
    const displayName = String(name || '').trim();
    if (!displayName) throw new Error('workspace name is required');
    const current = this.getWorkspaceForDevice(workspaceId, deviceId);
    if (!current) return null;
    if (current.name === displayName) return current;
    const now = this.now().toISOString();
    this.db.prepare(`
      UPDATE workspaces
      SET name = ?, updated_at = ?
      WHERE id = ?
    `).run(displayName, now, workspaceId);
    return this.getWorkspaceForDevice(workspaceId, deviceId);
  }

  deleteWorkspaceForDevice({ deviceId, workspaceId }) {
    if (!deviceId) throw new Error('deviceId is required');
    if (!workspaceId) throw new Error('workspaceId is required');
    const current = this.getWorkspaceForDevice(workspaceId, deviceId);
    if (!current) return false;
    const transaction = this.db.transaction(() => {
      this.db.prepare('DELETE FROM workspace_device_authorizations WHERE workspace_id = ?').run(workspaceId);
      this.db.prepare('DELETE FROM workspaces WHERE id = ?').run(workspaceId);
    });
    transaction();
    return true;
  }
```

- [ ] **Step 4: Run store tests**

Run: `npm test`

Expected: PASS for the new store tests. If other unrelated tests fail, capture the failing names and continue only after confirming the new store tests pass.

---

### Task 2: Workspace Registry Contract

**Files:**
- Modify: `daemon/src/workspace.js`
- Test: `scripts/run-tests.js`

- [ ] **Step 1: Add failing registry tests**

Add tests near existing `WorkspaceRegistry` tests:

```js
test('workspace registry renames visible workspace and preserves path', () => {
  const registry = new WorkspaceRegistry();
  const device = { id: 'device_1', allowedWorkspaceIds: new Set() };
  const workspace = registry.add({ id: 'workspace_1', name: 'Before', workspacePath: '.' });
  registry.authorizeDeviceForWorkspace(device, workspace.id);

  const renamed = registry.renameAuthorized(workspace.id, device, 'After');
  assert.equal(renamed.id, workspace.id);
  assert.equal(renamed.name, 'After');
  assert.equal(renamed.path, workspace.path);

  const same = registry.renameAuthorized(workspace.id, device, 'After');
  assert.equal(same.name, 'After');
});

test('workspace registry deletes visible workspace without deleting directory', () => {
  const registry = new WorkspaceRegistry();
  const device = { id: 'device_1', allowedWorkspaceIds: new Set() };
  const workspace = registry.add({ id: 'workspace_1', name: 'Delete', workspacePath: '.' });
  registry.authorizeDeviceForWorkspace(device, workspace.id);

  assert.equal(registry.deleteAuthorized(workspace.id, device), true);
  assert.equal(registry.listForDevice(device).length, 0);
  assert.equal(device.allowedWorkspaceIds.has(workspace.id), false);
  assert.throws(() => registry.getAuthorized(workspace.id, device), /workspace not found or not authorized/);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npm test`

Expected: FAIL with missing `renameAuthorized` and `deleteAuthorized`.

- [ ] **Step 3: Implement registry methods**

Add to `WorkspaceRegistry`:

```js
  renameAuthorized(workspaceId, device, name) {
    const displayName = String(name || '').trim();
    if (!displayName) {
      const error = new Error('workspace name is required');
      error.status = 400;
      error.code = 'WORKSPACE_NAME_REQUIRED';
      throw error;
    }
    if (this.store) {
      const workspace = this.store.renameWorkspaceForDevice({
        deviceId: device.id,
        workspaceId,
        name: displayName
      });
      if (!workspace) return this.getAuthorized(workspaceId, device);
      return workspace;
    }
    const workspace = this.getAuthorized(workspaceId, device);
    if (workspace.name === displayName) return workspace;
    const updated = { ...workspace, name: displayName };
    this.workspaces.set(workspaceId, updated);
    return updated;
  }

  deleteAuthorized(workspaceId, device) {
    this.getAuthorized(workspaceId, device);
    if (this.store) return this.store.deleteWorkspaceForDevice({ deviceId: device.id, workspaceId });
    device.allowedWorkspaceIds.delete(workspaceId);
    return this.workspaces.delete(workspaceId);
  }
```

- [ ] **Step 4: Run registry tests**

Run: `npm test`

Expected: PASS for registry tests, including existing authorization tests.

---

### Task 3: Daemon HTTP Routes

**Files:**
- Modify: `daemon/src/server.js`
- Test: `scripts/run-tests.js`

- [ ] **Step 1: Add failing HTTP tests**

Add an integration test near existing `/api/workspaces` tests:

```js
test('HTTP API renames and deletes workspaces with stable management semantics', async () => {
  const app = createTestApp();
  const { port, close } = await listen(app.server);
  try {
    const paired = await request(port, 'POST', '/api/pair', { code: app.pairingCode, label: 'phone', deviceId: 'device_1' });
    const token = paired.body.token;
    const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'http-workspace-management-'));
    const created = await request(port, 'POST', '/api/workspaces', {
      workspacePath: tempRoot,
      name: 'Original'
    }, token);

    const renamed = await request(port, 'PATCH', `/api/workspaces/${created.body.id}`, { name: 'Renamed' }, token);
    assert.equal(renamed.status, 200);
    assert.equal(renamed.body.name, 'Renamed');
    assert.equal(renamed.body.path, created.body.path);

    const same = await request(port, 'PATCH', `/api/workspaces/${created.body.id}`, { name: 'Renamed' }, token);
    assert.equal(same.status, 200);
    assert.equal(same.body.name, 'Renamed');

    const rejected = await request(port, 'PATCH', `/api/workspaces/${created.body.id}`, { name: '   ' }, token);
    assert.equal(rejected.status, 400);

    const deleted = await request(port, 'DELETE', `/api/workspaces/${created.body.id}`, null, token);
    assert.equal(deleted.status, 204);
    assert.deepEqual(deleted.body, null);
    assert.ok(fs.existsSync(tempRoot));

    const list = await request(port, 'GET', '/api/workspaces', null, token);
    assert.equal(list.body.workspaces.some((workspace) => workspace.id === created.body.id), false);
    fs.rmSync(tempRoot, { recursive: true, force: true });
  } finally {
    await close();
  }
});
```

- [ ] **Step 2: Run tests to verify route failures**

Run: `npm test`

Expected: FAIL because `PATCH` and `DELETE` routes return `404`.

- [ ] **Step 3: Add route handlers**

In `server.js`, after `POST /api/workspaces`, add:

```js
      const workspaceManage = url.pathname.match(/^\/api\/workspaces\/([^/]+)$/);
      if (method === 'PATCH' && workspaceManage) {
        const body = await readJson(req);
        return json(res, 200, workspaces.renameAuthorized(workspaceManage[1], device, body.name));
      }
      if (method === 'DELETE' && workspaceManage) {
        workspaces.deleteAuthorized(workspaceManage[1], device);
        res.writeHead(204);
        return res.end();
      }
```

- [ ] **Step 4: Ensure `request` helper supports empty 204 bodies**

If the test helper assumes JSON for every response, update it to return `body: null` when the raw response body is empty:

```js
const parsedBody = rawBody.length === 0 ? null : JSON.parse(rawBody);
resolve({ status: res.statusCode, headers: res.headers, body: parsedBody });
```

- [ ] **Step 5: Run daemon tests**

Run: `npm test`

Expected: PASS for workspace management tests and existing daemon regression tests.

---

### Task 4: Flutter Client Data Boundary

**Files:**
- Modify: `mobile/lib/src/services/daemon_client.dart`
- Create: `mobile/lib/src/features/workspace_picker/workspace_management_controller.dart`
- Test: `mobile/test/workspace_management_controller_test.dart`

- [ ] **Step 1: Add controller tests for filtering and local updates**

Create `mobile/test/workspace_management_controller_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/features/workspace_picker/workspace_management_controller.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';

void main() {
  const alpha = WorkspaceSummary(id: 'w1', name: 'Alpha App', path: r'D:\projects\alpha');
  const daemon = WorkspaceSummary(id: 'w2', name: 'Daemon', path: r'D:\tools\daemon');

  test('filters workspaces by name and path while preserving query across list updates', () {
    final controller = WorkspaceManagementController(workspaces: const <WorkspaceSummary>[alpha, daemon]);

    controller.setSearchQuery('alpha');
    expect(controller.visibleWorkspaces, const <WorkspaceSummary>[alpha]);

    controller.setWorkspaces(const <WorkspaceSummary>[alpha, daemon]);
    expect(controller.searchQuery, 'alpha');
    expect(controller.visibleWorkspaces, const <WorkspaceSummary>[alpha]);

    controller.setSearchQuery('TOOLS');
    expect(controller.visibleWorkspaces, const <WorkspaceSummary>[daemon]);
  });

  test('clearSearch restores all visible workspaces', () {
    final controller = WorkspaceManagementController(workspaces: const <WorkspaceSummary>[alpha, daemon]);

    controller.setSearchQuery('alpha');
    controller.clearSearch();

    expect(controller.searchQuery, '');
    expect(controller.visibleWorkspaces, const <WorkspaceSummary>[alpha, daemon]);
  });

  test('rename and delete update local state', () {
    final controller = WorkspaceManagementController(workspaces: const <WorkspaceSummary>[alpha, daemon]);
    const renamed = WorkspaceSummary(id: 'w1', name: 'Alpha Renamed', path: r'D:\projects\alpha');

    controller.applyRenamedWorkspace(renamed);
    expect(controller.workspaces.first.name, 'Alpha Renamed');

    controller.applyDeletedWorkspace('w1');
    expect(controller.workspaces, const <WorkspaceSummary>[daemon]);
  });
}
```

- [ ] **Step 2: Run controller test to verify it fails**

Run: `cd mobile && flutter test test/workspace_management_controller_test.dart`

Expected: FAIL because `WorkspaceManagementController` does not exist.

- [ ] **Step 3: Implement controller**

Create `mobile/lib/src/features/workspace_picker/workspace_management_controller.dart`:

```dart
import 'package:flutter/foundation.dart';

import '../../models/protocol.dart';
import 'workspace_picker.dart';

class WorkspaceManagementController extends ChangeNotifier {
  WorkspaceManagementController({List<WorkspaceSummary> workspaces = const <WorkspaceSummary>[]})
      : _workspaces = List<WorkspaceSummary>.of(workspaces);

  List<WorkspaceSummary> _workspaces;
  String _searchQuery = '';

  List<WorkspaceSummary> get workspaces => List<WorkspaceSummary>.unmodifiable(_workspaces);
  String get searchQuery => _searchQuery;

  List<WorkspaceSummary> get visibleWorkspaces {
    final deduped = dedupeWorkspacesByPath(_workspaces);
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return deduped;
    return deduped
        .where((workspace) =>
            workspace.name.toLowerCase().contains(query) ||
            workspace.path.toLowerCase().contains(query))
        .toList(growable: false);
  }

  void setWorkspaces(List<WorkspaceSummary> workspaces) {
    _workspaces = List<WorkspaceSummary>.of(workspaces);
    notifyListeners();
  }

  void setSearchQuery(String query) {
    if (_searchQuery == query) return;
    _searchQuery = query;
    notifyListeners();
  }

  void clearSearch() => setSearchQuery('');

  void applyRenamedWorkspace(WorkspaceSummary workspace) {
    _workspaces = _workspaces
        .map((current) => current.id == workspace.id ? workspace : current)
        .toList(growable: false);
    notifyListeners();
  }

  void applyDeletedWorkspace(String workspaceId) {
    _workspaces = _workspaces
        .where((workspace) => workspace.id != workspaceId)
        .toList(growable: false);
    notifyListeners();
  }
}
```

- [ ] **Step 4: Add daemon client methods**

In `DaemonClient`, add after `createWorkspace`:

```dart
  Future<WorkspaceSummary> renameWorkspace({
    required String workspaceId,
    required String name,
  }) async {
    final response = await _patch('/api/workspaces/$workspaceId', <String, Object?>{
      'name': name.trim(),
    });
    return WorkspaceSummary.fromJson(response);
  }

  Future<void> deleteWorkspace(String workspaceId) async {
    await _delete('/api/workspaces/$workspaceId');
  }
```

If `_patch` and `_delete` helpers do not exist, add private helpers near `_get` and `_post` that reuse the same retry/auth/decode conventions. `_delete` should accept `204 No Content` and return without decoding.

- [ ] **Step 5: Run Flutter controller test**

Run: `cd mobile && flutter test test/workspace_management_controller_test.dart`

Expected: PASS.

---

### Task 5: Workspace List Search UI

**Files:**
- Modify: `mobile/lib/src/features/workspace_picker/workspace_picker_sheet.dart`
- Modify: `mobile/lib/src/features/workbench/coding_workbench_page.dart`
- Modify: `mobile/lib/l10n/app_en.arb`
- Modify: `mobile/lib/l10n/app_zh.arb`
- Test: `mobile/test/workspace_management_controller_test.dart`

- [ ] **Step 1: Add localization strings**

Add to `app_en.arb`:

```json
"workspaceSearchHint": "Search workspaces by name or path",
"workspaceSearchClear": "Clear workspace search",
"workspaceNoSearchResultsTitle": "No matching workspaces",
"workspaceNoSearchResultsBody": "Clear the search or add another workspace."
```

Add to `app_zh.arb`:

```json
"workspaceSearchHint": "按名称或路径搜索工作区",
"workspaceSearchClear": "清空工作区搜索",
"workspaceNoSearchResultsTitle": "没有匹配的工作区",
"workspaceNoSearchResultsBody": "清空搜索，或添加另一个工作区。"
```

- [ ] **Step 2: Update `WorkspaceListPage` constructor**

Add required fields:

```dart
required this.searchQuery,
required this.onSearchChanged,
required this.onClearSearch,
```

And declarations:

```dart
final String searchQuery;
final ValueChanged<String> onSearchChanged;
final VoidCallback onClearSearch;
```

- [ ] **Step 3: Replace static search label with real text input**

Replace `const SessionSearchBox()` with:

```dart
_WorkspaceSearchField(
  query: searchQuery,
  onChanged: onSearchChanged,
  onClear: onClearSearch,
),
```

Add `_WorkspaceSearchField` in the same file:

```dart
class _WorkspaceSearchField extends StatelessWidget {
  const _WorkspaceSearchField({
    required this.query,
    required this.onChanged,
    required this.onClear,
  });

  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextField(
      controller: TextEditingController(text: query)
        ..selection = TextSelection.collapsed(offset: query.length),
      onChanged: onChanged,
      style: const TextStyle(color: theme.text, fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        hintText: l10n.workspaceSearchHint,
        hintStyle: const TextStyle(color: theme.faint, fontSize: 13),
        prefixIcon: const Icon(Icons.search_rounded, color: theme.muted, size: 18),
        suffixIcon: query.isEmpty
            ? null
            : IconButton(
                tooltip: l10n.workspaceSearchClear,
                icon: const Icon(Icons.close_rounded, color: theme.muted, size: 18),
                onPressed: onClear,
              ),
        filled: true,
        fillColor: const Color(0xFF101113),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: .075)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: theme.purple.withValues(alpha: .55)),
        ),
      ),
    );
  }
}
```

Implement `_WorkspaceSearchField` as a `StatefulWidget` with a retained `TextEditingController`. Sync external query changes in `didUpdateWidget` so the clear button can reset the field without causing cursor jumps during typing.

- [ ] **Step 4: Render filtered empty state**

When `visibleWorkspaces.isEmpty && searchQuery.trim().isNotEmpty`, render:

```dart
_WorkspaceSearchEmptyState(onClear: onClearSearch)
```

Add widget:

```dart
class _WorkspaceSearchEmptyState extends StatelessWidget {
  const _WorkspaceSearchEmptyState({required this.onClear});
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101113),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: .075)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l10n.workspaceNoSearchResultsTitle,
            style: const TextStyle(color: theme.text, fontSize: 13, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(l10n.workspaceNoSearchResultsBody,
            style: const TextStyle(color: theme.muted, fontSize: 12)),
        const SizedBox(height: 10),
        TinyActionButton(l10n.workspaceSearchClear, onTap: onClear),
      ]),
    );
  }
}
```

- [ ] **Step 5: Wire controller in workbench page**

Add a `WorkspaceManagementController` field in `CodingWorkbenchPageState`, initialize it from `_workspaces` after data is available, and pass:

```dart
workspaces: _workspaceManagement.visibleWorkspaces,
searchQuery: _workspaceManagement.searchQuery,
onSearchChanged: _workspaceManagement.setSearchQuery,
onClearSearch: _workspaceManagement.clearSearch,
```

When daemon snapshot workspaces update the route list, call:

```dart
_workspaceManagement.setWorkspaces(_workspaces);
```

- [ ] **Step 6: Run Flutter tests**

Run: `cd mobile && flutter test test/workspace_management_controller_test.dart`

Expected: PASS.

---

### Task 6: Workspace Rename/Delete UI

**Files:**
- Modify: `mobile/lib/src/features/workspace_picker/workspace_picker_sheet.dart`
- Modify: `mobile/lib/src/features/workbench/coding_workbench_page.dart`
- Modify: `mobile/lib/l10n/app_en.arb`
- Modify: `mobile/lib/l10n/app_zh.arb`

- [ ] **Step 1: Add localization strings**

Add to `app_en.arb`:

```json
"workspaceRenameAction": "Rename",
"workspaceDeleteAction": "Delete from app",
"workspaceRenameTitle": "Rename workspace",
"workspaceRenameNameLabel": "Workspace name",
"workspaceRenameSave": "Save name",
"workspaceDeleteTitle": "Delete workspace from app?",
"workspaceDeleteBody": "This removes the workspace from the app database. Local files and folders stay on disk.",
"workspaceDeleteConfirm": "Delete from app",
"workspaceCurrentDeleteBlocked": "Return to the workspace list before deleting this active workspace.",
"workspaceDeletedNotice": "Workspace removed from the app. Local files were not deleted."
```

Add equivalent Chinese strings to `app_zh.arb`:

```json
"workspaceRenameAction": "重命名",
"workspaceDeleteAction": "从应用删除",
"workspaceRenameTitle": "重命名工作区",
"workspaceRenameNameLabel": "工作区名称",
"workspaceRenameSave": "保存名称",
"workspaceDeleteTitle": "从应用删除工作区？",
"workspaceDeleteBody": "这只会从应用数据库移除该工作区。本地文件和文件夹会保留在磁盘上。",
"workspaceDeleteConfirm": "从应用删除",
"workspaceCurrentDeleteBlocked": "请先返回工作区列表，再删除这个活动工作区。",
"workspaceDeletedNotice": "工作区已从应用移除。本地文件没有被删除。"
```

- [ ] **Step 2: Extend `WorkspaceListPage` callbacks**

Add:

```dart
required this.onRenameWorkspace,
required this.onDeleteWorkspace,
```

With fields:

```dart
final ValueChanged<WorkspaceSummary> onRenameWorkspace;
final ValueChanged<WorkspaceSummary> onDeleteWorkspace;
```

- [ ] **Step 3: Add trailing overflow menu to workspace rows**

Extend `_WorkspaceChoiceRow` with optional action callbacks and add a trailing `PopupMenuButton<String>` that calls rename/delete. Keep row tap as workspace open.

```dart
PopupMenuButton<String>(
  color: theme.panelHi,
  icon: const Icon(Icons.more_horiz_rounded, color: theme.muted, size: 20),
  onSelected: (value) {
    if (value == 'rename') onRename?.call();
    if (value == 'delete') onDelete?.call();
  },
  itemBuilder: (context) => [
    PopupMenuItem(value: 'rename', child: Text(AppLocalizations.of(context).workspaceRenameAction)),
    PopupMenuItem(value: 'delete', child: Text(AppLocalizations.of(context).workspaceDeleteAction)),
  ],
)
```

- [ ] **Step 4: Add rename dialog**

In `CodingWorkbenchPageState`, add `_renameWorkspace(WorkspaceSummary workspace)` that opens an `AlertDialog` with a `TextField`, validates non-empty and changed text, calls `widget.client.renameWorkspace`, applies `_workspaceManagement.applyRenamedWorkspace`, updates `_routeState` workspace lists, and shows an error if the daemon throws.

- [ ] **Step 5: Add delete confirmation**

In `CodingWorkbenchPageState`, add `_deleteWorkspace(WorkspaceSummary workspace)` that blocks deletion if `workspace.id == _routeWorkspace?.id` and the current route cannot be replaced safely. Otherwise show a confirmation dialog and call `widget.client.deleteWorkspace(workspace.id)` only after confirmation.

- [ ] **Step 6: Apply successful delete locally**

After daemon success:

```dart
_workspaceManagement.applyDeletedWorkspace(workspace.id);
setState(() {
  _workspaces = _workspaces.where((item) => item.id != workspace.id).toList(growable: false);
  _routeState = WorkspaceListRouteState(workspaces: _workspaces, notice: l10n.workspaceDeletedNotice);
});
```

Render `WorkspaceListRouteState.notice` in `WorkspaceListPage` above the search field as a small muted notice panel using existing `theme.panelHi`, `theme.stroke`, and `theme.muted` tokens.

- [ ] **Step 7: Run targeted Flutter tests**

Run: `cd mobile && flutter test test/coding_workbench_controller_test.dart test/workspace_management_controller_test.dart`

Expected: PASS.

---

### Task 7: Localization Generation and Static Checks

**Files:**
- Modify: `mobile/lib/l10n/app_localizations.dart`
- Modify: `mobile/lib/l10n/app_localizations_en.dart`
- Modify: `mobile/lib/l10n/app_localizations_zh.dart`

- [ ] **Step 1: Generate localizations**

Run: `cd mobile && flutter gen-l10n`

Expected: generated localization accessors include all new `workspace...` keys.

- [ ] **Step 2: Format Dart files**

Run: `cd mobile && dart format lib/src/services/daemon_client.dart lib/src/features/workspace_picker/workspace_management_controller.dart lib/src/features/workspace_picker/workspace_picker_sheet.dart lib/src/features/workbench/coding_workbench_page.dart test/workspace_management_controller_test.dart test/coding_workbench_controller_test.dart`

Expected: formatter exits successfully.

- [ ] **Step 3: Analyze Flutter code**

Run: `cd mobile && flutter analyze`

Expected: no new analyzer errors.

---

### Task 8: Full Verification

**Files:**
- Verify all touched files.

- [ ] **Step 1: Run daemon regression tests**

Run: `npm test`

Expected: PASS.

- [ ] **Step 2: Run Flutter tests**

Run: `cd mobile && flutter test`

Expected: PASS.

- [ ] **Step 3: Run Flutter analyzer**

Run: `cd mobile && flutter analyze`

Expected: no issues introduced by this feature.

- [ ] **Step 4: Manual smoke checklist**

Start the daemon and app, then verify:

```text
1. Workspace search field receives focus on tap.
2. Typing a name filters the workspace list.
3. Typing a path segment filters the workspace list.
4. Clear button restores the full list.
5. Rename changes only the display name.
6. Delete removes the workspace from the app list.
7. The deleted workspace folder still exists on disk.
8. Deleting the active route workspace is blocked or safely returns to the list.
```

Expected: all checklist items pass.

---

## Self-Review

- Spec coverage: rename idempotency, `204` delete, explicit authorization deletion, no disk deletion, local search lifecycle, fixed rename dialog, current-route delete safety, i18n, architecture boundaries, and tests are all mapped to tasks.
- Placeholder scan: no open placeholder instructions remain; every implementation decision has a concrete target.
- Type consistency: daemon methods use `renameAuthorized`, `deleteAuthorized`, `renameWorkspaceForDevice`, and `deleteWorkspaceForDevice`; Flutter methods use `renameWorkspace`, `deleteWorkspace`, and `WorkspaceManagementController` consistently.
- Commit policy: plan intentionally omits commit steps because this session is not authorized to create git commits.
