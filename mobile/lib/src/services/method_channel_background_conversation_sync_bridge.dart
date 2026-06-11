import 'dart:async';

import 'package:flutter/services.dart';

import 'background_conversation_sync_bridge.dart';

class MethodChannelBackgroundConversationSyncBridge
    implements BackgroundConversationSyncBridge {
  MethodChannelBackgroundConversationSyncBridge({
    MethodChannel methodChannel = const MethodChannel(
      'lan_ai_cli_control/background_conversation_sync',
    ),
    EventChannel eventChannel = const EventChannel(
      'lan_ai_cli_control/background_conversation_sync/events',
    ),
    Stream<Object?>? eventStream,
  })  : _methodChannel = methodChannel,
        _events = _parseBackgroundConversationSyncEvents(
          eventStream ?? eventChannel.receiveBroadcastStream(),
        ).asBroadcastStream();

  final MethodChannel _methodChannel;
  final Stream<BackgroundConversationSyncSnapshot> _events;

  @override
  Future<bool> get isSupported async {
    final result = await _methodChannel.invokeMethod<bool>('isSupported');
    return result ?? false;
  }

  @override
  Stream<BackgroundConversationSyncSnapshot> get events => _events;

  @override
  Future<BackgroundConversationSyncSnapshot> start(
    BackgroundConversationSyncRequest request,
  ) async {
    final result = await _methodChannel.invokeMapMethod<String, Object?>(
      'start',
      request.toJson(),
    );
    if (result == null) {
      throw StateError(
        'Background conversation sync start returned no result.',
      );
    }
    try {
      return BackgroundConversationSyncSnapshot.fromJson(result);
    } on Object catch (error) {
      return BackgroundConversationSyncSnapshot(
        status: BackgroundConversationSyncStatus.starting,
        runningCount: request.runningCount,
        waitingApprovalCount: request.waitingApprovalCount,
        message: 'Malformed native start acknowledgement: $error',
      );
    }
  }

  @override
  Future<BackgroundConversationSyncSnapshot?> snapshot() async {
    final result = await _methodChannel.invokeMapMethod<String, Object?>(
      'snapshot',
    );
    return result == null
        ? null
        : BackgroundConversationSyncSnapshot.fromJson(result);
  }

  @override
  Future<void> stop() {
    return _methodChannel.invokeMethod<void>('stop');
  }
}

Stream<BackgroundConversationSyncSnapshot>
    _parseBackgroundConversationSyncEvents(Stream<Object?> events) async* {
  await for (final event in events) {
    if (event is! Map) continue;
    try {
      yield BackgroundConversationSyncSnapshot.fromJson(
        Map<String, Object?>.from(event),
      );
    } on Object {
      // Native service updates are diagnostic hints. Malformed frames must not
      // close the stream that tells Dart whether the platform anchor is alive.
    }
  }
}
