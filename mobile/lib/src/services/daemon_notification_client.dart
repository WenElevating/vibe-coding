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
typedef NotificationTraceMarkRecorder = void Function(
  String name, {
  String? conversationId,
  int? seq,
  String? eventType,
  String? correlationId,
  required bool critical,
  required Map<String, Object?> metadata,
});

// Empty reconnectDelays still back off so persistent failures cannot spin.
const Duration _fallbackReconnectDelay = Duration(milliseconds: 100);
const int _maxConcurrentBackfills = 4;
const List<Duration> _defaultReconnectDelays = <Duration>[
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 4),
  Duration(seconds: 8),
  Duration(seconds: 16),
  Duration(seconds: 30),
];

class NotificationProtocol {
  const NotificationProtocol._();

  static const topicConversationEvents = 'conversation.events';

  static const errorAuthRequired = 'AUTH_REQUIRED';
  static const errorBackpressure = 'BACKPRESSURE';
  static const errorClosed = 'CLOSED';
  static const errorForbidden = 'FORBIDDEN';
  static const errorInvalidMessage = 'INVALID_MESSAGE';
  static const errorReplayTruncated = 'REPLAY_TRUNCATED';
  static const errorTokenExpired = 'TOKEN_EXPIRED';
  static const errorUnknownTopic = 'UNKNOWN_TOPIC';
}

class NotificationClientConfig {
  const NotificationClientConfig({
    this.connector,
    this.reconnectDelayWaiter,
    this.backfillAfterFailedAttempts = 3,
    this.reconnectDelays = _defaultReconnectDelays,
  }) : assert(backfillAfterFailedAttempts > 0);

  final NotificationSocketConnector? connector;
  final NotificationReconnectDelayWaiter? reconnectDelayWaiter;
  final int backfillAfterFailedAttempts;
  final List<Duration> reconnectDelays;
}

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

class DaemonNotificationException implements Exception {
  const DaemonNotificationException({
    required this.code,
    required this.message,
  });

  final String code;
  final String message;

  @override
  String toString() => 'DaemonNotificationException($code): $message';
}

class DaemonNotificationClient implements NotificationService {
  DaemonNotificationClient({
    required this.baseUri,
    required this.tokenProvider,
    required this.fetchBackfill,
    this.refreshAuth,
    NotificationTraceMarkRecorder? traceMarkRecorder,
    this.config = const NotificationClientConfig(),
  })  : _connector = config.connector ?? _connectIoSocket,
        _reconnectDelayWaiter = config.reconnectDelayWaiter ??
            ((delay) => Future<void>.delayed(delay)),
        _traceMarkRecorder = traceMarkRecorder;

  final Uri baseUri;
  final NotificationTokenProvider tokenProvider;
  final NotificationBackfillFetcher fetchBackfill;
  final NotificationAuthRefresher? refreshAuth;
  final NotificationClientConfig config;
  final NotificationSocketConnector _connector;
  final NotificationReconnectDelayWaiter _reconnectDelayWaiter;
  NotificationTraceMarkRecorder? _traceMarkRecorder;

  bool _closed = false;
  NotificationSocket? _socket;
  Future<void>? _connectionTask;
  int _failedAttemptsSinceBackfill = 0;
  final Set<NotificationSocket> _activeSockets = <NotificationSocket>{};
  final Map<String, _ConversationRoute> _conversationRoutes =
      <String, _ConversationRoute>{};
  final Completer<void> _closedCompleter = Completer<void>();
  Completer<void> _routeChangeCompleter = Completer<void>();

  void setPerformanceTraceMarkRecorder(
    NotificationTraceMarkRecorder? recorder,
  ) {
    _traceMarkRecorder = recorder;
  }

  @override
  Stream<ConversationEvent> watchConversationEvents(
    String conversationId, {
    required int afterSeq,
  }) {
    if (_closed) {
      return Stream<ConversationEvent>.error(const DaemonNotificationException(
        code: NotificationProtocol.errorClosed,
        message: 'Notification client is closed.',
      ));
    }
    final route = _conversationRoutes.putIfAbsent(
      conversationId,
      () => _ConversationRoute(conversationId),
    );
    late final _ConversationWatcher watcher;
    final controller = StreamController<ConversationEvent>(
      onCancel: () => _removeConversationWatcher(conversationId, watcher),
    );
    watcher = _ConversationWatcher(afterSeq, controller);
    route.watchers.add(watcher);
    _wakeConnectionLoop();
    _ensureConnectionLoop();
    _sendSubscribe(route);
    return controller.stream;
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    if (!_closedCompleter.isCompleted) {
      _closedCompleter.complete();
    }
    final routes = List<_ConversationRoute>.of(_conversationRoutes.values);
    _conversationRoutes.clear();
    for (final route in routes) {
      await route.close();
    }
    final sockets = List<NotificationSocket>.of(_activeSockets);
    await Future.wait<void>(sockets.map(_closeSocket));
  }

  void _ensureConnectionLoop() {
    if (_closed || _conversationRoutes.isEmpty || _connectionTask != null) {
      return;
    }
    _connectionTask = _runConnectionLoop().whenComplete(() {
      _connectionTask = null;
      if (!_closed && _conversationRoutes.isNotEmpty) {
        _ensureConnectionLoop();
      }
    });
  }

  Future<void> _runConnectionLoop() async {
    var attempt = 0;
    while (!_closed && _conversationRoutes.isNotEmpty) {
      NotificationSocket? socket;
      var skipDelay = false;
      var socketFailed = false;
      var reconnectRequested = false;
      try {
        final token = tokenProvider();
        socket = await _connector(
          daemonNotificationWebSocketUri(baseUri),
          <String, String>{if (token != null) 'authorization': 'Bearer $token'},
        );
        if (_closed || _conversationRoutes.isEmpty) {
          break;
        }
        _socket = socket;
        _activeSockets.add(socket);
        _recordTraceMark(
          'ws.connected',
          metadata: <String, Object?>{
            'routeCount': _conversationRoutes.length,
          },
        );
        for (final route in List<_ConversationRoute>.of(
          _conversationRoutes.values,
        )) {
          _sendSubscribe(route);
        }
        attempt = 0;
        await for (final raw in socket.stream) {
          final action = await _handleSocketFrame(raw);
          if (action.reconnect) {
            reconnectRequested = true;
            skipDelay = action.skipDelay;
            break;
          }
          if (_closed || _conversationRoutes.isEmpty) {
            break;
          }
        }
        if (!reconnectRequested && !_closed && _conversationRoutes.isNotEmpty) {
          if (_isAuthClose(socket)) {
            if (refreshAuth != null) {
              await refreshAuth!();
              skipDelay = true;
            }
          } else {
            socketFailed = true;
          }
        }
      } catch (_) {
        socketFailed = true;
        // Connector and socket stream failures use the normal reconnect path.
      } finally {
        if (_socket == socket) {
          _socket = null;
        }
        if (socket != null) {
          _activeSockets.remove(socket);
          await _closeSocket(socket);
        }
      }
      if (!_closed && socketFailed && _conversationRoutes.isNotEmpty) {
        _failedAttemptsSinceBackfill += 1;
        if (_failedAttemptsSinceBackfill >=
            config.backfillAfterFailedAttempts) {
          await _tryBackfillAllRoutes();
        }
      }
      if (_closed || _conversationRoutes.isEmpty) {
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

  Future<_SocketFrameAction> _handleSocketFrame(Object? raw) async {
    _recordTraceMark(
      'ws.frame.received',
      metadata: _traceFrameMetadata(raw),
    );
    final frame = _decodeFrame(raw);
    if (frame == null) {
      return _SocketFrameAction.continueListening;
    }
    final type = frame['type'];
    if (type == 'event') {
      final event = _eventFromFrame(frame);
      if (event != null) {
        _recordTraceMarkForEvent('ws.event.received', event, critical: true);
        _deliverConversationEvent(event);
      }
      return _SocketFrameAction.continueListening;
    }
    if (type != 'error') {
      return _SocketFrameAction.continueListening;
    }
    final code = frame['code'];
    if (code == NotificationProtocol.errorReplayTruncated) {
      final route = _routeForFrame(frame);
      if (route != null) {
        final advanced = await _tryBackfillRoute(route);
        return _SocketFrameAction.reconnect(skipDelay: advanced);
      }
      return _SocketFrameAction.reconnect(skipDelay: false);
    }
    if (code == NotificationProtocol.errorAuthRequired ||
        code == NotificationProtocol.errorTokenExpired) {
      if (refreshAuth != null) {
        await refreshAuth!();
        return _SocketFrameAction.reconnect(skipDelay: true);
      }
      return _SocketFrameAction.reconnect(skipDelay: false);
    }
    if (_isNonRetryableNotificationError(code)) {
      final error = DaemonNotificationException(
        code: _notificationErrorCode(frame),
        message: _notificationErrorMessage(frame),
      );
      final route = _routeForFrame(frame);
      if (route == null) {
        return _SocketFrameAction.reconnect(skipDelay: false);
      }
      await _failRoute(route, error);
    }
    return _SocketFrameAction.continueListening;
  }

  void _sendSubscribe(_ConversationRoute route) {
    final socket = _socket;
    if (_closed || route.isEmpty || socket == null) {
      return;
    }
    try {
      _sendScopedFrame('subscribe', route, afterSeq: route.afterSeq);
    } catch (_) {
      _handleSocketWriteFailure(socket);
    }
  }

  void _sendUnsubscribe(_ConversationRoute route) {
    final socket = _socket;
    if (_closed || socket == null) {
      return;
    }
    try {
      _sendScopedFrame('unsubscribe', route);
    } catch (_) {
      _handleSocketWriteFailure(socket);
    }
  }

  void _sendScopedFrame(
    String type,
    _ConversationRoute route, {
    int? afterSeq,
  }) {
    final socket = _socket;
    if (_closed || socket == null) {
      return;
    }
    final frame = <String, Object?>{
      'type': type,
      'id': '${type == 'subscribe' ? 'sub' : 'unsub'}_${route.conversationId}',
      'topic': NotificationProtocol.topicConversationEvents,
      'scope': <String, Object?>{'conversationId': route.conversationId},
      if (afterSeq != null) 'afterSeq': afterSeq,
    };
    socket.add(jsonEncode(<String, Object?>{
      ...frame,
    }));
  }

  void _handleSocketWriteFailure(NotificationSocket socket) {
    if (_socket == socket) {
      _socket = null;
    }
    unawaited(_closeSocket(socket));
  }

  void _deliverConversationEvent(ConversationEvent event) {
    final route = _conversationRoutes[event.conversationId];
    if (route == null) {
      return;
    }
    var delivered = false;
    for (final watcher in List<_ConversationWatcher>.of(route.watchers)) {
      delivered = watcher.add(event) || delivered;
    }
    if (delivered) {
      _failedAttemptsSinceBackfill = 0;
    }
  }

  Future<void> _removeConversationWatcher(
    String conversationId,
    _ConversationWatcher watcher,
  ) async {
    final route = _conversationRoutes[conversationId];
    if (route == null) {
      return;
    }
    route.watchers.remove(watcher);
    if (!route.isEmpty) {
      return;
    }
    _conversationRoutes.remove(conversationId);
    _wakeConnectionLoop();
    _sendUnsubscribe(route);
    if (_conversationRoutes.isEmpty) {
      final socket = _socket;
      if (socket != null) {
        _socket = null;
        await _closeSocket(socket);
      }
    }
  }

  _ConversationRoute? _routeForFrame(Map<String, Object?> frame) {
    final scope = frame['scope'];
    if (scope is Map) {
      final conversationId = scope['conversationId'];
      if (conversationId is String) {
        return _conversationRoutes[conversationId];
      }
    }
    final payload = frame['payload'];
    if (payload is Map) {
      final conversationId = payload['conversationId'];
      if (conversationId is String) {
        return _conversationRoutes[conversationId];
      }
    }
    return null;
  }

  Future<bool> _backfillAllRoutes() async {
    var advanced = false;
    final routes = List<_ConversationRoute>.of(_conversationRoutes.values);
    for (var index = 0;
        index < routes.length;
        index += _maxConcurrentBackfills) {
      final batch = routes.skip(index).take(_maxConcurrentBackfills);
      final results = await Future.wait<bool>(batch.map(_backfillRoute));
      advanced = results.any((result) => result) || advanced;
    }
    return advanced;
  }

  Future<bool> _tryBackfillAllRoutes() async {
    try {
      return await _backfillAllRoutes();
    } catch (_) {
      return false;
    }
  }

  Future<bool> _backfillRoute(_ConversationRoute route) async {
    if (route.isEmpty) {
      return false;
    }
    final before = route.afterSeq;
    final backfill =
        await fetchBackfill(route.conversationId, afterSeq: before);
    final sorted = List<ConversationEvent>.of(backfill)
      ..sort((a, b) => a.seq.compareTo(b.seq));
    var advanced = false;
    for (final event in sorted) {
      if (event.conversationId != route.conversationId) {
        continue;
      }
      final currentRoute = _conversationRoutes[event.conversationId];
      if (currentRoute == null) {
        continue;
      }
      final deliveredBefore = currentRoute.afterSeq;
      _deliverConversationEvent(event);
      advanced = currentRoute.afterSeq > deliveredBefore || advanced;
    }
    if (advanced) {
      _failedAttemptsSinceBackfill = 0;
    }
    return advanced;
  }

  Future<bool> _tryBackfillRoute(_ConversationRoute route) async {
    try {
      return await _backfillRoute(route);
    } catch (_) {
      return false;
    }
  }

  Future<void> _failRoute(
    _ConversationRoute route,
    DaemonNotificationException error,
  ) async {
    _conversationRoutes.remove(route.conversationId);
    _wakeConnectionLoop();
    await route.addErrorAndClose(error);
  }

  Duration _delayForAttempt(int attempt) {
    final reconnectDelays = config.reconnectDelays;
    if (reconnectDelays.isEmpty) {
      return _fallbackReconnectDelay;
    }
    final delayIndex = attempt.clamp(0, reconnectDelays.length - 1);
    return reconnectDelays[delayIndex];
  }

  Future<void> _waitForReconnectDelay(Duration delay) async {
    if (_closed || delay <= Duration.zero) {
      return;
    }
    final routeChange = _routeChangeCompleter.future;
    await Future.any<void>(<Future<void>>[
      _reconnectDelayWaiter(delay),
      _closedCompleter.future,
      routeChange,
    ]);
  }

  void _wakeConnectionLoop() {
    final completer = _routeChangeCompleter;
    if (!completer.isCompleted) {
      completer.complete();
      _routeChangeCompleter = Completer<void>();
    }
  }

  void _recordTraceMark(
    String name, {
    String? conversationId,
    int? seq,
    String? eventType,
    String? correlationId,
    bool critical = false,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final recorder = _traceMarkRecorder;
    if (recorder == null) return;
    try {
      recorder(
        name,
        conversationId: conversationId,
        seq: seq,
        eventType: eventType,
        correlationId: correlationId,
        critical: critical,
        metadata: metadata,
      );
    } catch (_) {
      // Trace collection must not affect notification reconnect or delivery.
    }
  }

  void _recordTraceMarkForEvent(
    String name,
    ConversationEvent event, {
    bool critical = false,
  }) {
    _recordTraceMark(
      name,
      conversationId: event.conversationId,
      seq: event.seq,
      eventType: event.type,
      correlationId: _conversationEventCorrelationId(event),
      critical: critical,
      metadata: <String, Object?>{
        'topic': NotificationProtocol.topicConversationEvents,
      },
    );
  }
}

class _SocketFrameAction {
  const _SocketFrameAction._({
    required this.reconnect,
    required this.skipDelay,
  });

  static const continueListening = _SocketFrameAction._(
    reconnect: false,
    skipDelay: false,
  );

  factory _SocketFrameAction.reconnect({required bool skipDelay}) =>
      _SocketFrameAction._(reconnect: true, skipDelay: skipDelay);

  final bool reconnect;
  final bool skipDelay;
}

class _ConversationRoute {
  _ConversationRoute(this.conversationId);

  final String conversationId;
  final Set<_ConversationWatcher> watchers = <_ConversationWatcher>{};

  bool get isEmpty => watchers.isEmpty;

  int get afterSeq {
    var cursor = 0;
    var initialized = false;
    for (final watcher in watchers) {
      if (!initialized || watcher.cursor < cursor) {
        cursor = watcher.cursor;
        initialized = true;
      }
    }
    return cursor;
  }

  Future<void> addErrorAndClose(Object error) async {
    for (final watcher in List<_ConversationWatcher>.of(watchers)) {
      watcher.addError(error);
      await watcher.close();
    }
    watchers.clear();
  }

  Future<void> close() async {
    for (final watcher in List<_ConversationWatcher>.of(watchers)) {
      await watcher.close();
    }
    watchers.clear();
  }
}

class _ConversationWatcher {
  _ConversationWatcher(this.cursor, this.controller);

  int cursor;
  final StreamController<ConversationEvent> controller;

  bool add(ConversationEvent event) {
    if (controller.isClosed || event.seq <= cursor) {
      return false;
    }
    cursor = event.seq;
    controller.add(event);
    return true;
  }

  void addError(Object error) {
    if (!controller.isClosed) {
      controller.addError(error);
    }
  }

  Future<void> close() async {
    if (!controller.isClosed) {
      await controller.close();
    }
  }
}

bool _isNonRetryableNotificationError(Object? code) {
  return code == NotificationProtocol.errorForbidden ||
      code == NotificationProtocol.errorUnknownTopic ||
      code == NotificationProtocol.errorInvalidMessage;
}

String _notificationErrorCode(Map<String, Object?> frame) {
  final code = frame['code'];
  return code is String && code.isNotEmpty ? code : 'UNKNOWN';
}

String _notificationErrorMessage(Map<String, Object?> frame) {
  final message = frame['message'];
  return message is String && message.isNotEmpty
      ? message
      : 'Notification stream rejected the subscription.';
}

bool _isAuthClose(NotificationSocket socket) {
  if (socket.closeCode != WebSocketStatus.policyViolation) {
    return false;
  }
  final reason = socket.closeReason;
  if (reason == null) {
    return false;
  }
  return reason == NotificationProtocol.errorAuthRequired ||
      reason == NotificationProtocol.errorTokenExpired;
}

Map<String, Object?>? _decodeFrame(Object? raw) {
  try {
    final decoded = raw is String ? jsonDecode(raw) : raw;
    if (decoded is! Map) {
      return null;
    }
    return decoded.cast<String, Object?>();
  } catch (_) {
    return null;
  }
}

Map<String, Object?> _traceFrameMetadata(Object? raw) {
  if (raw is String) {
    return <String, Object?>{
      'bytes': utf8.encode(raw).length,
      'frameKind': 'text',
    };
  }
  if (raw is List<int>) {
    return <String, Object?>{
      'bytes': raw.length,
      'frameKind': 'binary',
    };
  }
  if (raw is Map) {
    return <String, Object?>{
      'frameKind': 'object',
    };
  }
  return <String, Object?>{
    'frameKind': raw == null ? 'null' : 'other',
  };
}

ConversationEvent? _eventFromFrame(Map<String, Object?> frame) {
  final topic = frame['topic'];
  if (topic != null && topic != NotificationProtocol.topicConversationEvents) {
    return null;
  }
  final payload = frame['payload'];
  if (payload is! Map) {
    return null;
  }
  try {
    final event = ConversationEvent.fromJson(
      Map<String, Object?>.from(payload),
    );
    final scopedConversationId = _conversationIdFromFrameScope(frame);
    if (scopedConversationId != null &&
        scopedConversationId != event.conversationId) {
      return null;
    }
    return event;
  } catch (_) {
    return null;
  }
}

String? _conversationIdFromFrameScope(Map<String, Object?> frame) {
  final scope = frame['scope'];
  if (scope == null) return null;
  if (scope is! Map) return '';
  final conversationId = scope['conversationId'];
  return conversationId is String && conversationId.isNotEmpty
      ? conversationId
      : '';
}

String _conversationEventCorrelationId(ConversationEvent event) =>
    '${event.conversationId}:${event.seq}';

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
