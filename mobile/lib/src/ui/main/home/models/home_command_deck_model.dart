import '../../../../models/protocol.dart';

enum HomeSignalKind { approval, failure, running, queue, idle }

class HomeSignalItem {
  const HomeSignalItem({
    required this.id,
    required this.kind,
    required this.workspaceId,
    required this.workspaceName,
    required this.title,
    required this.detail,
    this.tool,
  });

  final String id;
  final HomeSignalKind kind;
  final String workspaceId;
  final String workspaceName;
  final String title;
  final String detail;
  final String? tool;

  bool get isIdle => kind == HomeSignalKind.idle;
}

class HomeWorkspaceSignalsData {
  const HomeWorkspaceSignalsData({
    required this.changedFiles,
    required this.diagnostics,
    required this.queue,
    required this.recentFiles,
  });

  final int? changedFiles;
  final int? diagnostics;
  final int queue;
  final int? recentFiles;
}

class WorkspaceRunSummary {
  const WorkspaceRunSummary({
    required this.workspaceId,
    required this.runningCount,
    required this.failedCount,
    required this.latestRunId,
    required this.latestStatus,
    required this.latestTool,
  });

  final String workspaceId;
  final int runningCount;
  final int failedCount;
  final String latestRunId;
  final String latestStatus;
  final String latestTool;
}

class HomeCommandDeckData {
  const HomeCommandDeckData({
    required this.now,
    required this.nowOverflowCount,
    required this.interrupts,
    required this.executionStream,
    required this.signals,
    required this.workspaceRunSummaries,
    required this.allSignals,
  });

  final HomeSignalItem now;
  final int nowOverflowCount;
  final List<HomeSignalItem> interrupts;
  final List<HomeSignalItem> executionStream;
  final HomeWorkspaceSignalsData signals;
  final List<WorkspaceRunSummary> workspaceRunSummaries;
  final List<HomeSignalItem> allSignals;
}

HomeCommandDeckData buildHomeCommandDeckData({
  required WorkspaceSummary currentWorkspace,
  required List<WorkspaceSummary> workspaces,
  required List<RunSummary> runs,
  required List<ConversationSummary> conversations,
  required List<QueueItem> queue,
  required int? changedFiles,
  required int? diagnostics,
  required int? recentFiles,
}) {
  final workspaceNames = <String, String>{
    for (final workspace in workspaces) workspace.id: workspace.name,
  };
  final currentWorkspaceId = currentWorkspace.id;
  final allSignals = <HomeSignalItem>[
    ...conversations
        .map((conversation) => _conversationSignal(
              conversation,
              _workspaceName(workspaceNames, conversation.workspaceId),
            ))
        .whereType<HomeSignalItem>(),
    ...runs
        .map((run) =>
            _runSignal(run, _workspaceName(workspaceNames, run.workspaceId)))
        .whereType<HomeSignalItem>(),
    ...queue
        .map((item) => _queueSignal(
            item, _workspaceName(workspaceNames, item.workspaceId)))
        .whereType<HomeSignalItem>(),
  ]..sort(_compareSignals);

  final currentSignals = allSignals
      .where((item) => item.workspaceId == currentWorkspaceId)
      .toList();
  final actionableCurrentSignals =
      currentSignals.where((item) => item.kind != HomeSignalKind.idle).toList();
  final now = actionableCurrentSignals.isNotEmpty
      ? actionableCurrentSignals.first
      : HomeSignalItem(
          id: 'idle:$currentWorkspaceId',
          kind: HomeSignalKind.idle,
          workspaceId: currentWorkspaceId,
          workspaceName: currentWorkspace.name,
          title: currentWorkspace.name,
          detail: 'idle',
        );
  final overflow = actionableCurrentSignals
      .skip(1)
      .where((item) => _priority(item.kind) <= _priority(now.kind) + 1)
      .length;
  final workspaceRunSummaries = buildWorkspaceRunSummaries(runs);
  final hasStrongSignal = allSignals.any((item) =>
      item.kind == HomeSignalKind.approval ||
      item.kind == HomeSignalKind.failure ||
      item.kind == HomeSignalKind.queue);
  final urgentInterrupts = allSignals
      .where((item) => item.workspaceId != currentWorkspaceId)
      .where((item) => item.kind != HomeSignalKind.running)
      .where((item) => item.kind != HomeSignalKind.idle)
      .toList();
  final runningInterrupts = (!hasStrongSignal && now.isIdle)
      ? workspaceRunSummaries
          .where((summary) => summary.workspaceId != currentWorkspaceId)
          .where((summary) => summary.runningCount > 0)
          .map((summary) => HomeSignalItem(
                id: 'workspace-run:${summary.workspaceId}',
                kind: HomeSignalKind.running,
                workspaceId: summary.workspaceId,
                workspaceName:
                    _workspaceName(workspaceNames, summary.workspaceId),
                title: summary.latestStatus,
                detail: summary.latestRunId,
                tool: summary.latestTool,
              ))
          .toList()
      : <HomeSignalItem>[];
  final interrupts = <HomeSignalItem>[
    ...urgentInterrupts,
    ...runningInterrupts,
  ].take(3).toList();
  final executionStream = allSignals
      .where((item) => item.workspaceId == currentWorkspaceId)
      .where((item) => item.id != now.id)
      .take(3)
      .toList();
  final currentQueue =
      queue.where((item) => item.workspaceId == currentWorkspaceId).length;

  return HomeCommandDeckData(
    now: now,
    nowOverflowCount: overflow,
    interrupts: interrupts,
    executionStream: executionStream,
    signals: HomeWorkspaceSignalsData(
      changedFiles: changedFiles,
      diagnostics: diagnostics,
      queue: currentQueue,
      recentFiles: recentFiles,
    ),
    workspaceRunSummaries: workspaceRunSummaries,
    allSignals: allSignals,
  );
}

List<WorkspaceRunSummary> buildWorkspaceRunSummaries(List<RunSummary> runs) {
  final byWorkspace = <String, List<RunSummary>>{};
  for (final run in runs) {
    byWorkspace.putIfAbsent(run.workspaceId, () => <RunSummary>[]).add(run);
  }
  return byWorkspace.entries.map((entry) {
    final latest = entry.value.first;
    return WorkspaceRunSummary(
      workspaceId: entry.key,
      runningCount: entry.value.where((run) => _isRunning(run.status)).length,
      failedCount: entry.value.where((run) => _isFailed(run.status)).length,
      latestRunId: latest.id,
      latestStatus: latest.status,
      latestTool: latest.tool,
    );
  }).toList();
}

HomeSignalItem? _conversationSignal(
    ConversationSummary conversation, String workspaceName) {
  final lower = conversation.status.toLowerCase();
  final hasBlockingItem = conversation.blockingItem != null;
  if (hasBlockingItem || lower.contains('approval')) {
    return HomeSignalItem(
      id: 'conversation:${conversation.id}',
      kind: HomeSignalKind.approval,
      workspaceId: conversation.workspaceId,
      workspaceName: workspaceName,
      title: conversation.blockingItem?.summary ?? conversation.status,
      detail: conversation.adapter,
      tool: conversation.adapter,
    );
  }
  if (_isFailed(conversation.status)) {
    return HomeSignalItem(
      id: 'conversation:${conversation.id}',
      kind: HomeSignalKind.failure,
      workspaceId: conversation.workspaceId,
      workspaceName: workspaceName,
      title: conversation.status,
      detail: conversation.adapter,
      tool: conversation.adapter,
    );
  }
  if (_isRunning(conversation.status)) {
    return HomeSignalItem(
      id: 'conversation:${conversation.id}',
      kind: HomeSignalKind.running,
      workspaceId: conversation.workspaceId,
      workspaceName: workspaceName,
      title: conversation.status,
      detail: conversation.adapter,
      tool: conversation.adapter,
    );
  }
  return null;
}

HomeSignalItem? _runSignal(RunSummary run, String workspaceName) {
  if (_isFailed(run.status)) {
    return HomeSignalItem(
      id: 'run:${run.id}',
      kind: HomeSignalKind.failure,
      workspaceId: run.workspaceId,
      workspaceName: workspaceName,
      title: run.status,
      detail: run.id,
      tool: run.tool,
    );
  }
  if (_isRunning(run.status) || run.status == 'completed') {
    return HomeSignalItem(
      id: 'run:${run.id}',
      kind:
          _isRunning(run.status) ? HomeSignalKind.running : HomeSignalKind.idle,
      workspaceId: run.workspaceId,
      workspaceName: workspaceName,
      title: run.status,
      detail: run.id,
      tool: run.tool,
    );
  }
  return null;
}

HomeSignalItem? _queueSignal(QueueItem item, String workspaceName) {
  final lower = item.status.toLowerCase();
  if (lower == 'running') return null;
  return HomeSignalItem(
    id: 'queue:${item.runId}',
    kind: HomeSignalKind.queue,
    workspaceId: item.workspaceId,
    workspaceName: workspaceName,
    title: item.status,
    detail: item.reason,
  );
}

String _workspaceName(Map<String, String> names, String workspaceId) =>
    names[workspaceId] ?? workspaceId;

int _compareSignals(HomeSignalItem left, HomeSignalItem right) {
  final priority = _priority(left.kind).compareTo(_priority(right.kind));
  if (priority != 0) return priority;
  return left.id.compareTo(right.id);
}

int _priority(HomeSignalKind kind) => switch (kind) {
      HomeSignalKind.approval => 0,
      HomeSignalKind.failure => 1,
      HomeSignalKind.running => 2,
      HomeSignalKind.queue => 3,
      HomeSignalKind.idle => 4,
    };

bool _isRunning(String status) {
  final lower = status.toLowerCase();
  return lower == 'running' || lower == 'starting' || lower.contains('active');
}

bool _isFailed(String status) {
  final lower = status.toLowerCase();
  return lower == 'failed' ||
      lower.contains('error') ||
      lower.contains('cancel');
}
