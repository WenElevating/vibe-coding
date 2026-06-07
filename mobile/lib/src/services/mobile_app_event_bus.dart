import 'dart:async';

abstract class MobileAppEvent {
  const MobileAppEvent();
}

class MobileApprovalRequested extends MobileAppEvent {
  const MobileApprovalRequested({
    required this.workspaceId,
    required this.conversationId,
    required this.approvalId,
    required this.title,
    required this.body,
    required this.createdAt,
    this.conversationTitle,
    this.toolName,
    this.summary,
  });

  final String workspaceId;
  final String conversationId;
  final String approvalId;
  final String title;
  final String body;
  final DateTime createdAt;
  final String? conversationTitle;
  final String? toolName;
  final String? summary;
}

class MobileApprovalResolved extends MobileAppEvent {
  const MobileApprovalResolved({
    required this.conversationId,
    this.approvalId,
  });

  final String conversationId;
  final String? approvalId;
}

class MobilePerformanceTraceMark extends MobileAppEvent {
  const MobilePerformanceTraceMark({
    required this.name,
    required this.monotonicUs,
    required this.wallTimeMs,
    this.conversationId,
    this.seq,
    this.eventType,
    this.correlationId,
    this.critical = false,
    this.clockDriftWarning = false,
    this.metadata = const <String, Object?>{},
  });

  final String name;
  final int monotonicUs;
  final int wallTimeMs;
  final String? conversationId;
  final int? seq;
  final String? eventType;
  final String? correlationId;
  final bool critical;
  final bool clockDriftWarning;
  final Map<String, Object?> metadata;
}

class MobileAppEventBus {
  MobileAppEventBus();

  final StreamController<MobileAppEvent> _controller =
      StreamController<MobileAppEvent>.broadcast();

  Stream<MobileAppEvent> get events => _controller.stream;

  Stream<T> on<T extends MobileAppEvent>() =>
      events.where((event) => event is T).cast<T>();

  void publish(MobileAppEvent event) {
    if (!_controller.isClosed) _controller.add(event);
  }

  Future<void> dispose() => _controller.close();
}
