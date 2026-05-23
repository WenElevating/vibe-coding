import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../data/models/attachment_models.dart';
import 'draft_attachment.dart';

enum AttachmentPreviewCacheState { pending, ready, failed }

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

abstract class AttachmentThumbnailGenerator {
  Future<GeneratedAttachmentThumbnail> generate({
    required DraftAttachment draft,
    required File outputFile,
  });
}

class GeneratedAttachmentThumbnail {
  const GeneratedAttachmentThumbnail({
    required this.cachePath,
    required this.width,
    required this.height,
  });

  final String cachePath;
  final int width;
  final int height;
}

class BoundedAttachmentThumbnailGenerator
    implements AttachmentThumbnailGenerator {
  const BoundedAttachmentThumbnailGenerator({
    this.longestEdge = 640,
  });

  final int longestEdge;

  @override
  Future<GeneratedAttachmentThumbnail> generate({
    required DraftAttachment draft,
    required File outputFile,
  }) async {
    final bytes = await File(draft.localPath).readAsBytes();
    ui.Codec? originalCodec;
    ui.Codec? resizedCodec;
    ui.Image? image;

    try {
      originalCodec = await ui.instantiateImageCodec(bytes);
      final originalFrame = await originalCodec.getNextFrame();
      image = originalFrame.image;
      var width = image.width;
      var height = image.height;
      final longest = math.max(width, height);
      if (longest > longestEdge) {
        image.dispose();
        image = null;

        final scale = longestEdge / longest;
        final targetWidth = math.max(1, (width * scale).round());
        final targetHeight = math.max(1, (height * scale).round());
        resizedCodec = await ui.instantiateImageCodec(
          bytes,
          targetWidth: targetWidth,
          targetHeight: targetHeight,
        );
        final resizedFrame = await resizedCodec.getNextFrame();
        image = resizedFrame.image;
        width = image.width;
        height = image.height;
      }

      final pngBytes = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (pngBytes == null) {
        throw StateError('thumbnail_png_encode_failed');
      }

      await outputFile.parent.create(recursive: true);
      await outputFile.writeAsBytes(
        pngBytes.buffer.asUint8List(
          pngBytes.offsetInBytes,
          pngBytes.lengthInBytes,
        ),
        flush: true,
      );

      return GeneratedAttachmentThumbnail(
        cachePath: outputFile.path,
        width: width,
        height: height,
      );
    } finally {
      image?.dispose();
      resizedCodec?.dispose();
      originalCodec?.dispose();
    }
  }
}

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
    required this.attachmentId,
    required this.cachePath,
    required this.width,
    required this.height,
    required this.draftLocalPath,
    required this.failureCode,
    required this.createdAt,
    required this.lastAccessedAt,
    required this.lastAttemptedAt,
    required this.orphanedAt,
    required this.committedAt,
    bool commitRetryAttempted = false,
  }) : _commitRetryAttempted = commitRetryAttempted;

  factory AttachmentPreviewCacheRecord.fromJson(Map<String, Object?> json) {
    return AttachmentPreviewCacheRecord(
      conversationId: _requiredString(json, 'conversationId'),
      clientMessageId: _requiredString(json, 'clientMessageId'),
      contentHash: _requiredString(json, 'contentHash'),
      name: _requiredString(json, 'name'),
      mimeType: _requiredString(json, 'mimeType'),
      sizeBytes: _requiredInt(json, 'sizeBytes'),
      attachmentIndex: _requiredInt(json, 'attachmentIndex'),
      state: _stateFromJsonStrict(json, 'state'),
      attachmentId: _optionalString(json, 'attachmentId'),
      cachePath: _optionalString(json, 'cachePath'),
      width: _optionalInt(json, 'width'),
      height: _optionalInt(json, 'height'),
      draftLocalPath: _optionalString(json, 'draftLocalPath'),
      failureCode: _optionalString(json, 'failureCode'),
      createdAt: _requiredDateTime(json, 'createdAt'),
      lastAccessedAt: _requiredDateTime(json, 'lastAccessedAt'),
      lastAttemptedAt: _optionalDateTime(json, 'lastAttemptedAt'),
      orphanedAt: _optionalDateTime(json, 'orphanedAt'),
      committedAt: _optionalDateTime(json, 'committedAt'),
      commitRetryAttempted:
          _optionalBool(json, 'commitRetryAttempted') ?? false,
    );
  }

  final String conversationId;
  final String clientMessageId;
  final String contentHash;
  final String name;
  final String mimeType;
  final int sizeBytes;
  final int attachmentIndex;
  final AttachmentPreviewCacheState state;
  final String? attachmentId;
  final String? cachePath;
  final int? width;
  final int? height;
  final String? draftLocalPath;
  final String? failureCode;
  final DateTime createdAt;
  final DateTime lastAccessedAt;
  final DateTime? lastAttemptedAt;
  final DateTime? orphanedAt;
  final DateTime? committedAt;
  final bool _commitRetryAttempted;

  Map<String, Object?> toJson() => <String, Object?>{
        'conversationId': conversationId,
        'clientMessageId': clientMessageId,
        'contentHash': contentHash,
        'name': name,
        'mimeType': mimeType,
        'sizeBytes': sizeBytes,
        'attachmentIndex': attachmentIndex,
        'state': state.name,
        'attachmentId': attachmentId,
        'cachePath': cachePath,
        'width': width,
        'height': height,
        'draftLocalPath': draftLocalPath,
        'failureCode': failureCode,
        'createdAt': _dateTimeToJson(createdAt),
        'lastAccessedAt': _dateTimeToJson(lastAccessedAt),
        'lastAttemptedAt': _dateTimeToJson(lastAttemptedAt),
        'orphanedAt': _dateTimeToJson(orphanedAt),
        'committedAt': _dateTimeToJson(committedAt),
        'commitRetryAttempted': _commitRetryAttempted,
      };

  AttachmentPreviewCacheRecord copyWith({
    String? conversationId,
    String? clientMessageId,
    String? contentHash,
    String? name,
    String? mimeType,
    int? sizeBytes,
    int? attachmentIndex,
    AttachmentPreviewCacheState? state,
    Object? attachmentId = _unset,
    Object? cachePath = _unset,
    Object? width = _unset,
    Object? height = _unset,
    Object? draftLocalPath = _unset,
    Object? failureCode = _unset,
    DateTime? createdAt,
    DateTime? lastAccessedAt,
    Object? lastAttemptedAt = _unset,
    Object? orphanedAt = _unset,
    Object? committedAt = _unset,
    bool? commitRetryAttempted,
  }) =>
      AttachmentPreviewCacheRecord(
        conversationId: conversationId ?? this.conversationId,
        clientMessageId: clientMessageId ?? this.clientMessageId,
        contentHash: contentHash ?? this.contentHash,
        name: name ?? this.name,
        mimeType: mimeType ?? this.mimeType,
        sizeBytes: sizeBytes ?? this.sizeBytes,
        attachmentIndex: attachmentIndex ?? this.attachmentIndex,
        state: state ?? this.state,
        attachmentId: identical(attachmentId, _unset)
            ? this.attachmentId
            : attachmentId as String?,
        cachePath: identical(cachePath, _unset)
            ? this.cachePath
            : cachePath as String?,
        width: identical(width, _unset) ? this.width : width as int?,
        height: identical(height, _unset) ? this.height : height as int?,
        draftLocalPath: identical(draftLocalPath, _unset)
            ? this.draftLocalPath
            : draftLocalPath as String?,
        failureCode: identical(failureCode, _unset)
            ? this.failureCode
            : failureCode as String?,
        createdAt: createdAt ?? this.createdAt,
        lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
        lastAttemptedAt: identical(lastAttemptedAt, _unset)
            ? this.lastAttemptedAt
            : lastAttemptedAt as DateTime?,
        orphanedAt: identical(orphanedAt, _unset)
            ? this.orphanedAt
            : orphanedAt as DateTime?,
        committedAt: identical(committedAt, _unset)
            ? this.committedAt
            : committedAt as DateTime?,
        commitRetryAttempted: commitRetryAttempted ?? _commitRetryAttempted,
      );
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
    List<AttachmentPreviewIdentity>? pendingIdentities,
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

class NoopAttachmentPreviewCache implements AttachmentPreviewCache {
  const NoopAttachmentPreviewCache();

  @override
  Future<AttachmentPreviewIdentity> rememberPending({
    required String conversationId,
    required String clientMessageId,
    required int attachmentIndex,
    required DraftAttachment draft,
  }) async =>
      AttachmentPreviewIdentity(
        contentHash: '',
        name: draft.name,
        mimeType: draft.mimeType,
        sizeBytes: draft.sizeBytes,
        attachmentIndex: attachmentIndex,
      );

  @override
  Future<void> bindCommitted({
    required String conversationId,
    required String clientMessageId,
    required List<CommittedAttachment> attachments,
    List<AttachmentPreviewIdentity>? pendingIdentities,
  }) async {}

  @override
  Future<CachedAttachmentPreview?> resolve({
    required String conversationId,
    required CommittedAttachment attachment,
  }) async =>
      null;

  @override
  Future<void> markClientMessageOrphaned({
    required String conversationId,
    required String clientMessageId,
  }) async {}
}

class LocalAttachmentPreviewCache implements AttachmentPreviewCache {
  LocalAttachmentPreviewCache({
    PreviewRootDirectoryProvider? rootDirectoryProvider,
    this.identityProvider = const Sha256AttachmentPreviewIdentityProvider(),
    this.thumbnailGenerator = const BoundedAttachmentThumbnailGenerator(),
    DateTime Function()? now,
    this.maxBytes = 100 * 1024 * 1024,
    this.maxRecords = 500,
  })  : rootDirectoryProvider = rootDirectoryProvider ?? _defaultRootDirectory,
        _now = now ?? DateTime.now;

  final PreviewRootDirectoryProvider rootDirectoryProvider;
  final AttachmentPreviewIdentityProvider identityProvider;
  final AttachmentThumbnailGenerator thumbnailGenerator;
  final DateTime Function() _now;
  final int maxBytes;
  final int maxRecords;
  Future<void> _queue = Future<void>.value();

  static Future<Directory> _defaultRootDirectory() async {
    final base = await getApplicationSupportDirectory();
    return Directory(_joinPath(base.path, 'attachment_previews'));
  }

  @override
  Future<AttachmentPreviewIdentity> rememberPending({
    required String conversationId,
    required String clientMessageId,
    required int attachmentIndex,
    required DraftAttachment draft,
  }) async {
    final contentHash = await identityProvider.contentHashForFile(
      draft.localPath,
    );
    final identity = AttachmentPreviewIdentity(
      contentHash: contentHash,
      name: draft.name,
      mimeType: draft.mimeType,
      sizeBytes: draft.sizeBytes,
      attachmentIndex: attachmentIndex,
    );
    final attemptedAt = _now().toUtc();
    final record = AttachmentPreviewCacheRecord(
      conversationId: conversationId,
      clientMessageId: clientMessageId,
      contentHash: contentHash,
      name: draft.name,
      mimeType: draft.mimeType,
      sizeBytes: draft.sizeBytes,
      attachmentIndex: attachmentIndex,
      state: AttachmentPreviewCacheState.pending,
      attachmentId: null,
      cachePath: null,
      width: null,
      height: null,
      draftLocalPath: draft.localPath,
      failureCode: null,
      createdAt: attemptedAt,
      lastAccessedAt: attemptedAt,
      lastAttemptedAt: attemptedAt,
      orphanedAt: null,
      committedAt: null,
    );

    final outputFile = await _serialized(() async {
      final root = await _ensureRootDirectory();
      final records = await _readRecords(root);
      final index = _findRecordIndex(records, record);
      if (index == -1) {
        records.add(record);
      } else {
        records[index] = records[index].copyWith(
          name: record.name,
          mimeType: record.mimeType,
          sizeBytes: record.sizeBytes,
          state: AttachmentPreviewCacheState.pending,
          cachePath: null,
          width: null,
          height: null,
          draftLocalPath: draft.localPath,
          failureCode: null,
          lastAttemptedAt: attemptedAt,
          commitRetryAttempted: false,
        );
      }
      final nextRecords = await _evictIfNeeded(root, records);
      await _writeRecords(root, nextRecords);
      return _previewFileFor(root, record);
    });

    try {
      final thumbnail = await thumbnailGenerator.generate(
        draft: draft,
        outputFile: outputFile,
      );
      await _transitionGenerated(record, thumbnail);
    } catch (error) {
      await _deleteBestEffort(outputFile);
      await _transitionFailed(record, error, attemptedAt);
    }

    return identity;
  }

  @override
  Future<void> bindCommitted({
    required String conversationId,
    required String clientMessageId,
    required List<CommittedAttachment> attachments,
    List<AttachmentPreviewIdentity>? pendingIdentities,
  }) async {
    final retries = await _serialized(() async {
      final root = await _ensureRootDirectory();
      final records = await _readRecords(root);
      final retries = <_CommitRetry>[];
      final usedIndexes = <int>{};
      final usedIdentityIndexes = <int>{};
      final committedAt = _now().toUtc();

      for (var index = 0; index < attachments.length; index += 1) {
        final attachment = attachments[index];
        final int recordIndex;
        int? identityIndex;
        if (pendingIdentities == null) {
          recordIndex = _fallbackCommittedMatchIndex(
            records: records,
            usedIndexes: usedIndexes,
            conversationId: conversationId,
            clientMessageId: clientMessageId,
            attachment: attachment,
          );
        } else {
          identityIndex = _pendingIdentityMatchIndex(
            pendingIdentities: pendingIdentities,
            usedIdentityIndexes: usedIdentityIndexes,
            attachment: attachment,
          );
          recordIndex = identityIndex == null
              ? -1
              : _identityCommittedMatchIndex(
                  records: records,
                  usedIndexes: usedIndexes,
                  conversationId: conversationId,
                  clientMessageId: clientMessageId,
                  attachment: attachment,
                  identity: pendingIdentities[identityIndex],
                );
        }
        if (recordIndex == -1) continue;

        usedIndexes.add(recordIndex);
        if (identityIndex != null) {
          usedIdentityIndexes.add(identityIndex);
        }
        final record = records[recordIndex];
        final shouldRetry =
            record.state == AttachmentPreviewCacheState.failed &&
                record.draftLocalPath != null &&
                !record._commitRetryAttempted;
        final nextRecord = record.copyWith(
          attachmentId: attachment.id,
          committedAt: record.committedAt ?? committedAt,
          lastAttemptedAt: shouldRetry ? committedAt : record.lastAttemptedAt,
          commitRetryAttempted:
              shouldRetry ? true : record._commitRetryAttempted,
        );
        records[recordIndex] = nextRecord;

        if (shouldRetry) {
          retries.add(_CommitRetry(
            record: nextRecord,
            outputFile: _previewFileFor(root, nextRecord),
          ));
        }
      }

      final nextRecords = await _evictIfNeeded(root, records);
      await _writeRecords(root, nextRecords);
      return retries;
    });

    for (final retry in retries) {
      await _retryCommittedThumbnail(retry);
    }
  }

  @override
  Future<CachedAttachmentPreview?> resolve({
    required String conversationId,
    required CommittedAttachment attachment,
  }) =>
      _serialized(() async {
        final root = await _ensureRootDirectory();
        final records = await _readRecords(root);
        final index = records.indexWhere(
          (record) =>
              record.conversationId == conversationId &&
              record.attachmentId == attachment.id &&
              record.state == AttachmentPreviewCacheState.ready &&
              record.orphanedAt == null,
        );
        if (index == -1) return null;

        final record = records[index];
        final cachePath = record.cachePath;
        final width = record.width;
        final height = record.height;
        if (cachePath == null || width == null || height == null) {
          return null;
        }

        final cacheFile = File(cachePath);
        if (!await _isUnderRoot(cacheFile, root)) {
          records.removeAt(index);
          await _writeRecords(root, records);
          return null;
        }

        if (!await cacheFile.exists()) {
          records.removeAt(index);
          final nextRecords = await _evictIfNeeded(root, records);
          await _writeRecords(root, nextRecords);
          return null;
        }

        final accessedAt = _now().toUtc();
        final nextRecord = record.copyWith(lastAccessedAt: accessedAt);
        records[index] = nextRecord;
        final nextRecords = await _evictIfNeeded(root, records);
        await _writeRecords(root, nextRecords);
        return CachedAttachmentPreview(
          attachmentId: attachment.id,
          contentHash: nextRecord.contentHash,
          cachePath: cachePath,
          width: width,
          height: height,
          mimeType: nextRecord.mimeType,
          sizeBytes: nextRecord.sizeBytes,
          createdAt: nextRecord.createdAt,
          lastAccessedAt: nextRecord.lastAccessedAt,
        );
      });

  @override
  Future<void> markClientMessageOrphaned({
    required String conversationId,
    required String clientMessageId,
  }) =>
      _serialized(() async {
        final root = await _ensureRootDirectory();
        final records = await _readRecords(root);
        final orphanedAt = _now().toUtc();
        for (var index = 0; index < records.length; index += 1) {
          final record = records[index];
          if (record.conversationId != conversationId ||
              record.clientMessageId != clientMessageId ||
              record.committedAt != null) {
            continue;
          }
          records[index] = record.copyWith(orphanedAt: orphanedAt);
        }
        final nextRecords = await _evictIfNeeded(root, records);
        await _writeRecords(root, nextRecords);
      });

  Future<List<AttachmentPreviewCacheRecord>> recordsForTest() =>
      _serialized(() async {
        final root = await _ensureRootDirectory();
        return _readRecords(root);
      });

  Future<void> _retryCommittedThumbnail(_CommitRetry retry) async {
    final draftLocalPath = retry.record.draftLocalPath;
    if (draftLocalPath == null) return;

    final attemptedAt = _now().toUtc();
    final draft = DraftAttachment(
      localPath: draftLocalPath,
      name: retry.record.name,
      mimeType: retry.record.mimeType,
      kind: AttachmentKind.image,
      sizeBytes: retry.record.sizeBytes,
    );

    try {
      final thumbnail = await thumbnailGenerator.generate(
        draft: draft,
        outputFile: retry.outputFile,
      );
      await _transitionGenerated(retry.record, thumbnail);
    } catch (error) {
      await _deleteBestEffort(retry.outputFile);
      await _transitionFailed(retry.record, error, attemptedAt);
    }
  }

  Future<void> _transitionGenerated(
    AttachmentPreviewCacheRecord target,
    GeneratedAttachmentThumbnail thumbnail,
  ) =>
      _serialized(() async {
        final root = await _ensureRootDirectory();
        final records = await _readRecords(root);
        final index = _findRecordIndex(records, target);
        if (index == -1) {
          await _deleteBestEffortIfUnderRoot(File(thumbnail.cachePath), root);
          return;
        }

        if (!await _isUnderRoot(File(thumbnail.cachePath), root)) {
          records[index] = records[index].copyWith(
            state: AttachmentPreviewCacheState.failed,
            cachePath: null,
            width: null,
            height: null,
            failureCode: 'thumbnail_path_outside_cache_root',
          );
          final nextRecords = await _evictIfNeeded(root, records);
          await _writeRecords(root, nextRecords);
          return;
        }

        records[index] = records[index].copyWith(
          state: AttachmentPreviewCacheState.ready,
          cachePath: thumbnail.cachePath,
          width: thumbnail.width,
          height: thumbnail.height,
          failureCode: null,
        );
        final nextRecords = await _evictIfNeeded(root, records);
        await _writeRecords(root, nextRecords);
      });

  Future<void> _transitionFailed(
    AttachmentPreviewCacheRecord target,
    Object error,
    DateTime attemptedAt,
  ) =>
      _serialized(() async {
        final root = await _ensureRootDirectory();
        final records = await _readRecords(root);
        final index = _findRecordIndex(records, target);
        if (index == -1) return;

        records[index] = records[index].copyWith(
          state: AttachmentPreviewCacheState.failed,
          cachePath: null,
          width: null,
          height: null,
          failureCode: _failureCode(error),
          lastAttemptedAt: attemptedAt,
        );
        final nextRecords = await _evictIfNeeded(root, records);
        await _writeRecords(root, nextRecords);
      });

  Future<Directory> _ensureRootDirectory() async {
    final root = await rootDirectoryProvider();
    await root.create(recursive: true);
    return root;
  }

  Future<List<AttachmentPreviewCacheRecord>> _readRecords(
    Directory root,
  ) async {
    final indexFile = _indexFile(root);
    if (!await indexFile.exists()) return <AttachmentPreviewCacheRecord>[];

    try {
      final content = await indexFile.readAsString();
      if (content.trim().isEmpty) return <AttachmentPreviewCacheRecord>[];

      final decoded = jsonDecode(content);
      if (decoded is! List) return <AttachmentPreviewCacheRecord>[];

      return decoded.map<AttachmentPreviewCacheRecord>((item) {
        if (item is! Map) {
          throw const FormatException('Expected attachment preview record');
        }
        return AttachmentPreviewCacheRecord.fromJson(
          Map<String, Object?>.from(item),
        );
      }).toList();
    } on Object {
      return <AttachmentPreviewCacheRecord>[];
    }
  }

  Future<void> _writeRecords(
    Directory root,
    List<AttachmentPreviewCacheRecord> records,
  ) async {
    await root.create(recursive: true);
    final indexFile = _indexFile(root);
    final temporaryFile = File('${indexFile.path}.tmp');
    final encoded = jsonEncode(
      records.map((record) => record.toJson()).toList(growable: false),
    );
    await temporaryFile.writeAsString(encoded, flush: true);
    await temporaryFile.rename(indexFile.path);
  }

  Future<List<AttachmentPreviewCacheRecord>> _evictIfNeeded(
    Directory root,
    List<AttachmentPreviewCacheRecord> records,
  ) async {
    var nextRecords = List<AttachmentPreviewCacheRecord>.of(records);
    var totalBytes = await _cachedBytes(root, nextRecords);
    if (nextRecords.length <= maxRecords && totalBytes <= maxBytes) {
      return nextRecords;
    }

    final candidates = nextRecords.where(_isEvictionCandidate).toList()
      ..sort(_evictionSort);
    for (final candidate in candidates) {
      if (nextRecords.length <= maxRecords && totalBytes <= maxBytes) {
        break;
      }

      final index = _findRecordIndex(nextRecords, candidate);
      if (index == -1) continue;
      final removed = nextRecords.removeAt(index);
      await _deleteUnsharedPreviewFile(root, removed, nextRecords);
      totalBytes = await _cachedBytes(root, nextRecords);
    }

    return nextRecords;
  }

  Future<int> _cachedBytes(
    Directory root,
    List<AttachmentPreviewCacheRecord> records,
  ) async {
    var total = 0;
    final seenPaths = <String>{};
    for (final record in records) {
      final cachePath = record.cachePath;
      if (cachePath == null || !seenPaths.add(cachePath)) continue;
      final file = File(cachePath);
      if (await _isUnderRoot(file, root) && await file.exists()) {
        total += await file.length();
      }
    }
    return total;
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final run = _queue.then((_) => action(), onError: (_) => action());
    _queue = run.then<void>((_) {}, onError: (_, __) {});
    return run;
  }

  File _indexFile(Directory root) => File(_joinPath(root.path, 'index.json'));

  File _previewFileFor(
    Directory root,
    AttachmentPreviewCacheRecord record,
  ) =>
      File(
        _joinPath(
          root.path,
          'preview_${_safeSegment(record.conversationId)}_'
          '${_safeSegment(record.clientMessageId)}_'
          '${_safeSegment(record.contentHash)}_'
          '${record.attachmentIndex}.png',
        ),
      );

  int _findRecordIndex(
    List<AttachmentPreviewCacheRecord> records,
    AttachmentPreviewCacheRecord target,
  ) =>
      records.indexWhere(
        (record) =>
            record.conversationId == target.conversationId &&
            record.clientMessageId == target.clientMessageId &&
            record.contentHash == target.contentHash &&
            record.name == target.name &&
            record.mimeType == target.mimeType &&
            record.sizeBytes == target.sizeBytes &&
            record.attachmentIndex == target.attachmentIndex,
      );

  int _identityCommittedMatchIndex({
    required List<AttachmentPreviewCacheRecord> records,
    required Set<int> usedIndexes,
    required String conversationId,
    required String clientMessageId,
    required CommittedAttachment attachment,
    required AttachmentPreviewIdentity identity,
  }) {
    if (attachment.kind != AttachmentKind.image ||
        identity.contentHash.isEmpty ||
        !_identityMatchesAttachment(identity, attachment)) {
      return -1;
    }
    final alreadyBoundMatches = <int>[];
    final unboundMatches = <int>[];
    for (var index = 0; index < records.length; index += 1) {
      if (usedIndexes.contains(index)) continue;
      final record = records[index];
      if (record.conversationId != conversationId ||
          record.clientMessageId != clientMessageId ||
          record.contentHash != identity.contentHash ||
          !_recordMetadataMatchesAttachment(record, attachment) ||
          record.orphanedAt != null ||
          (record.attachmentId != null &&
              record.attachmentId != attachment.id)) {
        continue;
      }
      if (record.attachmentId == attachment.id) {
        alreadyBoundMatches.add(index);
      } else if (record.attachmentId == null) {
        unboundMatches.add(index);
      }
    }

    if (alreadyBoundMatches.length == 1) return alreadyBoundMatches.single;
    if (alreadyBoundMatches.length > 1) return -1;
    if (unboundMatches.length == 1) return unboundMatches.single;
    return -1;
  }

  int? _pendingIdentityMatchIndex({
    required List<AttachmentPreviewIdentity> pendingIdentities,
    required Set<int> usedIdentityIndexes,
    required CommittedAttachment attachment,
  }) {
    if (attachment.kind != AttachmentKind.image) return null;
    final matches = <int>[];
    for (var index = 0; index < pendingIdentities.length; index += 1) {
      if (usedIdentityIndexes.contains(index)) continue;
      final identity = pendingIdentities[index];
      if (identity.contentHash.isNotEmpty &&
          _identityMatchesAttachment(identity, attachment)) {
        matches.add(index);
      }
    }
    return matches.length == 1 ? matches.single : null;
  }

  int _fallbackCommittedMatchIndex({
    required List<AttachmentPreviewCacheRecord> records,
    required Set<int> usedIndexes,
    required String conversationId,
    required String clientMessageId,
    required CommittedAttachment attachment,
  }) {
    if (attachment.kind != AttachmentKind.image) return -1;
    final alreadyBoundMatches = <int>[];
    final unboundMatches = <int>[];
    for (var index = 0; index < records.length; index += 1) {
      if (usedIndexes.contains(index)) continue;
      final record = records[index];
      if (record.conversationId != conversationId ||
          record.clientMessageId != clientMessageId ||
          record.orphanedAt != null ||
          !_recordMetadataMatchesAttachment(record, attachment)) {
        continue;
      }

      if (record.attachmentId == attachment.id) {
        alreadyBoundMatches.add(index);
      } else if (record.attachmentId == null) {
        unboundMatches.add(index);
      }
    }

    if (alreadyBoundMatches.length == 1) return alreadyBoundMatches.single;
    if (alreadyBoundMatches.length > 1) return -1;
    if (unboundMatches.length == 1) return unboundMatches.single;
    return -1;
  }

  bool _identityMatchesAttachment(
    AttachmentPreviewIdentity identity,
    CommittedAttachment attachment,
  ) =>
      identity.name == attachment.name &&
      identity.mimeType == attachment.mimeType &&
      identity.sizeBytes == attachment.sizeBytes;

  bool _recordMetadataMatchesAttachment(
    AttachmentPreviewCacheRecord record,
    CommittedAttachment attachment,
  ) =>
      record.name == attachment.name &&
      record.mimeType == attachment.mimeType &&
      record.sizeBytes == attachment.sizeBytes;
}

class _CommitRetry {
  const _CommitRetry({
    required this.record,
    required this.outputFile,
  });

  final AttachmentPreviewCacheRecord record;
  final File outputFile;
}

const Object _unset = Object();

String _sha256FileByPath(String path) {
  final bytes = File(path).readAsBytesSync();
  return sha256.convert(bytes).toString();
}

String _requiredString(Map<String, Object?> json, String key) {
  if (!json.containsKey(key)) {
    throw FormatException('Missing attachment preview field: $key');
  }
  final value = json[key];
  if (value is String) return value;
  throw FormatException('Invalid attachment preview string field: $key');
}

String? _optionalString(Map<String, Object?> json, String key) {
  if (!json.containsKey(key)) return null;
  final value = json[key];
  if (value == null) return null;
  if (value is String) return value;
  throw FormatException('Invalid attachment preview string field: $key');
}

int _requiredInt(Map<String, Object?> json, String key) {
  if (!json.containsKey(key)) {
    throw FormatException('Missing attachment preview field: $key');
  }
  final value = json[key];
  if (value is int) return value;
  throw FormatException('Invalid attachment preview integer field: $key');
}

int? _optionalInt(Map<String, Object?> json, String key) {
  if (!json.containsKey(key)) return null;
  final value = json[key];
  if (value == null) return null;
  if (value is int) return value;
  throw FormatException('Invalid attachment preview integer field: $key');
}

bool? _optionalBool(Map<String, Object?> json, String key) {
  if (!json.containsKey(key)) return null;
  final value = json[key];
  if (value == null) return null;
  if (value is bool) return value;
  throw FormatException('Invalid attachment preview boolean field: $key');
}

DateTime _requiredDateTime(Map<String, Object?> json, String key) =>
    _parseDateTime(key, _requiredString(json, key));

DateTime? _optionalDateTime(Map<String, Object?> json, String key) {
  if (!json.containsKey(key)) return null;
  final value = json[key];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('Invalid attachment preview date field: $key');
  }
  return _parseDateTime(key, value);
}

DateTime _parseDateTime(String key, String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('Invalid attachment preview date field: $key');
  }
  return parsed.toUtc();
}

AttachmentPreviewCacheState _stateFromJsonStrict(
  Map<String, Object?> json,
  String key,
) {
  final value = _requiredString(json, key);
  for (final state in AttachmentPreviewCacheState.values) {
    if (state.name == value) return state;
  }
  throw FormatException('Invalid attachment preview state field: $key');
}

String? _dateTimeToJson(DateTime? value) => value?.toUtc().toIso8601String();

String _failureCode(Object error) {
  final type = error.runtimeType.toString();
  if (type.isEmpty) return 'thumbnail_generation_failed';
  return type;
}

int _evictionSort(
  AttachmentPreviewCacheRecord left,
  AttachmentPreviewCacheRecord right,
) {
  final leftOrphaned = left.orphanedAt != null;
  final rightOrphaned = right.orphanedAt != null;
  if (leftOrphaned != rightOrphaned) return leftOrphaned ? -1 : 1;

  final lastAccessed = left.lastAccessedAt.compareTo(right.lastAccessedAt);
  if (lastAccessed != 0) return lastAccessed;
  return left.createdAt.compareTo(right.createdAt);
}

bool _isEvictionCandidate(AttachmentPreviewCacheRecord record) =>
    record.orphanedAt != null ||
    record.state != AttachmentPreviewCacheState.pending;

Future<void> _deleteUnsharedPreviewFile(
  Directory root,
  AttachmentPreviewCacheRecord removed,
  List<AttachmentPreviewCacheRecord> remaining,
) async {
  final cachePath = removed.cachePath;
  if (cachePath == null) return;
  final stillReferenced =
      remaining.any((record) => record.cachePath == cachePath);
  if (stillReferenced) return;
  await _deleteBestEffortIfUnderRoot(File(cachePath), root);
}

Future<void> _deleteBestEffortIfUnderRoot(File file, Directory root) async {
  if (await _isUnderRoot(file, root)) {
    await _deleteBestEffort(file);
  }
}

Future<void> _deleteBestEffort(File file) async {
  try {
    if (await file.exists()) {
      await file.delete();
    }
  } on FileSystemException {
    // Cache cleanup is best-effort; stale paths become misses on resolve.
  }
}

Future<bool> _isUnderRoot(File file, Directory root) async {
  final rootPath = await _resolvedDirectoryPath(root);
  final filePath = await _resolvedFilePath(file);
  return filePath.startsWith(_pathWithTrailingSeparator(rootPath));
}

Future<String> _resolvedDirectoryPath(Directory directory) async {
  try {
    return _normalizePath(await directory.resolveSymbolicLinks());
  } on FileSystemException {
    return _normalizePath(directory.absolute.path);
  }
}

Future<String> _resolvedFilePath(File file) async {
  try {
    return _normalizePath(await file.resolveSymbolicLinks());
  } on FileSystemException {
    return _normalizePath(file.absolute.path);
  }
}

String _normalizePath(String path) {
  final normalized =
      Uri.file(path).normalizePath().toFilePath(windows: Platform.isWindows);
  return Platform.isWindows ? normalized.toLowerCase() : normalized;
}

String _pathWithTrailingSeparator(String path) =>
    path.endsWith(Platform.pathSeparator)
        ? path
        : '$path${Platform.pathSeparator}';

String _joinPath(String left, String right) {
  if (left.endsWith(Platform.pathSeparator)) return '$left$right';
  return '$left${Platform.pathSeparator}$right';
}

String _safeSegment(String value) {
  final buffer = StringBuffer();
  for (final codeUnit in value.codeUnits) {
    final isDigit = codeUnit >= 0x30 && codeUnit <= 0x39;
    final isUpper = codeUnit >= 0x41 && codeUnit <= 0x5a;
    final isLower = codeUnit >= 0x61 && codeUnit <= 0x7a;
    final isSafeSymbol =
        codeUnit == 0x2d || codeUnit == 0x2e || codeUnit == 0x5f;
    if (isDigit || isUpper || isLower || isSafeSymbol) {
      buffer.writeCharCode(codeUnit);
    } else {
      buffer.write('_${codeUnit.toRadixString(16)}');
    }
  }
  final result = buffer.toString();
  return result.isEmpty ? 'empty' : result;
}
