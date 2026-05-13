import '../../../models/protocol.dart';

class RunDetailState {
  const RunDetailState({
    this.events = const <AgentEvent>[],
    this.connectionState = RunConnectionState.disconnected,
    this.lastSeq = 0,
    this.pendingApprovalCount = 0,
  });

  final List<AgentEvent> events;
  final RunConnectionState connectionState;
  final int lastSeq;
  final int pendingApprovalCount;

  RunDetailState mergeEvents(Iterable<AgentEvent> incoming) {
    final bySeq = <int, AgentEvent>{
      for (final event in events) event.seq: event
    };
    for (final event in incoming) {
      bySeq[event.seq] = event;
    }
    final merged = bySeq.values.toList()
      ..sort((a, b) => a.seq.compareTo(b.seq));
    return RunDetailState(
      events: merged,
      connectionState:
          merged.any((event) => isTerminalAgentEventType(event.type))
              ? RunConnectionState.disconnected
              : connectionState,
      lastSeq: merged.isEmpty ? lastSeq : merged.last.seq,
      pendingApprovalCount: unresolvedApprovalCount(merged),
    );
  }

  RunDetailState copyWith({RunConnectionState? connectionState}) {
    return RunDetailState(
      events: events,
      connectionState: connectionState ?? this.connectionState,
      lastSeq: lastSeq,
      pendingApprovalCount: pendingApprovalCount,
    );
  }
}

int unresolvedApprovalCount(Iterable<AgentEvent> events) {
  final requested = <String>{};
  final resolved = <String>{};
  for (final event in events) {
    final approvalId = event.approvalId ?? event.raw['approvalId'] as String?;
    if (approvalId == null || approvalId.isEmpty) continue;
    if (event.type == 'approval.required') requested.add(approvalId);
    if (event.type == 'approval.responded') resolved.add(approvalId);
  }
  return requested.difference(resolved).length;
}

class NotificationPreferenceState {
  const NotificationPreferenceState(
      {required this.permissionGranted, this.privacyMode = true});

  final bool permissionGranted;
  final bool privacyMode;

  String messageFor(AgentEvent event) {
    if (privacyMode) {
      if (event.type == 'approval.required') {
        return 'Approval required for a LAN AI CLI run.';
      }
      if (event.type == 'run.completed') return 'LAN AI CLI run completed.';
      if (event.type == 'run.failed') return 'LAN AI CLI run failed.';
    }
    return event.text ?? event.type;
  }
}

enum RunConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  stale
}
