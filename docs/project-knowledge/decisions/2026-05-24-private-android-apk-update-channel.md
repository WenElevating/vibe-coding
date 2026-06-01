# Decision: Private Android APK Update Channel

- Status: accepted
- Date: 2026-05-24
- Last verified: 2026-05-27

## Context

The Android APK is distributed internally over LAN, not through Google Play.
Users should not manually copy APK files, but normal Android devices still
require system install confirmation.

## Decision

The daemon hosts a schema-versioned Android update manifest and streams only
the APK version currently referenced by that manifest. Mobile downloads with
Range and If-Range resume, verifies `sha256`, and installs through
`PackageInstaller.Session`.

On Android installer recovery, the native bridge treats an active, committed, or
sealed `PackageInstaller.SessionInfo` as a recoverable pending installer
session. On API 24-25, where committed/sealed state is not exposed by
`SessionInfo`, an existing persisted session is treated as recoverable because
the app records session ids only after `PackageInstaller.Session.commit()`
returns. It returns a `pendingUserAction` payload with the original `sessionId`,
`appPackageName`, and a diagnostic message, and re-adds the session id to the
in-process receiver whitelist so later terminal installer broadcasts are not
dropped. Missing native sessions return no native pending state. Dart then
clears only the matching persisted `installSessionId`, keeps the verified APK
cache, and returns to a retryable install state.

On Dart recovery, the app reads the persisted `installSessionId` from matching
download metadata only after the cached APK still verifies against the current
manifest. `MainPage` triggers that recovery on Android when the update
ViewModel is created and when the app resumes. Recovery is allowed from idle,
up-to-date, available, paused, or failed update states, and the ViewModel
re-checks that guard after async daemon/cache/native calls before applying any
recovery side effect, so a stale recovery result cannot overwrite or clear state
for an active user download or install flow. If the daemon manifest is
unavailable or no longer newer than the installed app, Dart clears orphan
install-session ids from cached update metadata only after the ViewModel
recovery guard still passes, avoiding retries of the same stale recovery on
every resume without racing an active download. While the UI is installing or
waiting for Android user confirmation, `install()` must not create another
`PackageInstaller.Session` for the same APK; the existing session must resolve
or the user must discard/retry from a non-pending state. If Dart fails to record
the `installSessionId` after Android has already accepted the install session,
the ViewModel keeps the install in progress and records diagnostics instead of
returning to a retryable install state. Terminal installer events clear the
persisted `installSessionId` while keeping the verified APK cache metadata,
preventing a future startup from recovering a completed or failed native session
as a ghost pending update. Installer event-stream failures are diagnostic-only
on Dart; they must not escape as unhandled asynchronous errors or mutate update
state.

The daemon validates the manifest-referenced APK digest when a new file identity
is observed, then caches that validated identity by real path, device/inode,
size, mtime, and sha256. Digest verification for changed APK identities uses an
asynchronous file stream rather than `fs.readFileSync`, so publishing or
replacing a large APK does not block the Node event loop with a full-file hash
scan. Each APK request opens the file descriptor and compares the fd/path
identity to the cached validated identity before streaming, avoiding per-request
synchronous SHA-256 scans of large APKs on the Node event loop.

The update channel is authenticated through the paired-device daemon boundary.
The current daemon auth model does not have app-level permission categories, so
an `appUpdate` permission split is deferred until such a permission system
exists.

## Alternatives

- Google Play In-App Updates: rejected for current private LAN distribution.
- Silent install: rejected because it requires device-owner or privileged
  installer conditions.
- Shorebird-only updates: rejected because native/plugin/manifest changes still
  need APK replacement.

## Evidence

- Spec: `docs/superpowers/specs/2026-05-24-android-private-apk-update-design.md`
- Plan: `docs/superpowers/plans/2026-05-24-android-private-apk-update.md`
- Daemon implementation: `daemon/src/app-update-service.js`
- Mobile downloader: `mobile/lib/src/services/app_update_download_manager.dart`
- Android bridge: `mobile/android/app/src/main/kotlin/com/example/lan_ai_cli_control/MainActivity.kt`
- ViewModel and lifecycle tests: `mobile/test/app_update_view_model_test.dart`,
  `mobile/test/widget_test.dart`

## Verification

Run daemon and mobile update tests plus one manual Android device install smoke.
The manual smoke must install a previous release-signed APK, download the newer
APK through the connected daemon, interrupt and resume the download, confirm the
Android installer UI appears, and verify the installed `versionCode` changes
after relaunch.

## Re-evaluate When

- Distribution moves to Google Play or enterprise MDM.
- Silent installation becomes mandatory.
- Daemon update hosting becomes multi-instance or HA.
- The daemon gains a permission-category model that can express `appUpdate`
  separately from general paired-device access.
