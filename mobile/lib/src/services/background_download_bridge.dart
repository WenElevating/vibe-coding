enum BackgroundDownloadKind {
  asrModel,
  appUpdate;

  String get wireName => switch (this) {
        BackgroundDownloadKind.asrModel => 'asrModel',
        BackgroundDownloadKind.appUpdate => 'appUpdate',
      };

  static BackgroundDownloadKind fromWireName(String value) => switch (value) {
        'asrModel' => BackgroundDownloadKind.asrModel,
        'appUpdate' => BackgroundDownloadKind.appUpdate,
        _ => throw FormatException('Unknown background download kind: $value'),
      };
}

enum BackgroundDownloadStatus {
  queued,
  downloading,
  completed,
  cancelled,
  failed;

  static BackgroundDownloadStatus fromWireName(String value) => switch (value) {
        'queued' => BackgroundDownloadStatus.queued,
        'downloading' => BackgroundDownloadStatus.downloading,
        'completed' => BackgroundDownloadStatus.completed,
        'cancelled' => BackgroundDownloadStatus.cancelled,
        'failed' => BackgroundDownloadStatus.failed,
        _ =>
          throw FormatException('Unknown background download status: $value'),
      };

  String get wireName => switch (this) {
        BackgroundDownloadStatus.queued => 'queued',
        BackgroundDownloadStatus.downloading => 'downloading',
        BackgroundDownloadStatus.completed => 'completed',
        BackgroundDownloadStatus.cancelled => 'cancelled',
        BackgroundDownloadStatus.failed => 'failed',
      };
}

class BackgroundDownloadRequest {
  const BackgroundDownloadRequest({
    required this.id,
    required this.kind,
    required this.url,
    required this.destinationPath,
    required this.headers,
    required this.expectedBytes,
    required this.resumeFromBytes,
    required this.notificationTitle,
    required this.notificationBody,
  });

  final String id;
  final BackgroundDownloadKind kind;
  final String url;
  final String destinationPath;
  final Map<String, String> headers;
  final int expectedBytes;
  final int resumeFromBytes;
  final String notificationTitle;
  final String notificationBody;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'kind': kind.wireName,
        'url': url,
        'destinationPath': destinationPath,
        'headers': headers,
        'expectedBytes': expectedBytes,
        'resumeFromBytes': resumeFromBytes,
        'notificationTitle': notificationTitle,
        'notificationBody': notificationBody,
      };
}

class BackgroundDownloadSnapshot {
  const BackgroundDownloadSnapshot({
    required this.id,
    required this.status,
    required this.downloadedBytes,
    required this.totalBytes,
    this.destinationPath,
    this.message,
  });

  factory BackgroundDownloadSnapshot.fromJson(Map<String, Object?> json) {
    return BackgroundDownloadSnapshot(
      id: json['id'] as String,
      status: BackgroundDownloadStatus.fromWireName(json['status'] as String),
      downloadedBytes: (json['downloadedBytes'] as num?)?.toInt() ?? 0,
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      destinationPath: json['destinationPath'] as String?,
      message: json['message'] as String?,
    );
  }

  final String id;
  final BackgroundDownloadStatus status;
  final int downloadedBytes;
  final int totalBytes;
  final String? destinationPath;
  final String? message;

  double get fraction {
    if (totalBytes <= 0) return 0;
    return (downloadedBytes / totalBytes).clamp(0, 1).toDouble();
  }
}

abstract class BackgroundDownloadBridge {
  const BackgroundDownloadBridge();

  Future<bool> get isSupported;

  Future<bool> prepareNotifications();

  Stream<BackgroundDownloadSnapshot> get events;

  Future<BackgroundDownloadSnapshot> start(BackgroundDownloadRequest request);

  Future<void> cancel(String id);

  Future<BackgroundDownloadSnapshot?> snapshot(String id);
}
