import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/data/models/approval_models.dart';
import 'package:lan_ai_cli_control/src/data/services/conversation_event_cache_store.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';

void main() {
  late Directory tempDir;
  late LocalConversationEventCacheStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('conversation_events_');
    store = LocalConversationEventCacheStore(
      rootDirectoryProvider: () async => tempDir,
      now: () => DateTime.parse('2026-05-31T00:00:00.000Z'),
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('persists and reads a tail page', () async {
    await store.upsertPage(
      'daemon',
      'conv_1',
      ConversationEventPage(
        events: <ConversationEvent>[
          _event(seq: 1),
          _event(seq: 2),
          _event(seq: 3),
        ],
        oldestSeq: 1,
        newestSeq: 3,
        hasMoreBefore: false,
      ),
    );

    final reloaded = LocalConversationEventCacheStore(
      rootDirectoryProvider: () async => tempDir,
    );
    final page = await reloaded.readTail('daemon', 'conv_1', limit: 2);

    expect(page, isNotNull);
    expect(page!.events.map((event) => event.seq), const <int>[2, 3]);
    expect(page.oldestSeq, 2);
    expect(page.newestSeq, 3);
    expect(page.hasMoreBefore, isTrue);
  });

  test('dedupes events by seq and keeps the latest raw payload', () async {
    await store.upsertEvents('daemon', 'conv_1', <ConversationEvent>[
      _event(seq: 1, text: 'old'),
      _event(seq: 1, text: 'new'),
    ]);

    final page = await store.readTail('daemon', 'conv_1', limit: 10);

    expect(page!.events, hasLength(1));
    expect(page.events.single.text, 'new');
  });

  test('preserves approval options across cache persistence', () async {
    const approvalOptions = ApprovalRequestOptions(
      supportsSessionScope: true,
      supportsCancel: true,
      denyBehavior: ApprovalDenyBehavior.continueTurn,
      command: 'opencode run',
    );
    await store.upsertEvents('daemon', 'conv_1', <ConversationEvent>[
      _event(
        seq: 1,
        type: 'approval.requested',
        approvalId: 'approval_1',
        approvalOptions: approvalOptions,
      ),
    ]);

    final reloaded = LocalConversationEventCacheStore(
      rootDirectoryProvider: () async => tempDir,
    );
    final page = await reloaded.readTail('daemon', 'conv_1', limit: 10);
    final restoredOptions = page!.events.single.approvalOptions;

    expect(restoredOptions.supportsSessionScope, isTrue);
    expect(restoredOptions.supportsCancel, isTrue);
    expect(restoredOptions.denyBehavior, ApprovalDenyBehavior.continueTurn);
    expect(restoredOptions.command, 'opencode run');
  });

  test('reads older cached page before a seq', () async {
    await store.upsertPage(
      'daemon',
      'conv_1',
      ConversationEventPage(
        events: <ConversationEvent>[
          _event(seq: 1),
          _event(seq: 2),
          _event(seq: 3),
          _event(seq: 4),
        ],
        oldestSeq: 1,
        newestSeq: 4,
        hasMoreBefore: false,
      ),
    );

    final page = await store.readBefore(
      'daemon',
      'conv_1',
      beforeSeq: 4,
      limit: 2,
    );

    expect(page!.events.map((event) => event.seq), const <int>[2, 3]);
    expect(page.hasMoreBefore, isTrue);
  });

  test('returns null for missing older range that daemon may still have',
      () async {
    await store.upsertPage(
      'daemon',
      'conv_1',
      ConversationEventPage(
        events: <ConversationEvent>[_event(seq: 10), _event(seq: 11)],
        oldestSeq: 10,
        newestSeq: 11,
        hasMoreBefore: true,
      ),
    );

    final page = await store.readBefore(
      'daemon',
      'conv_1',
      beforeSeq: 10,
      limit: 80,
    );

    expect(page, isNull);
  });

  test('corrupt cache file is ignored and removed', () async {
    final file = await _firstRecordFileAfterWrite(store, tempDir);
    await file.writeAsString('{not json');

    final page = await store.readTail('daemon', 'conv_1', limit: 80);

    expect(page, isNull);
    expect(await file.exists(), isFalse);
  });

  test('cache file with mismatched record identity is ignored and removed',
      () async {
    final file = _recordFileFor(tempDir, 'daemon', 'conv_1');
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(<String, Object?>{
      'version': 1,
      'namespace': 'daemon',
      'conversationId': 'conv_other',
      'updatedAt': '2026-05-31T00:00:00.000Z',
      'events': <Object?>[
        _event(conversationId: 'conv_other', seq: 1).raw,
      ],
    }));

    final page = await store.readTail('daemon', 'conv_1', limit: 80);

    expect(page, isNull);
    expect(await file.exists(), isFalse);
  });

  test('clearConversation is ordered after pending writes', () async {
    final writeEnteredRootProvider = Completer<void>();
    final releaseWriteRootProvider = Completer<void>();
    var rootCalls = 0;
    final racingStore = LocalConversationEventCacheStore(
      rootDirectoryProvider: () async {
        rootCalls += 1;
        if (rootCalls == 1) {
          writeEnteredRootProvider.complete();
          await releaseWriteRootProvider.future;
        }
        return tempDir;
      },
      now: () => DateTime.parse('2026-05-31T00:00:00.000Z'),
    );

    final writeFuture = racingStore.upsertEvents(
      'daemon',
      'conv_1',
      <ConversationEvent>[_event(seq: 1)],
    );
    await writeEnteredRootProvider.future;
    final clearFuture = racingStore.clearConversation('daemon', 'conv_1');

    releaseWriteRootProvider.complete();
    await Future.wait(<Future<void>>[writeFuture, clearFuture]);
    final page = await racingStore.readTail('daemon', 'conv_1', limit: 80);

    expect(page, isNull);
  });

  test('does not prune stored conversations automatically', () async {
    for (var i = 0; i < 5; i += 1) {
      await store.upsertEvents('daemon', 'conv_$i', <ConversationEvent>[
        _event(conversationId: 'conv_$i', seq: 1),
      ]);
    }

    final files = await tempDir
        .list(recursive: true)
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .toList();

    expect(files, hasLength(5));
  });
}

Future<File> _firstRecordFileAfterWrite(
  LocalConversationEventCacheStore store,
  Directory tempDir,
) async {
  await store.upsertEvents('daemon', 'conv_1', <ConversationEvent>[
    _event(seq: 1),
  ]);
  return await tempDir
      .list(recursive: true)
      .where((entity) => entity is File && entity.path.endsWith('.json'))
      .cast<File>()
      .first;
}

File _recordFileFor(
  Directory root,
  String namespace,
  String conversationId,
) {
  final namespaceHash = sha256.convert(utf8.encode(namespace)).toString();
  final conversationHash =
      sha256.convert(utf8.encode(conversationId)).toString();
  return File('${root.path}${Platform.pathSeparator}'
      '$namespaceHash${Platform.pathSeparator}$conversationHash.json');
}

ConversationEvent _event({
  String conversationId = 'conv_1',
  required int seq,
  String type = 'assistant.message',
  String? text,
  String? approvalId,
  ApprovalRequestOptions approvalOptions = const ApprovalRequestOptions(),
}) {
  final second = (seq % 60).toString().padLeft(2, '0');
  return ConversationEvent(
    type: type,
    seq: seq,
    conversationId: conversationId,
    createdAt: DateTime.parse('2026-05-31T00:00:$second.000Z'),
    text: text ?? 'event $seq',
    approvalId: approvalId,
    approvalOptions: approvalOptions,
    raw: <String, Object?>{
      'type': type,
      'seq': seq,
      'conversationId': conversationId,
      'createdAt': '2026-05-31T00:00:$second.000Z',
      'text': text ?? 'event $seq',
      if (approvalId != null) 'approvalId': approvalId,
      'rawMarker': 'raw $seq',
    },
  );
}
