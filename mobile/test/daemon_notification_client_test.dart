import 'dart:async';

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
      connector: (_, __) async => socket,
      fetchBackfill: (_, {required afterSeq}) async => <ConversationEvent>[],
      reconnectDelays: const <Duration>[Duration(milliseconds: 1)],
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

  test('reconnects and resubscribes from backfill cursor after replay truncated',
      () async {
    final sockets = <FakeNotificationSocket>[];
    final backfillAfterSeq = <int>[];
    final client = DaemonNotificationClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenProvider: () => 'token_1',
      connector: (_, __) async {
        final socket = FakeNotificationSocket();
        sockets.add(socket);
        return socket;
      },
      fetchBackfill: (_, {required afterSeq}) async {
        backfillAfterSeq.add(afterSeq);
        return <ConversationEvent>[
          conversationEvent(seq: 12),
        ];
      },
      reconnectDelays: const <Duration>[Duration.zero],
    );

    final events = <ConversationEvent>[];
    final subscription = client
        .watchConversationEvents('conv_1', afterSeq: 7)
        .listen(events.add);

    await waitFor(() => sockets.isNotEmpty);
    expect(sockets.single.sentJson.single['afterSeq'], 7);

    sockets.single.serverAddJson(<String, Object?>{
      'type': 'error',
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

  test('uses REST backfill after replay truncated error', () async {
    final socket = FakeNotificationSocket();
    final backfillCalls = <String>[];
    final client = DaemonNotificationClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenProvider: () => 'token_1',
      connector: (_, __) async => socket,
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

  test('refreshes token and reconnects from cursor after auth error', () async {
    final sockets = <FakeNotificationSocket>[];
    final tokens = <String>['token_old'];
    final refreshCalls = <String>[];
    final client = DaemonNotificationClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenProvider: () => tokens.last,
      connector: (_, headers) async {
        final socket = FakeNotificationSocket();
        socket.connectHeaders = Map<String, String>.from(headers);
        sockets.add(socket);
        return socket;
      },
      fetchBackfill: (_, {required afterSeq}) async => <ConversationEvent>[],
      refreshAuth: () async {
        refreshCalls.add('refresh');
        tokens.add('token_new');
      },
      reconnectDelays: const <Duration>[Duration.zero],
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

  test('does not refresh twice when token expired frame is followed by auth close',
      () async {
    final sockets = <FakeNotificationSocket>[];
    final tokens = <String>['token_old'];
    final refreshCalls = <String>[];
    final client = DaemonNotificationClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenProvider: () => tokens.last,
      connector: (_, headers) async {
        final socket = FakeNotificationSocket();
        socket.connectHeaders = Map<String, String>.from(headers);
        sockets.add(socket);
        return socket;
      },
      fetchBackfill: (_, {required afterSeq}) async => <ConversationEvent>[],
      refreshAuth: () async {
        refreshCalls.add('refresh');
        tokens.add('token_new');
      },
      reconnectDelays: const <Duration>[Duration.zero],
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
      connector: (_, headers) async {
        final socket = FakeNotificationSocket();
        socket.connectHeaders = Map<String, String>.from(headers);
        sockets.add(socket);
        return socket;
      },
      fetchBackfill: (_, {required afterSeq}) async => <ConversationEvent>[],
      refreshAuth: () async {
        refreshCalls.add('refresh');
        tokens.add('token_new');
      },
      reconnectDelays: const <Duration>[Duration.zero],
    );

    final events = <ConversationEvent>[];
    final subscription = client
        .watchConversationEvents('conv_1', afterSeq: 7)
        .listen(events.add);

    await waitFor(() => sockets.length == 1);
    sockets.single.serverAddJson(eventFrame(seq: 8, text: 'before close'));
    await waitFor(() => events.length == 1);
    await sockets.single.serverClose(1008, 'Bearer token required');

    await waitFor(() => sockets.length == 2);
    expect(refreshCalls, <String>['refresh']);
    expect(sockets[0].connectHeaders['authorization'], 'Bearer token_old');
    expect(sockets[1].connectHeaders['authorization'], 'Bearer token_new');
    expect(sockets[1].sentJson.single['afterSeq'], 8);

    await subscription.cancel();
    await client.close();
  });

  test('reconnects after connector failure and emits later events', () async {
    final sockets = <FakeNotificationSocket>[];
    final delay = ControlledDelay();
    var attempts = 0;
    final client = DaemonNotificationClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenProvider: () => 'token_1',
      connector: (_, __) async {
        attempts += 1;
        if (attempts == 1) {
          throw const SocketConnectionFailure();
        }
        final socket = FakeNotificationSocket();
        sockets.add(socket);
        return socket;
      },
      fetchBackfill: (_, {required afterSeq}) async => <ConversationEvent>[],
      reconnectDelays: const <Duration>[Duration(milliseconds: 25)],
      reconnectDelayWaiter: delay.wait,
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

  test('close actively closes current socket', () async {
    final socket = FakeNotificationSocket();
    final client = DaemonNotificationClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenProvider: () => 'token_1',
      connector: (_, __) async => socket,
      fetchBackfill: (_, {required afterSeq}) async => <ConversationEvent>[],
    );

    final subscription = client
        .watchConversationEvents('conv_1', afterSeq: 7)
        .listen((_) {});
    await waitFor(() => socket.sentJson.isNotEmpty);

    await client.close();

    expect(socket.closeCalls, 1);
    await subscription.cancel();
  });

  test('close wakes delayed reconnect', () async {
    final delay = ControlledDelay();
    var attempts = 0;
    final client = DaemonNotificationClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenProvider: () => 'token_1',
      connector: (_, __) async {
        attempts += 1;
        throw const SocketConnectionFailure();
      },
      fetchBackfill: (_, {required afterSeq}) async => <ConversationEvent>[],
      reconnectDelays: const <Duration>[Duration(seconds: 30)],
      reconnectDelayWaiter: delay.wait,
    );

    final subscription = client
        .watchConversationEvents('conv_1', afterSeq: 7)
        .listen((_) {});
    final done = subscription.asFuture<void>();

    await delay.started.future;
    await client.close();
    await done.timeout(const Duration(milliseconds: 100));

    expect(attempts, 1);
    await subscription.cancel();
  });

  test('ignores malformed frames and emits later valid events', () async {
    final socket = FakeNotificationSocket();
    final client = DaemonNotificationClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenProvider: () => 'token_1',
      connector: (_, __) async => socket,
      fetchBackfill: (_, {required afterSeq}) async => <ConversationEvent>[],
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
    final client = DaemonNotificationClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenProvider: () => 'token_1',
      connector: (_, __) async {
        final socket = FakeNotificationSocket();
        sockets.add(socket);
        return socket;
      },
      fetchBackfill: (_, {required afterSeq}) async => <ConversationEvent>[],
      reconnectDelays: const <Duration>[Duration(milliseconds: 25)],
      reconnectDelayWaiter: delay.wait,
    );

    final subscription = client
        .watchConversationEvents('conv_1', afterSeq: 7)
        .listen((_) {});

    await waitFor(() => sockets.length == 1);
    sockets.single.serverAddJson(<String, Object?>{
      'type': 'error',
      'code': 'REPLAY_TRUNCATED',
    });

    await delay.started.future;
    expect(sockets.length, 1);
    delay.complete();

    await waitFor(() => sockets.length == 2);
    expect(sockets[1].sentJson.single['afterSeq'], 7);

    await subscription.cancel();
    await client.close();
  });
}

class FakeNotificationSocket implements NotificationSocket {
  final StreamController<Object?> _incoming = StreamController<Object?>();
  final List<Map<String, Object?>> sentJson = <Map<String, Object?>>[];
  Map<String, String> connectHeaders = <String, String>{};
  int? _closeCode;
  String? _closeReason;
  int closeCalls = 0;

  @override
  Stream<Object?> get stream => _incoming.stream;

  @override
  int? get closeCode => _closeCode;

  @override
  String? get closeReason => _closeReason;

  @override
  void add(String data) {
    sentJson.add(jsonObject(data));
  }

  void serverAddJson(Map<String, Object?> json) {
    _incoming.add(json);
  }

  void serverAddRaw(Object? value) {
    _incoming.add(value);
  }

  Future<void> serverClose(int code, String reason) async {
    _closeCode = code;
    _closeReason = reason;
    await _incoming.close();
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    if (!_incoming.isClosed) {
      closeCalls += 1;
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
  final decoded = DaemonNotificationClient.decodeJson(source);
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

Map<String, Object?> eventFrame({required int seq, required String text}) =>
    <String, Object?>{
      'type': 'event',
      'topic': 'conversation.events',
      'scope': <String, Object?>{'conversationId': 'conv_1'},
      'seq': seq,
      'payload': <String, Object?>{
        'seq': seq,
        'conversationId': 'conv_1',
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
