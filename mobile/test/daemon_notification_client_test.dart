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
}

class FakeNotificationSocket implements NotificationSocket {
  final StreamController<Object?> _incoming = StreamController<Object?>();
  final List<Map<String, Object?>> sentJson = <Map<String, Object?>>[];

  @override
  Stream<Object?> get stream => _incoming.stream;

  @override
  void add(String data) {
    sentJson.add(jsonObject(data));
  }

  void serverAddJson(Map<String, Object?> json) {
    _incoming.add(json);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    await _incoming.close();
  }
}

Map<String, Object?> jsonObject(String source) =>
    Map<String, Object?>.from(DaemonNotificationClient.decodeJson(source));
