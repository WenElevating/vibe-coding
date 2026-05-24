# Decision: Private Android APK Update Channel

- Status: accepted
- Date: 2026-05-24
- Last verified: 2026-05-24

## Context

The Android APK is distributed internally over LAN, not through Google Play.
Users should not manually copy APK files, but normal Android devices still
require system install confirmation.

## Decision

The daemon hosts a schema-versioned Android update manifest and streams only
the APK version currently referenced by that manifest. Mobile downloads with
Range and If-Range resume, verifies `sha256`, and installs through
`PackageInstaller.Session`.

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
