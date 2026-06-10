import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'background_download_bridge.dart';

class MethodChannelBackgroundDownloadBridge
    implements BackgroundDownloadBridge {
  MethodChannelBackgroundDownloadBridge({
    MethodChannel methodChannel =
        const MethodChannel('lan_ai_cli_control/background_downloads'),
    EventChannel eventChannel =
        const EventChannel('lan_ai_cli_control/background_downloads/events'),
    FlutterLocalNotificationsPlugin? notificationsPlugin,
    Future<bool> Function()? notificationPermissionRequester,
    bool? forceAndroidForTesting,
    Stream<Object?>? eventStream,
  })  : _methodChannel = methodChannel,
        _notificationsPlugin =
            notificationsPlugin ?? FlutterLocalNotificationsPlugin(),
        _notificationPermissionRequester = notificationPermissionRequester,
        _forceAndroidForTesting = forceAndroidForTesting,
        _events = _parseBackgroundDownloadEvents(
          eventStream ?? eventChannel.receiveBroadcastStream(),
        ).asBroadcastStream();

  final MethodChannel _methodChannel;
  final FlutterLocalNotificationsPlugin _notificationsPlugin;
  final Future<bool> Function()? _notificationPermissionRequester;
  final bool? _forceAndroidForTesting;
  final Stream<BackgroundDownloadSnapshot> _events;
  Future<void>? _notificationInitialization;
  Future<bool>? _notificationPreparation;

  @override
  Future<bool> get isSupported async {
    final result = await _methodChannel.invokeMethod<bool>('isSupported');
    return result ?? false;
  }

  @override
  Future<bool> prepareNotifications() {
    final activePreparation = _notificationPreparation;
    if (activePreparation != null) return activePreparation;
    final preparation = _prepareNotifications();
    _notificationPreparation = preparation;
    return preparation.whenComplete(() {
      if (identical(_notificationPreparation, preparation)) {
        _notificationPreparation = null;
      }
    });
  }

  Future<bool> _prepareNotifications() async {
    if (!(_forceAndroidForTesting ?? Platform.isAndroid)) return true;
    try {
      final requester = _notificationPermissionRequester;
      if (requester != null) {
        await requester();
        return true;
      }
      _notificationInitialization ??= _notificationsPlugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      await _notificationInitialization;
      final android =
          _notificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
    } on Object {
      // Foreground services do not require POST_NOTIFICATIONS on Android 13+.
      // A denied or failed prompt must not turn a background transfer into a
      // paused download.
    }
    return true;
  }

  @override
  Stream<BackgroundDownloadSnapshot> get events => _events;

  @override
  Future<BackgroundDownloadSnapshot> start(
    BackgroundDownloadRequest request,
  ) async {
    final result = await _methodChannel.invokeMapMethod<String, Object?>(
      'start',
      request.toJson(),
    );
    if (result == null) {
      throw StateError('Background download start returned no result.');
    }
    try {
      return BackgroundDownloadSnapshot.fromJson(result);
    } on Object catch (error) {
      return BackgroundDownloadSnapshot(
        id: request.id,
        status: BackgroundDownloadStatus.queued,
        downloadedBytes: request.resumeFromBytes,
        totalBytes: request.expectedBytes,
        destinationPath: request.destinationPath,
        message: 'Malformed native start acknowledgement: $error',
      );
    }
  }

  @override
  Future<void> cancel(String id) {
    return _methodChannel.invokeMethod<void>('cancel', <String, Object?>{
      'id': id,
    });
  }

  @override
  Future<BackgroundDownloadSnapshot?> snapshot(String id) async {
    final result = await _methodChannel.invokeMapMethod<String, Object?>(
      'snapshot',
      <String, Object?>{'id': id},
    );
    return result == null ? null : BackgroundDownloadSnapshot.fromJson(result);
  }
}

Stream<BackgroundDownloadSnapshot> _parseBackgroundDownloadEvents(
  Stream<Object?> events,
) async* {
  await for (final event in events) {
    if (event is! Map) continue;
    try {
      yield BackgroundDownloadSnapshot.fromJson(
        Map<String, Object?>.from(event),
      );
    } on Object {
      // Native transfer events are best-effort progress notifications. A
      // malformed frame must not poison the broadcast stream and strand the
      // download manager waiting for a later terminal event.
    }
  }
}
