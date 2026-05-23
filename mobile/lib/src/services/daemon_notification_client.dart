import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../data/services/notification_service.dart';
import '../models/protocol.dart';

typedef NotificationTokenProvider = String? Function();
typedef NotificationBackfillFetcher = Future<List<ConversationEvent>> Function(
  String conversationId, {
  required int afterSeq,
});
typedef NotificationSocketConnector = Future<NotificationSocket> Function(
  Uri uri,
  Map<String, String> headers,
);

abstract class NotificationSocket {
  Stream<Object?> get stream;
  void add(String data);
  Future<void> close([int? code, String? reason]);
}

class IoNotificationSocket implements NotificationSocket {
  IoNotificationSocket(this._socket);

  final WebSocket _socket;

  @override
  Stream<Object?> get stream => _socket;

  @override
  void add(String data) => _socket.add(data);

  @override
  Future<void> close([int? code, String? reason]) =>
      _socket.close(code, reason);
}

class DaemonNotificationClient implements NotificationService {
  DaemonNotificationClient({
    required this.baseUri,
    required this.tokenProvider,
    required this.fetchBackfill,
    NotificationSocketConnector? connector,
    this.reconnectDelays = const <Duration>[
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
      Duration(seconds: 16),
      Duration(seconds: 30),
    ],
  }) : _connector = connector ?? _connectIoSocket;

  final Uri baseUri;
  final NotificationTokenProvider tokenProvider;
  final NotificationBackfillFetcher fetchBackfill;
  final NotificationSocketConnector _connector;
  final List<Duration> reconnectDelays;

  bool _closed = false;

  static Object? decodeJson(String source) => jsonDecode(source);

  @override
  Stream<ConversationEvent> watchConversationEvents(
    String conversationId, {
    required int afterSeq,
  }) async* {
    var cursor = afterSeq;
    var attempt = 0;
    while (!_closed) {
      NotificationSocket? socket;
      var reconnectNow = false;
      try {
        final token = tokenProvider();
        socket = await _connector(
          daemonNotificationWebSocketUri(baseUri),
          <String, String>{if (token != null) 'authorization': 'Bearer $token'},
        );
        socket.add(jsonEncode(<String, Object?>{
          'type': 'subscribe',
          'id': 'sub_$conversationId',
          'topic': 'conversation.events',
          'scope': <String, Object?>{'conversationId': conversationId},
          'afterSeq': cursor,
        }));
        attempt = 0;
        await for (final raw in socket.stream) {
          final decoded = raw is String ? jsonDecode(raw) : raw;
          if (decoded is! Map) {
            continue;
          }
          final frame = Map<String, Object?>.from(decoded);
          if (frame['type'] == 'event') {
            final payload = Map<String, Object?>.from(frame['payload'] as Map);
            final event = ConversationEvent.fromJson(payload);
            if (event.seq > cursor) {
              cursor = event.seq;
            }
            yield event;
          } else if (frame['type'] == 'error' &&
              frame['code'] == 'REPLAY_TRUNCATED') {
            final backfill =
                await fetchBackfill(conversationId, afterSeq: cursor);
            for (final event in backfill) {
              if (event.seq > cursor) {
                cursor = event.seq;
              }
              yield event;
            }
            reconnectNow = true;
            break;
          } else if (frame['type'] == 'error' &&
              (frame['code'] == 'AUTH_REQUIRED' ||
                  frame['code'] == 'TOKEN_EXPIRED')) {
            break;
          }
        }
      } finally {
        await socket?.close();
      }
      if (_closed) {
        break;
      }
      if (reconnectNow || reconnectDelays.isEmpty) {
        continue;
      }
      final delayIndex = attempt.clamp(0, reconnectDelays.length - 1) as int;
      final delay = reconnectDelays[delayIndex];
      attempt += 1;
      await Future<void>.delayed(delay);
    }
  }

  Future<void> close() async {
    _closed = true;
  }
}

Uri daemonNotificationWebSocketUri(Uri baseUri) {
  final scheme = baseUri.scheme == 'https' ? 'wss' : 'ws';
  return Uri(
    scheme: scheme,
    userInfo: baseUri.userInfo,
    host: baseUri.host,
    port: baseUri.hasPort ? baseUri.port : 0,
    path: '/api/notifications/ws',
  );
}

Future<NotificationSocket> _connectIoSocket(
  Uri uri,
  Map<String, String> headers,
) async {
  final socket = await WebSocket.connect(uri.toString(), headers: headers);
  return IoNotificationSocket(socket);
}
