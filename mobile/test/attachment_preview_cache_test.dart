import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/data/models/attachment_models.dart';
import 'package:lan_ai_cli_control/src/ui/features/workbench/attachments/attachment_preview_cache.dart';
import 'package:lan_ai_cli_control/src/ui/features/workbench/attachments/draft_attachment.dart';

void main() {
  test('rememberPending writes pending record before binding', () async {
    final fixture = await AttachmentPreviewCacheFixture.create(
      identityProvider: FixedAttachmentPreviewIdentityProvider('hash_ready'),
      thumbnailGenerator: TestCopyingAttachmentThumbnailGenerator(),
    );

    final draft = await fixture.createDraft(name: 'image-a.png', bytes: 'a');

    final identity = await fixture.cache.rememberPending(
      conversationId: 'conversation-1',
      clientMessageId: 'client-1',
      attachmentIndex: 2,
      draft: draft,
    );

    expect(identity.contentHash, 'hash_ready');

    final records = await fixture.cache.recordsForTest();
    expect(records, hasLength(1));
    expect(records.single.state, AttachmentPreviewCacheState.ready);
    expect(records.single.clientMessageId, 'client-1');
    expect(records.single.attachmentIndex, 2);
    expect(records.single.cachePath, isNotNull);
    expect(await File(records.single.cachePath!).exists(), isTrue);
  });

  test('bindCommitted uses hash instead of attachment index', () async {
    final generator = TestCopyingAttachmentThumbnailGenerator();
    final fixture = await AttachmentPreviewCacheFixture.create(
      identityProvider: SequenceAttachmentPreviewIdentityProvider(
        const <String>['hash_a', 'hash_b'],
      ),
      thumbnailGenerator: generator,
    );

    final draftA = await fixture.createDraft(name: 'image-a.png', bytes: 'a');
    final draftB = await fixture.createDraft(name: 'image-b.png', bytes: 'b');

    await fixture.cache.rememberPending(
      conversationId: 'conversation-1',
      clientMessageId: 'client-1',
      attachmentIndex: 0,
      draft: draftA,
    );
    await fixture.cache.rememberPending(
      conversationId: 'conversation-1',
      clientMessageId: 'client-1',
      attachmentIndex: 1,
      draft: draftB,
    );

    final committedB = committedAttachment(
      id: 'attachment-b',
      name: draftB.name,
      mimeType: draftB.mimeType,
      sizeBytes: draftB.sizeBytes,
    );
    final committedA = committedAttachment(
      id: 'attachment-a',
      name: draftA.name,
      mimeType: draftA.mimeType,
      sizeBytes: draftA.sizeBytes,
    );

    await fixture.cache.bindCommitted(
      conversationId: 'conversation-1',
      clientMessageId: 'client-1',
      attachments: <CommittedAttachment>[committedB, committedA],
    );

    final resolvedB = await fixture.cache.resolve(
      conversationId: 'conversation-1',
      attachment: committedB,
    );
    final resolvedA = await fixture.cache.resolve(
      conversationId: 'conversation-1',
      attachment: committedA,
    );

    expect(resolvedB, isNotNull);
    expect(resolvedB!.contentHash, 'hash_b');
    expect(resolvedA, isNotNull);
    expect(resolvedA!.contentHash, 'hash_a');
    expect(generator.calls, 2);
  });

  test('bindCommitted binds image identity after a non-image attachment',
      () async {
    final fixture = await AttachmentPreviewCacheFixture.create(
      identityProvider: FixedAttachmentPreviewIdentityProvider('hash_image'),
      thumbnailGenerator: TestCopyingAttachmentThumbnailGenerator(),
    );

    final imageDraft = await fixture.createDraft(
      name: 'image.png',
      bytes: 'image',
    );
    final imageIdentity = await fixture.cache.rememberPending(
      conversationId: 'conversation-1',
      clientMessageId: 'client-1',
      attachmentIndex: 0,
      draft: imageDraft,
    );

    final committedPdf = committedAttachment(
      id: 'attachment-pdf',
      name: 'document.pdf',
      kind: AttachmentKind.pdf,
      mimeType: 'application/pdf',
      sizeBytes: 4096,
      handling: AttachmentHandling.unsupported,
    );
    final committedImage = committedAttachment(
      id: 'attachment-image',
      name: imageDraft.name,
      mimeType: imageDraft.mimeType,
      sizeBytes: imageDraft.sizeBytes,
    );

    await fixture.cache.bindCommitted(
      conversationId: 'conversation-1',
      clientMessageId: 'client-1',
      attachments: <CommittedAttachment>[committedPdf, committedImage],
      pendingIdentities: <AttachmentPreviewIdentity>[imageIdentity],
    );

    final resolvedPdf = await fixture.cache.resolve(
      conversationId: 'conversation-1',
      attachment: committedPdf,
    );
    final resolvedImage = await fixture.cache.resolve(
      conversationId: 'conversation-1',
      attachment: committedImage,
    );

    expect(resolvedPdf, isNull);
    expect(resolvedImage, isNotNull);
    expect(resolvedImage!.contentHash, 'hash_image');
  });

  test('bindCommitted uses distinct pending identity metadata out of order',
      () async {
    final generator = TestCopyingAttachmentThumbnailGenerator();
    final fixture = await AttachmentPreviewCacheFixture.create(
      identityProvider: SequenceAttachmentPreviewIdentityProvider(
        const <String>['hash_a', 'hash_b'],
      ),
      thumbnailGenerator: generator,
    );

    final draftA = await fixture.createDraft(name: 'image-a.png', bytes: 'a');
    final draftB = await fixture.createDraft(name: 'image-b.png', bytes: 'bb');

    final identityA = await fixture.cache.rememberPending(
      conversationId: 'conversation-1',
      clientMessageId: 'client-1',
      attachmentIndex: 0,
      draft: draftA,
    );
    final identityB = await fixture.cache.rememberPending(
      conversationId: 'conversation-1',
      clientMessageId: 'client-1',
      attachmentIndex: 1,
      draft: draftB,
    );

    final committedB = committedAttachment(
      id: 'attachment-b',
      name: draftB.name,
      mimeType: draftB.mimeType,
      sizeBytes: draftB.sizeBytes,
    );
    final committedA = committedAttachment(
      id: 'attachment-a',
      name: draftA.name,
      mimeType: draftA.mimeType,
      sizeBytes: draftA.sizeBytes,
    );

    await fixture.cache.bindCommitted(
      conversationId: 'conversation-1',
      clientMessageId: 'client-1',
      attachments: <CommittedAttachment>[committedB, committedA],
      pendingIdentities: <AttachmentPreviewIdentity>[identityA, identityB],
    );

    final resolvedB = await fixture.cache.resolve(
      conversationId: 'conversation-1',
      attachment: committedB,
    );
    final resolvedA = await fixture.cache.resolve(
      conversationId: 'conversation-1',
      attachment: committedA,
    );

    expect(resolvedB, isNotNull);
    expect(resolvedB!.contentHash, 'hash_b');
    expect(resolvedA, isNotNull);
    expect(resolvedA!.contentHash, 'hash_a');
  });

  test('bindCommitted skips ambiguous duplicate pending identities', () async {
    final fixture = await AttachmentPreviewCacheFixture.create(
      identityProvider: SequenceAttachmentPreviewIdentityProvider(
        const <String>['hash_a', 'hash_b'],
      ),
      thumbnailGenerator: TestCopyingAttachmentThumbnailGenerator(),
    );

    final draftA = await fixture.createDraft(name: 'same.png', bytes: 'aa');
    final draftB = await fixture.createDraft(name: 'same.png', bytes: 'bb');

    final identityA = await fixture.cache.rememberPending(
      conversationId: 'conversation-1',
      clientMessageId: 'client-1',
      attachmentIndex: 0,
      draft: draftA,
    );
    final identityB = await fixture.cache.rememberPending(
      conversationId: 'conversation-1',
      clientMessageId: 'client-1',
      attachmentIndex: 1,
      draft: draftB,
    );

    final committedB = committedAttachment(
      id: 'attachment-b',
      name: draftB.name,
      mimeType: draftB.mimeType,
      sizeBytes: draftB.sizeBytes,
    );
    final committedA = committedAttachment(
      id: 'attachment-a',
      name: draftA.name,
      mimeType: draftA.mimeType,
      sizeBytes: draftA.sizeBytes,
    );

    await fixture.cache.bindCommitted(
      conversationId: 'conversation-1',
      clientMessageId: 'client-1',
      attachments: <CommittedAttachment>[committedB, committedA],
      pendingIdentities: <AttachmentPreviewIdentity>[identityB, identityA],
    );

    final resolvedB = await fixture.cache.resolve(
      conversationId: 'conversation-1',
      attachment: committedB,
    );
    final resolvedA = await fixture.cache.resolve(
      conversationId: 'conversation-1',
      attachment: committedA,
    );
    final records = await fixture.cache.recordsForTest();

    expect(resolvedB, isNull);
    expect(resolvedA, isNull);
    expect(records.map((record) => record.attachmentId), everyElement(isNull));
  });

  test('bindCommitted skips ambiguous fallback metadata matches', () async {
    final fixture = await AttachmentPreviewCacheFixture.create(
      identityProvider: SequenceAttachmentPreviewIdentityProvider(
        const <String>['hash_a', 'hash_b'],
      ),
      thumbnailGenerator: TestCopyingAttachmentThumbnailGenerator(),
    );

    final draftA = await fixture.createDraft(name: 'same.png', bytes: 'aa');
    final draftB = await fixture.createDraft(name: 'same.png', bytes: 'bb');

    await fixture.cache.rememberPending(
      conversationId: 'conversation-1',
      clientMessageId: 'client-1',
      attachmentIndex: 0,
      draft: draftA,
    );
    await fixture.cache.rememberPending(
      conversationId: 'conversation-1',
      clientMessageId: 'client-1',
      attachmentIndex: 1,
      draft: draftB,
    );

    final committed = committedAttachment(
      id: 'attachment-ambiguous',
      name: draftA.name,
      mimeType: draftA.mimeType,
      sizeBytes: draftA.sizeBytes,
    );

    await fixture.cache.bindCommitted(
      conversationId: 'conversation-1',
      clientMessageId: 'client-1',
      attachments: <CommittedAttachment>[committed],
    );

    final resolved = await fixture.cache.resolve(
      conversationId: 'conversation-1',
      attachment: committed,
    );
    final records = await fixture.cache.recordsForTest();

    expect(resolved, isNull);
    expect(records.map((record) => record.attachmentId), everyElement(isNull));
  });

  test('thumbnail failure records failed state and one retry can recover',
      () async {
    final generator = FailingThenCopyingThumbnailGenerator();
    final fixture = await AttachmentPreviewCacheFixture.create(
      identityProvider: FixedAttachmentPreviewIdentityProvider('hash_retry'),
      thumbnailGenerator: generator,
    );

    final draft = await fixture.createDraft(name: 'retry.png', bytes: 'retry');

    await fixture.cache.rememberPending(
      conversationId: 'conversation-1',
      clientMessageId: 'client-1',
      attachmentIndex: 0,
      draft: draft,
    );

    var records = await fixture.cache.recordsForTest();
    expect(records.single.state, AttachmentPreviewCacheState.failed);
    expect(records.single.failureCode, isNotNull);
    expect(generator.calls, 1);

    final committed = committedAttachment(
      id: 'attachment-retry',
      name: draft.name,
      mimeType: draft.mimeType,
      sizeBytes: draft.sizeBytes,
    );
    await fixture.cache.bindCommitted(
      conversationId: 'conversation-1',
      clientMessageId: 'client-1',
      attachments: <CommittedAttachment>[committed],
    );

    final resolved = await fixture.cache.resolve(
      conversationId: 'conversation-1',
      attachment: committed,
    );

    expect(resolved, isNotNull);
    expect(resolved!.contentHash, 'hash_retry');
    expect(generator.calls, 2);

    records = await fixture.cache.recordsForTest();
    expect(records.single.state, AttachmentPreviewCacheState.ready);
    expect(records.single.failureCode, isNull);
  });

  test('orphaned pending records never bind as historical previews', () async {
    final generator = FailingThenCopyingThumbnailGenerator();
    final fixture = await AttachmentPreviewCacheFixture.create(
      identityProvider: FixedAttachmentPreviewIdentityProvider('hash_orphan'),
      thumbnailGenerator: generator,
    );

    final draft = await fixture.createDraft(name: 'orphan.png', bytes: 'old');

    await fixture.cache.rememberPending(
      conversationId: 'conversation-1',
      clientMessageId: 'client-old',
      attachmentIndex: 0,
      draft: draft,
    );
    await fixture.cache.markClientMessageOrphaned(
      conversationId: 'conversation-1',
      clientMessageId: 'client-old',
    );

    final committed = committedAttachment(
      id: 'attachment-orphan',
      name: draft.name,
      mimeType: draft.mimeType,
      sizeBytes: draft.sizeBytes,
    );
    await fixture.cache.bindCommitted(
      conversationId: 'conversation-1',
      clientMessageId: 'client-new',
      attachments: <CommittedAttachment>[committed],
    );

    final resolved = await fixture.cache.resolve(
      conversationId: 'conversation-1',
      attachment: committed,
    );

    expect(resolved, isNull);
    expect(generator.calls, 1);
  });

  test('missing preview file downgrades to cache miss', () async {
    final fixture = await AttachmentPreviewCacheFixture.create(
      identityProvider: FixedAttachmentPreviewIdentityProvider('hash_missing'),
      thumbnailGenerator: TestCopyingAttachmentThumbnailGenerator(),
    );

    final draft = await fixture.createDraft(name: 'missing.png', bytes: 'gone');

    await fixture.cache.rememberPending(
      conversationId: 'conversation-1',
      clientMessageId: 'client-1',
      attachmentIndex: 0,
      draft: draft,
    );

    final committed = committedAttachment(
      id: 'attachment-missing',
      name: draft.name,
      mimeType: draft.mimeType,
      sizeBytes: draft.sizeBytes,
    );
    await fixture.cache.bindCommitted(
      conversationId: 'conversation-1',
      clientMessageId: 'client-1',
      attachments: <CommittedAttachment>[committed],
    );

    final firstResolved = await fixture.cache.resolve(
      conversationId: 'conversation-1',
      attachment: committed,
    );
    expect(firstResolved, isNotNull);

    await File(firstResolved!.cachePath).delete();

    final secondResolved = await fixture.cache.resolve(
      conversationId: 'conversation-1',
      attachment: committed,
    );
    expect(secondResolved, isNull);

    final records = await fixture.cache.recordsForTest();
    expect(records, isEmpty);
  });

  test('malformed and invalid index records fail closed', () async {
    final fixture = await AttachmentPreviewCacheFixture.create(
      identityProvider: FixedAttachmentPreviewIdentityProvider('hash_bad'),
      thumbnailGenerator: TestCopyingAttachmentThumbnailGenerator(),
    );

    await fixture.indexFile.writeAsString('not json', flush: true);

    expect(await fixture.cache.recordsForTest(), isEmpty);

    await fixture.indexFile.writeAsString(
      '[{"conversationId":[],"sizeBytes":[]}]',
      flush: true,
    );

    expect(await fixture.cache.recordsForTest(), isEmpty);

    final validReadyRecord = cacheRecord(
      conversationId: 'conversation-1',
      clientMessageId: 'client-1',
      contentHash: 'hash_valid',
      name: 'valid.png',
      mimeType: 'image/png',
      sizeBytes: 5,
      attachmentId: 'attachment-valid',
      cachePath: '${fixture.root.path}${Platform.pathSeparator}valid.png',
      width: 1,
      height: 1,
      state: AttachmentPreviewCacheState.ready,
    ).toJson();
    await fixture.indexFile.writeAsString(
      jsonEncode(<Object?>[
        validReadyRecord,
        <String, Object?>{
          'conversationId': <Object?>[],
          'sizeBytes': <Object?>[],
        },
      ]),
      flush: true,
    );

    expect(await fixture.cache.recordsForTest(), isEmpty);
  });

  test('resolve removes outside-root cache path without deleting it', () async {
    final fixture = await AttachmentPreviewCacheFixture.create(
      identityProvider: FixedAttachmentPreviewIdentityProvider('hash_outside'),
      thumbnailGenerator: TestCopyingAttachmentThumbnailGenerator(),
    );
    final outside = File('${fixture.root.path}_outside.png');
    addTearDown(() async {
      if (await outside.exists()) {
        await outside.delete();
      }
    });
    await outside.writeAsString('outside', flush: true);

    final committed = committedAttachment(
      id: 'attachment-outside',
      name: 'outside.png',
      mimeType: 'image/png',
      sizeBytes: 7,
    );
    await fixture.writeRecords(<AttachmentPreviewCacheRecord>[
      cacheRecord(
        conversationId: 'conversation-1',
        clientMessageId: 'client-1',
        contentHash: 'hash_outside',
        name: committed.name,
        mimeType: committed.mimeType,
        sizeBytes: committed.sizeBytes,
        attachmentId: committed.id,
        cachePath: outside.path,
        width: 1,
        height: 1,
        state: AttachmentPreviewCacheState.ready,
      ),
    ]);

    final resolved = await fixture.cache.resolve(
      conversationId: 'conversation-1',
      attachment: committed,
    );
    final records = await fixture.cache.recordsForTest();

    expect(resolved, isNull);
    expect(await outside.exists(), isTrue);
    expect(records, isEmpty);
  });

  test('eviction ignores outside-root cache paths', () async {
    final fixture = await AttachmentPreviewCacheFixture.create(
      identityProvider: FixedAttachmentPreviewIdentityProvider('hash_inside'),
      thumbnailGenerator: TestCopyingAttachmentThumbnailGenerator(),
      maxRecords: 1,
    );
    final outside = File('${fixture.root.path}_outside_eviction.png');
    addTearDown(() async {
      if (await outside.exists()) {
        await outside.delete();
      }
    });
    await outside.writeAsString('outside', flush: true);
    await fixture.writeRecords(<AttachmentPreviewCacheRecord>[
      cacheRecord(
        conversationId: 'conversation-1',
        clientMessageId: 'client-old',
        contentHash: 'hash_outside',
        name: 'outside.png',
        mimeType: 'image/png',
        sizeBytes: 7,
        attachmentId: 'attachment-outside',
        cachePath: outside.path,
        width: 1,
        height: 1,
        state: AttachmentPreviewCacheState.ready,
      ),
    ]);

    final draft =
        await fixture.createDraft(name: 'inside.png', bytes: 'inside');
    await fixture.cache.rememberPending(
      conversationId: 'conversation-1',
      clientMessageId: 'client-new',
      attachmentIndex: 0,
      draft: draft,
    );

    final records = await fixture.cache.recordsForTest();

    expect(await outside.exists(), isTrue);
    expect(records.map((record) => record.cachePath),
        isNot(contains(outside.path)));
  });

  test('active pending records are not evicted under maxRecords pressure',
      () async {
    final generator = BlockingAttachmentThumbnailGenerator();
    addTearDown(generator.release);
    final fixture = await AttachmentPreviewCacheFixture.create(
      identityProvider: SequenceAttachmentPreviewIdentityProvider(
        const <String>['hash_active_a', 'hash_active_b'],
      ),
      thumbnailGenerator: generator,
      maxRecords: 1,
    );

    final draftA = await fixture.createDraft(name: 'active-a.png', bytes: 'a');
    final draftB = await fixture.createDraft(name: 'active-b.png', bytes: 'b');

    final firstPending = fixture.cache.rememberPending(
      conversationId: 'conversation-1',
      clientMessageId: 'client-a',
      attachmentIndex: 0,
      draft: draftA,
    );
    await generator.waitForCall(1);

    final secondPending = fixture.cache.rememberPending(
      conversationId: 'conversation-1',
      clientMessageId: 'client-b',
      attachmentIndex: 0,
      draft: draftB,
    );
    await generator.waitForCall(2);

    final records = await fixture.cache.recordsForTest();

    expect(records, hasLength(2));
    expect(
      records.map((record) => record.state),
      everyElement(AttachmentPreviewCacheState.pending),
    );

    generator.release();
    await Future.wait(<Future<AttachmentPreviewIdentity>>[
      firstPending,
      secondPending,
    ]);
  });

  test('generated output is deleted if its record disappeared', () async {
    final generator = BlockingAttachmentThumbnailGenerator();
    addTearDown(generator.release);
    final fixture = await AttachmentPreviewCacheFixture.create(
      identityProvider: FixedAttachmentPreviewIdentityProvider('hash_missing'),
      thumbnailGenerator: generator,
    );

    final draft = await fixture.createDraft(name: 'missing.png', bytes: 'gone');
    final pending = fixture.cache.rememberPending(
      conversationId: 'conversation-1',
      clientMessageId: 'client-1',
      attachmentIndex: 0,
      draft: draft,
    );
    await generator.waitForCall(1);
    await fixture.indexFile.delete();

    generator.release();
    await pending;

    expect(generator.outputPaths, hasLength(1));
    expect(await File(generator.outputPaths.single).exists(), isFalse);
    expect(await fixture.cache.recordsForTest(), isEmpty);
  });

  test('evicts non-pending records by oldest access', () async {
    final fixture = await AttachmentPreviewCacheFixture.create(
      identityProvider: SequenceAttachmentPreviewIdentityProvider(
        const <String>['hash_old_ready', 'hash_new_failed', 'hash_new_ready'],
      ),
      thumbnailGenerator: SequenceAttachmentThumbnailGenerator(
        const <bool>[true, false, true],
      ),
      maxRecords: 2,
    );

    final oldReady = await fixture.createDraft(name: 'old.png', bytes: 'old');
    final newFailed = await fixture.createDraft(
      name: 'failed.png',
      bytes: 'failed',
    );
    final newReady = await fixture.createDraft(name: 'new.png', bytes: 'new');

    await fixture.cache.rememberPending(
      conversationId: 'conversation-1',
      clientMessageId: 'client-old-ready',
      attachmentIndex: 0,
      draft: oldReady,
    );
    await fixture.cache.rememberPending(
      conversationId: 'conversation-1',
      clientMessageId: 'client-new-failed',
      attachmentIndex: 0,
      draft: newFailed,
    );
    await fixture.cache.rememberPending(
      conversationId: 'conversation-1',
      clientMessageId: 'client-new-ready',
      attachmentIndex: 0,
      draft: newReady,
    );

    final records = await fixture.cache.recordsForTest();

    expect(records, hasLength(2));
    expect(
      records.map((record) => record.contentHash),
      containsAll(<String>['hash_new_failed', 'hash_new_ready']),
    );
    expect(
      records.map((record) => record.contentHash),
      isNot(contains('hash_old_ready')),
    );
  });
}

CommittedAttachment committedAttachment({
  required String id,
  required String name,
  AttachmentKind kind = AttachmentKind.image,
  required String mimeType,
  required int sizeBytes,
  AttachmentHandling handling = AttachmentHandling.native,
}) =>
    CommittedAttachment(
      id: id,
      name: name,
      kind: kind,
      mimeType: mimeType,
      sizeBytes: sizeBytes,
      handling: handling,
    );

class AttachmentPreviewCacheFixture {
  AttachmentPreviewCacheFixture._({
    required this.root,
    required this.cache,
  });

  final Directory root;
  final LocalAttachmentPreviewCache cache;
  int _draftCounter = 0;

  File get indexFile => File('${root.path}${Platform.pathSeparator}index.json');

  static Future<AttachmentPreviewCacheFixture> create({
    required AttachmentPreviewIdentityProvider identityProvider,
    required AttachmentThumbnailGenerator thumbnailGenerator,
    int maxRecords = 500,
  }) async {
    final root = await Directory.systemTemp.createTemp(
      'attachment_preview_cache_test_',
    );
    var now = DateTime.utc(2026, 5, 22);
    DateTime nextNow() {
      final value = now;
      now = now.add(const Duration(milliseconds: 1));
      return value;
    }

    final fixture = AttachmentPreviewCacheFixture._(
      root: root,
      cache: LocalAttachmentPreviewCache(
        rootDirectoryProvider: () async => root,
        identityProvider: identityProvider,
        thumbnailGenerator: thumbnailGenerator,
        now: nextNow,
        maxRecords: maxRecords,
      ),
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    return fixture;
  }

  Future<DraftAttachment> createDraft({
    required String name,
    required String bytes,
  }) async {
    _draftCounter += 1;
    final file = File(
      '${root.path}${Platform.pathSeparator}$_draftCounter-$name',
    );
    await file.writeAsString(bytes, flush: true);
    return DraftAttachment(
      localPath: file.path,
      name: name,
      mimeType: 'image/png',
      kind: AttachmentKind.image,
      sizeBytes: await file.length(),
    );
  }

  Future<void> writeRecords(List<AttachmentPreviewCacheRecord> records) =>
      indexFile.writeAsString(
        jsonEncode(
          records.map((record) => record.toJson()).toList(growable: false),
        ),
        flush: true,
      );
}

AttachmentPreviewCacheRecord cacheRecord({
  required String conversationId,
  required String clientMessageId,
  required String contentHash,
  required String name,
  required String mimeType,
  required int sizeBytes,
  required AttachmentPreviewCacheState state,
  String? attachmentId,
  String? cachePath,
  int? width,
  int? height,
  int attachmentIndex = 0,
}) {
  final now = DateTime.utc(2026, 5, 22);
  return AttachmentPreviewCacheRecord(
    conversationId: conversationId,
    clientMessageId: clientMessageId,
    contentHash: contentHash,
    name: name,
    mimeType: mimeType,
    sizeBytes: sizeBytes,
    attachmentIndex: attachmentIndex,
    state: state,
    attachmentId: attachmentId,
    cachePath: cachePath,
    width: width,
    height: height,
    draftLocalPath: null,
    failureCode: null,
    createdAt: now,
    lastAccessedAt: now,
    lastAttemptedAt: now,
    orphanedAt: null,
    committedAt: attachmentId == null ? null : now,
  );
}

class FixedAttachmentPreviewIdentityProvider
    implements AttachmentPreviewIdentityProvider {
  FixedAttachmentPreviewIdentityProvider(this.contentHash);

  final String contentHash;

  @override
  Future<String> contentHashForFile(String path) async => contentHash;
}

class SequenceAttachmentPreviewIdentityProvider
    implements AttachmentPreviewIdentityProvider {
  SequenceAttachmentPreviewIdentityProvider(this.contentHashes);

  final List<String> contentHashes;
  int _index = 0;

  @override
  Future<String> contentHashForFile(String path) async {
    final value = contentHashes[_index];
    _index += 1;
    return value;
  }
}

class TestCopyingAttachmentThumbnailGenerator
    implements AttachmentThumbnailGenerator {
  int calls = 0;

  @override
  Future<GeneratedAttachmentThumbnail> generate({
    required DraftAttachment draft,
    required File outputFile,
  }) async {
    calls += 1;
    await outputFile.parent.create(recursive: true);
    await File(draft.localPath).copy(outputFile.path);
    return GeneratedAttachmentThumbnail(
      cachePath: outputFile.path,
      width: 11,
      height: 7,
    );
  }
}

class FailingThenCopyingThumbnailGenerator
    extends TestCopyingAttachmentThumbnailGenerator {
  @override
  Future<GeneratedAttachmentThumbnail> generate({
    required DraftAttachment draft,
    required File outputFile,
  }) async {
    if (calls == 0) {
      calls += 1;
      throw StateError('thumbnail failed');
    }
    return super.generate(draft: draft, outputFile: outputFile);
  }
}

class SequenceAttachmentThumbnailGenerator
    extends TestCopyingAttachmentThumbnailGenerator {
  SequenceAttachmentThumbnailGenerator(this.successes);

  final List<bool> successes;

  @override
  Future<GeneratedAttachmentThumbnail> generate({
    required DraftAttachment draft,
    required File outputFile,
  }) async {
    final shouldSucceed = successes[calls];
    if (!shouldSucceed) {
      calls += 1;
      throw StateError('thumbnail failed');
    }
    return super.generate(draft: draft, outputFile: outputFile);
  }
}

class BlockingAttachmentThumbnailGenerator
    implements AttachmentThumbnailGenerator {
  final Completer<void> _release = Completer<void>();
  final Completer<void> _firstCall = Completer<void>();
  final Completer<void> _secondCall = Completer<void>();
  final List<String> outputPaths = <String>[];
  int calls = 0;

  Future<void> waitForCall(int callNumber) {
    if (callNumber == 1) return _firstCall.future;
    if (callNumber == 2) return _secondCall.future;
    throw ArgumentError.value(callNumber, 'callNumber');
  }

  void release() {
    if (!_release.isCompleted) {
      _release.complete();
    }
  }

  @override
  Future<GeneratedAttachmentThumbnail> generate({
    required DraftAttachment draft,
    required File outputFile,
  }) async {
    calls += 1;
    outputPaths.add(outputFile.path);
    if (calls == 1 && !_firstCall.isCompleted) {
      _firstCall.complete();
    }
    if (calls == 2 && !_secondCall.isCompleted) {
      _secondCall.complete();
    }

    await _release.future;
    await outputFile.parent.create(recursive: true);
    await File(draft.localPath).copy(outputFile.path);
    return GeneratedAttachmentThumbnail(
      cachePath: outputFile.path,
      width: 11,
      height: 7,
    );
  }
}
