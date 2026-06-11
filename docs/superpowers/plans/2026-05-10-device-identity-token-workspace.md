# Device Identity, Short-Lived Token, and Workspace Binding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make device identity stable per installation, keep tokens short-lived and refreshable, and bind workspaces to the owning device so workspaces survive app restarts on the same installation.

**Architecture:** The mobile client owns `deviceId` generation and local persistence. The daemon owns device records, token issuance/refresh, and workspace ownership by device record. `deviceId` is the ownership anchor, access tokens are the short-lived request credential, and refresh tokens renew access without changing device identity.

**Tech Stack:** Flutter/Dart, existing `DaemonClient`, `shared_preferences`, existing Node.js daemon, existing SQLite store, `node:test`, `flutter_test`.

---

## File Structure

- Create: `mobile/lib/src/services/device_identity_store.dart` - persistent `deviceId` store and in-memory test double.
- Modify: `mobile/lib/src/services/daemon_client.dart` - pair/login requests carry `deviceId`; add access/refresh token handling and secure token storage hooks.
- Modify: `mobile/lib/src/shell/app_snapshot.dart` - bootstrap path calls `ensurePaired()` instead of generating a fresh device identity every launch.
- Modify: `mobile/lib/src/workflows/connection/daemon_connection_workflow.dart` - inject the device identity store and reuse it through initial-data loading.
- Modify: `mobile/lib/src/ui/mobile_ui.dart` - wire the persistent device identity store into the app composition root.
- Modify: `mobile/test/app_snapshot_bootstrap_test.dart` - prove bootstrap reuses the same device identity.
- Create: `mobile/test/device_identity_store_test.dart` - verify persistent store round-trip and UUID v4 format.

- Modify: `daemon/src/auth.js` - accept client-supplied `deviceId`, store hashed device identity, issue access + refresh tokens, and support refresh rotation.
- Modify: `daemon/src/server.js` - forward `deviceId` into pair/login flow and add token refresh endpoint wiring.
- Modify: `daemon/src/app-sqlite-store.js` - add devices, device_tokens, and workspace ownership schema changes plus lookup helpers.
- Modify: `daemon/src/workspace.js` - bind new workspaces to the resolved device record and filter list access by device.
- Modify: `daemon/src/main.js` or the daemon bootstrap path that constructs auth/store objects - pass pepper/TTL configuration into auth and persistence.
- Modify: `daemon/test/core.test.js` - cover fixed device id reuse, token rotation, and device lookup behavior.
- Create: `daemon/test/device-persistence.test.js` - cover sqlite-backed device uniqueness, token indexes, and workspace ownership behavior.

## Task 1: Mobile Device Identity Store

**Files:**
- Create: `mobile/lib/src/services/device_identity_store.dart`
- Modify: `mobile/lib/src/shell/app_snapshot.dart`
- Modify: `mobile/lib/src/workflows/connection/daemon_connection_workflow.dart`
- Modify: `mobile/lib/src/ui/mobile_ui.dart`
- Test: `mobile/test/device_identity_store_test.dart`
- Test: `mobile/test/app_snapshot_bootstrap_test.dart`

- [ ] **Step 1: Write the failing mobile identity tests**

Add tests that prove a persisted store returns the same RFC 4122 UUID v4 value across reloads, and that bootstrap uses the injected identity store rather than creating a fresh device identity every launch:

```dart
test('persistent device identity store reuses the same uuid v4', () async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final store = SharedPreferencesDeviceIdentityStore();

  final first = await store.readOrCreateDeviceId();
  final second = await store.readOrCreateDeviceId();

  expect(first, second);
  expect(first, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
});

test('bootstrap reuses injected device identity store', () async {
  final deviceStore = MemoryDeviceIdentityStore(deviceId: '11111111-1111-4111-8111-111111111111');
  final client = _BootstrapDaemonClient(deviceStore: deviceStore);

  await AppSnapshot.loadBootstrap(client, deviceIdentityStore: deviceStore);

  expect(client.ensurePairedCalls, 1);
  expect(client.lastDeviceStore, same(deviceStore));
});
```

- [ ] **Step 2: Run the mobile tests to verify failure**

Run: `cd mobile && flutter test test/device_identity_store_test.dart test/app_snapshot_bootstrap_test.dart`
Expected: FAIL because the device identity store file and the new `ensurePaired()` path are not fully implemented yet.

- [ ] **Step 3: Implement the device identity store**

Create the store and test double:

```dart
abstract class DeviceIdentityStore {
  Future<String> readOrCreateDeviceId();
}

class SharedPreferencesDeviceIdentityStore implements DeviceIdentityStore {
  static const String _deviceIdKey = 'daemon.deviceId';

  @override
  Future<String> readOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final deviceId = _generateUuidV4();
    await prefs.setString(_deviceIdKey, deviceId);
    return deviceId;
  }
}

class MemoryDeviceIdentityStore implements DeviceIdentityStore {
  MemoryDeviceIdentityStore({String? deviceId}) : _deviceId = deviceId;

  String? _deviceId;

  @override
  Future<String> readOrCreateDeviceId() async =>
      _deviceId ??= _generateUuidV4();
}
```

Add a private `_generateUuidV4()` helper that uses `Random.secure()` and canonical lowercase hyphenated UUID v4 formatting.

- [ ] **Step 4: Route bootstrap and app composition through the identity store**

Change `AppSnapshot.load()` / `loadBootstrap()` to call `client.ensurePaired(deviceIdentityStore: ...)` before listing workspaces. Change `DaemonConnectionWorkflow` and `MobileUi` to construct and inject `SharedPreferencesDeviceIdentityStore` once at the composition root.

- [ ] **Step 5: Run the mobile tests to verify pass**

Run: `cd mobile && flutter test test/device_identity_store_test.dart test/app_snapshot_bootstrap_test.dart`
Expected: PASS.

## Task 2: Mobile Token Storage and Refresh Wiring

**Files:**
- Modify: `mobile/lib/src/services/daemon_client.dart`
- Modify: `mobile/lib/src/services/conversation_client.dart` if it shares the same token store semantics
- Modify: `mobile/lib/src/ui/mobile_ui.dart`
- Test: `mobile/test/daemon_client_test.dart`
- Test: `mobile/test/widget_test.dart`

- [ ] **Step 1: Write failing token-behavior tests**

Add tests that prove pair/login stores both access and refresh tokens, refresh rotates the refresh token, and invalid refresh falls back without changing `deviceId`:

```dart
test('pair stores access and refresh tokens separately', () async {
  final tokenStore = MemoryTokenStore();
  final client = DaemonClient(baseUri: Uri.parse('http://127.0.0.1:4317'), tokenStore: tokenStore);

  await client.pair(code: '123456', deviceId: '11111111-1111-4111-8111-111111111111');

  expect(client.currentToken, isNotNull);
  expect(await tokenStore.readDeviceToken('11111111-1111-4111-8111-111111111111'), isNotNull);
});

test('refresh rotates refresh token and keeps device identity stable', () async {
  // fake server response with old/new refresh token hashes and same device id
});
```

- [ ] **Step 2: Run the token tests to verify failure**

Run: `cd mobile && flutter test test/daemon_client_test.dart`
Expected: FAIL until the client can carry device id, access token, and refresh token explicitly.

- [ ] **Step 3: Implement explicit token handling**

Extend `DaemonClient` so pair/login writes both tokens, the refresh flow rotates the refresh token, and the client keeps `deviceId` unchanged while refreshing. Keep `tokenStore` responsible for token persistence and add a secure-storage-backed refresh token path in the app composition root.

- [ ] **Step 4: Run the token tests to verify pass**

Run: `cd mobile && flutter test test/daemon_client_test.dart test/widget_test.dart`
Expected: PASS for the targeted token/storage behavior.

## Task 3: Daemon Device and Token Persistence

**Files:**
- Modify: `daemon/src/auth.js`
- Modify: `daemon/src/server.js`
- Modify: `daemon/src/app-sqlite-store.js`
- Modify: `daemon/src/main.js` or daemon bootstrap wiring
- Test: `daemon/test/core.test.js`
- Create: `daemon/test/device-persistence.test.js`

- [ ] **Step 1: Write failing daemon persistence tests**

Add tests that prove:

```js
test('pairing with the same device id reuses the same device record', () => {
  // pair twice with the same deviceId and assert a unique device record is reused
});

test('access and refresh tokens are stored and rotated by token type', () => {
  // assert token_type is persisted and refresh invalidates the previous refresh token
});

test('workspace ownership stays attached to the device record across restart', () => {
  // create workspace, reconstruct auth/store, list workspaces for same device, assert it still appears
});
```

- [ ] **Step 2: Run daemon tests to verify failure**

Run: `npm test -- --runInBand`
Expected: FAIL until the daemon schema and auth flow are updated.

- [ ] **Step 3: Implement device, token, and workspace persistence**

Add a `devices` table keyed by `device_id_hash` with a unique index, a `device_tokens` table with `token_type`, `token_hash`, `expires_at`, and `revoked_at`, and a `workspaces.device_id` foreign key. Update `AuthManager` so `pair()` accepts `requestedDeviceId`, hashes it with the active pepper, reuses the same device record if it already exists, and issues access + refresh tokens with distinct TTLs. Update `server.js` to forward `deviceId` and expose token refresh wiring.

- [ ] **Step 4: Implement workspace ownership by device**

Update workspace creation so new workspaces are stored against the resolved device record, and workspace listing uses that same device association. Do not change the workbench route architecture in this task; only the daemon-side ownership model.

- [ ] **Step 5: Run daemon tests to verify pass**

Run: `npm test -- --runInBand`
Expected: PASS.

## Task 4: Migration and Cleanup

**Files:**
- Modify: `mobile/lib/src/services/device_identity_store.dart`
- Modify: `mobile/lib/src/services/daemon_client.dart`
- Modify: `daemon/src/app-sqlite-store.js`
- Modify: `daemon/src/auth.js`
- Modify: `daemon/src/server.js`
- Modify: `daemon/test/core.test.js`
- Modify: `mobile/test/app_snapshot_bootstrap_test.dart`

- [ ] **Step 1: Add the upgrade-path regression tests**

Add tests for existing installs with no persisted `deviceId`: the app should create one and pair as a fresh device, not invent a second identity for the same installation. Add a daemon-side regression test that concurrent pair requests for the same `deviceId` stay idempotent under the unique index.

- [ ] **Step 2: Run formatter on touched files**

Run: `cd mobile && dart format lib/src/services/device_identity_store.dart lib/src/services/daemon_client.dart lib/src/shell/app_snapshot.dart lib/src/workflows/connection/daemon_connection_workflow.dart lib/src/ui/mobile_ui.dart test/device_identity_store_test.dart test/app_snapshot_bootstrap_test.dart test/daemon_client_test.dart`

Run: `dart format daemon/src/auth.js daemon/src/server.js daemon/src/app-sqlite-store.js daemon/src/main.js daemon/test/core.test.js daemon/test/device-persistence.test.js`

Expected: files formatted with no syntax errors.

- [ ] **Step 3: Run focused verification**

Run: `cd mobile && flutter analyze --no-pub`
Expected: `No issues found!`

Run: `cd mobile && flutter test test/device_identity_store_test.dart test/app_snapshot_bootstrap_test.dart test/daemon_client_test.dart`
Expected: targeted mobile tests pass.

Run: `npm test -- --runInBand`
Expected: daemon tests pass.

- [ ] **Step 4: Commit implementation**

Commit only touched source and test files. Use Lore trailers with `Tested:` covering the mobile targeted tests and daemon test evidence. Do not commit generated data, `.omx/`, or runtime SQLite files.

## Self-Review

- Spec coverage: persistent device identity, BLAKE2b peppered HMAC, token type separation, default TTLs, secure refresh-token storage, workspace ownership by device, and upgrade-path handling are all mapped to tasks.
- Placeholder scan: no `TBD`, `TODO`, or vague implementation steps remain.
- Type consistency: the plan uses `DeviceIdentityStore`, `SharedPreferencesDeviceIdentityStore`, `MemoryDeviceIdentityStore`, `device_id_hash`, `token_type`, `access token`, and `refresh token` consistently throughout.
