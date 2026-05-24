import 'dart:async';

import 'package:flutter/services.dart';

enum AndroidInstallStatus {
  pendingUserAction,
  committed,
  success,
  cancelled,
  failed,
}

class AndroidInstallEvent {
  const AndroidInstallEvent({
    required this.status,
    this.sessionId,
    this.message,
  });

  final AndroidInstallStatus status;
  final int? sessionId;
  final String? message;

  factory AndroidInstallEvent.fromJson(Map<Object?, Object?> json) {
    final status = switch (json['status'] as String?) {
      'pendingUserAction' => AndroidInstallStatus.pendingUserAction,
      'committed' => AndroidInstallStatus.committed,
      'success' => AndroidInstallStatus.success,
      'cancelled' => AndroidInstallStatus.cancelled,
      _ => AndroidInstallStatus.failed,
    };
    return AndroidInstallEvent(
      status: status,
      sessionId: json['sessionId'] as int?,
      message: json['message'] as String?,
    );
  }
}

abstract class PackageInstallerService {
  Stream<AndroidInstallEvent> get events;
  Future<bool> canRequestPackageInstalls();
  Future<void> openInstallPermissionSettings();
  Future<int> installApk(String filePath);
  Future<int> availableBytes();
  Future<AndroidInstallEvent?> recoverInstallSession(int sessionId);
}

class AndroidPackageInstaller implements PackageInstallerService {
  AndroidPackageInstaller({
    MethodChannel methodChannel = const MethodChannel(
      'lan_ai_cli_control/app_update_installer',
    ),
    EventChannel eventChannel = const EventChannel(
      'lan_ai_cli_control/app_update_installer/events',
    ),
  })  : _methodChannel = methodChannel,
        _eventChannel = eventChannel;

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  late final Stream<AndroidInstallEvent> _events = _eventChannel
      .receiveBroadcastStream()
      .map((event) =>
          AndroidInstallEvent.fromJson(Map<Object?, Object?>.from(event)));

  @override
  Stream<AndroidInstallEvent> get events => _events;

  @override
  Future<bool> canRequestPackageInstalls() async {
    return await _methodChannel.invokeMethod<bool>(
          'canRequestPackageInstalls',
        ) ??
        false;
  }

  @override
  Future<void> openInstallPermissionSettings() {
    return _methodChannel.invokeMethod<void>('openInstallPermissionSettings');
  }

  @override
  Future<int> installApk(String filePath) async {
    return await _methodChannel.invokeMethod<int>(
          'installApk',
          <String, Object?>{'filePath': filePath},
        ) ??
        -1;
  }

  @override
  Future<int> availableBytes() async {
    return await _methodChannel.invokeMethod<int>('availableBytes') ?? 0;
  }

  @override
  Future<AndroidInstallEvent?> recoverInstallSession(int sessionId) async {
    final result = await _methodChannel.invokeMethod<Map<Object?, Object?>>(
      'recoverInstallSession',
      <String, Object?>{'sessionId': sessionId},
    );
    return result == null ? null : AndroidInstallEvent.fromJson(result);
  }
}
