import 'package:flutter/foundation.dart';

import '../../../../data/repositories/cached_conversation_repository.dart';
import '../../../../data/repositories/cached_run_repository.dart';
import '../../../../data/repositories/workspace_repository.dart';
import '../../../../models/protocol.dart';
import '../models/home_command_deck_model.dart';

class HomeWorkspaceSignalMetrics {
  const HomeWorkspaceSignalMetrics({
    this.changedFiles,
    this.diagnostics,
    this.recentFiles,
  });

  final int? changedFiles;
  final int? diagnostics;
  final int? recentFiles;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HomeWorkspaceSignalMetrics &&
          other.changedFiles == changedFiles &&
          other.diagnostics == diagnostics &&
          other.recentFiles == recentFiles;

  @override
  int get hashCode => Object.hash(changedFiles, diagnostics, recentFiles);
}

class HomeDashboardState {
  const HomeDashboardState({
    required this.attentionCount,
    required this.runningCount,
    required this.queueCount,
    required this.attentionItems,
    required this.activityItems,
  });

  const HomeDashboardState.empty()
      : attentionCount = 0,
        runningCount = 0,
        queueCount = 0,
        attentionItems = const <HomeSignalItem>[],
        activityItems = const <HomeSignalItem>[];

  final int attentionCount;
  final int runningCount;
  final int queueCount;
  final List<HomeSignalItem> attentionItems;
  final List<HomeSignalItem> activityItems;

  bool get needsAttention => attentionCount > 0;
}

class HomeViewModel extends ChangeNotifier {
  HomeViewModel({
    required WorkspaceRepository workspaceRepository,
    required CachedConversationRepository conversationRepository,
    required CachedRunRepository runRepository,
    HomeWorkspaceSignalMetrics signalMetrics =
        const HomeWorkspaceSignalMetrics(),
  })  : _workspaceRepository = workspaceRepository,
        _conversationRepository = conversationRepository,
        _runRepository = runRepository,
        _signalMetrics = signalMetrics {
    _workspaceRepository.addListener(_onRepositoryChanged);
    _conversationRepository.addListener(_onRepositoryChanged);
    _runRepository.addListener(_onRepositoryChanged);
  }

  final WorkspaceRepository _workspaceRepository;
  final CachedConversationRepository _conversationRepository;
  final CachedRunRepository _runRepository;
  HomeWorkspaceSignalMetrics _signalMetrics;

  List<WorkspaceSummary> get workspaces => _workspaceRepository.workspaces;
  WorkspaceSummary? get currentWorkspace =>
      _workspaceRepository.selectedWorkspace;
  bool get loading =>
      _workspaceRepository.loading ||
      _conversationRepository.loading ||
      _runRepository.loading;
  Object? get error =>
      _workspaceRepository.error ??
      _conversationRepository.error ??
      _runRepository.error;

  HomeCommandDeckData? get deck {
    final workspace = currentWorkspace;
    if (workspace == null) return null;
    return buildHomeCommandDeckData(
      currentWorkspace: workspace,
      workspaces: _workspaceRepository.workspaces,
      runs: _runRepository.runs,
      conversations: _conversationRepository.conversations,
      queue: _runRepository.queue,
      changedFiles: _signalMetrics.changedFiles,
      diagnostics: _signalMetrics.diagnostics,
      recentFiles: _signalMetrics.recentFiles,
    );
  }

  HomeDashboardState? get dashboard {
    final deck = this.deck;
    if (deck == null) return null;
    final allAttentionItems = deck.allSignals
        .where((item) =>
            item.kind == HomeSignalKind.approval ||
            item.kind == HomeSignalKind.failure ||
            item.kind == HomeSignalKind.queue)
        .toList();
    final attentionItems = allAttentionItems.take(3).toList();
    final activityItems = deck.allSignals
        .where((item) => item.kind != HomeSignalKind.idle)
        .take(4)
        .toList();
    return HomeDashboardState(
      attentionCount: allAttentionItems.length,
      runningCount: deck.allSignals
          .where((item) => item.kind == HomeSignalKind.running)
          .length,
      queueCount: deck.allSignals
          .where((item) => item.kind == HomeSignalKind.queue)
          .length,
      attentionItems: attentionItems,
      activityItems: activityItems,
    );
  }

  void updateSignalMetrics(HomeWorkspaceSignalMetrics signalMetrics) {
    if (_signalMetrics == signalMetrics) return;
    _signalMetrics = signalMetrics;
    notifyListeners();
  }

  Future<void> refresh() async {
    await Future.wait<void>([
      _workspaceRepository.refresh(),
      _conversationRepository.refresh(),
      _runRepository.refresh(),
    ]);
  }

  void _onRepositoryChanged() => notifyListeners();

  @override
  void dispose() {
    _workspaceRepository.removeListener(_onRepositoryChanged);
    _conversationRepository.removeListener(_onRepositoryChanged);
    _runRepository.removeListener(_onRepositoryChanged);
    super.dispose();
  }
}
