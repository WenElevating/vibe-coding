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
typedef NotificationAuthRefresher = Future<void> Function();
typedef NotificationSocketConnector = Future<NotificationSocket> Function(
  Uri uri,
  Map<String, String> headers,
);
typedef NotificationReconnectDelayWaiter = Future<void> Function(
  Duration delay,
);

// Empty reconnectDelays still back off so persistent failures cannot spin.
const Duration _fallbackReconnectDelay = Duration(milliseconds: 100);

abstract class NotificationSocket {
  Stream<Object?> get stream;
  int? get closeCode;
  String? get closeReason;
  void add(String data);
  Future<void> close([int? code, String? reason]);
}

class IoNotificationSocket implements NotificationSocket {
  IoNotificationSocket(this._socket);

  final WebSocket _socket;

  @override
  Stream<Object?> get stream => _socket;

  @override
  int? get closeCode => _socket.closeCode;

  @override
  String? get closeReason => _socket.closeReason;

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
    this.refreshAuth,
    NotificationSocketConnector? connector,
    NotificationReconnectDelayWaiter? reconnectDelayWaiter,
    this.backfillAfterFailedAttempts = 3,
    this.reconnectDelays = const <Duration>[
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
      Duration(seconds: 16),
      Duration(seconds: 30),
    ],
  })  : assert(backfillAfterFailedAttempts > 0),
        _connector = connector ?? _connectIoSocket,
        _reconnectDelayWaiter =
            reconnectDelayWaiter ?? ((delay) => Future<void>.delayed(delay));

  final Uri baseUri;
  final NotificationTokenProvider tokenProvider;
  final NotificationBackfillFetcher fetchBackfill;
  final NotificationAuthRefresher? refreshAuth;
  final NotificationSocketConnector _connector;
  final NotificationReconnectDelayWaiter _reconnectDelayWaiter;
  final int backfillAfterFailedAttempts;
  final List<Duration> reconnectDelays;

  bool _closed = false;
  final Set<NotificationSocket> _activeSockets = <NotificationSocket>{};
  final Completer<void> _closedCompleter = Completer<void>();

  static Object? decodeJson(String source) => jsonDecode(source);

  @override
  Stream<ConversationEvent> watchConversationEvents(
    String conversationId, {
    required int afterSeq,
  }) async* {
    var cursor = afterSeq;
    var attempt = 0;
    var failedAttemptsSinceBackfill = 0;
    while (!_closed) {
      NotificationSocket? socket;
      var skipDelay = false;
      var authRecovered = false;
      var socketFailed = false;
      try {
        final token = tokenProvider();
        socket = await _connector(
          daemonNotificationWebSocketUri(baseUri),
          <String, String>{if (token != null) 'authorization': 'Bearer $token'},
        );
        if (_closed) {
          break;
        }
        _activeSockets.add(socket);
        socket.add(jsonEncode(<String, Object?>{
          'type': 'subscribe',
          'id': 'sub_$conversationId',
          'topic': 'conversation.events',
          'scope': <String, Object?>{'conversationId': conversationId},
          'afterSeq': cursor,
        }));
        attempt = 0;
        await for (final raw in socket.stream) {
          final frame = _decodeFrame(raw);
          if (frame == null) {
            continue;
          }
          if (frame['type'] == 'event') {
            final event = _eventFromFrame(frame);
            if (event == null) {
              continue;
            }
            if (event.seq > cursor) {
              cursor = event.seq;
            }
            failedAttemptsSinceBackfill = 0;
            yield event;
          } else if (frame['type'] == 'error' &&
              frame['code'] == 'REPLAY_TRUNCATED') {
            final previousCursor = cursor;
            final backfill =
                await fetchBackfill(conversationId, afterSeq: cursor);
            for (final event in backfill) {
              if (event.seq > cursor) {
                cursor = event.seq;
              }
              failedAttemptsSinceBackfill = 0;
              yield event;
            }
            skipDelay = cursor > previousCursor;
            break;
          } else if (frame['type'] == 'error' &&
              (frame['code'] == 'AUTH_REQUIRED' ||
                  frame['code'] == 'TOKEN_EXPIRED')) {
            if (refreshAuth != null) {
              await refreshAuth!();
              authRecovered = true;
              skipDelay = true;
            }
            break;
          }
        }
        if (!authRecovered && _isAuthClose(socket)) {
          if (refreshAuth != null) {
            await refreshAuth!();
            skipDelay = true;
          }
        }
      } catch (_) {
        socketFailed = true;
        // Connector and socket stream failures use the normal reconnect path.
      } finally {
        if (socket != null) {
          _activeSockets.remove(socket);
          await _closeSocket(socket);
        }
      }
      if (!_closed && socketFailed) {
        failedAttemptsSinceBackfill += 1;
        if (failedAttemptsSinceBackfill >= backfillAfterFailedAttempts) {
          failedAttemptsSinceBackfill = 0;
          final backfill =
              await fetchBackfill(conversationId, afterSeq: cursor);
          for (final event in backfill) {
            if (event.seq <= cursor) {
              continue;
            }
            cursor = event.seq;
            yield event;
          }
        }
      }
      if (_closed) {
        break;
      }
      if (skipDelay) {
        continue;
      }
      final delay = _delayForAttempt(attempt);
      attempt += 1;
      await _waitForReconnectDelay(delay);
    }
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    if (!_closedCompleter.isCompleted) {
      _closedCompleter.complete();
    }
    final sockets = List<NotificationSocket>.of(_activeSockets);
    await Future.wait<void>(sockets.map(_closeSocket));
  }

  Duration _delayForAttempt(int attempt) {
    if (reconnectDelays.isEmpty) {
      return _fallbackReconnectDelay;
    }
    final delayIndex = attempt.clamp(0, reconnectDelays.length - 1) as int;
    return reconnectDelays[delayIndex];
  }

  Future<void> _waitForReconnectDelay(Duration delay) async {
    if (_closed || delay <= Duration.zero) {
      return;
    }
    await Future.any<void>(<Future<void>>[
      _reconnectDelayWaiter(delay),
      _closedCompleter.future,
    ]);
  }
}

bool _isAuthClose(NotificationSocket socket) {
  if (socket.closeCode != WebSocketStatus.policyViolation) {
    return false;
  }
  final reason = socket.closeReason?.toLowerCase();
  if (reason == null) {
    return false;
  }
  return reason.contains('bearer token required') ||
      reason.contains('auth_required') ||
      reason.contains('token_expired') ||
      reason.contains('authorization expired');
}

Map<String, Object?>? _decodeFrame(Object? raw) {
  try {
    final decoded = raw is String ? jsonDecode(raw) : raw;
    if (decoded is! Map) {
      return null;
    }
    return Map<String, Object?>.from(decoded);
  } catch (_) {
    return null;
  }
}

ConversationEvent? _eventFromFrame(Map<String, Object?> frame) {
  final payload = frame['payload'];
  if (payload is! Map) {
    return null;
  }
  try {
    return ConversationEvent.fromJson(Map<String, Object?>.from(payload));
  } catch (_) {
    return null;
  }
}

Future<void> _closeSocket(NotificationSocket socket) async {
  try {
    await socket.close();
  } catch (_) {
    // Closing is best-effort because the socket may already be gone.
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
