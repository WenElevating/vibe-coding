import 'package:flutter/foundation.dart';

import '../../../../domain/models/codex_app_server_models.dart';
import '../../../../domain/repositories/codex_app_server_repository.dart';

class CodexAppServerState {
  CodexAppServerState({
    this.loading = false,
    this.error,
    this.workspaceId,
    this.capabilities,
    this.discovery,
    List<CodexAppServerThreadSummary> threads =
        const <CodexAppServerThreadSummary>[],
  }) : threads = List<CodexAppServerThreadSummary>.unmodifiable(threads);

  final bool loading;
  final String? error;
  final String? workspaceId;
  final CodexAppServerCapabilities? capabilities;
  final CodexAppServerDiscoverySnapshot? discovery;
  final List<CodexAppServerThreadSummary> threads;

  CodexAppServerState copyWith({
    bool? loading,
    String? error,
    bool clearError = false,
    String? workspaceId,
    CodexAppServerCapabilities? capabilities,
    CodexAppServerDiscoverySnapshot? discovery,
    List<CodexAppServerThreadSummary>? threads,
  }) {
    return CodexAppServerState(
      loading: loading ?? this.loading,
      error: clearError ? null : error ?? this.error,
      workspaceId: workspaceId,
      capabilities: capabilities ?? this.capabilities,
      discovery: discovery ?? this.discovery,
      threads: threads ?? this.threads,
    );
  }
}

class CodexAppServerViewModel extends ChangeNotifier {
  CodexAppServerViewModel({required CodexAppServerRepository repository})
      : _repository = repository;

  final CodexAppServerRepository _repository;
  CodexAppServerState _state = CodexAppServerState();
  int _loadGeneration = 0;
  bool _disposed = false;

  CodexAppServerState get state => _state;

  Future<void> load({required String workspaceId}) async {
    final generation = ++_loadGeneration;
    if (_disposed) return;
    _state = CodexAppServerState(loading: true, workspaceId: workspaceId);
    _notifyIfAlive();
    try {
      final capabilities = await _repository.loadCapabilities();
      if (_disposed || generation != _loadGeneration) return;
      final page = await _repository.listThreads(workspaceId);
      if (_disposed || generation != _loadGeneration) return;
      final discovery = await _repository.loadDiscovery();
      if (_disposed || generation != _loadGeneration) return;
      _state = CodexAppServerState(
        workspaceId: workspaceId,
        capabilities: capabilities,
        discovery: discovery,
        threads: page.threads,
      );
      _notifyIfAlive();
    } catch (error) {
      if (_disposed || generation != _loadGeneration) return;
      _state = CodexAppServerState(
        workspaceId: workspaceId,
        error: '$error',
      );
      _notifyIfAlive();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _loadGeneration++;
    super.dispose();
  }

  void _notifyIfAlive() {
    if (!_disposed) notifyListeners();
  }
}
