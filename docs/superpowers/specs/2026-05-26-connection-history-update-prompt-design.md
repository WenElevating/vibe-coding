# Connection History and Update Prompt Design

Date: 2026-05-26

## Problem

The mobile connection gate has three usability gaps:

- The top-right decorative control on the connection screen looks like an
  action but does not do anything useful.
- Users must manually re-enter daemon addresses they have already connected to.
- Users only discover app updates when they manually visit settings and check.

The goal is to make reconnection faster and make Android app updates visible
without adding background notification complexity or weakening the existing
private LAN update channel.

## Accepted Direction

Build two small enhancements on top of the current Flutter architecture:

1. Replace the unused connection header control with no control.
2. Add address-only recent history to the daemon address input.
3. Add foreground, in-app update prompting after daemon connection and app
   resume.

The user selected these constraints:

- Do not put recent addresses behind the top-right button.
- Show recent addresses from the address input itself.
- Store only addresses, not proxy mode or manual proxy values.
- Selecting a recent address only fills the input. It must not start a
  connection.
- Optional update reminders are in-app prompts, not Android notification bar
  notifications.
- If the user chooses "later", the same version is not proactively prompted
  again during the current app session. Settings can still manually check.

## Non-Goals

This design does not add:

- Connection profiles that bind address, proxy mode, and manual proxy.
- QR pairing or LAN discovery.
- A management screen for editing saved addresses.
- Android background notifications or periodic background update checks.
- A new update delivery protocol.
- Silent install behavior.

## Current Architecture Context

The mobile app already follows a layered shape:

- UI widgets render state and own local interaction details.
- ViewModels expose presentation state and command methods.
- Data/services own persistence and platform or daemon-facing access.
- Workflows coordinate ordered multi-step side effects.
- Domain stays free of Flutter, SharedPreferences, HTTP clients, concrete
  daemon clients, and UI code.

Relevant existing boundaries:

- `MobileConnectionPage` is a standalone gate using its own `Scaffold` and
  `ListView`, not the shared bottom-tab page shell.
- `DaemonConnectionViewModel` owns connection state and input mutation.
- `DaemonConnectionConfigStore` currently persists the last successful address,
  proxy mode, and manual proxy through `SharedPreferences`.
- `MainTabsPage` creates the connected update ViewModel and already forwards
  Android resume lifecycle events for installer recovery.
- `AppUpdateViewModel` owns update check, download, install, recovery, discard,
  and lifecycle-facing commands.
- `AppUpdatePanel` renders the manual settings surface and already shows update
  prompts for available update state.

## Connection History Design

### Storage

Extend the existing connection configuration persistence boundary to store a
small recent-address list.

Suggested storage key:

```text
daemonConnection.recentAddresses
```

Rules:

- Store only successful daemon address input strings.
- Trim whitespace before saving.
- Do not store empty strings.
- Do not store failed connection attempts.
- Deduplicate by exact trimmed address input.
- When an address is used again, move it to the front.
- Keep at most 8 addresses.
- Preserve the existing last successful `DaemonConnectionConfig` behavior.

The first implementation can keep the list in `DaemonConnectionConfigStore`
because that store is already the local persistence adapter for daemon
connection settings. If the app later needs richer connection history, promote
the behavior behind a repository interface before it grows into profile
management.

### ViewModel State

`DaemonConnectionViewModel` should expose immutable recent address state:

```text
recentAddresses: List<String>
```

It should provide a command:

```text
selectRecentAddress(String address)
```

The command updates `addressInput`, clears transient input/connection errors,
and notifies listeners. It must not call `connect()`.

On `load()`, the ViewModel loads both the last successful connection config and
recent addresses. On successful `connect()`, it records the trimmed address in
history after the connection has actually completed and persistence succeeds.

Failed validation, health, or snapshot loading must not write address history.

### UI Interaction

`MobileConnectionPage` owns focus and dropdown visibility because these are
local widget interaction details.

Behavior:

- The address input receives focus.
- If recent addresses exist, show a dropdown directly below the input.
- While the user types, filter recent addresses by case-insensitive substring
  match against the current input.
- If the filter has no matches, hide the dropdown rather than showing an empty
  panel.
- Tapping a row calls `selectRecentAddress(address)`, updates the text field,
  and closes the dropdown.
- Busy connection states disable row taps.
- Proxy mode and manual proxy input are not changed.
- The connection action remains explicit. The user must still tap connect.

The dropdown should feel integrated with the current dark instrument-style gate:

- Same width as the input.
- No nested cards.
- Low-contrast panel background and one-pixel stroke.
- Compact row height suitable for phone screens.
- Monospace address text.
- A simple leading history or link icon is acceptable if it improves scanning.
- No decorative neon, glass blur, or modal sheet for this interaction.

### Header Cleanup

Remove the top-right decorative signal pill from the connection header unless a
real action is introduced later. The header should focus on title and subtitle,
not fake affordances.

If a future feature needs a header action, it should be a standard icon button
with a clear semantic label and a tested command.

## In-App Update Prompt Design

### Trigger Points

The update prompt remains foreground-only and daemon-backed.

Trigger a silent update check when:

- `MainTabsPage` creates a connected `AppUpdateViewModel`.
- The app returns to foreground through `AppLifecycleState.resumed`.

Only do this when:

- The platform is Android, using the same platform gate as installer recovery.
- The update ViewModel exists.
- No active update operation is running.
- The current update status is not downloading, verifying, installing, or
  awaiting Android user confirmation.

The manual settings "check update" action remains available and should not be
blocked by the session-level optional prompt suppression.

### Prompt Suppression

Maintain an in-memory set or single key for optional update versions already
postponed in the current app session.

Suggested key:

```text
versionCode:mandatory
```

Rules:

- If a newer optional update is found and has not been postponed in this app
  session, show the update prompt.
- If the user taps "later", remember that version key until process exit.
- If a higher version appears, prompt again.
- Manual check from settings can still show current update state and actions.
- Mandatory update state is not silently suppressed as an optional reminder.

This is intentionally not persisted across app restarts. A restart is a
reasonable point to remind the user again that a newer internal APK exists.

### Prompt Behavior

When a new update is available:

- Show an in-app dialog using the existing localized update copy and actions.
- Primary action starts the download.
- Secondary action dismisses the prompt for this session.
- Download, verify, install, and Android confirmation remain blocking once the
  user starts the update, matching the current update operation dialog behavior.

The design does not change the existing Android PackageInstaller confirmation
requirement. The app may guide the user into unknown-app install settings when
permission is missing, but Android still owns the final install approval UI.

### Error Handling

Silent update checks must not create disruptive error UI during normal app use.

Rules:

- Manifest check failures from silent triggers should record diagnostics and
  keep the current app usable.
- The settings panel may still show failure state after a manual check.
- If a silent check discovers a recoverable update session, installer recovery
  should keep its existing priority.
- Silent checks must not interrupt active download/install/recovery flows.

## Layering Rules

Implementation must preserve Flutter architecture boundaries:

- UI may own focus nodes, overlay/dropdown visibility, text controller sync, and
  row rendering.
- UI must not read or write `SharedPreferences`.
- UI must not perform daemon update checks directly.
- ViewModels own connection/update presentation state and user commands.
- Local persistence remains in the existing service or repository boundary.
- Domain models remain pure and do not import Flutter.
- `MainTabsPage` may coordinate lifecycle triggers because it already owns the
  connected shell lifecycle, but update decision logic should stay in
  `AppUpdateViewModel`.

No new dependency is needed for these changes.

## Testing Plan

Connection persistence tests:

- Saves a successful address into recent history.
- Moves an existing address to the front.
- Trims whitespace before saving.
- Ignores empty addresses.
- Limits history to 8 entries.
- Does not disturb last successful proxy settings.

Connection ViewModel tests:

- `load()` exposes saved recent addresses.
- Successful connection records the address.
- Failed connection does not record the address.
- Selecting a recent address only updates `addressInput`.
- Selecting a recent address does not call connect.
- Selecting a recent address leaves proxy mode and manual proxy input unchanged.

Connection widget tests:

- Header no longer renders the unused top-right control.
- Focusing the address field shows matching recent addresses.
- Typing filters the recent address dropdown.
- Tapping a recent address fills the input and closes the dropdown.
- Busy connection state disables recent-address selection.

Update ViewModel or shell tests:

- Creating the connected shell triggers one silent update check on Android.
- Resuming the app triggers a silent update check on Android.
- Silent check is skipped during downloading, verifying, installing, or awaiting
  Android confirmation.
- Optional update prompt appears for a newer version.
- Choosing "later" suppresses the same version for the current app session.
- A higher version can prompt again in the same session.
- Manual settings check still works after "later".
- Mandatory update state is not treated as a suppressed optional prompt.

Architecture verification:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
dart run tool\check_architecture_imports.dart
dart analyze lib test
flutter test --no-pub test\daemon_connection_config_store_test.dart test\daemon_connection_controller_test.dart test\widget_test.dart test\app_update_view_model_test.dart test\app_update_panel_test.dart -r expanded
```

If Flutter or Dart commands time out in this environment, stop retrying
automatically and report the exact command for manual execution.

## Open Risks

- A dropdown inside a small phone viewport can crowd the proxy section. Keep row
  height compact and hide the dropdown when there are no matches.
- Exact-string deduplication means `192.168.1.10` and
  `http://192.168.1.10:4317` can both appear even if they normalize to the same
  daemon. This is acceptable for address-only history because users asked to
  save the input address, not a full normalized profile.
- Silent update checks rely on the currently connected daemon. If the daemon is
  offline or stale, the app cannot discover newer APKs until a working daemon is
  connected.
- Optional update prompt suppression is session-only by design. Users may see
  the same optional version again after restarting the app.

## Implementation Phases

1. Extend connection config persistence with recent address history and tests.
2. Expose recent addresses and selection command through the connection
   ViewModel.
3. Update the connection page header and address input dropdown.
4. Add foreground silent update check orchestration and prompt suppression.
5. Add widget/ViewModel tests for the agreed behaviors.
6. Run architecture, analysis, and focused Flutter tests.
