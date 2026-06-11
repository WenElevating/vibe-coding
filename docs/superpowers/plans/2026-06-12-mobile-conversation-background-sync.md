# Mobile Conversation Background Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move live conversation event syncing out of the conversation page so active sessions keep syncing across foreground route changes, with explicit background policy seams.

**Architecture:** Add a workflow-level `ConversationSyncCoordinator` that owns one repository watcher per tracked conversation and hands the UI disposable leases for foreground rendering. Keep cache writes inside `CachedConversationRepository`; the coordinator only controls watcher lifetime, event fan-out, approval event publication, and lifecycle policy.

**Tech Stack:** Flutter/Dart, existing repository interfaces, `MobileAppEventBus`, existing widget/unit tests.

---

### Task 1: Coordinator Core

**Files:**
- Create: `mobile/lib/src/workflows/conversation_sync/conversation_sync_policy.dart`
- Create: `mobile/lib/src/workflows/conversation_sync/conversation_sync_coordinator.dart`
- Test: `mobile/test/conversation_sync_coordinator_test.dart`

- [ ] **Step 1: Write failing coordinator tests**

Cover these behaviors:

```dart
test('detaching foreground lease keeps watcher alive while app is foreground', () async {});
test('background grace cancels watcher when keep-live setting is disabled', () async {});
test('approval events are published without a foreground lease', () async {});
```

- [ ] **Step 2: Run RED**

Run: `cd mobile && flutter test --no-pub test\conversation_sync_coordinator_test.dart`
Expected: FAIL because the coordinator does not exist yet.

- [ ] **Step 3: Implement minimal coordinator**

Implement:
- policy defaults: `terminalGrace = 45s`, `backgroundDisconnectGrace = 30s`, `consumerLagQueueLimit = 256`;
- `ConversationSyncLease` with idempotent `dispose()`;
- one underlying watcher per conversation;
- `trackConversation(...)`, `attachForegroundConsumer(...)`, `setAppForeground(...)`, and `dispose()`;
- per-lease single-subscription stream controllers;
- approval request/resolution publication via `MobileAppEventBus`.

- [ ] **Step 4: Run GREEN**

Run: `cd mobile && flutter test --no-pub test\conversation_sync_coordinator_test.dart`
Expected: PASS.

### Task 2: Workbench Wiring

**Files:**
- Modify: `mobile/lib/src/ui/features/workbench/workbench_dependencies.dart`
- Modify: `mobile/lib/src/app/app_dependencies.dart`
- Modify: `mobile/lib/src/ui/main/main_page.dart`
- Modify: `mobile/lib/src/ui/features/workbench/coding_workbench_page.dart`
- Test: `mobile/test/widget_test.dart`

- [ ] **Step 1: Write failing widget test**

Add a regression proving that returning to the session list while foregrounded does not cancel the active conversation watcher, and that a streamed event updates the repository-backed session list state.

- [ ] **Step 2: Run RED**

Run: `cd mobile && flutter test --no-pub test\widget_test.dart --plain-name "foreground route changes keep conversation event sync alive"`
Expected: FAIL because `_goToWorkspaces()` / `_goToSessions()` currently cancel the page-owned watcher.

- [ ] **Step 3: Wire coordinator into workbench**

Create one coordinator per connected session in `FeatureDependencies.createWorkbenchDependencies`, pass it through `WorkbenchDependencies`, and dispose it from `MainPage` with other workbench-scoped dependencies.

- [ ] **Step 4: Replace page-owned watcher**

Change `CodingWorkbenchPage` to:
- call `trackConversation` when opening/sending an active conversation;
- attach a foreground lease for detail rendering;
- detach the lease on route reset without stopping the underlying watcher;
- use lifecycle background transitions to call coordinator background policy;
- keep existing initial page load and reducer application behavior.

- [ ] **Step 5: Run GREEN**

Run: `cd mobile && flutter test --no-pub test\widget_test.dart --plain-name "foreground route changes keep conversation event sync alive"`
Expected: PASS.

### Task 3: Verification And Documentation

**Files:**
- Modify if needed: `docs/project-knowledge/decisions/`

- [ ] **Step 1: Run architecture and focused tests**

Run:

```powershell
cd mobile
dart run tool\check_architecture_imports.dart
flutter test --no-pub test\conversation_sync_coordinator_test.dart
flutter test --no-pub test\widget_test.dart --plain-name "workbench lifecycle"
```

- [ ] **Step 2: Decide whether project knowledge changed**

If the coordinator is committed as a durable ownership decision, add one concise project-knowledge decision entry pointing to the approved spec and tests.

- [ ] **Step 3: Commit with Lore trailers**

Commit only after verification. Include honest `Tested:` and `Not-tested:` trailers; do not claim Android/iOS native background execution unless native bridge work and verification are present.
