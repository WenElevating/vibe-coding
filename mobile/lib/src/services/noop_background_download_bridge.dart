import 'dart:async';

import 'background_download_bridge.dart';

class UnsupportedBackgroundDownloadBridge implements BackgroundDownloadBridge {
  UnsupportedBackgroundDownloadBridge();

  final StreamController<BackgroundDownloadSnapshot> _controller =
      StreamController<BackgroundDownloadSnapshot>.broadcast();

  @override
  Future<bool> get isSupported async => false;

  @override
  Future<bool> prepareNotifications() async => false;

  @override
  Stream<BackgroundDownloadSnapshot> get events => _controller.stream;

  @override
  Future<BackgroundDownloadSnapshot> start(
    BackgroundDownloadRequest request,
  ) async {
    final snapshot = BackgroundDownloadSnapshot(
      id: request.id,
      status: BackgroundDownloadStatus.failed,
      downloadedBytes: request.resumeFromBytes,
      totalBytes: request.expectedBytes,
      destinationPath: request.destinationPath,
      message: 'Background downloads are not supported on this platform.',
    );
    _controller.add(snapshot);
    return snapshot;
  }

  @override
  Future<void> cancel(String id) async {}

  @override
  Future<BackgroundDownloadSnapshot?> snapshot(String id) async => null;
}
