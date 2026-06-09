import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/services/daemon_notification_client.dart';

void main() {
  test('notification websocket uri converts http to ws', () {
    expect(
      daemonNotificationWebSocketUri(Uri.parse('http://127.0.0.1:4317')),
      Uri.parse('ws://127.0.0.1:4317/api/notifications/ws'),
    );
    expect(
      daemonNotificationWebSocketUri(Uri.parse('https://example.test/base')),
      Uri.parse('wss://example.test/api/notifications/ws'),
    );
  });

  test('subscribes with scope and afterSeq then emits conversation events',
      () async {
    final socket = FakeNotificationSocket();
    final client = DaemonNotificationClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenProvider: () => 'token_1',
      fetchBackfill: (_, {required afterSeq}) async => <ConversationEvent>[],
      config: NotificationClientConfig(
        connector: (_, __) async => socket,
        reconnectDelays: const <Duration>[Duration(milliseconds: 1)],
      ),
    );

    final events = <ConversationEvent>[];
    final subscription = client
        .watchConversationEvents('conv_1', afterSeq: 7)
        .listen(events.add);

    socket.serverAddJson(<String, Object?>{
      'type': 'hello',
      'connectionId': 'ws_test',
      'protocolVersion': 1,
      'heartbeatIntervalMs': 25000,
      'capabilities': <String, Object?>{
        'topics': <String>['conversation.events'],
        'maxReplayEvents': 1000,
      },
    });
    await Future<void>.delayed(Duration.zero);
    expect(socket.sentJson.single['type'], 'subscribe');
    expect(socket.sentJson.single['topic'], 'conversation.events');
    expect(socket.sentJson.single['scope'],
        <String, Object?>{'conversationId': 'conv_1'});
    expect(socket.sentJson.single['afterSeq'], 7);

    socket.serverAddJson(<String, Object?>{
      'type': 'event',
      'topic': 'conversation.events',
      'scope': <String, Object?>{'conversationId': 'conv_1'},
      'seq': 8,
      'payload': <String, Object?>{
        'seq': 8,
        'conversationId': 'conv_1',
        'type': 'assistant.message',
        'createdAt': '2026-05-23T05:18:14.000Z',
        'text': 'hello',
      },
    });
    await Future<void>.delayed(Duration.zero);
    expect(events.single.seq, 8);
    expect(events.single.type, 'assistant.message');

    await subscription.cancel();
    await client.close();
  });

  test('records websocket connection frame and event trace marks', () async {
    final socket = FakeNotificationSocket();
    final marks = <Map<String, Object?>>[];
    void recordTrace(
      String name, {
      String? conversationId,
      int? seq,
      String? eventType,
      String? correlationId,
      required bool critical,
      required Map<String, Object?> metadata,
    }) {
      marks.add(<String, Object?>{
        'name': name,
        'conversationId': conversationId,
        'seq': seq,
        'eventType': eventType,
        'correlationId': correlationId,
        'critical': critical,
        'metadata': metadata,
      });
    }

    final client = DaemonNotificationClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenProvider: () => 'token_1',
      fetchBackfill: (_, {required afterSeq}) async => <ConversationEvent>[],
      traceMarkRecorder: recordTrace,
      config: NotificationClientConfig(
        connector: (_, __) async => socket,
        reconnectDelays: const <Duration>[Duration(milliseconds: 1)],
      ),
    );

    final events = <ConversationEvent>[];
    final subscription = client
        .watchConversationEvents('conv_1', afterSeq: 7)
        .listen(events.add);

    await waitFor(() => socket.sentJson.isNotEmpty);
    socket.serverAddJson(<String, Object?>{
      'type': 'hello',
      'connectionId': 'ws_test',
      'protocolVersion': 1,
    });
    socket.serverAddJson(<String, Object?>{
      'type': 'event',
      'topic': 'conversation.events',
      'scope': <String, Object?>{'conversationId': 'conv_1'},
      'seq': 8,
      'payload': <String, Object?>{
        'seq': 8,
        'conversationId': 'conv_1',
        'type': 'assistant.message',
        'createdAt': '2026-05-23T05:18:14.000Z',
        'text': 'assistant text must not enter trace metadata',
      },
    });

    await waitFor(() => events.length == 1);
    expect(marks.map((mark) => mark['name']), contains('ws.connected'));
    expect(
      marks.where((mark) => mark['name'] == 'ws.frame.received'),
      hasLength(2),
    );
    final eventMark = marks.singleWhere(
      (mark) => mark['name'] == 'ws.event.received',
    );
    expect(eventMark['conversationId'], 'conv_1');
    expect(eventMark['seq'], 8);
    expect(eventMark['eventType'], 'assistant.message');
    expect(eventMark['correlationId'], 'conv_1:8');
    expect(eventMark['critical'], isTrue);
    expect(eventMark['metadata'],
        const <String, Object?>{'topic': 'conversation.events'});

    await subscription.cancel();
    await client.close();
  });

  test('multiplexes active conversation subscriptions over one websocket',
      () async {
    final sockets = <FakeNotificationSocket>[];
    final client = DaemonNotificationClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenProvider: () => 'token_1',
      fetchBackfill: (_, {required afterSeq}) async => <ConversationEvent>[],
      config: NotificationClientConfig(
        connector: (_, __) async {
          final socket = FakeNotificationSocket();
          sockets.add(socket);
          return socket;
        },
        reconnectDelays: const <Duration>[Duration.zero],
      ),
    );

    final conv1Events = <ConversationEvent>[];
    final conv2Events = <ConversationEvent>[];
    final conv1Subscription = client
        .watchConversationEvents('conv_1', afterSeq: 4)
        .listen(conv1Events.add);
    final conv2Subscription = client
        .watchConversationEvents('conv_2', afterSeq: 9)
        .listen(conv2Events.add);

    await waitFor(
        () => sockets.length == 1 && sockets.single.sentJson.length == 2);
    expect(sockets, hasLength(1));
    expect(
      sockets.single.sentJson.map((frame) => frame['scope']).toList(),
      containsAll(<Map<String, Object?>>[
        <String, Object?>{'conversationId': 'conv_1'},
        <String, Object?>{'conversationId': 'conv_2'},
      ]),
    );

    sockets.single.serverAddJson(
        eventFrame(conversationId: 'conv_2', seq: 10, text: 'two'));
    sockets.single.serverAddJson(
        eventFrame(conversationId: 'conv_1', seq: 5, text: 'one'));
    await waitFor(() => conv1Events.length == 1 && conv2Events.length == 1);

    expect(conv1Events.single.conversationId, 'conv_1');
    expect(conv1Events.single.text, 'one');
    expect(conv2Events.single.conversationId, 'conv_2');
    expect(conv2Events.single.text, 'two');

    await conv1Subscription.cancel();
    await conv2Subscription.cancel();
    await client.close();
  });

  test('ignores event frames with mismatched scope and payload conversation',
      () async {
    final socket = FakeNotificationSocket();
    final client = DaemonNotificationClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenProvider: () => 'token_1',
      fetchBackfill: (_, {required afterSeq}) async => <ConversationEvent>[],
      config: NotificationClientConfig(
        connector: (_, __) async => socket,
        reconnectDelays: const <Duration>[Duration(milliseconds: 1)],
      ),
    );

    final conv1Events = <ConversationEvent>[];
    final conv2Events = <ConversationEvent>[];
    final conv1Subscription = client
        .watchConversationEvents('conv_1', afterSeq: 7)
        .listen(conv1Events.add);
    final conv2Subscription = client
        .watchConversationEvents('conv_2', afterSeq: 7)
        .listen(conv2Events.add);

    await waitFor(() => socket.sentJson.length == 2);
    socket.serverAddJson(<String, Object?>{
      'type': 'event',
      'topic': 'conversation.events',
      'scope': <String, Object?>{'conversationId': 'conv_1'},
      'seq': 8,
      'payload': <String, Object?>{
        'seq': 8,
        'conversationId': 'conv_2',
        'type': 'assistant.message',
        'createdAt': '2026-05-23T05:18:14.000Z',
        'text': 'wrong route',
      },
    });
    await pumpEventQueue();

    expect(conv1Events, isEmpty);
    expect(conv2Events, isEmpty);

    await conv1Subscription.cancel();
    await conv2Subscription.cancel();
    await client.close();
  });

  test('ignores event frames for unsupported topics', () async {
    final socket = FakeNotificationSocket();
    final client = DaemonNotificationClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenProvider: () => 'token_1',
      fetchBackfill: (_, {required afterSeq}) async => <ConversationEvent>[],
      config: NotificationClientConfig(
        connector: (_, __) async => socket,
        reconnectDelays: const <Duration>[Duration(milliseconds: 1)],
      ),
    );

    final events = <ConversationEvent>[];
    final subscription = client
        .watchConversationEvents('conv_1', afterSeq: 7)
        .listen(events.add);

    await waitFor(() => socket.sentJson.isNotEmpty);
    socket.serverAddJson(<String, Object?>{
      'type': 'event',
      'topic': 'other.events',
      'scope': <String, Object?>{'conversationId': 'conv_1'},
      'seq': 8,
      'payload': <String, Object?>{
        'seq': 8,
        'conversationId': 'conv_1',
        'type': 'assistant.message',
        'createdAt': '2026-05-23T05:18:14.000Z',
        'text': 'wrong topic',
      },
    });
    await pumpEventQueue();

    expect(events, isEmpty);

    await subscription.cancel();
    await client.close();
  });

  test(
      'reconnects and resubscribes from backfill cursor after replay truncated',
      () async {
    final sockets = <FakeNotificationSocket>[];
    final backfillAfterSeq = <int>[];
    final client = DaemonNotificationClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenProvider: () => 'token_1',
      fetchBackfill: (_, {required afterSeq}) async {
        backfillAfterSeq.add(afterSeq);
        return <ConversationEvent>[
          conversationEvent(seq: 12),
        ];
      },
      config: NotificationClientConfig(
        connector: (_, __) async {
          final socket = FakeNotificationSocket();
          sockets.add(socket);
          return socket;
        },
        reconnectDelays: const <Duration>[Duration.zero],
      ),
    );

    final events = <ConversationEvent>[];
    final subscription = client
        .watchConversationEvents('conv_1', afterSeq: 7)
        .listen(events.add);

    await waitFor(() => sockets.isNotEmpty);
    expect(sockets.single.sentJson.single['afterSeq'], 7);

    sockets.single.serverAddJson(<String, Object?>{
      'type': 'error',
      'topic': 'conversation.events',
      'scope': <String, Object?>{'conversationId': 'conv_1'},
      'code': 'REPLAY_TRUNCATED',
      'message': 'requested replay window is no longer available',
    });

    await waitFor(() => sockets.length == 2);
    expect(backfillAfterSeq, <int>[7]);
    expect(events.single.seq, 12);
    expect(sockets[1].sentJson.single['type'], 'subscribe');
    expect(sockets[1].sentJson.single['topic'], 'conversation.events');
    expect(sockets[1].sentJson.single['scope'],
        <String, Object?>{'conversationId': 'conv_1'});
    expect(sockets[1].sentJson.single['afterSeq'], 12);

    await subscription.cancel();
    await client.close();
  });

  test('unscoped replay truncated does not backfill the only active route',
      () async {
    final sockets = <FakeNotificationSocket>[];
    final delay = ControlledDelay();
    final backfillAfterSeq = <int>[];
    final client = DaemonNotificationClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenProvider: () => 'token_1',
      fetchBackfill: (_, {required afterSeq}) async {
        backfillAfterSeq.add(afterSeq);
        return <ConversationEvent>[conversationEvent(seq: afterSeq + 1)];
      },
      config: NotificationClientConfig(
        connector: (_, __) async {
          final socket = FakeNotificationSocket();
          sockets.add(socket);
          return socket;
        },
        reconnectDelays: const <Duration>[Duration(milliseconds: 25)],
        reconnectDelayWaiter: delay.wait,
      ),
    );

    final events = <ConversationEvent>[];
    final subscription = client
        .watchConversationEvents('conv_1', afterSeq: 7)
        .listen(events.add);

    await waitFor(() => sockets.length == 1);
    sockets.single.serverAddJson(<String, Object?>{
      'type': 'error',
      'code': 'REPLAY_TRUNCATED',
      'message': 'Replay scope missing.',
    });

    try {
      await waitFor(
        () => backfillAfterSeq.isNotEmpty || delay.started.isCompleted,
      );
      expect(backfillAfterSeq, isEmpty);
      expect(events, isEmpty);
      delay.complete();

      await waitFor(() => sockets.length == 2);
      expect(sockets[1].sentJson.single['afterSeq'], 7);
    } finally {
      delay.complete();
      await subscription.cancel();
      await client.close();
    }
  });

  test('uses REST backfill after replay truncated error', () async {
    final socket = FakeNotificationSocket();
    final backfillCalls = <String>[];
    final client = DaemonNotificationClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenProvider: () => 'token_1',
      fetchBackfill: (conversationId, {required afterSeq}) async {
        backfillCalls.add('$conversationId:$afterSeq');
        return <ConversationEvent>[
          ConversationEvent(
            seq: 9,
            conversationId: 'conv_1',
            type: 'assistant.message',
            createdAt: DateTime.parse('2026-05-23T05:18:14.000Z'),
            text: 'backfilled',
          ),
        ];
      },
      config: NotificationClientConfig(connector: (_, __) async => socket),
    );
    final events = <ConversationEvent>[];
    final subscription = client
        .watchConversationEvents('conv_1', afterSeq: 8)
        .listen(events.add);
    await waitFor(() => socket.sentJson.isNotEmpty);

    socket.serverAddJson(<String, Object?>{
      'type': 'error',
      'topic': 'conversation.events',
      'scope': <String, Object?>{'conversationId': 'conv_1'},
      'code': 'REPLAY_TRUNCATED',
      'message': 'Replay too large.',
    });

    await waitFor(() => events.length == 1);
    expect(backfillCalls, <String>['conv_1:8']);
    expect(events.single.text, 'backfilled');
    await subscription.cancel();
    await client.close();
  });

  test('scoped backfill ignores events for other conversations', () async {
    final socket = FakeNotificationSocket();
    final backfillCalls = <String>[];
    final client = DaemonNotificationClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenProvider: () => 'token_1',
      fetchBackfill: (conversationId, {required afterSeq}) async {
        backfillCalls.add('$conversationId:$afterSeq');
        return <ConversationEvent>[
          ConversationEvent(
            seq: 21,
            conversationId: 'conv_2',
            type: 'assistant.message',
            createdAt: DateTime.parse('2026-05-23T05:18:14.000Z'),
            text: 'wrong conversation',
          ),
        ];
      },
      config: NotificationClientConfig(connector: (_, __) async => socket),
    );
    final conv1Events = <ConversationEvent>[];
    final conv2Events = <ConversationEvent>[];
    final conv1Subscription = client
        .watchConversationEvents('conv_1', afterSeq: 8)
        .listen(conv1Events.add);
    final conv2Subscription = client
        .watchConversationEvents('conv_2', afterSeq: 20)
        .listen(conv2Events.add);
    await waitFor(() => socket.sentJson.length == 2);

    socket.serverAddJson(<String, Object?>{
      'type': 'error',
      'topic': 'conversation.events',
      'scope': <String, Object?>{'conversationId': 'conv_1'},
      'code': 'REPLAY_TRUNCATED',
      'message': 'Replay too large.',
    });

    await waitFor(() => backfillCalls.length == 1);
    await pumpEventQueue();
    expect(backfillCalls, <String>['conv_1:8']);
    expect(conv1Events, isEmpty);
    expect(conv2Events, isEmpty);

    await conv1Subscription.cancel();
    await conv2Subscription.cancel();
    await client.close();
  });

  test('refreshes token and reconnects from cursor after auth error', () async {
    final sockets = <FakeNotificationSocket>[];
    final tokens = <String>['token_old'];
    final refreshCalls = <String>[];
    final client = DaemonNotificationClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenProvider: () => tokens.last,
      fetchBackfill: (_, {required afterSeq}) async => <ConversationEvent>[],
      refreshAuth: () async {
        refreshCalls.add('refresh');
        tokens.add('token_new');
      },
      config: NotificationClientConfig(
        connector: (_, headers) async {
          final socket = FakeNotificationSocket();
          socket.connectHeaders = Map<String, String>.from(headers);
          sockets.add(socket);
          return socket;
        },
        reconnectDelays: const <Duration>[Duration.zero],
      ),
    );

    final events = <ConversationEvent>[];
    final subscription = client
        .watchConversationEvents('conv_1', afterSeq: 7)
        .listen(events.add);

    await waitFor(() => sockets.length == 1);
    sockets.single.serverAddJson(eventFrame(seq: 8, text: 'before refresh'));
    await waitFor(() => events.length == 1);
    sockets.single.serverAddJson(<String, Object?>{
      'type': 'error',
      'topic': 'conversation.events',
      'scope': <String, Object?>{'conversationId': 'conv_1'},
      'code': 'TOKEN_EXPIRED',
      'message': 'WebSocket authorization expired.',
    });

    await waitFor(() => sockets.length == 2);
    expect(refreshCalls, <String>['refresh']);
    expect(sockets[0].connectHeaders['authorization'], 'Bearer token_old');
    expect(sockets[1].connectHeaders['authorization'], 'Bearer token_new');
    expect(sockets[1].sentJson.single['afterSeq'], 8);

    await subscription.cancel();
    await client.close();
  });

  test(
      'does not refresh twice when token expired frame is followed by auth close',
      () async {
    final sockets = <FakeNotificationSocket>[];
    final tokens = <String>['token_old'];
    final refreshCalls = <String>[];
    final client = DaemonNotificationClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenProvider: () => tokens.last,
      fetchBackfill: (_, {required afterSeq}) async => <ConversationEvent>[],
      refreshAuth: () async {
        refreshCalls.add('refresh');
        tokens.add('token_new');
      },
      config: NotificationClientConfig(
        connector: (_, headers) async {
          final socket = FakeNotificationSocket();
          socket.connectHeaders = Map<String, String>.from(headers);
          sockets.add(socket);
          return socket;
        },
        reconnectDelays: const <Duration>[Duration.zero],
      ),
    );

    final events = <ConversationEvent>[];
    final subscription = client
        .watchConversationEvents('conv_1', afterSeq: 7)
        .listen(events.add);

    await waitFor(() => sockets.length == 1);
    sockets.single.serverAddJson(eventFrame(seq: 8, text: 'before expiry'));
    await waitFor(() => events.length == 1);
    sockets.single.serverAddJson(<String, Object?>{
      'type': 'error',
      'topic': 'conversation.events',
      'scope': <String, Object?>{'conversationId': 'conv_1'},
      'code': 'TOKEN_EXPIRED',
      'message': 'WebSocket authorization expired.',
    });
    await sockets.single.serverClose(1008, 'TOKEN_EXPIRED');

    await waitFor(() => sockets.length == 2);
    expect(refreshCalls, <String>['refresh']);
    expect(sockets[0].connectHeaders['authorization'], 'Bearer token_old');
    expect(sockets[1].connectHeaders['authorization'], 'Bearer token_new');
    expect(sockets[1].sentJson.single['afterSeq'], 8);

    await subscription.cancel();
    await client.close();
  });

  test('refreshes token after auth websocket close and reconnects from cursor',
      () async {
    final sockets = <FakeNotificationSocket>[];
    final tokens = <String>['token_old'];
    final refreshCalls = <String>[];
    final client = DaemonNotificationClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenProvider: () => tokens.last,
      fetchBackfill: (_, {required afterSeq}) async => <ConversationEvent>[],
      refreshAuth: () async {
        refreshCalls.add('refresh');
        tokens.add('token_new');
      },
      config: NotificationClientConfig(
        connector: (_, headers) async {
          final socket = FakeNotificationSocket();
          socket.connectHeaders = Map<String, String>.from(headers);
          sockets.add(socket);
          return socket;
        },
        reconnectDelays: const <Duration>[Duration.zero],
      ),
    );

    final events = <ConversationEvent>[];
    final subscription = client
        .watchConversationEvents('conv_1', afterSeq: 7)
        .listen(events.add);

    await waitFor(() => sockets.length == 1);
    sockets.single.serverAddJson(eventFrame(seq: 8, text: 'before close'));
    await waitFor(() => events.length == 1);
    await sockets.single.serverClose(1008, 'AUTH_REQUIRED');

    await waitFor(() => sockets.length == 2);
    expect(refreshCalls, <String>['refresh']);
    expect(sockets[0].connectHeaders['authorization'], 'Bearer token_old');
    expect(sockets[1].connectHeaders['authorization'], 'Bearer token_new');
    expect(sockets[1].sentJson.single['afterSeq'], 8);

    await subscription.cancel();
    await client.close();
  });

  test('does not refresh token from natural-language close reasons', () async {
    final sockets = <FakeNotificationSocket>[];
    final delay = ControlledDelay();
    final refreshCalls = <String>[];
    final client = DaemonNotificationClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenProvider: () => 'token_1',
      fetchBackfill: (_, {required afterSeq}) async => <ConversationEvent>[],
      refreshAuth: () async {
        refreshCalls.add('refresh');
      },
      config: NotificationClientConfig(
        connector: (_, __) async {
          final socket = FakeNotificationSocket();
          sockets.add(socket);
          return socket;
        },
        reconnectDelays: const <Duration>[Duration(seconds: 30)],
        reconnectDelayWaiter: delay.wait,
      ),
    );

    final subscription =
        client.watchConversationEvents('conv_1', afterSeq: 7).listen((_) {});

    await waitFor(() => sockets.length == 1);
    await sockets.single.serverClose(1008, 'Bearer token required');
    await delay.started.future;

    expect(refreshCalls, isEmpty);
    await client.close();
    await subscription.cancel();
  });

  test('surfaces forbidden protocol errors without reconnecting', () async {
    final sockets = <FakeNotificationSocket>[];
    final client = DaemonNotificationClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenProvider: () => 'token_1',
      fetchBackfill: (_, {required afterSeq}) async => <ConversationEvent>[],
      config: NotificationClientConfig(
        connector: (_, __) async {
          final socket = FakeNotificationSocket();
          sockets.add(socket);
          return socket;
        },
        reconnectDelays: const <Duration>[Duration.zero],
      ),
    );

    final errors = <Object>[];
    final subscription = client
        .watchConversationEvents('conv_1', afterSeq: 7)
        .listen((_) {}, onError: errors.add);

    await waitFor(() => sockets.length == 1);
    sockets.single.serverAddJson(<String, Object?>{
      'type': 'error',
      'topic': 'conversation.events',
      'scope': <String, Object?>{'conversationId': 'conv_1'},
      'code': 'FORBIDDEN',
      'message': 'Device is not authorized for this conversation.',
    });

    await waitFor(() => errors.isNotEmpty);
    expect(sockets.length, 1);
    expect(errors.single, isA<DaemonNotificationException>());
    expect((errors.single as DaemonNotificationException).code, 'FORBIDDEN');

    await subscription.cancel();
    await client.close();
  });

  test('unscoped non-retryable errors reconnect without closing active routes',
      () async {
    final sockets = <FakeNotificationSocket>[];
    final delay = ControlledDelay();
    final client = DaemonNotificationClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenProvider: () => 'token_1',
      fetchBackfill: (_, {required afterSeq}) async => <ConversationEvent>[],
      config: NotificationClientConfig(
        connector: (_, __) async {
          final socket = FakeNotificationSocket();
          sockets.add(socket);
          return socket;
        },
        reconnectDelays: const <Duration>[Duration(milliseconds: 25)],
        reconnectDelayWaiter: delay.wait,
      ),
    );

    final conv1Errors = <Object>[];
    final conv2Errors = <Object>[];
    final conv1Events = <ConversationEvent>[];
    final conv2Events = <ConversationEvent>[];
    final conv1Subscription = client
        .watchConversationEvents('conv_1', afterSeq: 7)
        .listen(conv1Events.add, onError: conv1Errors.add);
    final conv2Subscription = client
        .watchConversationEvents('conv_2', afterSeq: 3)
        .listen(conv2Events.add, onError: conv2Errors.add);

    try {
      await waitFor(
          () => sockets.length == 1 && sockets.single.sentJson.length == 2);
      sockets.single.serverAddJson(<String, Object?>{
        'type': 'error',
        'code': 'FORBIDDEN',
        'message': 'Ambiguous global error.',
      });

      await waitFor(
        () =>
            conv1Errors.isNotEmpty ||
            conv2Errors.isNotEmpty ||
            delay.started.isCompleted,
      );
      expect(conv1Errors, isEmpty);
      expect(conv2Errors, isEmpty);
      expect(delay.started.isCompleted, isTrue);
      delay.complete();

      await waitFor(
          () => sockets.length == 2 && sockets[1].sentJson.length == 2);
      sockets[1].serverAddJson(eventFrame(
        conversationId: 'conv_1',
        seq: 8,
        text: 'one',
      ));
      sockets[1].serverAddJson(eventFrame(
        conversationId: 'conv_2',
        seq: 4,
        text: 'two',
      ));
      await waitFor(() => conv1Events.length == 1 && conv2Events.length == 1);
      expect(conv1Events.single.text, 'one');
      expect(conv2Events.single.text, 'two');
    } finally {
      delay.complete();
      await conv1Subscription.cancel();
      await conv2Subscription.cancel();
      await client.close();
    }
  });

  test('reconnects after connector failure and emits later events', () async {
    final sockets = <FakeNotificationSocket>[];
    final delay = ControlledDelay();
    var attempts = 0;
    final client = DaemonNotificationClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenProvider: () => 'token_1',
      fetchBackfill: (_, {required afterSeq}) async => <ConversationEvent>[],
      config: NotificationClientConfig(
        connector: (_, __) async {
          attempts += 1;
          if (attempts == 1) {
            throw const SocketConnectionFailure();
          }
          final socket = FakeNotificationSocket();
          sockets.add(socket);
          return socket;
        },
        reconnectDelays: const <Duration>[Duration(milliseconds: 25)],
        reconnectDelayWaiter: delay.wait,
      ),
    );

    final events = <ConversationEvent>[];
    final subscription = client
        .watchConversationEvents('conv_1', afterSeq: 7)
        .listen(events.add);

    await delay.started.future;
    expect(sockets, isEmpty);
    delay.complete();

    await waitFor(() => sockets.length == 1);
    expect(sockets.single.sentJson.single['afterSeq'], 7);

    sockets.single.serverAddJson(eventFrame(seq: 8, text: 'after reconnect'));
    await waitFor(() => events.length == 1);
    expect(events.single.seq, 8);

    await subscription.cancel();
    await client.close();
  });

  test(
      'uses REST backfill after repeated connector failures and advances cursor',
      () async {
    final sockets = <FakeNotificationSocket>[];
    final backfillAfterSeq = <int>[];
    var attempts = 0;
    final client = DaemonNotificationClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenProvider: () => 'token_1',
      fetchBackfill: (_, {required afterSeq}) async {
        backfillAfterSeq.add(afterSeq);
        return <ConversationEvent>[
          conversationEvent(seq: afterSeq + 1),
        ];
      },
      config: NotificationClientConfig(
        connector: (_, __) async {
          attempts += 1;
          if (attempts <= 3) {
            throw const SocketConnectionFailure();
          }
          final socket = FakeNotificationSocket();
          sockets.add(socket);
          return socket;
        },
        backfillAfterFailedAttempts: 3,
        reconnectDelays: const <Duration>[Duration.zero],
      ),
    );

    final events = <ConversationEvent>[];
    final subscription = client
        .watchConversationEvents('conv_1', afterSeq: 7)
        .listen(events.add);

    await waitFor(() => events.length == 1);
    expect(backfillAfterSeq, <int>[7]);
    expect(events.single.seq, 8);

    await waitFor(() => sockets.length == 1);
    expect(sockets.single.sentJson.single['afterSeq'], 8);

    await subscription.cancel();
    await client.close();
  });

  test(
      'uses REST backfill after repeated socket stream failures and advances cursor',
      () async {
    final sockets = <FakeNotificationSocket>[];
    final backfillAfterSeq = <int>[];
    final client = DaemonNotificationClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenProvider: () => 'token_1',
      fetchBackfill: (_, {required afterSeq}) async {
        backfillAfterSeq.add(afterSeq);
        return <ConversationEvent>[
          conversationEvent(seq: afterSeq + 1),
        ];
      },
      config: NotificationClientConfig(
        connector: (_, __) async {
          final socket = FakeNotificationSocket();
          sockets.add(socket);
          return socket;
        },
        backfillAfterFailedAttempts: 3,
        reconnectDelays: const <Duration>[Duration.zero],
      ),
    );

    final events = <ConversationEvent>[];
    final subscription = client
        .watchConversationEvents('conv_1', afterSeq: 7)
        .listen(events.add);

    await waitFor(() => sockets.length == 1);
    await sockets[0].serverFail(const SocketConnectionFailure());
    await waitFor(() => sockets.length == 2);
    await sockets[1].serverFail(const SocketConnectionFailure());
    await waitFor(() => sockets.length == 3);
    await sockets[2].serverFail(const SocketConnectionFailure());

    await waitFor(() => events.length == 1);
    expect(backfillAfterSeq, <int>[7]);
    expect(events.single.seq, 8);

    await waitFor(() => sockets.length == 4);
    expect(sockets[3].sentJson.single['afterSeq'], 8);

    await subscription.cancel();
    await client.close();
  });

  test('backfills active routes concurrently after socket failures', () async {
    final allowFirstConnect = Completer<void>();
    final firstBackfillStarted = Completer<void>();
    final releaseBackfills = Completer<void>();
    final sockets = <FakeNotificationSocket>[];
    final backfillStarts = <String>[];
    var attempts = 0;
    final client = DaemonNotificationClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenProvider: () => 'token_1',
      fetchBackfill: (conversationId, {required afterSeq}) async {
        backfillStarts.add(conversationId);
        if (!firstBackfillStarted.isCompleted) {
          firstBackfillStarted.complete();
        }
        await releaseBackfills.future;
        return <ConversationEvent>[
          ConversationEvent.fromJson(<String, Object?>{
            'seq': afterSeq + 1,
            'conversationId': conversationId,
            'type': 'assistant.message',
            'createdAt': '2026-05-23T05:18:14.000Z',
            'text': conversationId,
          }),
        ];
      },
      config: NotificationClientConfig(
        connector: (_, __) async {
          attempts += 1;
          if (attempts == 1) {
            await allowFirstConnect.future;
            throw const SocketConnectionFailure();
          }
          final socket = FakeNotificationSocket();
          sockets.add(socket);
          return socket;
        },
        backfillAfterFailedAttempts: 1,
        reconnectDelays: const <Duration>[Duration.zero],
      ),
    );

    final conv1Subscription =
        client.watchConversationEvents('conv_1', afterSeq: 7).listen((_) {});
    final conv2Subscription =
        client.watchConversationEvents('conv_2', afterSeq: 3).listen((_) {});

    allowFirstConnect.complete();
    await firstBackfillStarted.future;
    await Future<void>.delayed(Duration.zero);
    final startedBeforeAnyBackfillCompletes = List<String>.of(backfillStarts);
    releaseBackfills.complete();

    expect(
      startedBeforeAnyBackfillCompletes,
      unorderedEquals(<String>['conv_1', 'conv_2']),
    );
    await waitFor(() => sockets.length == 1);

    await conv1Subscription.cancel();
    await conv2Subscription.cancel();
    await client.close();
  });

  test('limits concurrent route backfills after socket failures', () async {
    final allowFirstConnect = Completer<void>();
    final fourBackfillsStarted = Completer<void>();
    final sockets = <FakeNotificationSocket>[];
    final backfillStarts = <String>[];
    final backfillReleases = <Completer<void>>[];
    var attempts = 0;
    final client = DaemonNotificationClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenProvider: () => 'token_1',
      fetchBackfill: (conversationId, {required afterSeq}) async {
        backfillStarts.add(conversationId);
        final release = Completer<void>();
        backfillReleases.add(release);
        if (backfillStarts.length == 4 && !fourBackfillsStarted.isCompleted) {
          fourBackfillsStarted.complete();
        }
        await release.future;
        return <ConversationEvent>[
          ConversationEvent.fromJson(<String, Object?>{
            'seq': afterSeq + 1,
            'conversationId': conversationId,
            'type': 'assistant.message',
            'createdAt': '2026-05-23T05:18:14.000Z',
            'text': conversationId,
          }),
        ];
      },
      config: NotificationClientConfig(
        connector: (_, __) async {
          attempts += 1;
          if (attempts == 1) {
            await allowFirstConnect.future;
            throw const SocketConnectionFailure();
          }
          final socket = FakeNotificationSocket();
          sockets.add(socket);
          return socket;
        },
        backfillAfterFailedAttempts: 1,
        reconnectDelays: const <Duration>[Duration.zero],
      ),
    );

    final subscriptions = <StreamSubscription<ConversationEvent>>[];
    try {
      for (var index = 1; index <= 5; index += 1) {
        subscriptions.add(client
            .watchConversationEvents('conv_$index', afterSeq: index)
            .listen((_) {}));
      }

      allowFirstConnect.complete();
      await fourBackfillsStarted.future;
      await Future<void>.delayed(Duration.zero);
      expect(backfillStarts.length, 4);

      for (final release in List<Completer<void>>.of(backfillReleases)) {
        release.complete();
      }
      await waitFor(() => backfillStarts.length == 5);
      for (final release in List<Completer<void>>.of(backfillReleases)) {
        if (!release.isCompleted) release.complete();
      }
      await waitFor(() => sockets.length == 1);
    } finally {
      if (!allowFirstConnect.isCompleted) {
        allowFirstConnect.complete();
      }
      for (final release in backfillReleases) {
        if (!release.isCompleted) release.complete();
      }
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      await client.close();
    }
  });

  test('failed recovery backfill still waits before reconnecting', () async {
    final delay = ControlledDelay();
    var attempts = 0;
    var backfillCalls = 0;
    final client = DaemonNotificationClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenProvider: () => 'token_1',
      fetchBackfill: (_, {required afterSeq}) async {
        backfillCalls += 1;
        throw StateError('backfill unavailable');
      },
      config: NotificationClientConfig(
        connector: (_, __) async {
          attempts += 1;
          throw const SocketConnectionFailure();
        },
        backfillAfterFailedAttempts: 1,
        reconnectDelays: const <Duration>[Duration(seconds: 30)],
        reconnectDelayWaiter: delay.wait,
      ),
    );

    final subscription =
        client.watchConversationEvents('conv_1', afterSeq: 7).listen((_) {});
    final done = subscription.asFuture<void>();

    await delay.started.future.timeout(const Duration(milliseconds: 100));

    expect(attempts, 1);
    expect(backfillCalls, 1);

    await client.close();
    await done.timeout(const Duration(milliseconds: 100));
    await subscription.cancel();
  });

  test('close actively closes current socket', () async {
    final socket = FakeNotificationSocket();
    final client = DaemonNotificationClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenProvider: () => 'token_1',
      fetchBackfill: (_, {required afterSeq}) async => <ConversationEvent>[],
      config: NotificationClientConfig(connector: (_, __) async => socket),
    );

    final subscription =
        client.watchConversationEvents('conv_1', afterSeq: 7).listen((_) {});
    await waitFor(() => socket.sentJson.isNotEmpty);

    await client.close();

    expect(socket.closeCalls, 1);
    await subscription.cancel();
  });

  test('cancel ignores unsubscribe write failures and closes current socket',
      () async {
    final socket = FakeNotificationSocket(
      throwOnFrameTypes: const <String>{'unsubscribe'},
    );
    final client = DaemonNotificationClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenProvider: () => 'token_1',
      fetchBackfill: (_, {required afterSeq}) async => <ConversationEvent>[],
      config: NotificationClientConfig(connector: (_, __) async => socket),
    );

    final subscription =
        client.watchConversationEvents('conv_1', afterSeq: 7).listen((_) {});
    await waitFor(() => socket.sentJson.isNotEmpty);

    await subscription.cancel();

    expect(socket.closeCalls, 1);
    await client.close();
  });

  test('close wakes delayed reconnect', () async {
    final delay = ControlledDelay();
    var attempts = 0;
    final client = DaemonNotificationClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenProvider: () => 'token_1',
      fetchBackfill: (_, {required afterSeq}) async => <ConversationEvent>[],
      config: NotificationClientConfig(
        connector: (_, __) async {
          attempts += 1;
          throw const SocketConnectionFailure();
        },
        reconnectDelays: const <Duration>[Duration(seconds: 30)],
        reconnectDelayWaiter: delay.wait,
      ),
    );

    final subscription =
        client.watchConversationEvents('conv_1', afterSeq: 7).listen((_) {});
    final done = subscription.asFuture<void>();

    await delay.started.future;
    await client.close();
    await done.timeout(const Duration(milliseconds: 100));

    expect(attempts, 1);
    await subscription.cancel();
  });

  test('route changes wake delayed reconnect', () async {
    final sockets = <FakeNotificationSocket>[];
    final delay = ControlledDelay();
    final client = DaemonNotificationClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenProvider: () => 'token_1',
      fetchBackfill: (_, {required afterSeq}) async => <ConversationEvent>[],
      config: NotificationClientConfig(
        connector: (_, __) async {
          final socket = FakeNotificationSocket();
          sockets.add(socket);
          return socket;
        },
        reconnectDelays: const <Duration>[Duration(seconds: 30)],
        reconnectDelayWaiter: delay.wait,
      ),
    );

    final firstSubscription =
        client.watchConversationEvents('conv_1', afterSeq: 7).listen((_) {});
    await waitFor(() => sockets.length == 1);
    await sockets.single.serverFail(const SocketConnectionFailure());
    await delay.started.future;

    await firstSubscription.cancel();
    final secondSubscription =
        client.watchConversationEvents('conv_2', afterSeq: 3).listen((_) {});

    await waitFor(() => sockets.length == 2);
    expect(sockets[1].sentJson.single['scope'],
        <String, Object?>{'conversationId': 'conv_2'});
    expect(sockets[1].sentJson.single['afterSeq'], 3);

    await secondSubscription.cancel();
    await client.close();
  });

  test('resubscribing after last watcher cancel waits for a fresh socket',
      () async {
    final sockets = <FakeNotificationSocket>[];
    var connectCount = 0;
    final client = DaemonNotificationClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenProvider: () => 'token_1',
      fetchBackfill: (_, {required afterSeq}) async => <ConversationEvent>[],
      config: NotificationClientConfig(
        connector: (_, __) async {
          connectCount += 1;
          final socket = FakeNotificationSocket(
            clientCloseCompletesStream: connectCount != 1,
            throwOnAddAfterClose: true,
          );
          sockets.add(socket);
          return socket;
        },
        reconnectDelays: const <Duration>[Duration.zero],
      ),
    );

    final firstSubscription =
        client.watchConversationEvents('conv_1', afterSeq: 7).listen((_) {});
    await waitFor(
      () => sockets.length == 1 && sockets.single.sentJson.length == 1,
    );

    await firstSubscription.cancel();
    expect(sockets.single.closeCalls, 1);

    StreamSubscription<ConversationEvent>? secondSubscription;
    Object? subscribeError;
    try {
      try {
        secondSubscription = client
            .watchConversationEvents('conv_1', afterSeq: 7)
            .listen((_) {});
      } catch (error) {
        subscribeError = error;
      }
      expect(subscribeError, isNull);
      expect(
        sockets.single.sentJson.where((frame) => frame['type'] == 'subscribe'),
        hasLength(1),
      );

      await sockets.single.serverClose(1000, 'closed');
      await waitFor(
        () => sockets.length == 2 && sockets[1].sentJson.isNotEmpty,
      );
      expect(sockets[1].sentJson.single['type'], 'subscribe');
      expect(sockets[1].sentJson.single['afterSeq'], 7);
    } finally {
      if (sockets.isNotEmpty && !sockets.first.isStreamClosed) {
        await sockets.first.serverClose(1000, 'cleanup');
      }

      await secondSubscription?.cancel();
      await client.close();
    }
  });

  test('ignores malformed frames and emits later valid events', () async {
    final socket = FakeNotificationSocket();
    final client = DaemonNotificationClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenProvider: () => 'token_1',
      fetchBackfill: (_, {required afterSeq}) async => <ConversationEvent>[],
      config: NotificationClientConfig(connector: (_, __) async => socket),
    );

    final events = <ConversationEvent>[];
    final subscription = client
        .watchConversationEvents('conv_1', afterSeq: 7)
        .listen(events.add);

    await waitFor(() => socket.sentJson.isNotEmpty);
    socket.serverAddRaw('{bad json');
    socket.serverAddJson(<String, Object?>{'type': 'event'});
    socket.serverAddJson(<String, Object?>{
      'type': 'event',
      'payload': 'not an object',
    });
    socket.serverAddJson(eventFrame(seq: 8, text: 'valid'));

    await waitFor(() => events.length == 1);
    expect(events.single.seq, 8);
    expect(events.single.text, 'valid');

    await subscription.cancel();
    await client.close();
  });

  test('replay truncated without cursor advancement waits before reconnect',
      () async {
    final sockets = <FakeNotificationSocket>[];
    final delay = ControlledDelay();
    final backfillAfterSeq = <int>[];
    final client = DaemonNotificationClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenProvider: () => 'token_1',
      fetchBackfill: (_, {required afterSeq}) async {
        backfillAfterSeq.add(afterSeq);
        return <ConversationEvent>[];
      },
      config: NotificationClientConfig(
        connector: (_, __) async {
          final socket = FakeNotificationSocket();
          sockets.add(socket);
          return socket;
        },
        reconnectDelays: const <Duration>[Duration(milliseconds: 25)],
        reconnectDelayWaiter: delay.wait,
      ),
    );

    final subscription =
        client.watchConversationEvents('conv_1', afterSeq: 7).listen((_) {});

    await waitFor(() => sockets.length == 1);
    sockets.single.serverAddJson(<String, Object?>{
      'type': 'error',
      'topic': 'conversation.events',
      'scope': <String, Object?>{'conversationId': 'conv_1'},
      'code': 'REPLAY_TRUNCATED',
    });

    await delay.started.future;
    expect(backfillAfterSeq, <int>[7]);
    expect(sockets.length, 1);
    delay.complete();

    await waitFor(() => sockets.length == 2);
    expect(sockets[1].sentJson.single['afterSeq'], 7);

    await subscription.cancel();
    await client.close();
  });
}

class FakeNotificationSocket implements NotificationSocket {
  FakeNotificationSocket({
    this.clientCloseCompletesStream = true,
    this.throwOnAddAfterClose = false,
    this.throwOnFrameTypes = const <String>{},
  });

  final StreamController<Object?> _incoming = StreamController<Object?>();
  final List<Map<String, Object?>> sentJson = <Map<String, Object?>>[];
  final bool clientCloseCompletesStream;
  final bool throwOnAddAfterClose;
  final Set<String> throwOnFrameTypes;
  Map<String, String> connectHeaders = <String, String>{};
  int? _closeCode;
  String? _closeReason;
  int closeCalls = 0;
  bool _clientClosed = false;

  bool get isStreamClosed => _incoming.isClosed;

  @override
  Stream<Object?> get stream => _incoming.stream;

  @override
  int? get closeCode => _closeCode;

  @override
  String? get closeReason => _closeReason;

  @override
  void add(String data) {
    if (throwOnAddAfterClose && _clientClosed) {
      throw StateError('StreamSink is closed');
    }
    final frame = jsonObject(data);
    final type = frame['type'];
    if (type is String && throwOnFrameTypes.contains(type)) {
      throw StateError('StreamSink is closed');
    }
    sentJson.add(frame);
  }

  void serverAddJson(Map<String, Object?> json) {
    _incoming.add(json);
  }

  void serverAddRaw(Object? value) {
    _incoming.add(value);
  }

  Future<void> serverFail(Object error) async {
    _incoming.addError(error);
    await _incoming.close();
  }

  Future<void> serverClose(int code, String reason) async {
    _closeCode = code;
    _closeReason = reason;
    await _incoming.close();
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    if (!_clientClosed) {
      _clientClosed = true;
      closeCalls += 1;
    }
    if (clientCloseCompletesStream && !_incoming.isClosed) {
      await _incoming.close();
    }
  }
}

class ControlledDelay {
  final Completer<void> started = Completer<void>();
  final Completer<void> _released = Completer<void>();

  Future<void> wait(Duration delay) {
    if (!started.isCompleted) {
      started.complete();
    }
    return _released.future;
  }

  void complete() {
    if (!_released.isCompleted) {
      _released.complete();
    }
  }
}

class SocketConnectionFailure implements Exception {
  const SocketConnectionFailure();
}

Map<String, Object?> jsonObject(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map) {
    fail('Expected JSON object, got ${decoded.runtimeType}.');
  }
  return Map<String, Object?>.from(decoded);
}

ConversationEvent conversationEvent({required int seq}) =>
    ConversationEvent.fromJson(<String, Object?>{
      'seq': seq,
      'conversationId': 'conv_1',
      'type': 'assistant.message',
      'createdAt': '2026-05-23T05:18:14.000Z',
      'text': 'backfilled',
    });

Map<String, Object?> eventFrame({
  String conversationId = 'conv_1',
  required int seq,
  required String text,
}) =>
    <String, Object?>{
      'type': 'event',
      'topic': 'conversation.events',
      'scope': <String, Object?>{'conversationId': conversationId},
      'seq': seq,
      'payload': <String, Object?>{
        'seq': seq,
        'conversationId': conversationId,
        'type': 'assistant.message',
        'createdAt': '2026-05-23T05:18:14.000Z',
        'text': text,
      },
    };

Future<void> waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 20; attempt += 1) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Condition was not met before timeout.');
}
