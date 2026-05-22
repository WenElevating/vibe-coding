# Decision: Attachment Previews Are Mobile-Owned Cache

- Status: accepted; implementation pending
- Date: 2026-05-22
- Last verified: 2026-05-22

## Context

The temporary image-preview implementation copied sent image bytes into daemon
storage and returned `previewPath` values to the mobile client. That made
historical previews visible, but it turned the daemon into a persistent media
preview service.

The accepted product scope is device-local: historical image previews only need
to survive restart on the mobile device that sent the image. Other devices and
cleared caches may show attachment metadata without a preview.

## Decision

Daemon owns conversation history and attachment metadata. Mobile owns durable
local thumbnail previews for images it sent.

The committed attachment protocol must not include `previewPath`, `previewUrl`,
or `previewHeaders`. Do not keep compatibility for those temporary fields.
Existing old preview data may fall back to the normal attachment card.

Daemon send-time scratch storage remains valid because CLI adapters still need
temporary attachment files. Scratch storage must not be treated as historical
media storage.

Pending-to-committed preview binding must use attachment content hash as the
primary identity and `clientMessageId` as the message bridge. `attachmentIndex`
is only an ordering hint. Retrying the same attachment message must reuse the
same `clientMessageId` so daemon idempotency and mobile preview cache binding
stay aligned.

Hash calculation must run off the Flutter UI isolate. `bindCommitted` binds
committed metadata to existing pending cache records; thumbnail generation and
background retry are owned by the cache service state machine, not by binding
logic.

The first mobile cache implementation should protect local storage with default
limits of 100 MB or 500 records, evicting least-recently-accessed records first.
If the cache index is file-backed, writes must be serialized and atomic; an
existing local database is preferred when available.

Uncommitted pending records from abandoned drafts or changed `clientMessageId`
values are orphan cache entries. They must never bind to history and should be
cleaned before normal ready historical previews.

## Alternatives

- Daemon media store: rejected for current scope because it creates retention,
  auth, cleanup, migration, and cross-device media semantics the product did not
  choose.
- Source `localPath` only: rejected because app restart, file moves, and
  platform permissions make history previews unreliable even on the sending
  mobile device.
- Compatibility migration from `previewPath`: rejected by user decision. The
  temporary server preview fields should be removed rather than carried forward.

## Evidence

- User selected the local-device guarantee: only the sending mobile device must
  preserve previews after restart.
- User explicitly rejected retaining `previewPath`/`previewUrl` compatibility.
- Detailed design:
  [2026-05-22 mobile-owned attachment preview cache](../../superpowers/specs/2026-05-22-mobile-owned-attachment-preview-cache-design.md)

## Verification

Implementation should verify:

```powershell
node scripts/run-tests.js
npm run lint
cd mobile
$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
dart run tool\check_architecture_imports.dart
flutter test
```

If Flutter commands time out in Codex, stop after the first timeout and provide
the exact mirror-configured command for manual verification.

## Re-Evaluate When

- Multiple mobile devices must see the same historical image previews.
- Attachment previews need backup, restore, export, or sharing semantics.
- The daemon gains an explicit media-store product responsibility.
- The app adds cloud sync or a shared object store.
- A tablet, desktop companion, or linked device must share the same
  preview-availability guarantee.
