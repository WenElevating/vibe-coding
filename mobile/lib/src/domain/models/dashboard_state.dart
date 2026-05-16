import '../../models/protocol.dart';

/// Temporary protocol-backed domain projection tracked by
/// `docs/adr/2026-05-16-mobile-protocol-dto-boundary.md`.
class DashboardState {
  const DashboardState({
    required this.health,
    required this.version,
    this.adapters = const <AdapterStatus>[],
    this.queue = const <QueueItem>[],
    this.workspaces = const <WorkspaceSummary>[],
    this.runs = const <RunSummary>[],
  });

  final DaemonHealth health;
  final DaemonVersionInfo version;
  final List<AdapterStatus> adapters;
  final List<QueueItem> queue;
  final List<WorkspaceSummary> workspaces;
  final List<RunSummary> runs;

  bool get hasVersionMismatch => !version.daemonVersion.startsWith('1.3.');
  bool get securityBoundaryVisible =>
      health.security['ptyEnabled'] == false &&
      health.security['rawCommandApiEnabled'] == false;
  bool get hasQueuedRuns => queue.isNotEmpty;
}
