enum BackgroundConversationSyncStatus {
  inactive,
  starting,
  active,
  denied,
  stopped,
  failed;

  static BackgroundConversationSyncStatus fromWireName(String value) =>
      switch (value) {
        'inactive' => BackgroundConversationSyncStatus.inactive,
        'starting' => BackgroundConversationSyncStatus.starting,
        'active' => BackgroundConversationSyncStatus.active,
        'denied' => BackgroundConversationSyncStatus.denied,
        'stopped' => BackgroundConversationSyncStatus.stopped,
        'failed' => BackgroundConversationSyncStatus.failed,
        _ => throw FormatException(
            'Unknown background conversation sync status: $value',
          ),
      };

  String get wireName => switch (this) {
        BackgroundConversationSyncStatus.inactive => 'inactive',
        BackgroundConversationSyncStatus.starting => 'starting',
        BackgroundConversationSyncStatus.active => 'active',
        BackgroundConversationSyncStatus.denied => 'denied',
        BackgroundConversationSyncStatus.stopped => 'stopped',
        BackgroundConversationSyncStatus.failed => 'failed',
      };
}

class BackgroundConversationSyncSnapshot {
  const BackgroundConversationSyncSnapshot({
    required this.status,
    required this.runningCount,
    required this.waitingApprovalCount,
    this.message,
  });

  factory BackgroundConversationSyncSnapshot.fromJson(
    Map<String, Object?> json,
  ) =>
      BackgroundConversationSyncSnapshot(
        status: BackgroundConversationSyncStatus.fromWireName(
          json['status'] as String,
        ),
        runningCount: (json['runningCount'] as num?)?.toInt() ?? 0,
        waitingApprovalCount:
            (json['waitingApprovalCount'] as num?)?.toInt() ?? 0,
        message: json['message'] as String?,
      );

  final BackgroundConversationSyncStatus status;
  final int runningCount;
  final int waitingApprovalCount;
  final String? message;

  Map<String, Object?> toJson() => <String, Object?>{
        'status': status.wireName,
        'runningCount': runningCount,
        'waitingApprovalCount': waitingApprovalCount,
        'message': message,
      };
}

class BackgroundConversationSyncRequest {
  const BackgroundConversationSyncRequest({
    required this.runningCount,
    required this.waitingApprovalCount,
    required this.notificationTitle,
    required this.notificationBody,
  });

  final int runningCount;
  final int waitingApprovalCount;
  final String notificationTitle;
  final String notificationBody;

  Map<String, Object?> toJson() => <String, Object?>{
        'runningCount': runningCount,
        'waitingApprovalCount': waitingApprovalCount,
        'notificationTitle': notificationTitle,
        'notificationBody': notificationBody,
      };
}

abstract class BackgroundConversationSyncBridge {
  const BackgroundConversationSyncBridge();

  Future<bool> get isSupported;

  Stream<BackgroundConversationSyncSnapshot> get events;

  Future<BackgroundConversationSyncSnapshot> start(
    BackgroundConversationSyncRequest request,
  );

  Future<BackgroundConversationSyncSnapshot?> snapshot();

  Future<void> stop();
}
