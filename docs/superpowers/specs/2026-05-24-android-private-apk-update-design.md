# Android Private APK Update Design

Date: 2026-05-24

## Problem

The Android build currently produces an APK that must be manually copied,
installed, and replaced on each device. That is acceptable during early local
testing, but it becomes slow and error-prone for internal/team use.

The goal is an internal online update path:

```text
mobile app -> connected LAN daemon -> update manifest -> APK download -> Android installer
```

The app should not require users to manually find or transfer APK files. It may
use Android's system installation confirmation UI.

## Current Project Context

The Flutter app currently has:

```text
mobile/pubspec.yaml version: 1.3.0+1
android applicationId: com.example.lan_ai_cli_control
release signingConfig: debug
```

The existing architecture separates daemon-owned HTTP/API behavior from mobile
UI/data/domain layers. The update feature should follow that shape:

- `daemon/` hosts update metadata and APK downloads.
- `mobile/lib/src/services/` owns platform/update infrastructure.
- `mobile/lib/src/data/` adapts update API responses into app-facing models.
- `mobile/lib/src/ui/` shows update state and user actions.

Before this feature is used as a real distribution channel, release signing
must move from the debug key to a stable private release keystore. Android will
not install an update over an existing app unless package name and signing
identity are compatible and `versionCode` increases.

## Platform Constraints

This is not a silent installer design.

For normal Android apps distributed outside Google Play, the app can download
an APK and invoke the Android package installer. The user still sees system UI
and confirms installation. True silent installation requires special device
owner, enterprise management, or privileged installer conditions and is out of
scope.

Google Play In-App Updates are also out of scope for this design because the
chosen distribution model is internal/LAN hosting rather than Play delivery.

Shorebird or other Flutter code-push systems can be evaluated later for Dart/UI
patches, but they do not replace APK updates for native plugins, Android
manifest changes, permissions, signing, package identity, or Flutter engine
changes.

The Android build should keep `targetSdkVersion` at a modern supported value.
Android 14 blocks installation of apps targeting very old SDK levels, and newer
target SDKs also control how install-permission prompts and package visibility
behave. The project currently uses Flutter's generated SDK values in Gradle; the
update implementation should verify the resolved `minSdkVersion` and
`targetSdkVersion` as part of the first device test instead of assuming the
template defaults.

Useful platform references:

- Android In-App Updates:
  `https://developer.android.com/guide/playcore/in-app-updates`
- Android PackageInstaller:
  `https://developer.android.com/reference/android/content/pm/PackageInstaller`
- Android PackageInstaller Session:
  `https://developer.android.com/reference/android/content/pm/PackageInstaller.Session`
- Android install-package permission:
  `https://developer.android.com/reference/android/Manifest.permission#REQUEST_INSTALL_PACKAGES`
- Android 14 install restrictions for old target SDK apps:
  `https://developer.android.com/about/versions/14/behavior-changes-all`
- APK signing schemes:
  `https://source.android.com/docs/security/features/apksigning`
- Shorebird code push:
  `https://docs.shorebird.dev/code-push/`

## Accepted Direction

Build a daemon-hosted Android APK update channel with resumable downloads.

The daemon exposes:

```text
GET  /api/app-updates/android/latest
HEAD /api/app-updates/android/apk/:versionCode
GET  /api/app-updates/android/apk/:versionCode
```

The mobile app:

1. Checks the latest update manifest after it is connected to a daemon.
2. Compares remote `versionCode` with the installed app `versionCode`.
3. Shows an update prompt only when a newer APK is available.
4. Downloads the APK with pause/resume support.
5. Verifies `sizeBytes` and `sha256`.
6. Invokes Android's system installer through a native bridge.
7. Keeps the current app usable if download, verification, or installation is
   cancelled or fails.

The installer bridge uses Android `PackageInstaller.Session`, not
`ACTION_INSTALL_PACKAGE`. Intent-only installation cannot reliably report
whether the user installed, cancelled, or hit a package parse/signature failure,
and `ACTION_INSTALL_PACKAGE` is deprecated. Session-based installation gives the
native layer a status callback that can be forwarded back to Dart.

## Non-Goals

The first version does not need:

- Google Play, Play Core, or store-managed updates.
- Silent installation.
- Background downloads that survive all Android process kills.
- Multiple concurrent APK downloads.
- Delta patches or binary diff updates.
- Shorebird integration.
- Remote rollback after installation.
- Automatic daemon update.
- Updating desktop/mobile platforms other than Android.

## Update Manifest

The daemon returns a stable JSON manifest:

```json
{
  "schemaVersion": 1,
  "platform": "android",
  "packageName": "com.example.lan_ai_cli_control",
  "versionName": "1.4.0",
  "versionCode": 2,
  "minSupportedVersionCode": 1,
  "mandatory": false,
  "apkUrl": "/api/app-updates/android/apk/2",
  "sha256": "4b7f...",
  "sizeBytes": 48214531,
  "etag": "\"android-apk-2-4b7f\"",
  "releaseNotes": "Fixes notification recovery and improves update UX.",
  "publishedAt": "2026-05-24T08:30:00.000Z"
}
```

Rules:

- `schemaVersion` is the manifest contract version. Clients accept only schema
  versions they explicitly implement. Unknown values must be rejected even if
  the rest of the manifest parses.
- Version `1` clients must ignore unknown fields within `schemaVersion: 1`.
  Breaking schema changes require the daemon to serve the new schema only to
  clients that advertise support, for example through an `Accept` header or
  explicit version negotiation, while continuing to serve `schemaVersion: 1` to
  legacy clients.
- `versionCode` is the compatibility and ordering boundary.
- `versionName` is display text only.
- `sha256` is computed over the exact APK bytes served by `apkUrl`.
- `sizeBytes` must match the exact APK byte length.
- `etag` must change whenever the APK bytes change.
- `mandatory` is true when the daemon wants the update to block normal use.
- `minSupportedVersionCode` is stricter than `mandatory`: if the installed
  `versionCode` is lower than `minSupportedVersionCode`, mobile must treat the
  update as mandatory even when `mandatory` is false.
- Mandatory updates still do not bypass Android's installer confirmation UI.
- `apkUrl` may be relative to the daemon base URL so private LAN deployments do
  not need a public hostname. Clients must resolve it against the connected
  daemon base URL. Absolute URLs are accepted only when their scheme and
  authority match the connected daemon base; cross-origin URLs are rejected.

If no update is available, the daemon can either return the latest manifest and
let mobile compare versions, or return:

```json
{
  "schemaVersion": 1,
  "platform": "android",
  "available": false
}
```

The first implementation should prefer returning the latest manifest because it
is simpler to cache and diagnose.

Mandatory example:

```json
{
  "schemaVersion": 1,
  "platform": "android",
  "packageName": "com.example.lan_ai_cli_control",
  "versionName": "1.7.0",
  "versionCode": 5,
  "minSupportedVersionCode": 4,
  "mandatory": false,
  "apkUrl": "/api/app-updates/android/apk/5",
  "sha256": "9aa3...",
  "sizeBytes": 49300210,
  "etag": "\"android-apk-5-9aa3\"",
  "releaseNotes": "Protocol compatibility update.",
  "publishedAt": "2026-05-24T10:00:00.000Z"
}
```

A client installed at `versionCode: 3` must treat this as mandatory because it
is lower than `minSupportedVersionCode: 4`. A client installed at
`versionCode: 4` treats it as optional because `mandatory` is false.

## Daemon Design

Add a small update service around a configured artifact directory:

```text
daemon/update-artifacts/android/latest.json
daemon/update-artifacts/android/lan_ai_cli_control-1.4.0+2.apk
```

The daemon should not scan arbitrary directories at request time. It should load
or validate a manifest at startup, then serve only files referenced by that
manifest.

Suggested daemon responsibilities:

- Read update configuration from daemon config or environment.
- Validate manifest fields on startup.
- Verify that the configured APK exists.
- Verify APK byte length on startup.
- Load a sidecar digest file such as `lan_ai_cli_control-1.4.0+2.apk.sha256`
  or trust the digest embedded in `latest.json` only after the release script
  has generated it.
- Run full APK sha256 validation either in the release script, on first request,
  or in a low-priority background startup task. The daemon should avoid blocking
  every restart on hashing large APK files.
- Serve `latest` metadata to authenticated devices with `ETag` and
  `If-None-Match` support. Return `304 Not Modified` when the manifest has not
  changed.
- Serve APK bytes with `HEAD`, full `GET`, and single-range `GET` support only
  for the `versionCode` currently referenced by `latest.json`. If the daemon
  retains older APK files, those files become active only after an operator
  changes the manifest back to that version. Requests for retained but
  non-latest `versionCode` values return `404`.
- Set `Content-Length`, `Content-Type: application/vnd.android.package-archive`,
  `ETag`, and `Accept-Ranges: bytes`.
- Return `206 Partial Content` for valid `Range` requests.
- Return `416 Range Not Satisfiable` for invalid resume offsets.
- Honor `If-Range` with the manifest `ETag`: return `206` only when the local
  partial is still for the same APK bytes, otherwise return `200` with the full
  file.

The daemon does not need multi-range support.

Keep the latest manifest pointed at one version, but retain the last three APK
artifacts by default. This makes quick rollback and staged manual recovery
possible without changing the mobile protocol. The daemon should still serve
only configured artifact files and never arbitrary paths from the artifact
directory.

Authentication should match the existing daemon API boundary. An authenticated
mobile device that can connect to the daemon can check and download app updates.
If future deployments need stricter policy, add an `appUpdate` permission at the
daemon authorization layer instead of making update endpoints public.

APK download authentication must work for streaming responses and `Range`
requests without buffering the APK in memory. Token refresh belongs in the
shared daemon HTTP client interceptor layer, not in the downloader. The HTTP
layer should handle `401` by refreshing or re-authenticating through the
existing daemon session flow and replaying the request with the new bearer
token. If refresh fails, the downloader receives a terminal auth error while
keeping any `.part` file for a later retry.

## Mobile Architecture

Add update infrastructure without putting network or installer logic in widgets.

Suggested files:

```text
mobile/lib/src/services/app_update_client.dart
mobile/lib/src/services/android_package_installer.dart
mobile/lib/src/data/models/app_update_manifest.dart
mobile/lib/src/data/repositories/daemon_app_update_repository.dart
mobile/lib/src/domain/repositories/app_update_repository.dart
mobile/lib/src/ui/features/settings/view_models/app_update_view_model.dart
mobile/lib/src/ui/features/settings/widgets/app_update_panel.dart
```

The exact file names can follow nearby settings and connection patterns when
implementation starts. The responsibilities should stay separated:

- API client: fetch manifest, `HEAD` APK, stream APK bytes.
- Repository: compare manifest with installed package info and expose update
  availability.
- Download manager/service: own `.part` file, metadata, progress, resume,
  verify, and cleanup.
- Android installer bridge: check install permission, open unknown-source
  settings if needed, commit the verified APK through a
  `PackageInstaller.Session`, and forward session status events to Dart.
- ViewModel: expose immutable UI state and commands.
- UI: render status, progress, release notes, and buttons.

The app needs a reliable way to read current `versionName` and `versionCode`.
Use an established package such as `package_info_plus`, or expose the values
through a tiny platform bridge if the project wants to avoid another dependency.
The recommended first implementation is `package_info_plus` because version
inspection is not product-specific logic.

## Android Native Integration

Manifest additions:

```xml
<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />
```

Add a `FileProvider` entry for the downloaded APK cache directory:

```xml
<provider
    android:name="androidx.core.content.FileProvider"
    android:authorities="${applicationId}.fileprovider"
    android:exported="false"
    android:grantUriPermissions="true">
    <meta-data
        android:name="android.support.FILE_PROVIDER_PATHS"
        android:resource="@xml/file_paths" />
</provider>
```

`mobile/android/app/src/main/res/xml/file_paths.xml` should match the cache
path used by the downloader:

```xml
<?xml version="1.0" encoding="utf-8"?>
<paths xmlns:android="http://schemas.android.com/apk/res/android">
    <cache-path
        name="app_updates"
        path="app_updates/" />
</paths>
```

The native installer bridge should expose:

```text
canRequestPackageInstalls() -> bool
openInstallPermissionSettings() -> void
installApk(filePath) -> void
installEvents() -> stream
```

`installApk` should create a `PackageInstaller.Session`, stream the verified APK
into the session, and commit with an `IntentSender` callback. The callback
receiver reports status through an `EventChannel` or equivalent stream back to
Dart.

The bridge should map native statuses into Dart events:

```text
pendingUserAction
success
cancelled
failed
```

When PackageInstaller returns `STATUS_PENDING_USER_ACTION`, the native layer
launches the confirmation intent supplied by Android. When it returns a failure,
the bridge should preserve the platform status code and message for diagnostics.

The bridge must persist the `PackageInstaller` `sessionId` after
`createSession()` returns and before `session.commit()` is called. If Android
kills the app while the user is in the system confirmation UI, Dart may not
receive the callback. On next launch, the bridge should call
`PackageInstaller.getSessionInfo(sessionId)` and reconcile the persisted
installing state into `installSucceeded`, `installFailed`, `installCancelled`,
or `readyToInstall` when the session no longer exists but the installed
`versionCode` has not changed. Runtime receivers registered for the callback
must be explicitly non-exported on modern Android versions, for example with
`Context.RECEIVER_NOT_EXPORTED` when using dynamic registration.

`FileProvider` remains useful for diagnostic fallback or explicit APK sharing,
but the primary install path is the PackageInstaller session. The app must not
expose raw `file://` paths.

If Android reports that this app cannot request package installs, the UI moves
to `installPermissionNeeded` and asks the user to open the system settings page.
After the user returns, the app re-checks the permission and lets them continue.

## Resumable Download Design

Downloads write to app-private cache storage under the same root exposed by
`file_paths.xml`:

```text
<cacheDir>/app_updates/app-update-<versionCode>.apk.part
<cacheDir>/app_updates/app-update-<versionCode>.json
<cacheDir>/app_updates/app-update-<versionCode>.apk
```

The `app_updates/` subdirectory name must stay aligned with the
`<cache-path name="app_updates" path="app_updates/" />` FileProvider
configuration. A mismatch causes Android to reject the URI because no configured
root contains the APK path.

Files in `<cacheDir>/app_updates/` may be removed by Android under storage
pressure without notice. The app treats missing partial, final, or metadata
files as equivalent to no download in progress and starts the flow again if the
user re-triggers an update. Files-dir is intentionally not used so stale APKs do
not permanently count against app data storage.

Before starting or resuming a download, the app should preflight available
storage for at least the remaining APK bytes plus a small safety margin. On
Android versions where `StorageManager.getAllocatableBytes()` is available, use
that through the platform bridge; otherwise fall back to the best available free
space API and handle write failures as authoritative. Insufficient storage fails
before download with a message asking the user to free space.

The metadata file stores:

```json
{
  "versionCode": 2,
  "versionName": "1.4.0",
  "apkUrl": "/api/app-updates/android/apk/2",
  "sha256": "4b7f...",
  "sizeBytes": 48214531,
  "etag": "\"android-apk-2-4b7f\"",
  "downloadedBytes": 16777216,
  "updatedAt": "2026-05-24T08:45:00.000Z"
}
```

Resume rules:

Auth failures are mostly hidden from the downloader. `401` responses are
absorbed by the shared HTTP client interceptor: successful refresh replays the
request transparently, and the downloader sees the eventual `200` or `206`
outcome. The rules below cover outcomes visible to the downloader.

1. If `.part` and metadata match the current manifest, resume from the current
   `.part` byte length.
2. If `versionCode`, `apkUrl`, `sha256`, `sizeBytes`, or `etag` differs, delete
   the partial file and start over.
3. Send `Range: bytes=<localLength>-` and `If-Range: <etag>` when resuming.
4. If the daemon returns `206 Partial Content`, append to the partial file.
5. If the daemon returns `200 OK` to a resume request, truncate and restart from
   byte zero because the ETag no longer matches or the server declined resume.
6. If the daemon returns `416`, delete the partial file and restart from byte
   zero.
7. If the shared HTTP client surfaces a terminal auth failure, keep `.part` and
   move to a paused or failed state that can be retried after reconnecting or
   logging in.
8. When byte count reaches `sizeBytes`, rename `.part` to `.apk` only after
   successful sha256 verification.
9. If sha256 verification fails, delete the APK and partial metadata.

Only one update download runs at a time. Pressing pause cancels the active HTTP
request but keeps the `.part` file and metadata. Pressing resume starts another
download command against the same manifest.

Hashing must not block the Flutter UI isolate. Prefer computing sha256
incrementally while bytes stream into the file, using the `crypto` package's
chunked conversion APIs. If implementation simplicity wins, run final-file
verification in `Isolate.run` or an equivalent worker isolate. Do not synchronously
hash a large APK on the main isolate.

The first version should not promise long-running background downloads. If the
process survives in the background, the download may continue; if Android kills
the app, the next launch resumes from the partial file.

## UI State Model

Expose a small state machine:

```text
idle
checking
upToDate
available
downloading
paused
verifying
readyToInstall
installPermissionNeeded
installing
installSucceeded
installCancelled
installFailed
cancelled
failed
```

Useful fields:

```text
currentVersionName
currentVersionCode
remoteVersionName
remoteVersionCode
releaseNotes
mandatory
downloadedBytes
sizeBytes
bytesPerSecond
errorMessage
```

Recommended UI behavior:

- Check once after daemon connection is established.
- Provide a manual "Check for updates" action in settings.
- Do not interrupt active work for optional updates.
- For optional updates, show a visible but dismissible prompt.
- For mandatory updates, block normal work with an update dialog or route, but
  still allow connection/settings access needed to complete the update.
- Mandatory update mode must still allow switching or disconnecting the daemon,
  because the current daemon could be serving a bad manifest.
- Mandatory update mode must still allow diagnostics export and uninstall/help
  access so developers can recover evidence from a bad rollout.
- Show progress as downloaded size, total size, percent, and speed.
- Show pause/resume during download.
- Show "Install" only after verification succeeds.
- If installation is cancelled, keep the verified APK and let the user retry.
- If installation succeeds, the current process may be stopped or replaced by
  Android. On next launch, if the installed `versionCode` matches the downloaded
  manifest version, clean the verified APK and metadata.
- If installation fails because of parse/signature/package errors, delete the
  verified APK and move to `installFailed` or `failed` with the platform reason.
- Provide a "discard download" action that deletes `.part`, `.apk`, and metadata
  and moves through `cancelled` back to `available` or `idle`.

Startup reconciliation rules:

1. If both `.apk` and `.part` exist for the same `versionCode`, prefer `.apk`
   because it has already been verified, and delete `.part`.
2. If installed `versionCode` is greater than or equal to persisted update
   metadata `versionCode`, delete `.part`, `.apk`, and metadata. The user either
   installed this update or moved beyond it through another channel.
3. If installed `versionCode` is lower than persisted metadata `versionCode` and
   a verified `.apk` still exists, keep it and return to `readyToInstall`.
4. If installed `versionCode` is lower than persisted metadata `versionCode` and
   only `.part` exists, return to `paused` or `available` based on whether the
   manifest still matches the metadata.
5. If the latest manifest `etag`, `sha256`, `sizeBytes`, `apkUrl`, or
   `versionCode` differs from persisted metadata, delete stale files and start
   from the new manifest.

## Error Handling

Expected failures and responses:

```text
manifest unavailable -> show "could not check updates", keep app usable
daemon returns older/equal version -> upToDate
APK HEAD mismatch -> fail before download
insufficient storage -> fail before download, prompt user to free space
network disconnect -> paused/retryable with partial file kept
401 during manifest or APK request -> shared HTTP client refreshes auth and replays request
transient server error (5xx, timeout, connection reset) -> paused with retry, partial file kept
terminal server error (4xx other than 401) -> failed with server message
server does not support Range -> restart download from zero
cache file missing after OS cleanup -> treat as no download in progress
416 resume offset invalid -> delete partial and restart
size mismatch -> delete final APK and retry
sha256 mismatch -> delete final APK, show integrity error
install permission missing -> open Android settings path
installer pending user action -> launch Android confirmation UI
installer cancelled -> installCancelled, then readyToInstall for retry
installer success -> installSucceeded, cleanup on next launch
installer failure -> installFailed or failed with platform reason
package signature mismatch -> show install failed, require correct build signing
```

Integrity errors should be treated as hard failures for that downloaded file.
The app must not offer to install an APK whose hash does not match the manifest.

## Observability

This feature should leave enough evidence to diagnose failed internal updates
without adding a full telemetry system.

Daemon logs should include:

```text
deviceId
installedVersionCode when reported by mobile
requestedVersionCode
rangeStart
rangeEnd
httpStatus
bytesServed
durationMs
etag
errorCode
```

Mobile diagnostics should record:

```text
update.check.started
update.check.completed
update.download.started
update.download.resumed
update.download.paused
update.download.failed
update.discard
update.storage.preflight_failed
update.verify.started
update.verify.failed
update.ready_to_install
update.install.permission_needed
update.install.committed
update.install.pending_user_action
update.install.cancelled
update.install.failed
update.install.succeeded
```

Useful counters:

```text
download attempt count
average download speed
resume hit rate
sha256 failure count
install cancellation count
install failure count
installed versionCode distribution
```

The first implementation can keep these as daemon/mobile structured logs and
existing trace rows. It does not need a standalone metrics database.

## Release Process

The private update channel needs a repeatable release process:

Phase 0 is signing migration:

1. Generate a stable private release keystore.
2. Define keystore backup, access, and recovery ownership. Losing this keystore
   permanently breaks the private update channel for already-installed apps.
3. Configure release builds to use that keystore.
4. Ensure APK signing includes v2 or newer signature schemes, with v2+v3
   recommended for the supported Android range. Keep v1 only if explicitly
   needed for older device compatibility.
5. Uninstall existing debug-signed APKs from test devices and install the first
   release-signed baseline APK. Android cannot update a debug-signed install to
   a differently signed release APK without uninstalling, so this first
   migration is intentionally destructive for local app data.

Normal update release process:

1. Increment `versionCode` and `versionName`.
2. Build release APK with the stable release keystore.
3. Compute `sha256` and byte size using the release script.
4. Write/update the daemon Android update manifest and sidecar digest.
5. Copy APK to the configured daemon artifact directory.
6. Start/restart daemon and verify manifest startup validation passes.
7. Install the previous release-signed APK on a test device.
8. Use the app update flow to download, verify, and install the new APK.

The project should not ship this feature while `release` still signs with the
debug key except for throwaway test devices.

## Testing Plan

Daemon tests:

- returns latest Android update manifest for authenticated devices;
- returns `304 Not Modified` for manifest `If-None-Match` matches;
- rejects unauthenticated update requests if the daemon API requires auth;
- validates manifest schema and configured artifact paths;
- validates APK `sizeBytes` at startup and exposes digest metadata from the
  manifest or sidecar;
- returns full APK with correct headers;
- returns `HEAD` metadata without body;
- returns `404` when the requested APK `versionCode` is retained on disk but is
  not the current manifest version;
- returns `206` and correct `Content-Range` for a valid single-range request;
- returns `206` for `Range` plus matching `If-Range`;
- returns `200` for `Range` plus stale `If-Range`;
- returns `416` for invalid range offsets;
- authenticates streaming full and range downloads without buffering the APK;
- does not serve paths outside the configured artifact directory.

Mobile unit tests:

- compares remote `versionCode` against installed `versionCode`;
- ignores equal or older versions;
- accepts newer version manifests;
- treats `installedVersionCode < minSupportedVersionCode` as mandatory even
  when `mandatory` is false;
- rejects unsupported manifest schema versions;
- parses `available: false` using the same `schemaVersion: 1` envelope;
- rejects manifests with cross-origin `apkUrl`;
- resumes when local metadata matches the manifest;
- restarts when local metadata differs;
- restarts after `200 OK` response to resume request;
- restarts after `416 Range Not Satisfiable`;
- relies on the shared HTTP client to refresh auth and replay `401` manifest or
  APK requests;
- fails before download when storage preflight reports insufficient space;
- treats missing cache files after OS cleanup as no download in progress;
- computes sha256 without blocking the UI isolate;
- verifies sha256 before exposing `readyToInstall`;
- deletes corrupted APK after sha256 mismatch;
- preserves `.part` file on pause;
- deletes partial/final APK files on discard/cancel cleanup.

Android bridge tests:

- reports install permission availability;
- opens unknown-source install settings when permission is missing;
- commits a verified APK through `PackageInstaller.Session`;
- emits pending-user-action events from the `IntentSender` callback;
- emits success, cancelled, and failed install results with platform details;
- persists and restores PackageInstaller session state across process restart.

Mobile widget tests:

- settings update panel shows up-to-date state;
- available update shows version, size, release notes, and download button;
- download progress shows percent and pause action;
- paused state shows resume action;
- verified APK shows install action;
- permission-needed state shows settings action;
- install-cancelled state returns to ready-to-install;
- discard action removes downloaded state;
- mandatory update gate still allows daemon switching/disconnect and diagnostic
  export;
- failure state shows useful retry/cleanup actions.

Manual device test:

- confirm resolved `minSdkVersion`, `targetSdkVersion`, and APK signing schemes;
- one-time Phase 0 baseline: uninstall any debug-signed install, then install
  the first release-signed baseline APK;
- per-update regression: ensure the device has the previous release-signed
  `versionCode` installed. The baseline counts as the first previous version;
- connect to daemon with newer manifest;
- download halfway, kill network, resume;
- verify hash and install through Android system UI;
- confirm PackageInstaller result events are observed for cancel and success;
- confirm installed version is the new `versionCode`;
- confirm old partial files are cleaned on next launch.

Device matrix:

- Android 10;
- Android 13;
- Android 14;
- Android 15.

## Phased Implementation

Phase 0: release keystore creation, backup policy, signing configuration, and
debug-signed device migration.

Phase 1: daemon manifest serving, artifact validation, `HEAD`, full `GET`, and
single-range `GET`.

Phase 2: mobile update check, version comparison, settings UI, and optional
update prompt.

Phase 3: resumable downloader, shared HTTP auth replay, storage preflight,
non-blocking sha256 verification, and file cleanup.

Phase 4: PackageInstaller session bridge, install result events, permission
settings flow, and device install validation.

Phase 5: mandatory update gating, observability polish, and retained-artifact
cleanup.

Phase 5 can also add an explicit daemon `appUpdate` permission if the current
authorization model has a natural permission hook. The default grant should
preserve today's behavior for already authenticated devices. If the permission
model is not ready, keep update access aligned with the existing authenticated
daemon API boundary and defer permission splitting.

This order keeps the riskiest platform assumptions visible early: signing,
manifest correctness, package installer permissions, and device behavior.

## Open Risks

- Android vendor ROMs may present different install-permission screens.
- Long downloads may be interrupted if the app is backgrounded or killed.
- Android may clear `<cacheDir>/app_updates/` under storage pressure, so paused
  downloads are best-effort and must be restartable.
- Debug-key builds are not a valid long-term update base.
- Release keystore loss permanently breaks updates for existing installs.
- PackageInstaller result behavior should be verified on the actual Android
  versions and vendor ROMs used by the team.
- If package name changes later, Android treats the APK as a different app.
- If the daemon is unavailable, the app cannot discover updates unless a future
  static update URL is added.

## Re-Evaluate When

Revisit this design if:

- the app moves to Google Play or an enterprise app store;
- silent installation becomes a hard requirement;
- release artifacts need cloud/public distribution;
- update downloads must continue reliably in the background;
- daemon update hosting moves to multi-instance or HA deployment;
- the team wants Dart-only hot patches between full APK releases.
