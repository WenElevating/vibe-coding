import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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

ConversationEvent _event({
  String conversationId = 'conv_1',
  required int seq,
  String? text,
}) {
  final second = (seq % 60).toString().padLeft(2, '0');
  return ConversationEvent.fromJson(<String, Object?>{
    'type': 'assistant.message',
    'seq': seq,
    'conversationId': conversationId,
    'createdAt': '2026-05-31T00:00:$second.000Z',
    'text': text ?? 'event $seq',
    'rawMarker': 'raw $seq',
  });
}
