# Mobile Conversation Background Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move live conversation event syncing out of the conversation page so active sessions keep syncing across foreground route changes, with explicit background policy seams and an Android foreground-service anchor.

**Architecture:** Add a workflow-level `ConversationSyncCoordinator` that owns one repository watcher per tracked conversation and hands the UI disposable leases for foreground rendering. Keep cache writes inside `CachedConversationRepository`; the coordinator only controls watcher lifetime, event fan-out, approval event publication, and lifecycle policy.

**Tech Stack:** Flutter/Dart, existing repository interfaces, `MobileAppEventBus`, existing widget/unit tests.

**Current status (2026-06-12):**

- Foreground route-independent sync is implemented in commit `9239dcb`.
- Android background continuation is implemented as a native foreground-service
  process/notification anchor while Dart remains the transport/auth owner.
- Dart degraded-resume backfill is implemented for foreground returns after
  app-background non-keepalive sync stops. Native iOS cleanup is not implemented
  because this repository currently has no `mobile/ios` target.

---

### Task 1: Coordinator Core

**Files:**
- Create: `mobile/lib/src/workflows/conversation_sync/conversation_sync_policy.dart`
- Create: `mobile/lib/src/workflows/conversation_sync/conversation_sync_coordinator.dart`
- Test: `mobile/test/conversation_sync_coordinator_test.dart`

- [x] **Step 1: Write failing coordinator tests**

Cover these behaviors:

```dart
test('detaching foreground lease keeps watcher alive while app is foreground', () async {});
test('background grace cancels watcher when keep-live setting is disabled', () async {});
test('approval events are published without a foreground lease', () async {});
```

- [x] **Step 2: Run RED**

Run: `cd mobile && flutter test --no-pub test\conversation_sync_coordinator_test.dart`
Expected: FAIL because the coordinator does not exist yet.

- [x] **Step 3: Implement minimal coordinator**

Implement:
- policy defaults: `terminalGrace = 45s`, `backgroundDisconnectGrace = 30s`, `consumerLagQueueLimit = 256`;
- `ConversationSyncLease` with idempotent `dispose()`;
- one underlying watcher per conversation;
- `trackConversation(...)`, `attachForegroundConsumer(...)`, `setAppForeground(...)`, and `dispose()`;
- per-lease single-subscription stream controllers;
- approval request/resolution publication via `MobileAppEventBus`.

- [x] **Step 4: Run GREEN**

Run: `cd mobile && flutter test --no-pub test\conversation_sync_coordinator_test.dart`
Expected: PASS.

### Task 2: Workbench Wiring

**Files:**
- Modify: `mobile/lib/src/ui/features/workbench/workbench_dependencies.dart`
- Modify: `mobile/lib/src/app/app_dependencies.dart`
- Modify: `mobile/lib/src/ui/main/main_page.dart`
- Modify: `mobile/lib/src/ui/features/workbench/coding_workbench_page.dart`
- Test: `mobile/test/widget_test.dart`

- [x] **Step 1: Write failing widget test**

Add a regression proving that returning to the session list while foregrounded does not cancel the active conversation watcher, and that a streamed event updates the repository-backed session list state.

- [x] **Step 2: Run RED**

Run: `cd mobile && flutter test --no-pub test\widget_test.dart --plain-name "foreground route changes keep conversation event sync alive"`
Expected: FAIL because `_goToWorkspaces()` / `_goToSessions()` currently cancel the page-owned watcher.

- [x] **Step 3: Wire coordinator into workbench**

Create one coordinator per connected session in `FeatureDependencies.createWorkbenchDependencies`, pass it through `WorkbenchDependencies`, and dispose it from `MainPage` with other workbench-scoped dependencies.

- [x] **Step 4: Replace page-owned watcher**

Change `CodingWorkbenchPage` to:
- call `trackConversation` when opening/sending an active conversation;
- attach a foreground lease for detail rendering;
- detach the lease on route reset without stopping the underlying watcher;
- use lifecycle background transitions to call coordinator background policy;
- keep existing initial page load and reducer application behavior.

- [x] **Step 5: Run GREEN**

Run: `cd mobile && flutter test --no-pub test\widget_test.dart --plain-name "foreground route changes keep conversation event sync alive"`
Expected: PASS.

### Task 3: Verification And Documentation

**Files:**
- Modify if needed: `docs/project-knowledge/decisions/`

- [x] **Step 1: Run architecture and focused tests**

Run:

```powershell
cd mobile
dart run tool\check_architecture_imports.dart
flutter test --no-pub test\conversation_sync_coordinator_test.dart
flutter test --no-pub test\widget_test.dart --plain-name "workbench lifecycle"
```

- [x] **Step 2: Decide whether project knowledge changed**

If the coordinator is committed as a durable ownership decision, add one concise project-knowledge decision entry pointing to the approved spec and tests.

- [x] **Step 3: Commit with Lore trailers**

Commit only after verification. Include honest `Tested:` and `Not-tested:` trailers; do not claim Android/iOS native background execution unless native bridge work and verification are present.

### Task 4: Android Foreground-Service Anchor

**Files:**
- Create: `mobile/lib/src/services/background_conversation_sync_bridge.dart`
- Create: `mobile/lib/src/services/method_channel_background_conversation_sync_bridge.dart`
- Create: `mobile/lib/src/services/noop_background_conversation_sync_bridge.dart`
- Create: `mobile/android/app/src/main/kotlin/com/example/lan_ai_cli_control/BackgroundConversationSyncChannels.kt`
- Create: `mobile/android/app/src/main/kotlin/com/example/lan_ai_cli_control/BackgroundConversationSyncService.kt`
- Modify: `mobile/lib/src/workflows/conversation_sync/conversation_sync_coordinator.dart`
- Modify: `mobile/lib/src/app/app_dependencies.dart`
- Modify: `mobile/lib/src/ui/features/workbench/workbench_dependencies.dart`
- Modify: `mobile/android/app/src/main/AndroidManifest.xml`
- Modify: `mobile/android/app/src/main/kotlin/com/example/lan_ai_cli_control/MainActivity.kt`
- Test: `mobile/test/background_conversation_sync_bridge_test.dart`
- Test: `mobile/test/conversation_sync_coordinator_test.dart`
- Test: `mobile/test/app_dependencies_test.dart`

- [x] **Step 1: Add Dart platform bridge contract**

Model background sync status snapshots, start requests, unsupported fallback,
and MethodChannel/EventChannel parsing without making native code own auth,
WebSocket, or cursor semantics.

- [x] **Step 2: Hook coordinator background policy to the bridge**

When the app backgrounds with keep-alive enabled and active tracked
conversations remain, start the platform anchor. If native reports denied,
failed, stopped, or errors, fall back to normal background disconnect grace.

- [x] **Step 3: Add Android native foreground service**

Register a `dataSync` foreground service, create the notification channel,
publish service snapshots to Dart, add a notification content intent to reopen
the app, and add a stop action that stops the background anchor.

- [x] **Step 4: Wire defaults through app dependencies**

Use `MethodChannelBackgroundConversationSyncBridge` on Android and
`UnsupportedBackgroundConversationSyncBridge` elsewhere.

- [x] **Step 5: Verify and commit**

Run the feasible Dart/Flutter and repository checks, then commit with Lore
trailers that distinguish Android anchor support from unfinished iOS native
degraded-resume work.

### Task 5: iOS Degraded-Resume Cleanup

- [x] **Step 1: Add Dart degraded-resume backfill**

When app-background sync stops because keep-alive is disabled or the native
anchor falls back, foreground resume stops any stale watcher, fetches daemon
events after the tracked cursor, applies cached conversation status projection,
and restarts the watcher from the advanced cursor.

- [ ] **Step 2: Add native iOS `beginBackgroundTask` cleanup bridge**

Blocked by repository shape: `mobile/` has Android, web, and Windows targets,
but no `mobile/ios` Runner/AppDelegate target to host an iOS native bridge.
Do not claim native iOS background cleanup until an iOS target exists and the
bridge is implemented and verified on-device.
