# Coding CLI Preload Gate Design

## Problem

Mobile connection currently stays fast by loading a lightweight bootstrap snapshot. CLI adapter capability detection is deferred until the user opens the Coding tab. That avoids blocking connection, but it makes the first Coding visit awkward: history and new-session UI can render before real CLI readiness is known.

## Goals

- Keep daemon connection and the home screen fast.
- Start CLI adapter capability loading immediately after connection succeeds.
- When the user enters Coding before loading completes, show an explicit loading state instead of empty or disabled history UI.
- Render Coding history and new-session controls only after adapter capabilities are loaded or a clear retryable error exists.
- Avoid duplicate adapter probes when preload and Coding entry overlap.

## Non-Goals

- Do not block initial connection on CLI detection.
- Do not add a new backend API if the existing `/api/adapters` endpoint is sufficient.
- Do not change run creation, conversation persistence, or adapter launch behavior.
- Do not introduce new dependencies.

## Current Flow

`DaemonConnectionController.connect()` loads `AppSnapshot.loadBootstrap()`, which intentionally leaves `adapters` empty. `MainTabsPage` then calls `_ensureCodingAdaptersLoaded()` only when tab index `2` is selected. That method calls `DaemonClient.listAdapters()`, updates the snapshot, and marks adapters loaded.

## Proposed Flow

After `MainTabsPage` receives a connected snapshot, it starts `_ensureCodingAdaptersLoaded()` from `initState()` as a background preload. The home tab remains usable immediately.

When the user selects the Coding tab, `MainTabsPage` still calls `_ensureCodingAdaptersLoaded()`. If the background preload is already running, the call reuses the same in-flight future. While adapter loading is incomplete, the Coding tab shows a loading gate such as “Loading CLI…”. It does not show the session list, history empty state, adapter selector, or New Session controls yet.

When adapter loading succeeds, `MainTabsPage` replaces the snapshot with one containing real adapters and renders the normal Coding page. When adapter loading fails, the Coding tab shows an error gate with a retry action. Retrying calls the same loader and, on success, renders the Coding page.

## State Model

`MainTabsPage` should track adapter loading with explicit state instead of two booleans:

- `idle`: not requested yet.
- `loading`: request in flight.
- `loaded`: adapter list is available in `_data.adapters`.
- `failed`: the last load failed and can be retried.

The implementation may keep the existing booleans if the resulting UI behavior remains clear, but an enum makes the gate easier to test and less ambiguous.

## Backend Behavior

`AdapterRegistry.listCapabilities()` should use a single in-flight promise so concurrent `/api/adapters` requests share one probe. This prevents a connection-time preload and a Coding-tab entry from launching duplicate CLI version/help probes. A short cache is optional; single-flight is enough for this feature.

## Error Handling

- Background preload failure should not move the user off the home tab.
- Coding tab should show a retryable error only when the user enters Coding and adapters are still unavailable.
- Retry should clear the error, show the loading gate, and call `/api/adapters` again.

## Testing

- Widget test: connection renders home immediately, then triggers adapter preload without entering Coding.
- Widget test: entering Coding while adapter preload is pending shows the CLI loading gate and hides history/new-session UI.
- Widget test: adapter preload success updates Coding to the normal page.
- Widget test: adapter preload failure shows a retry gate in Coding and retry succeeds.
- Daemon test: concurrent `listCapabilities()` calls share one adapter detection pass.

## Self-Review

- No TBD or placeholder requirements remain.
- Scope is limited to adapter capability preload/gating and duplicate probe prevention.
- The design keeps initial connection non-blocking while making Coding entry wait for real CLI readiness.
- Backend single-flight is included because it protects the new overlapping request path without adding an API.
