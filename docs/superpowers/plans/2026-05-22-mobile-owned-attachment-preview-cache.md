# Mobile-Owned Attachment Preview Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove daemon-owned historical image preview storage and replace it with a mobile-owned local thumbnail cache for images sent from the current device.

**Architecture:** Keep daemon as the authority for conversation events and attachment metadata only. Keep `AttachmentScratchStore` for send-time adapter input, remove `AttachmentPreviewStore` and preview routes, and make mobile resolve image previews from a feature-local `AttachmentPreviewCache`. Use content hash plus `clientMessageId` for pending-to-committed binding, with bounded local cache records and normal attachment-card fallback on cache miss.

**Tech Stack:** Node.js daemon tests in `scripts/run-tests.js`; Flutter/Dart mobile data models, feature ViewModel, widget tests, `crypto`, `path_provider`, `dart:ui` image decoding, and feature-local cache service under `mobile/lib/src/ui/features/workbench/attachments/`.

---

## Source Spec

- `docs/superpowers/specs/2026-05-22-mobile-owned-attachment-preview-cache-design.md`
- `docs/project-knowledge/decisions/2026-05-22-mobile-owned-attachment-preview-cache.md`
- The `Cache Record State Machine` section in the spec is the implementation authority for legal `pending`, `ready`, `failed`, `orphanedAt`, `committedAt`, and eviction transitions.

## File Structure

- Delete: `daemon/src/attachment-preview-store.js`
- Modify: `daemon/src/conversation-manager.js`
  - Remove `AttachmentPreviewStore` import, constructor field, `committedAttachmentMetadata(conversation, files)` method body that copies image files, and `getAttachmentPreview()`.
  - Keep module-level `committedAttachmentMetadata(files)` and all scratch cleanup behavior.
- Modify: `daemon/src/main.js`
  - Stop constructing `attachmentPreviewStore`.
- Modify: `daemon/src/server.js`
  - Delete preview route and `streamAttachmentPreview()`.
- Modify: `scripts/run-tests.js`
  - Replace preview persistence test with metadata-only and route-absent assertions.
  - Remove direct tests for `AttachmentPreviewStore`.
- Modify: `mobile/lib/src/data/models/attachment_models.dart`
  - Remove `previewPath`, `previewUrl`, and `previewHeaders`.
  - Keep `localPath` as a mobile/UI-only resolved cache path, but stop reading it from daemon JSON.
- Modify: `mobile/lib/src/services/daemon_client.dart`
  - Remove `_withResolvedAttachmentPreviews()` and `_resolveAttachmentPreview()`.
- Create: `mobile/lib/src/ui/features/workbench/attachments/attachment_preview_cache.dart`
  - Own `AttachmentPreviewIdentity`, `AttachmentPreviewCacheRecord`, `CachedAttachmentPreview`, `AttachmentPreviewCache`, `NoopAttachmentPreviewCache`, and `LocalAttachmentPreviewCache`.
- Modify: `mobile/lib/src/ui/features/workbench/workbench_dependencies.dart`
  - Add `AttachmentPreviewCache attachmentPreviewCache`.
- Modify: `mobile/lib/src/app/app_dependencies.dart`
  - Construct `LocalAttachmentPreviewCache`.
- Modify: `mobile/lib/src/ui/features/workbench/view_models/workbench_view_model.dart`
  - Replace in-memory preview maps with the injected cache.
  - Prepare pending previews before send.
  - Bind committed attachments after event replay.
  - Resolve cached previews into `CommittedAttachment.localPath` for UI rendering.
- Modify: `mobile/lib/src/ui/features/workbench/workbench_event_cards.dart`
  - Remove `Image.network` branch and viewer opening for cache misses.
- Modify tests:
  - `mobile/test/attachment_preview_cache_test.dart`
  - `mobile/test/daemon_client_test.dart`
  - `mobile/test/protocol_compatibility_test.dart`
  - `mobile/test/adapter_model_test.dart`
  - `mobile/test/coding_workbench_controller_test.dart`
  - `mobile/test/widget_test.dart`

---

### Task 1: Remove Daemon Preview Storage

**Files:**
- Modify: `scripts/run-tests.js`
- Modify: `daemon/src/conversation-manager.js`
- Modify: `daemon/src/main.js`
- Modify: `daemon/src/server.js`
- Delete: `daemon/src/attachment-preview-store.js`

- [ ] **Step 1: Replace the daemon preview persistence regression test**

In `scripts/run-tests.js`, replace the test named `multipart conversation image preview survives turn scratch cleanup` with this metadata-only test:

```javascript
test('multipart conversation image attachments commit metadata without preview storage', async () => {
  const adapter = codexNativeImageAttachmentAdapter();
  const { app, port, token, conversationId } = await createAttachmentConversationApp({
    adapter,
    dbPrefix: 'app-db-attachments-image-metadata-'
  });
  try {
    const boundary = '----attachments-image-metadata';
    const imageBytes = minimalPngBytes({ width: 1, height: 1 });
    const body = multipartBody({
      boundary,
      payload: {
        text: 'inspect image',
        clientMessageId: 'client_image_metadata',
        capabilityVersion: attachmentImageCapabilityVersion(),
        attachments: [{ field: 'files[0]', name: 'preview.png', mimeType: 'image/png', kind: 'image', sizeBytes: imageBytes.length }]
      },
      files: [{ name: 'preview.png', mimeType: 'image/png', bytes: imageBytes }]
    });
    const response = await requestRaw(port, 'POST', `/api/conversations/${conversationId}/messages`, body, token, {
      'content-type': `multipart/form-data; boundary=${boundary}`
    });

    assert.equal(response.status, 200);
    const internal = app.conversations.conversations.get(conversationId);
    const userMessage = app.conversationEventStore.list(conversationId, 0).find((event) => event.type === 'user.message');
    const attachment = userMessage.attachments[0];
    assert.equal(attachment.name, 'preview.png');
    assert.equal(attachment.kind, 'image');
    assert.equal(attachment.mimeType, 'image/png');
    assert.equal(attachment.handling, 'native');
    assert.equal(Object.prototype.hasOwnProperty.call(attachment, 'previewPath'), false);
    assert.equal(Object.prototype.hasOwnProperty.call(attachment, 'previewUrl'), false);
    assert.equal(Object.prototype.hasOwnProperty.call(attachment, 'scratchPath'), false);
    assert.equal(Object.prototype.hasOwnProperty.call(attachment, 'contentSha256'), false);

    app.conversations.recordAdapterEvent(internal, { type: 'conversation.completed' });
    await waitForAttachmentScratchCleanup(app);
    assert.deepEqual(attachmentScratchEntries(app), []);

    const previewRoute = `/api/conversations/${conversationId}/attachments/${attachment.id}/preview`;
    const preview = await requestRaw(port, 'GET', previewRoute, null, token);
    assert.equal(preview.status, 404);
  } finally {
    await closeAttachmentConversationApp(app);
  }
});
```

- [ ] **Step 2: Run the daemon test and verify it fails**

Run:

```powershell
node scripts\run-tests.js
```

Expected: the new test fails because daemon still writes `previewPath` and the preview route still returns `200`.

- [ ] **Step 3: Remove daemon preview implementation**

Apply these edits:

```javascript
// daemon/src/conversation-manager.js
// Remove:
const { AttachmentPreviewStore } = require('./attachment-preview-store');

// Constructor: remove attachmentPreviewStore parameter and field.
constructor({ workspaces, eventStore, auditLog, adapters, persistentStore = null, idleTtlMs = 600000, now = () => new Date(), attachmentScratchStore = null }) {
  this.workspaces = workspaces;
  this.eventStore = eventStore;
  this.auditLog = auditLog;
  this.adapters = adapters;
  this.persistentStore = persistentStore;
  this.idleTtlMs = idleTtlMs;
  this.now = now;
  this.attachmentScratchStore = attachmentScratchStore || new AttachmentScratchStore({ root: path.join(os.tmpdir(), 'vibe-coding-attachment-scratch') });
  this.multipartDeviceLocks = new Map();
  this.multipartActiveCount = 0;
  this.multipartMaxPerDaemon = 4;
  this.messageIdempotencyMaxEntries = 1000;
  this.conversations = new Map();
  this.loadPersistedConversations();
}

// Replace class method committedAttachmentMetadata with a metadata-only method.
async committedAttachmentMetadata(_conversation, files) {
  return committedAttachmentMetadata(files);
}

// Delete getAttachmentPreview().
```

```javascript
// daemon/src/main.js
// Remove:
const { AttachmentPreviewStore } = require('./attachment-preview-store');
const attachmentPreviewStore = new AttachmentPreviewStore({ root: path.join(path.dirname(appDbPath), 'attachment-previews') });

// Remove attachmentPreviewStore from ConversationManager construction.
```

```javascript
// daemon/src/server.js
// Delete preview route block:
const conversationAttachmentPreview = url.pathname.match(/^\/api\/conversations\/([^/]+)\/attachments\/([^/]+)\/preview$/);
if (method === 'GET' && conversationAttachmentPreview) {
  return streamAttachmentPreview(
    res,
    await conversations.getAttachmentPreview(conversationAttachmentPreview[1], conversationAttachmentPreview[2], device)
  );
}

// Delete streamAttachmentPreview().
```

Delete the file:

```powershell
git rm daemon\src\attachment-preview-store.js
```

- [ ] **Step 4: Run daemon tests**

Run:

```powershell
node scripts\run-tests.js
```

Expected: daemon tests pass. If remaining failures reference `AttachmentPreviewStore`, remove or replace those tests with metadata-only assertions that preserve scratch cleanup coverage.

- [ ] **Step 5: Commit daemon removal**

```powershell
git add scripts\run-tests.js daemon\src\conversation-manager.js daemon\src\main.js daemon\src\server.js daemon\src\attachment-preview-store.js
git commit -m "Remove daemon attachment preview storage"
```

---

### Task 2: Remove Preview URL Fields From Mobile Protocol Models

**Files:**
- Modify: `mobile/lib/src/data/models/attachment_models.dart`
- Modify: `mobile/lib/src/services/daemon_client.dart`
- Modify: `mobile/test/daemon_client_test.dart`
- Modify: `mobile/test/protocol_compatibility_test.dart`

- [ ] **Step 1: Change protocol tests to reject preview URL exposure**

In `mobile/test/daemon_client_test.dart`, replace `fetchConversationEvents resolves persisted attachment preview paths` with:

```dart
test('fetchConversationEvents ignores legacy attachment preview fields', () async {
  final tokenStore = MemoryTokenStore();
  await tokenStore.writeAccessTokenSession(
    'device-1',
    TokenSession(
      token: 'access-1',
      expiresAt: DateTime.parse('2026-06-01T08:00:00.000Z'),
    ),
  );
  final requests = <http.Request>[];
  final client = DaemonClient(
    baseUri: Uri.parse('http://127.0.0.1:4317'),
    tokenStore: tokenStore,
    httpClient: MockClient((request) async {
      requests.add(request);
      expect(request.url.path, '/api/conversations/conv_1/events');
      return http.Response(
        jsonEncode(const <String, Object?>{
          'events': <Object?>[
            <String, Object?>{
              'seq': 1,
              'conversationId': 'conv_1',
              'type': 'user.message',
              'createdAt': '2026-05-22T00:00:00.000Z',
              'text': 'see image',
              'attachments': <Object?>[
                <String, Object?>{
                  'id': 'att_0',
                  'name': 'legacy.png',
                  'kind': 'image',
                  'mimeType': 'image/png',
                  'sizeBytes': 42,
                  'handling': 'native',
                  'previewPath': '/api/conversations/conv_1/attachments/att_0/preview',
                  'previewUrl': 'http://127.0.0.1:4317/legacy',
                },
              ],
            },
          ],
        }),
        200,
      );
    }),
  );
  await client.ensurePaired(
      deviceIdentityStore: MemoryDeviceIdentityStore(deviceId: 'device-1'));

  final events = await client.fetchConversationEvents('conv_1');

  expect(requests, hasLength(1));
  expect(requests.single.headers['authorization'], 'Bearer access-1');
  final attachment = events.single.attachments.single;
  expect(attachment.id, 'att_0');
  expect(attachment.name, 'legacy.png');
  expect(attachment.localPath, isNull);
});
```

In `mobile/test/protocol_compatibility_test.dart`, extend the existing attachment metadata test:

```dart
expect(attachment.localPath, isNull);
```

- [ ] **Step 2: Run focused mobile protocol tests and verify they fail**

Run from `mobile/` with mirrors:

```powershell
$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test test\daemon_client_test.dart test\protocol_compatibility_test.dart -r expanded
```

Expected: failures because model still exposes preview fields and daemon client still resolves preview URLs.

- [ ] **Step 3: Simplify `CommittedAttachment`**

Update `mobile/lib/src/data/models/attachment_models.dart`:

```dart
class CommittedAttachment {
  const CommittedAttachment({
    required this.id,
    required this.name,
    required this.kind,
    required this.mimeType,
    required this.sizeBytes,
    required this.handling,
    this.localPath,
  });

  final String id;
  final String name;
  final AttachmentKind kind;
  final String mimeType;
  final int sizeBytes;
  final AttachmentHandling handling;
  final String? localPath;

  bool get hasImagePreview =>
      kind == AttachmentKind.image && localPath != null;

  factory CommittedAttachment.fromJson(Map<String, Object?> json) =>
      CommittedAttachment(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        kind: parseAttachmentKind(json['kind']),
        mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
        handling: parseAttachmentHandling(json['handling']),
      );

  CommittedAttachment copyWith({
    String? localPath,
    bool clearLocalPath = false,
  }) =>
      CommittedAttachment(
        id: id,
        name: name,
        kind: kind,
        mimeType: mimeType,
        sizeBytes: sizeBytes,
        handling: handling,
        localPath: clearLocalPath ? null : localPath ?? this.localPath,
      );
}
```

Remove `_stringMap()` if it becomes unused.

- [ ] **Step 4: Remove daemon client preview resolution**

In `mobile/lib/src/services/daemon_client.dart`:

```dart
// Delete _withResolvedAttachmentPreviews().
// Delete _resolveAttachmentPreview().
// Stop calling _withResolvedAttachmentPreviews() from _conversationEventFromJson().
```

`ConversationEvent.fromJson` should receive daemon event JSON directly.

- [ ] **Step 5: Run focused tests**

Run:

```powershell
$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test test\daemon_client_test.dart test\protocol_compatibility_test.dart -r expanded
```

Expected: both test files pass.

- [ ] **Step 6: Commit protocol cleanup**

```powershell
git add mobile\lib\src\data\models\attachment_models.dart mobile\lib\src\services\daemon_client.dart mobile\test\daemon_client_test.dart mobile\test\protocol_compatibility_test.dart
git commit -m "Remove attachment preview URLs from mobile protocol"
```

---

### Task 3: Add Feature-Local Attachment Preview Cache

**Files:**
- Create: `mobile/lib/src/ui/features/workbench/attachments/attachment_preview_cache.dart`
- Create: `mobile/test/attachment_preview_cache_test.dart`

- [ ] **Step 1: Add cache tests first**

Create `mobile/test/attachment_preview_cache_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/domain/models/attachment_types.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/ui/features/workbench/attachments/attachment_preview_cache.dart';
import 'package:lan_ai_cli_control/src/ui/features/workbench/attachments/draft_attachment.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('preview-cache-test-');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('rememberPending writes pending record before binding', () async {
    final cache = LocalAttachmentPreviewCache(
      rootDirectoryProvider: () async => root,
      identityProvider: const FixedAttachmentPreviewIdentityProvider('hash_a'),
      thumbnailGenerator: const TestCopyingAttachmentThumbnailGenerator(),
    );
    final source = File('${root.path}${Platform.pathSeparator}source.png');
    await source.writeAsBytes(<int>[1, 2, 3]);

    final identity = await cache.rememberPending(
      conversationId: 'conv_1',
      clientMessageId: 'client_1',
      draft: DraftAttachment(
        localPath: source.path,
        name: 'source.png',
        mimeType: 'image/png',
        kind: AttachmentKind.image,
        sizeBytes: 3,
      ),
      attachmentIndex: 0,
    );

    expect(identity.contentHash, 'hash_a');
    final records = await cache.recordsForTest();
    expect(records.single.state, AttachmentPreviewCacheState.ready);
    expect(records.single.clientMessageId, 'client_1');
    expect(records.single.attachmentIndex, 0);
  });

  test('bindCommitted uses hash instead of attachment index', () async {
    final cache = LocalAttachmentPreviewCache(
      rootDirectoryProvider: () async => root,
      identityProvider: SequenceAttachmentPreviewIdentityProvider(<String>['hash_a', 'hash_b']),
      thumbnailGenerator: const TestCopyingAttachmentThumbnailGenerator(),
    );
    final first = File('${root.path}${Platform.pathSeparator}first.png');
    final second = File('${root.path}${Platform.pathSeparator}second.png');
    await first.writeAsBytes(<int>[1]);
    await second.writeAsBytes(<int>[2]);
    await cache.rememberPending(
      conversationId: 'conv_1',
      clientMessageId: 'client_1',
      attachmentIndex: 0,
      draft: DraftAttachment(localPath: first.path, name: 'first.png', mimeType: 'image/png', kind: AttachmentKind.image, sizeBytes: 1),
    );
    await cache.rememberPending(
      conversationId: 'conv_1',
      clientMessageId: 'client_1',
      attachmentIndex: 1,
      draft: DraftAttachment(localPath: second.path, name: 'second.png', mimeType: 'image/png', kind: AttachmentKind.image, sizeBytes: 1),
    );

    await cache.bindCommitted(
      conversationId: 'conv_1',
      clientMessageId: 'client_1',
      attachments: const <CommittedAttachment>[
        CommittedAttachment(id: 'att_b', name: 'second.png', kind: AttachmentKind.image, mimeType: 'image/png', sizeBytes: 1, handling: AttachmentHandling.native),
        CommittedAttachment(id: 'att_a', name: 'first.png', kind: AttachmentKind.image, mimeType: 'image/png', sizeBytes: 1, handling: AttachmentHandling.native),
      ],
    );

    final secondResolved = await cache.resolve(
      conversationId: 'conv_1',
      attachment: const CommittedAttachment(id: 'att_b', name: 'second.png', kind: AttachmentKind.image, mimeType: 'image/png', sizeBytes: 1, handling: AttachmentHandling.native),
    );
    expect(secondResolved, isNotNull);
    expect(secondResolved!.contentHash, 'hash_b');
  });

  test('thumbnail failure records failed state and one retry can recover', () async {
    final generator = FailingThenCopyingThumbnailGenerator();
    final cache = LocalAttachmentPreviewCache(
      rootDirectoryProvider: () async => root,
      identityProvider: const FixedAttachmentPreviewIdentityProvider('hash_fail'),
      thumbnailGenerator: generator,
    );
    final source = File('${root.path}${Platform.pathSeparator}source.png');
    await source.writeAsBytes(<int>[1, 2, 3]);

    await cache.rememberPending(
      conversationId: 'conv_1',
      clientMessageId: 'client_1',
      attachmentIndex: 0,
      draft: DraftAttachment(localPath: source.path, name: 'source.png', mimeType: 'image/png', kind: AttachmentKind.image, sizeBytes: 3),
    );
    expect((await cache.recordsForTest()).single.state, AttachmentPreviewCacheState.failed);

    await cache.bindCommitted(
      conversationId: 'conv_1',
      clientMessageId: 'client_1',
      attachments: const <CommittedAttachment>[
        CommittedAttachment(id: 'att_0', name: 'source.png', kind: AttachmentKind.image, mimeType: 'image/png', sizeBytes: 3, handling: AttachmentHandling.native),
      ],
    );

    final resolved = await cache.resolve(
      conversationId: 'conv_1',
      attachment: const CommittedAttachment(id: 'att_0', name: 'source.png', kind: AttachmentKind.image, mimeType: 'image/png', sizeBytes: 3, handling: AttachmentHandling.native),
    );
    expect(resolved, isNotNull);
    expect(generator.calls, 2);
  });

  test('orphaned pending records never bind as historical previews', () async {
    final cache = LocalAttachmentPreviewCache(
      rootDirectoryProvider: () async => root,
      identityProvider: const FixedAttachmentPreviewIdentityProvider('hash_orphan'),
      thumbnailGenerator: const TestCopyingAttachmentThumbnailGenerator(),
    );
    final source = File('${root.path}${Platform.pathSeparator}source.png');
    await source.writeAsBytes(<int>[1]);

    await cache.rememberPending(
      conversationId: 'conv_1',
      clientMessageId: 'client_old',
      attachmentIndex: 0,
      draft: DraftAttachment(localPath: source.path, name: 'source.png', mimeType: 'image/png', kind: AttachmentKind.image, sizeBytes: 1),
    );
    await cache.markClientMessageOrphaned(
      conversationId: 'conv_1',
      clientMessageId: 'client_old',
    );
    await cache.bindCommitted(
      conversationId: 'conv_1',
      clientMessageId: 'client_new',
      attachments: const <CommittedAttachment>[
        CommittedAttachment(id: 'att_0', name: 'source.png', kind: AttachmentKind.image, mimeType: 'image/png', sizeBytes: 1, handling: AttachmentHandling.native),
      ],
    );

    final resolved = await cache.resolve(
      conversationId: 'conv_1',
      attachment: const CommittedAttachment(id: 'att_0', name: 'source.png', kind: AttachmentKind.image, mimeType: 'image/png', sizeBytes: 1, handling: AttachmentHandling.native),
    );
    expect(resolved, isNull);
  });

  test('missing preview file downgrades to cache miss', () async {
    final cache = LocalAttachmentPreviewCache(
      rootDirectoryProvider: () async => root,
      identityProvider: const FixedAttachmentPreviewIdentityProvider('hash_missing'),
      thumbnailGenerator: const TestCopyingAttachmentThumbnailGenerator(),
    );
    final source = File('${root.path}${Platform.pathSeparator}source.png');
    await source.writeAsBytes(<int>[1]);
    await cache.rememberPending(
      conversationId: 'conv_1',
      clientMessageId: 'client_1',
      attachmentIndex: 0,
      draft: DraftAttachment(localPath: source.path, name: 'source.png', mimeType: 'image/png', kind: AttachmentKind.image, sizeBytes: 1),
    );
    await cache.bindCommitted(
      conversationId: 'conv_1',
      clientMessageId: 'client_1',
      attachments: const <CommittedAttachment>[
        CommittedAttachment(id: 'att_0', name: 'source.png', kind: AttachmentKind.image, mimeType: 'image/png', sizeBytes: 1, handling: AttachmentHandling.native),
      ],
    );
    final record = (await cache.recordsForTest()).single;
    await File(record.cachePath!).delete();

    final resolved = await cache.resolve(
      conversationId: 'conv_1',
      attachment: const CommittedAttachment(id: 'att_0', name: 'source.png', kind: AttachmentKind.image, mimeType: 'image/png', sizeBytes: 1, handling: AttachmentHandling.native),
    );
    expect(resolved, isNull);
  });
}

class FixedAttachmentPreviewIdentityProvider
    implements AttachmentPreviewIdentityProvider {
  const FixedAttachmentPreviewIdentityProvider(this.hash);

  final String hash;

  @override
  Future<String> contentHashForFile(String path) async => hash;
}

class SequenceAttachmentPreviewIdentityProvider
    implements AttachmentPreviewIdentityProvider {
  SequenceAttachmentPreviewIdentityProvider(this.hashes);

  final List<String> hashes;
  int _next = 0;

  @override
  Future<String> contentHashForFile(String path) async => hashes[_next++];
}

class TestCopyingAttachmentThumbnailGenerator
    implements AttachmentThumbnailGenerator {
  const TestCopyingAttachmentThumbnailGenerator();

  @override
  Future<GeneratedAttachmentThumbnail> generate({
    required DraftAttachment draft,
    required Directory outputDirectory,
    required String contentHash,
  }) async {
    final target =
        File('${outputDirectory.path}${Platform.pathSeparator}$contentHash.png');
    await File(draft.localPath).copy(target.path);
    return GeneratedAttachmentThumbnail(file: target, width: 1, height: 1);
  }
}

class FailingThenCopyingThumbnailGenerator
    implements AttachmentThumbnailGenerator {
  int calls = 0;

  @override
  Future<GeneratedAttachmentThumbnail> generate({
    required DraftAttachment draft,
    required Directory outputDirectory,
    required String contentHash,
  }) async {
    calls += 1;
    if (calls == 1) {
      throw const FileSystemException('test thumbnail failure');
    }
    return const TestCopyingAttachmentThumbnailGenerator().generate(
      draft: draft,
      outputDirectory: outputDirectory,
      contentHash: contentHash,
    );
  }
}
```

- [ ] **Step 2: Run cache tests and verify they fail**

Run:

```powershell
$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test test\attachment_preview_cache_test.dart -r expanded
```

Expected: compilation fails because `attachment_preview_cache.dart` does not exist.

- [ ] **Step 3: Create cache service skeleton and state model**

Create `mobile/lib/src/ui/features/workbench/attachments/attachment_preview_cache.dart` with these public types:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../domain/models/attachment_types.dart';
import '../../../../models/protocol.dart';
import 'draft_attachment.dart';

enum AttachmentPreviewCacheState { pending, ready, failed }

class AttachmentPreviewIdentity {
  const AttachmentPreviewIdentity({
    required this.contentHash,
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
    required this.attachmentIndex,
  });

  final String contentHash;
  final String name;
  final String mimeType;
  final int sizeBytes;
  final int attachmentIndex;
}

class CachedAttachmentPreview {
  const CachedAttachmentPreview({
    required this.attachmentId,
    required this.contentHash,
    required this.cachePath,
    required this.width,
    required this.height,
    required this.mimeType,
    required this.sizeBytes,
    required this.createdAt,
    required this.lastAccessedAt,
  });

  final String attachmentId;
  final String contentHash;
  final String cachePath;
  final int width;
  final int height;
  final String mimeType;
  final int sizeBytes;
  final DateTime createdAt;
  final DateTime lastAccessedAt;
}

class AttachmentPreviewCacheRecord {
  const AttachmentPreviewCacheRecord({
    required this.conversationId,
    required this.clientMessageId,
    required this.contentHash,
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
    required this.attachmentIndex,
    required this.state,
    required this.createdAt,
    this.attachmentId,
    this.cachePath,
    this.width,
    this.height,
    this.draftLocalPath,
    this.failureCode,
    this.orphanedAt,
    this.committedAt,
    this.lastAccessedAt,
    this.lastAttemptedAt,
  });

  final String conversationId;
  final String clientMessageId;
  final String contentHash;
  final String name;
  final String mimeType;
  final int sizeBytes;
  final int attachmentIndex;
  final AttachmentPreviewCacheState state;
  final DateTime createdAt;
  final String? attachmentId;
  final String? cachePath;
  final int? width;
  final int? height;
  final String? draftLocalPath;
  final String? failureCode;
  final DateTime? orphanedAt;
  final DateTime? committedAt;
  final DateTime? lastAccessedAt;
  final DateTime? lastAttemptedAt;
}

abstract class AttachmentPreviewCache {
  Future<AttachmentPreviewIdentity> rememberPending({
    required String conversationId,
    required String clientMessageId,
    required int attachmentIndex,
    required DraftAttachment draft,
  });

  Future<void> bindCommitted({
    required String conversationId,
    required String clientMessageId,
    required List<CommittedAttachment> attachments,
  });

  Future<CachedAttachmentPreview?> resolve({
    required String conversationId,
    required CommittedAttachment attachment,
  });

  Future<void> markClientMessageOrphaned({
    required String conversationId,
    required String clientMessageId,
  });
}
```

Also add `NoopAttachmentPreviewCache` returning misses. Tests can use this for unrelated ViewModel coverage.

- [ ] **Step 4: Implement LocalAttachmentPreviewCache**

In the same file:

```dart
typedef PreviewRootDirectoryProvider = Future<Directory> Function();

abstract class AttachmentPreviewIdentityProvider {
  Future<String> contentHashForFile(String path);
}

class Sha256AttachmentPreviewIdentityProvider
    implements AttachmentPreviewIdentityProvider {
  const Sha256AttachmentPreviewIdentityProvider();

  @override
  Future<String> contentHashForFile(String path) =>
      compute(_sha256FileByPath, path);
}

Future<String> _sha256FileByPath(String path) async {
  final digest = await sha256.bind(File(path).openRead()).first;
  return digest.toString();
}

abstract class AttachmentThumbnailGenerator {
  Future<GeneratedAttachmentThumbnail> generate({
    required DraftAttachment draft,
    required Directory outputDirectory,
    required String contentHash,
  });
}

class GeneratedAttachmentThumbnail {
  const GeneratedAttachmentThumbnail({
    required this.file,
    required this.width,
    required this.height,
  });

  final File file;
  final int width;
  final int height;
}

class BoundedAttachmentThumbnailGenerator
    implements AttachmentThumbnailGenerator {
  const BoundedAttachmentThumbnailGenerator({this.longestEdge = 640});

  final int longestEdge;

  @override
  Future<GeneratedAttachmentThumbnail> generate({
    required DraftAttachment draft,
    required Directory outputDirectory,
    required String contentHash,
  }) async {
    final sourceBytes = await File(draft.localPath).readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(
      Uint8List.fromList(sourceBytes),
    );
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final sourceWidth = descriptor.width;
    final sourceHeight = descriptor.height;
    final scale = sourceWidth >= sourceHeight
        ? longestEdge / sourceWidth
        : longestEdge / sourceHeight;
    final targetWidth = scale < 1
        ? (sourceWidth * scale).round().clamp(1, sourceWidth)
        : sourceWidth;
    final targetHeight = scale < 1
        ? (sourceHeight * scale).round().clamp(1, sourceHeight)
        : sourceHeight;
    final codec = await descriptor.instantiateCodec(
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    try {
      final frame = await codec.getNextFrame();
      try {
        final byteData =
            await frame.image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData == null) {
          throw const FileSystemException('thumbnail encoding returned null');
        }
        final target = File(
          '${outputDirectory.path}${Platform.pathSeparator}$contentHash.png',
        );
        await target.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
        return GeneratedAttachmentThumbnail(
          file: target,
          width: targetWidth,
          height: targetHeight,
        );
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
    }
  }
}
```

Implement `LocalAttachmentPreviewCache` with:

```dart
class LocalAttachmentPreviewCache implements AttachmentPreviewCache {
  LocalAttachmentPreviewCache({
    PreviewRootDirectoryProvider? rootDirectoryProvider,
    AttachmentPreviewIdentityProvider identityProvider =
        const Sha256AttachmentPreviewIdentityProvider(),
    AttachmentThumbnailGenerator thumbnailGenerator =
        const BoundedAttachmentThumbnailGenerator(),
    DateTime Function()? now,
    int maxBytes = 100 * 1024 * 1024,
    int maxRecords = 500,
  })  : _rootDirectoryProvider = rootDirectoryProvider ?? _defaultRoot,
        _identityProvider = identityProvider,
        _thumbnailGenerator = thumbnailGenerator,
        _now = now ?? DateTime.now,
        _maxBytes = maxBytes,
        _maxRecords = maxRecords;

  final PreviewRootDirectoryProvider _rootDirectoryProvider;
  final AttachmentPreviewIdentityProvider _identityProvider;
  final AttachmentThumbnailGenerator _thumbnailGenerator;
  final DateTime Function() _now;
  final int _maxBytes;
  final int _maxRecords;
  Future<void> _writeQueue = Future<void>.value();

  static Future<Directory> _defaultRoot() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}${Platform.pathSeparator}attachment_previews');
  }
}
```

Use a queue helper like this for every index read-modify-write path, then write JSON through `index.json.tmp` and `rename('index.json')`:

```dart
Future<T> _serialized<T>(Future<T> Function() action) {
  final operation = _writeQueue.then((_) => action());
  _writeQueue = operation.then<void>((_) {}, onError: (_) {});
  return operation;
}
```

- [ ] **Step 5: Run cache tests**

Run:

```powershell
$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test test\attachment_preview_cache_test.dart -r expanded
```

Expected: cache tests pass.

- [ ] **Step 6: Commit cache service**

```powershell
git add mobile\lib\src\ui\features\workbench\attachments\attachment_preview_cache.dart mobile\test\attachment_preview_cache_test.dart
git commit -m "Add mobile attachment preview cache"
```

---

### Task 4: Wire Cache Into Workbench ViewModel

**Files:**
- Modify: `mobile/lib/src/ui/features/workbench/workbench_dependencies.dart`
- Modify: `mobile/lib/src/app/app_dependencies.dart`
- Modify: `mobile/lib/src/ui/features/workbench/workbench.dart`
- Modify: `mobile/lib/src/ui/features/workbench/view_models/workbench_view_model.dart`
- Modify: `mobile/test/adapter_model_test.dart`
- Modify: `mobile/test/coding_workbench_controller_test.dart`

- [ ] **Step 1: Add fake cache tests for ViewModel send and replay**

In `mobile/test/adapter_model_test.dart`, add a fake cache class near `_FakeConversationRepository`:

```dart
class _FakeAttachmentPreviewCache implements AttachmentPreviewCache {
  final remembered = <String>[];
  final bound = <String>[];
  final resolved = <String, String>{};

  @override
  Future<AttachmentPreviewIdentity> rememberPending({
    required String conversationId,
    required String clientMessageId,
    required int attachmentIndex,
    required DraftAttachment draft,
  }) async {
    remembered.add('$conversationId|$clientMessageId|$attachmentIndex|${draft.name}');
    return AttachmentPreviewIdentity(
      contentHash: 'hash_${draft.name}',
      name: draft.name,
      mimeType: draft.mimeType,
      sizeBytes: draft.sizeBytes,
      attachmentIndex: attachmentIndex,
    );
  }

  @override
  Future<void> bindCommitted({
    required String conversationId,
    required String clientMessageId,
    required List<CommittedAttachment> attachments,
  }) async {
    bound.add('$conversationId|$clientMessageId|${attachments.map((item) => item.id).join(',')}');
  }

  @override
  Future<CachedAttachmentPreview?> resolve({
    required String conversationId,
    required CommittedAttachment attachment,
  }) async {
    final path = resolved[attachment.id];
    if (path == null) return null;
    return CachedAttachmentPreview(
      attachmentId: attachment.id,
      contentHash: 'hash_${attachment.name}',
      cachePath: path,
      width: 1,
      height: 1,
      mimeType: attachment.mimeType,
      sizeBytes: attachment.sizeBytes,
      createdAt: DateTime.parse('2026-05-22T00:00:00.000Z'),
      lastAccessedAt: DateTime.parse('2026-05-22T00:00:00.000Z'),
    );
  }

  @override
  Future<void> markClientMessageOrphaned({
    required String conversationId,
    required String clientMessageId,
  }) async {}
}
```

Update the existing `existing conversation send forwards draft attachment metadata` test to pass `_FakeAttachmentPreviewCache`, then assert:

```dart
expect(cache.remembered.single, startsWith('conv_1|'));
expect(cache.remembered.single, contains('|0|screenshot.png'));
```

- [ ] **Step 2: Add committed replay bind/resolve test**

In `mobile/test/coding_workbench_controller_test.dart`, replace the old local preview memory expectation with a cache-backed test:

```dart
test('committed attachment event resolves cached preview through cache service', () async {
  final cache = _FakeAttachmentPreviewCache()
    ..resolved['att_0'] = r'C:\cache\screenshot.png';
  final repository = _FakeConversationRepository();
  final viewModel = WorkbenchViewModel(
    initialData: _snapshot(
      workspaces: const <WorkspaceSummary>[_workspace],
      adapters: const <AdapterStatus>[_codexAdapter],
    ),
    conversationRepository: repository,
    attachmentPreviewCache: cache,
  );
  viewModel.updateActiveConversation(_conversation(
      id: 'conv_1', workspaceId: _workspace.id, status: 'sending'));
  viewModel.addDraftAttachmentForTest(const DraftAttachment(
    localPath: r'C:\tmp\screenshot.png',
    name: 'screenshot.png',
    mimeType: 'image/png',
    kind: AttachmentKind.image,
    sizeBytes: 42,
  ));

  await viewModel.sendExistingConversationPrompt(
    conversationId: 'conv_1',
    prompt: 'inspect image',
  );
  final clientMessageId = repository.sentRequests.single.clientMessageId!;
  await viewModel.applyConversationEventsAsync(<ConversationEvent>[
    ConversationEvent(
      seq: 1,
      conversationId: 'conv_1',
      type: 'user.message',
      createdAt: DateTime.parse('2026-05-12T00:00:01.000Z'),
      text: 'inspect image',
      raw: <String, Object?>{'clientMessageId': clientMessageId},
      attachments: const <CommittedAttachment>[
        CommittedAttachment(id: 'att_0', name: 'screenshot.png', kind: AttachmentKind.image, mimeType: 'image/png', sizeBytes: 42, handling: AttachmentHandling.native),
      ],
    ),
  ], streamOutput: false);

  expect(cache.bound.single, 'conv_1|$clientMessageId|att_0');
  expect(viewModel.messages.single.attachments.single.localPath,
      r'C:\cache\screenshot.png');
});
```

- [ ] **Step 3: Run ViewModel tests and verify they fail**

Run:

```powershell
$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test test\adapter_model_test.dart test\coding_workbench_controller_test.dart -r expanded
```

Expected: compilation failures because ViewModel has no `attachmentPreviewCache` and no async event-apply method.

- [ ] **Step 4: Inject cache through dependencies**

Update `mobile/lib/src/ui/features/workbench/workbench_dependencies.dart`:

```dart
import 'attachments/attachment_preview_cache.dart';

class WorkbenchDependencies {
  const WorkbenchDependencies({
    required this.adapterRepository,
    required this.asrModelManager,
    required this.conversationRepository,
    required this.diagnosticsRepository,
    required this.runRepository,
    required this.speechInputServiceBuilder,
    required this.workspaceRepository,
    required this.attachmentPreviewCache,
  });

  final AttachmentPreviewCache attachmentPreviewCache;
}
```

Update `mobile/lib/src/app/app_dependencies.dart`:

```dart
import '../ui/features/workbench/attachments/attachment_preview_cache.dart';

// Inside WorkbenchDependencies construction:
attachmentPreviewCache: LocalAttachmentPreviewCache(),
```

Update `mobile/lib/src/ui/features/workbench/coding_workbench_page.dart` where `WorkbenchViewModel` is created:

```dart
_workbenchViewModel = WorkbenchViewModel(
  initialData: widget.data,
  conversationRepository: widget.dependencies.conversationRepository,
  diagnosticsRepository: widget.dependencies.diagnosticsRepository,
  runRepository: widget.dependencies.runRepository,
  workspaceRepository: widget.dependencies.workspaceRepository,
  attachmentPreviewCache: widget.dependencies.attachmentPreviewCache,
)..addListener(_syncWorkbenchViewModel);
```

- [ ] **Step 5: Make send request building async and prepare pending cache before send**

In `WorkbenchViewModel`:

```dart
final AttachmentPreviewCache _attachmentPreviewCache;

WorkbenchViewModel({
  required AppSnapshot initialData,
  ConversationRepository? conversationRepository,
  DiagnosticsRepository? diagnosticsRepository,
  RunRepository? runRepository,
  WorkspaceRepository? workspaceRepository,
  AttachmentPreviewCache attachmentPreviewCache = const NoopAttachmentPreviewCache(),
  Duration workspaceCreationTimeout = const Duration(seconds: 20),
})  : _attachmentPreviewCache = attachmentPreviewCache,
      _conversationRepository = conversationRepository,
      _diagnosticsRepository = diagnosticsRepository,
      _runRepository = runRepository,
      _workspaceRepository = workspaceRepository,
      _workspaceCreationTimeout = workspaceCreationTimeout,
      _routeState = WorkspaceListRouteState(
        workspaces: List.unmodifiable(initialData.workspaces),
      ),
      _adapters = List<AdapterStatus>.unmodifiable(initialData.adapters),
      _selectedAdapter = _computePreferredAdapter(initialData.adapters),
      _draftModel = _initialSelectedModel(initialData.adapters);
```

Change `_buildConversationMessageRequest`:

```dart
Future<ConversationMessageSendRequest> _buildConversationMessageRequest(
  String conversationId,
  String prompt,
) async {
  final attachments = _draftAttachments
      .where((item) => item.isValid)
      .map((item) => ConversationMessageAttachment(
            localPath: item.localPath,
            name: item.name,
            mimeType: item.mimeType,
            kind: item.kind,
            sizeBytes: item.sizeBytes,
          ))
      .toList(growable: false);
  if (attachments.isEmpty) {
    return ConversationMessageSendRequest(text: prompt);
  }
  _currentAttachmentClientMessageId ??= _generateUuidV4();
  final clientMessageId = _currentAttachmentClientMessageId!;
  for (var index = 0; index < _draftAttachments.length; index += 1) {
    final draft = _draftAttachments[index];
    if (!draft.isValid || draft.kind != AttachmentKind.image) continue;
    await _attachmentPreviewCache.rememberPending(
      conversationId: conversationId,
      clientMessageId: clientMessageId,
      attachmentIndex: index,
      draft: draft,
    );
  }
  return ConversationMessageSendRequest(
    text: prompt,
    clientMessageId: clientMessageId,
    capabilityVersion: selectedAdapterStatus?.capabilityVersion,
    attachments: attachments,
  );
}
```

Update caller:

```dart
final request = await _buildConversationMessageRequest(conversationId, prompt);
```

- [ ] **Step 6: Bind and resolve committed attachments asynchronously**

Add:

```dart
Future<bool> applyConversationEventsAsync(
  List<ConversationEvent> events, {
  required bool streamOutput,
  bool notify = true,
}) async {
  final changed = applyConversationEvents(
    events,
    streamOutput: streamOutput,
    notify: false,
  );
  if (!changed) return false;
  final previewChanged = await _bindAndResolveAttachmentPreviews(events);
  if (notify && (changed || previewChanged)) notifyListeners();
  return changed || previewChanged;
}

Future<bool> _bindAndResolveAttachmentPreviews(
    Iterable<ConversationEvent> events) async {
  var previewChanged = false;
  for (final event in events) {
    if (event.type != 'user.message' || event.attachments.isEmpty) continue;
    final clientMessageId = event.raw['clientMessageId'] as String?;
    if (clientMessageId == null || clientMessageId.isEmpty) continue;
    await _attachmentPreviewCache.bindCommitted(
      conversationId: event.conversationId,
      clientMessageId: clientMessageId,
      attachments: event.attachments,
    );
    previewChanged = true;
  }
  final resolved = <WorkbenchMessage>[];
  for (final message in _messages) {
    if (message.role != 'user' || message.attachments.isEmpty) {
      resolved.add(message);
      continue;
    }
    final attachments = <CommittedAttachment>[];
    for (final attachment in message.attachments) {
      final activeConversationId = _activeConversationId;
      if (attachment.kind != AttachmentKind.image ||
          activeConversationId == null) {
        attachments.add(attachment);
        continue;
      }
      final cached = await _attachmentPreviewCache.resolve(
        conversationId: activeConversationId,
        attachment: attachment,
      );
      attachments.add(cached == null
          ? attachment.copyWith(clearLocalPath: true)
          : attachment.copyWith(localPath: cached.cachePath));
    }
    resolved.add(message.copyWith(attachments: attachments));
  }
  if (_sameWorkbenchAttachmentPaths(_messages, resolved)) return previewChanged;
  _messages
    ..clear()
    ..addAll(resolved);
  return true;
}

bool _sameWorkbenchAttachmentPaths(
  List<WorkbenchMessage> left,
  List<WorkbenchMessage> right,
) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i += 1) {
    final leftAttachments = left[i].attachments;
    final rightAttachments = right[i].attachments;
    if (leftAttachments.length != rightAttachments.length) return false;
    for (var j = 0; j < leftAttachments.length; j += 1) {
      if (leftAttachments[j].localPath != rightAttachments[j].localPath) {
        return false;
      }
    }
  }
  return true;
}
```

Then update `CodingWorkbenchPage._pollEvents()` to avoid `await` inside `setState`:

```dart
final changed = await _workbenchViewModel.applyConversationEventsAsync(
  conversationEvents,
  streamOutput: widget.streamOutput,
  notify: false,
);
final cancelledAfterApply = !mounted ||
    conversationId != _activeConversationId ||
    runId != _activeRunId;
if (cancelledAfterApply) {
  recordPollTrace(
      returnedCount: conversationEvents.length,
      cancelled: true,
      changed: changed);
  return;
}
if (mounted) setState(() {});
if (changed) _scrollToBottom();
```

- [ ] **Step 7: Remove in-memory preview maps**

Delete these fields and helpers from `WorkbenchViewModel`:

```dart
final Map<String, String> _localAttachmentPreviewPaths = <String, String>{};
final Map<String, List<CommittedAttachment>> _localAttachmentPreviewsByClientMessageId = <String, List<CommittedAttachment>>{};
List<CommittedAttachment> _draftAttachmentPreviews()
List<CommittedAttachment> _mergeLocalAttachmentPreviews(
  List<CommittedAttachment> committed,
  List<CommittedAttachment> optimistic,
  String? clientMessageId,
)
String? _matchingLocalPreviewPath(
  CommittedAttachment attachment,
  List<CommittedAttachment> optimistic, {
  required int index,
  required String? clientMessageId,
})
void _rememberLocalAttachmentPreviews(List<CommittedAttachment> attachments)
void _rememberLocalAttachmentPreviewsForClientMessage(
  String clientMessageId,
  List<CommittedAttachment> attachments,
)
bool _isCompatibleAttachmentPreview(
  CommittedAttachment committed,
  CommittedAttachment localPreview,
)
bool _sameAttachmentPreviewPaths(
  List<CommittedAttachment> left,
  List<CommittedAttachment> right,
)
String _attachmentPreviewKey(CommittedAttachment attachment)
```

- [ ] **Step 8: Run ViewModel tests**

Run:

```powershell
$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test test\adapter_model_test.dart test\coding_workbench_controller_test.dart -r expanded
```

Expected: both test files pass.

- [ ] **Step 9: Commit ViewModel integration**

```powershell
git add mobile\lib\src\ui\features\workbench\workbench_dependencies.dart mobile\lib\src\app\app_dependencies.dart mobile\lib\src\ui\features\workbench\workbench.dart mobile\lib\src\ui\features\workbench\view_models\workbench_view_model.dart mobile\test\adapter_model_test.dart mobile\test\coding_workbench_controller_test.dart
git commit -m "Use mobile cache for attachment previews"
```

---

### Task 5: Update Attachment Preview UI To Cache-Only

**Files:**
- Modify: `mobile/lib/src/ui/features/workbench/workbench_event_cards.dart`
- Modify: `mobile/test/widget_test.dart`

- [ ] **Step 1: Update widget tests**

In `mobile/test/widget_test.dart`:

1. Keep `user message card splits image attachment and text preview`, but construct the attachment directly instead of `fromJson`:

```dart
const CommittedAttachment(
  id: 'att_0',
  name: 'screenshot.png',
  kind: AttachmentKind.image,
  mimeType: 'image/png',
  sizeBytes: 1219716,
  handling: AttachmentHandling.native,
  localPath: imageFile.path,
)
```

2. Replace `user message card renders persisted image preview without frame` with a cache-miss fallback test:

```dart
testWidgets('user message card falls back to file card when image preview is missing',
    (WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
      supportedLocales: appSupportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
      theme: theme.buildAppTheme(),
      home: Scaffold(
          backgroundColor: theme.bg,
          body: Padding(
              padding: const EdgeInsets.all(16),
              child: WorkbenchMessageCard(
                  message: WorkbenchMessage(
                    'user',
                    'You',
                    'cache miss',
                    attachments: const <CommittedAttachment>[
                      CommittedAttachment(
                        id: 'att_0',
                        name: 'persisted.png',
                        kind: AttachmentKind.image,
                        mimeType: 'image/png',
                        sizeBytes: 1219716,
                        handling: AttachmentHandling.native,
                      ),
                    ],
                  ),
                  onApproval: (_) {},
                  onSuggestion: (_) {},
                  expandThinking: false)))));

  expect(find.text('cache miss'), findsOneWidget);
  expect(find.text('persisted.png'), findsOneWidget);
  expect(find.byKey(const Key('workbench-user-attachment-bubble')),
      findsOneWidget);
  expect(find.byKey(const Key('workbench-message-image-preview')), findsNothing);
  expect(find.byIcon(Icons.image_outlined), findsWidgets);
});
```

3. Add an eviction race test:

```dart
testWidgets('image attachment viewer does not open after cached file is evicted',
    (WidgetTester tester) async {
  final tempDir = Directory.systemTemp.createTempSync('workbench-evict-test-');
  addTearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });
  final imageFile = File('${tempDir.path}${Platform.pathSeparator}evicted.png')
    ..writeAsBytesSync(<int>[0x00]);

  await tester.pumpWidget(MaterialApp(
      supportedLocales: appSupportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
      theme: theme.buildAppTheme(),
      home: Scaffold(
          backgroundColor: theme.bg,
          body: Padding(
              padding: const EdgeInsets.all(16),
              child: WorkbenchMessageCard(
                  message: WorkbenchMessage(
                    'user',
                    'You',
                    'open',
                    attachments: <CommittedAttachment>[
                      CommittedAttachment(
                        id: 'att_0',
                        name: 'evicted.png',
                        kind: AttachmentKind.image,
                        mimeType: 'image/png',
                        sizeBytes: 1,
                        handling: AttachmentHandling.native,
                        localPath: imageFile.path,
                      ),
                    ],
                  ),
                  onApproval: (_) {},
                  onSuggestion: (_) {},
                  expandThinking: false)))));
  await imageFile.delete();

  await tester.tap(find.byKey(const Key('workbench-message-image-preview-shell')));
  await tester.pumpAndSettle();

  expect(find.byKey(const Key('workbench-message-image-viewer')), findsNothing);
});
```

- [ ] **Step 2: Run widget tests and verify failure**

Run:

```powershell
$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test test\widget_test.dart -r expanded --plain-name "user message card"
```

Expected: failures because UI still has a network preview branch and opens viewer without checking file existence.

- [ ] **Step 3: Remove network preview branch**

In `mobile/lib/src/ui/features/workbench/workbench_event_cards.dart`, update `_attachmentPreviewImage`:

```dart
Widget _attachmentPreviewImage(
  CommittedAttachment attachment, {
  Key? key,
  BoxFit fit = BoxFit.cover,
  double errorIconSize = 18,
}) {
  Widget errorBuilder(
          BuildContext context, Object error, StackTrace? stackTrace) =>
      Icon(_attachmentIcon(attachment.kind),
          color: theme.muted, size: errorIconSize);

  final localPath = attachment.localPath;
  if (localPath != null && File(localPath).existsSync()) {
    return Image.file(
      File(localPath),
      key: key,
      fit: fit,
      errorBuilder: errorBuilder,
    );
  }
  return Icon(_attachmentIcon(attachment.kind),
      key: key, color: theme.muted, size: errorIconSize);
}
```

Insert this guard at the top of `_showImageAttachmentViewer` and leave the existing dialog body after it:

```dart
final localPath = attachment.localPath;
if (localPath == null || !File(localPath).existsSync()) return;
```

Render `_MessageImageAttachmentPreview` only when `attachment.hasImagePreview` is true. Cache miss should go through the existing compact attachment chip/card path.

- [ ] **Step 4: Run widget tests**

Run:

```powershell
$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test test\widget_test.dart -r expanded --plain-name "user message card"
```

Expected: user message card tests pass.

- [ ] **Step 5: Commit UI cleanup**

```powershell
git add mobile\lib\src\ui\features\workbench\workbench_event_cards.dart mobile\test\widget_test.dart
git commit -m "Render attachment previews from local cache only"
```

---

### Task 6: Final Verification And Architecture Checks

**Files:**
- No source edits expected unless a check finds a real issue.

- [ ] **Step 1: Run daemon regression tests**

Run from repo root:

```powershell
node scripts\run-tests.js
```

Expected: all daemon tests pass.

- [ ] **Step 2: Run JavaScript lint**

Run:

```powershell
npm run lint
```

Expected: lint passes.

- [ ] **Step 3: Run Flutter architecture check**

Run from `mobile/`:

```powershell
$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
dart run tool\check_architecture_imports.dart
```

Expected: `No forbidden imports found`.

- [ ] **Step 4: Run focused Flutter tests**

Run from `mobile/`:

```powershell
$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test test\attachment_preview_cache_test.dart test\daemon_client_test.dart test\protocol_compatibility_test.dart test\adapter_model_test.dart test\coding_workbench_controller_test.dart -r expanded
```

Expected: all focused tests pass.

- [ ] **Step 5: Run widget attachment preview tests**

Run from `mobile/`:

```powershell
$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test test\widget_test.dart -r expanded --plain-name "user message card"
```

Expected: user message card tests pass.

- [ ] **Step 6: Run Dart analysis**

Run from `mobile/`:

```powershell
$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
dart analyze lib test
```

Expected: no issues.

- [ ] **Step 7: Run final diff hygiene**

Run from repo root:

```powershell
git diff --check
git status -sb --untracked-files=all
```

Expected: no whitespace errors and only intended tracked source/test/doc changes.

- [ ] **Step 8: Commit any verification-only fixes**

If verification uncovered real fixes, commit them with a focused message:

```powershell
git add <changed-files>
git commit -m "Stabilize attachment preview cache integration"
```

If no fixes were required, do not create an empty commit.

---

## Self-Review

- Spec coverage: daemon preview storage removal is covered in Task 1; hard removal of `previewPath`/`previewUrl` is covered in Task 2; mobile cache identity/state/orphan/miss behavior is covered in Task 3; ViewModel pending/bind/resolve flow is covered in Task 4; cache-only UI and eviction race are covered in Task 5; verification commands are covered in Task 6.
- Placeholder scan: no placeholder sections are intentionally left for the executor; every task names exact files and commands.
- Type consistency: `AttachmentPreviewIdentity`, `AttachmentPreviewCacheRecord`, `CachedAttachmentPreview`, `AttachmentPreviewCache`, `LocalAttachmentPreviewCache`, `NoopAttachmentPreviewCache`, and `AttachmentPreviewCacheState` are introduced in Task 3 and reused consistently afterward.
- Risk note: the first implementation uses a copied local image as the cached preview file to avoid adding a new image-processing dependency. The cache API keeps this replaceable so a later thumbnail-resizing generator can be added without changing daemon/mobile protocol boundaries.
