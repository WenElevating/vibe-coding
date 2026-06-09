import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../models/approval_models.dart';
import '../../models/protocol.dart';

typedef ConversationEventCacheRootProvider = Future<Directory> Function();

abstract class ConversationEventCacheStore {
  Future<ConversationEventPage?> readTail(
    String namespace,
    String conversationId, {
    required int limit,
  });

  Future<ConversationEventPage?> readBefore(
    String namespace,
    String conversationId, {
    required int beforeSeq,
    required int limit,
  });

  Future<void> upsertPage(
    String namespace,
    String conversationId,
    ConversationEventPage page,
  );

  Future<void> upsertEvents(
    String namespace,
    String conversationId,
    List<ConversationEvent> events,
  );

  Future<void> clearConversation(String namespace, String conversationId);
}

class NoopConversationEventCacheStore implements ConversationEventCacheStore {
  const NoopConversationEventCacheStore();

  @override
  Future<ConversationEventPage?> readTail(
    String namespace,
    String conversationId, {
    required int limit,
  }) async =>
      null;

  @override
  Future<ConversationEventPage?> readBefore(
    String namespace,
    String conversationId, {
    required int beforeSeq,
    required int limit,
  }) async =>
      null;

  @override
  Future<void> upsertPage(
    String namespace,
    String conversationId,
    ConversationEventPage page,
  ) async {}

  @override
  Future<void> upsertEvents(
    String namespace,
    String conversationId,
    List<ConversationEvent> events,
  ) async {}

  @override
  Future<void> clearConversation(
      String namespace, String conversationId) async {}
}

class LocalConversationEventCacheStore implements ConversationEventCacheStore {
  LocalConversationEventCacheStore({
    ConversationEventCacheRootProvider? rootDirectoryProvider,
    DateTime Function()? now,
  })  : rootDirectoryProvider =
            rootDirectoryProvider ?? _defaultRootDirectoryProvider,
        _now = now ?? DateTime.now;

  final ConversationEventCacheRootProvider rootDirectoryProvider;
  final DateTime Function() _now;
  Future<void> _queue = Future<void>.value();

  static Future<Directory> _defaultRootDirectoryProvider() async {
    final base = await getApplicationSupportDirectory();
    return Directory(_joinPath(base.path, 'conversation_events'));
  }

  @override
  Future<ConversationEventPage?> readTail(
    String namespace,
    String conversationId, {
    required int limit,
  }) async {
    final record = await _readRecord(namespace, conversationId);
    if (record == null || record.events.isEmpty) return null;
    final boundedLimit = _normalizeLimit(limit);
    final start = record.events.length > boundedLimit
        ? record.events.length - boundedLimit
        : 0;
    final events = record.events.sublist(start);
    return ConversationEventPage(
      events: events,
      oldestSeq: events.first.seq,
      newestSeq: events.last.seq,
      hasMoreBefore: start > 0 || _hasMoreBefore(record, events.first.seq),
    );
  }

  @override
  Future<ConversationEventPage?> readBefore(
    String namespace,
    String conversationId, {
    required int beforeSeq,
    required int limit,
  }) async {
    final record = await _readRecord(namespace, conversationId);
    if (record == null) return null;
    final previous =
        record.events.where((event) => event.seq < beforeSeq).toList();
    if (previous.isEmpty) {
      if (!_hasMoreBefore(record, beforeSeq)) {
        return const ConversationEventPage(
          events: <ConversationEvent>[],
          oldestSeq: null,
          newestSeq: null,
          hasMoreBefore: false,
        );
      }
      return null;
    }
    final boundedLimit = _normalizeLimit(limit);
    final start =
        previous.length > boundedLimit ? previous.length - boundedLimit : 0;
    final events = previous.sublist(start);
    if (events.length < boundedLimit &&
        _hasMoreBefore(record, events.first.seq)) {
      return null;
    }
    return ConversationEventPage(
      events: events,
      oldestSeq: events.first.seq,
      newestSeq: events.last.seq,
      hasMoreBefore: start > 0 || _hasMoreBefore(record, events.first.seq),
    );
  }

  @override
  Future<void> upsertPage(
    String namespace,
    String conversationId,
    ConversationEventPage page,
  ) {
    final scopedEvents = page.events
        .where((event) => event.conversationId == conversationId)
        .toList(growable: false);
    if (scopedEvents.isEmpty) return Future<void>.value();
    return _serialized(() async {
      final record = await _readRecord(namespace, conversationId) ??
          _ConversationEventCacheRecord.empty(namespace, conversationId);
      final updated = record.upsert(
        scopedEvents,
        updatedAt: _now().toUtc(),
        knownStartSeq: page.hasMoreBefore
            ? record.knownStartSeq
            : page.oldestSeq ?? scopedEvents.first.seq,
      );
      await _writeRecord(updated);
    });
  }

  @override
  Future<void> upsertEvents(
    String namespace,
    String conversationId,
    List<ConversationEvent> events,
  ) {
    if (events.isEmpty) return Future<void>.value();
    return _serialized(() async {
      final record = await _readRecord(namespace, conversationId) ??
          _ConversationEventCacheRecord.empty(namespace, conversationId);
      await _writeRecord(record.upsert(events, updatedAt: _now().toUtc()));
    });
  }

  @override
  Future<void> clearConversation(
    String namespace,
    String conversationId,
  ) {
    return _serialized(() async {
      final root = await _ensureRootDirectory();
      final file = _recordFile(root, namespace, conversationId);
      if (await file.exists()) {
        await file.delete();
      }
    });
  }

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _queue = _queue.catchError((Object _) {}).then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  Future<_ConversationEventCacheRecord?> _readRecord(
    String namespace,
    String conversationId,
  ) async {
    final root = await _ensureRootDirectory();
    final file = _recordFile(root, namespace, conversationId);
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      final record = _ConversationEventCacheRecord.fromJson(
        Map<String, Object?>.from(decoded),
      );
      if (record.namespace != namespace ||
          record.conversationId != conversationId) {
        await _deleteBestEffort(file);
        return null;
      }
      return record;
    } catch (_) {
      await _deleteBestEffort(file);
      return null;
    }
  }

  Future<void> _writeRecord(_ConversationEventCacheRecord record) async {
    final root = await _ensureRootDirectory();
    final file = _recordFile(root, record.namespace, record.conversationId);
    await file.parent.create(recursive: true);
    final temporaryFile = File('${file.path}.tmp');
    await temporaryFile.writeAsString(jsonEncode(record.toJson()));
    if (await file.exists()) {
      await file.delete();
    }
    await temporaryFile.rename(file.path);
  }

  Future<Directory> _ensureRootDirectory() async {
    final root = await rootDirectoryProvider();
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return root;
  }

  File _recordFile(
    Directory root,
    String namespace,
    String conversationId,
  ) {
    final namespaceHash = _hashSegment(namespace);
    final conversationHash = _hashSegment(conversationId);
    return File(_joinPath(
      _joinPath(root.path, namespaceHash),
      '$conversationHash.json',
    ));
  }
}

class _ConversationEventCacheRecord {
  const _ConversationEventCacheRecord({
    required this.namespace,
    required this.conversationId,
    required this.updatedAt,
    required this.events,
    this.knownStartSeq,
  });

  factory _ConversationEventCacheRecord.empty(
    String namespace,
    String conversationId,
  ) =>
      _ConversationEventCacheRecord(
        namespace: namespace,
        conversationId: conversationId,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        events: const <ConversationEvent>[],
      );

  factory _ConversationEventCacheRecord.fromJson(Map<String, Object?> json) {
    final conversationId = json['conversationId'] as String? ?? '';
    final events = ((json['events'] as List<Object?>?) ?? const <Object?>[])
        .whereType<Map>()
        .map((item) => ConversationEvent.fromJson(
              Map<String, Object?>.from(item),
            ))
        .where((event) => event.conversationId == conversationId)
        .toList()
      ..sort((left, right) => left.seq.compareTo(right.seq));
    return _ConversationEventCacheRecord(
      namespace: json['namespace'] as String? ?? '',
      conversationId: conversationId,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      knownStartSeq: json['knownStartSeq'] as int?,
      events: _dedupeEvents(events),
    );
  }

  final String namespace;
  final String conversationId;
  final DateTime updatedAt;
  final int? knownStartSeq;
  final List<ConversationEvent> events;

  _ConversationEventCacheRecord upsert(
    List<ConversationEvent> incoming, {
    required DateTime updatedAt,
    int? knownStartSeq,
  }) {
    final bySeq = <int, ConversationEvent>{
      for (final event in events) event.seq: event,
      for (final event in incoming)
        if (event.conversationId == conversationId) event.seq: event,
    };
    final sorted = bySeq.values.toList()
      ..sort((left, right) => left.seq.compareTo(right.seq));
    return _ConversationEventCacheRecord(
      namespace: namespace,
      conversationId: conversationId,
      updatedAt: updatedAt,
      knownStartSeq: knownStartSeq ?? this.knownStartSeq,
      events: List<ConversationEvent>.unmodifiable(sorted),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'version': 1,
        'namespace': namespace,
        'conversationId': conversationId,
        'updatedAt': updatedAt.toIso8601String(),
        if (knownStartSeq != null) 'knownStartSeq': knownStartSeq,
        'events': events.map(_eventToJson).toList(growable: false),
      };
}

List<ConversationEvent> _dedupeEvents(List<ConversationEvent> events) {
  final bySeq = <int, ConversationEvent>{
    for (final event in events) event.seq: event,
  };
  final sorted = bySeq.values.toList()
    ..sort((left, right) => left.seq.compareTo(right.seq));
  return List<ConversationEvent>.unmodifiable(sorted);
}

bool _hasMoreBefore(_ConversationEventCacheRecord record, int seq) {
  final knownStartSeq = record.knownStartSeq;
  return knownStartSeq == null || seq > knownStartSeq;
}

Map<String, Object?> _eventToJson(ConversationEvent event) {
  final raw = Map<String, Object?>.from(event.raw);
  raw['type'] = event.type;
  raw['seq'] = event.seq;
  raw['conversationId'] = event.conversationId;
  raw['createdAt'] = event.createdAt.toUtc().toIso8601String();
  if (event.text != null) raw['text'] = event.text;
  if (event.taskId != null) raw['taskId'] = event.taskId;
  if (event.source != null) raw['source'] = event.source;
  if (event.updatedAt != null) {
    raw['updatedAt'] = event.updatedAt!.toUtc().toIso8601String();
  }
  if (event.taskItems.isNotEmpty) {
    raw['items'] = event.taskItems
        .map((item) => <String, Object?>{
              'id': item.id,
              'title': item.title,
              'status': item.status,
            })
        .toList(growable: false);
  }
  if (event.completedCount != null) {
    raw['completedCount'] = event.completedCount;
  }
  if (event.totalCount != null) raw['totalCount'] = event.totalCount;
  if (event.questionId != null) raw['questionId'] = event.questionId;
  if (event.approvalId != null) raw['approvalId'] = event.approvalId;
  if (event.toolUseId != null) raw['toolUseId'] = event.toolUseId;
  if (event.toolName != null) raw['toolName'] = event.toolName;
  if (event.summary != null) raw['summary'] = event.summary;
  if (event.suggestions.isNotEmpty) raw['suggestions'] = event.suggestions;
  if (event.input.isNotEmpty) raw['input'] = event.input;
  if (_shouldPersistApprovalOptions(event)) {
    raw['approvalOptions'] = event.approvalOptions.toJson();
  }
  if (event.exitCode != null) raw['exitCode'] = event.exitCode;
  if (event.isError) raw['isError'] = event.isError;
  if (event.durationMs != null) raw['durationMs'] = event.durationMs;
  if (event.attachments.isNotEmpty) {
    raw['attachments'] = event.attachments.map(_attachmentToJson).toList();
  }
  return raw;
}

Map<String, Object?> _attachmentToJson(CommittedAttachment attachment) =>
    <String, Object?>{
      'id': attachment.id,
      'name': attachment.name,
      'kind': attachment.kind.name,
      'mimeType': attachment.mimeType,
      'sizeBytes': attachment.sizeBytes,
      'handling': _attachmentHandlingName(attachment.handling),
    };

bool _shouldPersistApprovalOptions(ConversationEvent event) {
  final options = event.approvalOptions;
  return event.type == 'approval.requested' ||
      event.approvalId != null ||
      event.raw.containsKey('approvalOptions') ||
      options.kind != ApprovalRequestKind.generic ||
      options.supportsSessionScope ||
      options.supportsCancel ||
      options.denyBehavior != ApprovalDenyBehavior.interrupt ||
      options.command != null ||
      options.cwd != null ||
      options.reason != null ||
      options.proposedExecPolicyAmendment.isNotEmpty ||
      options.proposedPermissions.isNotEmpty;
}

String _attachmentHandlingName(AttachmentHandling handling) =>
    switch (handling) {
      AttachmentHandling.native => 'native',
      AttachmentHandling.textExtract => 'text_extract',
      AttachmentHandling.stagedPath => 'staged_path',
      AttachmentHandling.unsupported => 'unsupported',
    };

int _normalizeLimit(int limit) => limit < 1 ? 1 : limit;

String _hashSegment(String value) =>
    sha256.convert(utf8.encode(value)).toString();

Future<void> _deleteBestEffort(File file) async {
  try {
    if (await file.exists()) await file.delete();
  } catch (_) {}
}

String _joinPath(String left, String right) =>
    left.endsWith(Platform.pathSeparator)
        ? '$left$right'
        : '$left${Platform.pathSeparator}$right';
