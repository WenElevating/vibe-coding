import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'approval_notification_handler.dart';

class SystemApprovalNotificationPresenter
    implements ApprovalNotificationPresenter {
  SystemApprovalNotificationPresenter({
    FlutterLocalNotificationsPlugin? plugin,
    bool Function()? isAndroid,
  })  : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
        _isAndroid = isAndroid ?? (() => Platform.isAndroid);

  static const String _channelId = 'approval_requests';
  static const String _channelName = 'Approval requests';
  static const String _channelDescription =
      'Notifications for CLI approval requests.';

  final FlutterLocalNotificationsPlugin _plugin;
  final bool Function() _isAndroid;
  final StreamController<ApprovalNotificationTap> _taps =
      StreamController<ApprovalNotificationTap>.broadcast();
  Future<void>? _initialization;
  bool _disposed = false;

  @override
  Stream<ApprovalNotificationTap> get taps => _taps.stream;

  @override
  Future<void> initialize() {
    if (!_isAndroid() || _disposed) return Future<void>.value();
    return _ensureInitialized();
  }

  @override
  Future<bool> showOrUpdateApproval(
      ApprovalNotificationDisplay notification) async {
    if (!_isAndroid() || _disposed) return true;
    await _ensureInitialized();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final allowed = await android?.requestNotificationsPermission();
    if (allowed == false) return false;
    await _plugin.show(
      notification.id,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.status,
          ticker: 'Approval required',
        ),
      ),
      payload: jsonEncode(<String, Object?>{
        'workspaceId': notification.workspaceId,
        'conversationId': notification.conversationId,
        'approvalId': notification.approvalId,
      }),
    );
    return true;
  }

  @override
  Future<void> cancelApproval({
    required int id,
    required String conversationId,
  }) async {
    if (!_isAndroid() || _disposed) return;
    await _ensureInitialized();
    await _plugin.cancel(id);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _taps.close();
  }

  Future<void> _ensureInitialized() {
    final current = _initialization;
    if (current != null) return current;
    late final Future<void> initialization;
    initialization = _initialize().catchError((Object error, StackTrace stack) {
      if (identical(_initialization, initialization)) {
        _initialization = null;
      }
      Error.throwWithStackTrace(error, stack);
    });
    _initialization = initialization;
    return initialization;
  }

  Future<void> _initialize() async {
    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );
    final details = await _plugin.getNotificationAppLaunchDetails();
    final response = details?.notificationResponse;
    if (details?.didNotificationLaunchApp == true && response != null) {
      _handleNotificationResponse(response);
    }
  }

  void _handleNotificationResponse(NotificationResponse response) {
    final tap = _tapFromPayload(response.payload);
    if (tap != null && !_disposed && !_taps.isClosed) {
      _taps.add(tap);
    }
  }
}

ApprovalNotificationTap? _tapFromPayload(String? payload) {
  if (payload == null || payload.isEmpty) return null;
  try {
    final decoded = jsonDecode(payload);
    if (decoded is! Map) return null;
    final workspaceId = decoded['workspaceId'];
    final conversationId = decoded['conversationId'];
    if (workspaceId is! String ||
        workspaceId.isEmpty ||
        conversationId is! String ||
        conversationId.isEmpty) {
      return null;
    }
    final approvalId = decoded['approvalId'];
    return ApprovalNotificationTap(
      workspaceId: workspaceId,
      conversationId: conversationId,
      approvalId:
          approvalId is String && approvalId.isNotEmpty ? approvalId : null,
    );
  } catch (_) {
    return null;
  }
}
