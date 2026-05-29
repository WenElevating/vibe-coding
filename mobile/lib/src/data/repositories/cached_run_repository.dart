import 'package:flutter/foundation.dart';

import '../../domain/repositories/run_repository.dart';
import '../../models/protocol.dart';
import 'bootstrap_hydration.dart';

class CachedRunRepository extends ChangeNotifier
    implements RunRepository, RunBootstrapTarget {
  CachedRunRepository({required RunRepository delegate}) : _delegate = delegate;

  final RunRepository _delegate;

  List<RunSummary> _runs = const <RunSummary>[];
  List<QueueItem> _queue = const <QueueItem>[];
  bool _loading = false;
  Object? _error;
  bool _loaded = false;
  String? _loadedWorkspaceId;
  int _refreshGeneration = 0;
  int _mutationEpoch = 0;
  final _locallyMutatedRunIds = <String>{};
  Future<void>? _refreshFuture;
  bool _disposed = false;

  List<RunSummary> get runs => List.unmodifiable(_runs);
  List<QueueItem> get queue => List.unmodifiable(_queue);
  bool get loading => _loading;
  Object? get error => _error;
  @override
  String? get loadedWorkspaceId => _loadedWorkspaceId;

  @override
  void replaceFromBootstrap({
    required String workspaceId,
    required List<RunSummary> runs,
    required List<QueueItem> queue,
  }) {
    if (_disposed) return;
    _refreshGeneration++;
    _refreshFuture = null;
    _loading = false;
    _error = null;
    _loadedWorkspaceId = workspaceId;
    _runs = List<RunSummary>.unmodifiable(runs);
    _queue = List<QueueItem>.unmodifiable(queue);
    _loaded = true;
    _locallyMutatedRunIds.clear();
    _notifyIfActive();
  }

  Future<void> refresh() {
    final generation = _startRefresh();
    final mutationEpoch = _mutationEpoch;
    final mutatedIdsAtStart = Set<String>.from(_locallyMutatedRunIds);
    final future = _refreshForGeneration(
      generation: generation,
      mutationEpoch: mutationEpoch,
      mutatedIdsAtStart: mutatedIdsAtStart,
    );
    _refreshFuture = future;
    return future;
  }

  Future<void> _refreshForGeneration({
    required int generation,
    required int mutationEpoch,
    required Set<String> mutatedIdsAtStart,
  }) async {
    try {
      final results = await Future.wait<Object>([
        _delegate.listRuns(),
        _delegate.listQueue(),
      ]);
      if (_canApplyRefreshResult(generation)) {
        final runs = results[0] as List<RunSummary>;
        _runs = _mutationEpoch == mutationEpoch
            ? List<RunSummary>.unmodifiable(runs)
            : _mergeRunRefresh(
                runs,
                mutatedIdsAtStart: mutatedIdsAtStart,
              );
        _queue = List<QueueItem>.unmodifiable(results[1] as List<QueueItem>);
        _locallyMutatedRunIds.clear();
        _loaded = true;
      }
    } catch (error) {
      if (_isCurrentRefresh(generation)) _error = error;
      rethrow;
    } finally {
      if (!_disposed && _isCurrentRefresh(generation)) {
        _loading = false;
        _refreshFuture = null;
        _notifyIfActive();
      }
    }
  }

  @override
  Future<List<RunSummary>> listRuns({
    String? tool,
    String? workspaceId,
    String? status,
  }) async {
    if (tool != null || workspaceId != null || status != null) {
      return _delegate.listRuns(
        tool: tool,
        workspaceId: workspaceId,
        status: status,
      );
    }
    await _ensureLoaded();
    return runs;
  }

  @override
  Future<List<QueueItem>> listQueue() async {
    await _ensureLoaded();
    return queue;
  }

  @override
  Future<RunSummary> createRun({
    required String tool,
    required String workspaceId,
    String? prompt,
    String? shortcutId,
    String permissionMode = 'default',
  }) async {
    _startMutation();
    try {
      final run = await _delegate.createRun(
        tool: tool,
        workspaceId: workspaceId,
        prompt: prompt,
        shortcutId: shortcutId,
        permissionMode: permissionMode,
      );
      _upsert(run);
      return run;
    } catch (error) {
      _applyMutationError(error);
      rethrow;
    }
  }

  @override
  Future<List<AgentEvent>> fetchEvents(String runId, {int afterSeq = 0}) =>
      _delegate.fetchEvents(runId, afterSeq: afterSeq);

  @override
  Future<RunSummary> sendRunInput(
    String runId,
    String prompt, {
    String permissionMode = 'default',
  }) async {
    _startMutation();
    try {
      final run = await _delegate.sendRunInput(
        runId,
        prompt,
        permissionMode: permissionMode,
      );
      _upsert(run);
      return run;
    } catch (error) {
      _applyMutationError(error);
      rethrow;
    }
  }

  @override
  Future<RunSummary> cancelRun(String runId) async {
    _startMutation();
    try {
      final run = await _delegate.cancelRun(runId);
      _upsert(run);
      return run;
    } catch (error) {
      _applyMutationError(error);
      rethrow;
    }
  }

  @override
  Future<void> respondApproval(String approvalId, String decision) async {
    final loadedWorkspaceId = _loadedWorkspaceId;
    await _delegate.respondApproval(approvalId, decision);
    if (_loadedWorkspaceId != loadedWorkspaceId) return;
    await refresh();
  }

  @override
  Future<RunSummary> invokeCommandTemplate({
    required String templateId,
    required String workspaceId,
    String tool = 'claude',
  }) async {
    _startMutation();
    try {
      final run = await _delegate.invokeCommandTemplate(
        templateId: templateId,
        workspaceId: workspaceId,
        tool: tool,
      );
      _upsert(run);
      return run;
    } catch (error) {
      _applyMutationError(error);
      rethrow;
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _refreshGeneration++;
    _mutationEpoch++;
    super.dispose();
  }

  int _startRefresh() {
    final generation = ++_refreshGeneration;
    if (_disposed) return generation;
    _loading = true;
    _error = null;
    _notifyIfActive();
    return generation;
  }

  void _startMutation() {
    _mutationEpoch++;
  }

  bool _isCurrentRefresh(int generation) => generation == _refreshGeneration;

  bool _canApplyRefreshResult(int generation) =>
      !_disposed && _isCurrentRefresh(generation);

  Future<void> _ensureLoaded() async {
    final refreshFuture = _refreshFuture;
    if (refreshFuture != null) {
      await refreshFuture;
      return;
    }
    if (!_loaded) {
      await refresh();
    }
  }

  void _upsert(RunSummary run) {
    if (_disposed) return;
    final loadedWorkspaceId = _loadedWorkspaceId;
    if (loadedWorkspaceId != null && run.workspaceId != loadedWorkspaceId) {
      return;
    }
    _mutationEpoch++;
    _locallyMutatedRunIds.add(run.id);
    final index = _runs.indexWhere((item) => item.id == run.id);
    final updated = <RunSummary>[..._runs];
    if (index == -1) {
      updated.insert(0, run);
    } else {
      updated[index] = run;
    }
    _runs = List<RunSummary>.unmodifiable(updated);
    _notifyIfActive();
  }

  void _applyMutationError(Object error) {
    if (_disposed) return;
    _error = error;
    _notifyIfActive();
  }

  void _notifyIfActive() {
    if (!_disposed) notifyListeners();
  }

  List<RunSummary> _mergeRunRefresh(
    List<RunSummary> refreshed, {
    required Set<String> mutatedIdsAtStart,
  }) {
    final mutatedDuringRefresh = _locallyMutatedRunIds.difference(
      mutatedIdsAtStart,
    );
    final byId = <String, RunSummary>{
      for (final run in refreshed) run.id: run,
      for (final run in _runs)
        if (mutatedDuringRefresh.contains(run.id)) run.id: run,
    };
    return List<RunSummary>.unmodifiable(byId.values);
  }
}
