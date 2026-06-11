# Mobile Connection Architecture Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the mobile daemon connection startup path into explicit data, workflow, domain, ViewModel, and View boundaries without changing user-visible behavior.

**Architecture:** Keep this migration narrow and compatibility-first. Add the new layered files around the existing connection path, make `DaemonConnectionController` a compatibility surface over the new ViewModel, and keep old import paths available while tests migrate.

**Tech Stack:** Flutter, Dart, `ChangeNotifier`, `SharedPreferences`, existing daemon client and Flutter test tooling.

---

## File Structure

- Create: `mobile/lib/src/data/repositories/daemon_connection_config_repository.dart` — persistence-only config repository wrapping `DaemonConnectionConfigStore`.
- Create: `mobile/lib/src/domain/models/daemon_initial_data.dart` — startup daemon data name replacing generic snapshot language.
- Create: `mobile/lib/src/domain/models/connected_app_session.dart` — connected bundle of daemon client, initial data, and config.
- Create: `mobile/lib/src/workflows/connection/daemon_connection_workflow.dart` — application-layer connection orchestration.
- Create: `mobile/lib/src/ui/features/connection/view_models/daemon_connection_view_model.dart` — `ChangeNotifier` state holder and command surface.
- Create: `mobile/lib/src/ui/features/connection/views/mobile_connection_gate.dart` — connection entry widget that renders loading, connection form, or main tabs.
- Modify: `mobile/lib/src/state/daemon_connection_controller.dart` — compatibility export/subclass for existing tests and call sites.
- Modify: `mobile/lib/src/ui/mobile_ui.dart` — delegate connection gating to the connection feature.
- Modify: `mobile/lib/src/shell/app_snapshot.dart` — add compatibility typedef/export path for `DaemonInitialData` if needed.
- Modify: `mobile/test/daemon_connection_controller_test.dart` — keep compatibility tests green and add ViewModel/workflow assertions where signatures change.
- Add tests: `mobile/test/daemon_connection_workflow_test.dart` — focused workflow orchestration coverage.

## Task 1: Add Persistence Repository

**Files:**
- Create: `mobile/lib/src/data/repositories/daemon_connection_config_repository.dart`
- Test: `mobile/test/daemon_connection_config_store_test.dart`

- [ ] **Step 1: Add repository wrapper**

Create `DaemonConnectionConfigRepository` with this API:

```dart
import '../../services/daemon_connection_config.dart';
import '../../services/daemon_connection_config_store.dart';

class DaemonConnectionConfigRepository {
  DaemonConnectionConfigRepository({required DaemonConnectionConfigStore store})
      : _store = store;

  final DaemonConnectionConfigStore _store;

  Future<DaemonConnectionConfig> load() => _store.load();

  Future<void> save(DaemonConnectionConfig config) => _store.save(config);
}
```

- [ ] **Step 2: Run existing config tests**

Run: `cd mobile && flutter test test/daemon_connection_config_store_test.dart`

Expected: existing config store tests pass unchanged.

## Task 2: Add Domain Session Names

**Files:**
- Create: `mobile/lib/src/domain/models/daemon_initial_data.dart`
- Create: `mobile/lib/src/domain/models/connected_app_session.dart`
- Modify: `mobile/lib/src/shell/app_snapshot.dart`
- Test: `mobile/test/app_snapshot_bootstrap_test.dart`

- [ ] **Step 1: Introduce `DaemonInitialData` as compatibility type**

Keep existing behavior by making `DaemonInitialData` an alias of the current startup data class until a deeper rename is safe:

```dart
import '../../shell/app_snapshot.dart';

typedef DaemonInitialData = AppSnapshot;
```

- [ ] **Step 2: Add connected session model**

Create `ConnectedAppSession`:

```dart
import '../../services/daemon_client.dart';
import '../../services/daemon_connection_config.dart';
import 'daemon_initial_data.dart';

class ConnectedAppSession {
  const ConnectedAppSession({
    required this.client,
    required this.initialData,
    required this.connectedConfig,
  });

  final DaemonClient client;
  final DaemonInitialData initialData;
  final DaemonConnectionConfig connectedConfig;
}
```

- [ ] **Step 3: Run bootstrap test**

Run: `cd mobile && flutter test test/app_snapshot_bootstrap_test.dart`

Expected: bootstrap behavior remains unchanged.

## Task 3: Extract Connection Workflow

**Files:**
- Create: `mobile/lib/src/workflows/connection/daemon_connection_workflow.dart`
- Create: `mobile/test/daemon_connection_workflow_test.dart`

- [ ] **Step 1: Add workflow tests**

Cover successful ordering, health failure, initial-data failure, and config save. Use fake `DaemonClient` subclasses and injected loader/probe functions so no network is used.

- [ ] **Step 2: Implement workflow**

Implement constructor-injected dependencies:

```dart
typedef DaemonClientFactory = DaemonClient Function({
  required Uri baseUri,
  required SecureTokenStore tokenStore,
  required DaemonProxyMode proxyMode,
  Uri? manualProxy,
});

typedef DaemonInitialDataLoader = Future<DaemonInitialData> Function(
    DaemonClient client);

typedef DaemonHealthProbe = Future<void> Function(DaemonClient client);
```

The workflow validates address/proxy, creates the client, probes health, loads `DaemonInitialData`, saves config through `DaemonConnectionConfigRepository`, and returns `ConnectedAppSession`.

- [ ] **Step 3: Run workflow tests**

Run: `cd mobile && flutter test test/daemon_connection_workflow_test.dart`

Expected: all workflow tests pass.

## Task 4: Move UI State to ViewModel

**Files:**
- Create: `mobile/lib/src/ui/features/connection/view_models/daemon_connection_view_model.dart`
- Modify: `mobile/lib/src/state/daemon_connection_controller.dart`
- Test: `mobile/test/daemon_connection_controller_test.dart`

- [ ] **Step 1: Port controller behavior into ViewModel**

Move existing fields, getters, input setters, timeout handling, stale attempt protection, and error summary mapping into `DaemonConnectionViewModel`. Keep getter names compatible: `status`, `addressInput`, `proxyMode`, `manualProxyInput`, `inputError`, `errorSummary`, `errorDetail`, `snapshot`, `client`, `connectedConfig`, `connectionTimeout`, `isBusy`, and `statusLabel`.

- [ ] **Step 2: Make controller a compatibility subclass**

Keep `DaemonConnectionController` available by extending `DaemonConnectionViewModel` and forwarding existing constructor parameters into the new repository/workflow dependencies.

- [ ] **Step 3: Run controller tests**

Run: `cd mobile && flutter test test/daemon_connection_controller_test.dart`

Expected: existing tests pass with no behavior changes.

## Task 5: Add Connection Gate View

**Files:**
- Create: `mobile/lib/src/ui/features/connection/views/mobile_connection_gate.dart`
- Modify: `mobile/lib/src/ui/mobile_ui.dart`
- Test: `mobile/test/widget_test.dart`

- [ ] **Step 1: Extract gate widget**

Move `MobileUi` branching into `MobileConnectionGate`. It listens to `DaemonConnectionViewModel`, shows `MobileLoadingPage` while loading config, shows `MainTabsPage` when connected, and otherwise shows `MobileConnectionPage`.

- [ ] **Step 2: Keep `MobileUi` as composition root**

`MobileUi` manually constructs `DaemonConnectionConfigRepository`, `MemoryTokenStore`, `DaemonConnectionWorkflow`, and `DaemonConnectionViewModel` when no controller is injected. No DI package is added.

- [ ] **Step 3: Run widget tests**

Run: `cd mobile && flutter test test/widget_test.dart`

Expected: widget tests pass or only require import updates for the compatibility surface.

## Task 6: Full Verification

**Files:**
- Modify only if verification exposes migration regressions.

- [ ] **Step 1: Run focused connection tests**

Run: `cd mobile && flutter test test/daemon_connection_controller_test.dart test/daemon_connection_workflow_test.dart test/app_snapshot_bootstrap_test.dart`

Expected: all focused tests pass.

- [ ] **Step 2: Run static analysis**

Run: `cd mobile && flutter analyze`

Expected: no new analysis errors.

- [ ] **Step 3: Run full mobile tests**

Run: `cd mobile && flutter test`

Expected: all tests pass.

## Self-Review

- Spec coverage: plan covers repository persistence, workflow application layer, `DaemonInitialData`, stale attempt ownership, initial config loading, constructor injection, compatibility exports, and focused verification.
- Placeholder scan: no task uses deferred placeholders; implementation names and file paths are explicit.
- Type consistency: later tasks use `DaemonConnectionViewModel`, `DaemonConnectionWorkflow`, `DaemonInitialData`, and `ConnectedAppSession` consistently.
