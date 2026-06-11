import 'dart:async';

import 'background_conversation_sync_bridge.dart';

class UnsupportedBackgroundConversationSyncBridge
    implements BackgroundConversationSyncBridge {
  UnsupportedBackgroundConversationSyncBridge();

  final StreamController<BackgroundConversationSyncSnapshot> _controller =
      StreamController<BackgroundConversationSyncSnapshot>.broadcast();

  @override
  Future<bool> get isSupported async => false;

  @override
  Stream<BackgroundConversationSyncSnapshot> get events => _controller.stream;

  @override
  Future<BackgroundConversationSyncSnapshot> start(
    BackgroundConversationSyncRequest request,
  ) async {
    final snapshot = BackgroundConversationSyncSnapshot(
      status: BackgroundConversationSyncStatus.failed,
      runningCount: request.runningCount,
      waitingApprovalCount: request.waitingApprovalCount,
      message: 'Background conversation sync is unavailable.',
    );
    _controller.add(snapshot);
    return snapshot;
  }

  @override
  Future<BackgroundConversationSyncSnapshot?> snapshot() async => null;

  @override
  Future<void> stop() async {}
}
