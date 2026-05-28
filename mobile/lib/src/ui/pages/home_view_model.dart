import 'package:flutter/foundation.dart';

import '../../data/repositories/cached_conversation_repository.dart';
import '../../data/repositories/cached_run_repository.dart';
import '../../data/repositories/workspace_repository.dart';
import '../../models/protocol.dart';
import 'home_command_deck_model.dart';

class HomeViewModel extends ChangeNotifier {
  HomeViewModel({
    required WorkspaceRepository workspaceRepository,
    required CachedConversationRepository conversationRepository,
    required CachedRunRepository runRepository,
  })  : _workspaceRepository = workspaceRepository,
        _conversationRepository = conversationRepository,
        _runRepository = runRepository {
    _workspaceRepository.addListener(_onRepositoryChanged);
    _conversationRepository.addListener(_onRepositoryChanged);
    _runRepository.addListener(_onRepositoryChanged);
  }

  final WorkspaceRepository _workspaceRepository;
  final CachedConversationRepository _conversationRepository;
  final CachedRunRepository _runRepository;

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
      changedFiles: null,
      diagnostics: null,
      recentFiles: null,
    );
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
