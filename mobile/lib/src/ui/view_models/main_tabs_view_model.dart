import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/repositories/adapter_repository.dart';
import '../../models/protocol.dart';
import '../../shell/app_route.dart';
import '../../shell/app_snapshot.dart';

enum CodingAdapterLoadState { idle, loading, loaded, failed }

class MainTabsViewModel extends ChangeNotifier {
  MainTabsViewModel({
    required AppSnapshot initialData,
    required AdapterRepository adapterRepository,
  })  : _data = initialData,
        _adapterRepository = adapterRepository;

  AdapterRepository _adapterRepository;
  AppSnapshot _data;

  int _activeTab = 0;
  bool _streamOutput = false;
  bool _expandThinking = false;
  String _permissionMode = 'auto';
  bool _codingSessionListOpen = true;
  int _openSessionListRequest = 0;
  CodingAdapterLoadState _adapterLoadState = CodingAdapterLoadState.idle;
  Future<void>? _adapterLoadFuture;
  int _adapterLoadGeneration = 0;
  Object? _adapterLoadError;
  RoutePage _activeRoute = RoutePage.tabs;
  bool _disposed = false;

  int get activeTab => _activeTab;
  bool get streamOutput => _streamOutput;
  bool get expandThinking => _expandThinking;
  String get permissionMode => _permissionMode;
  bool get codingSessionListOpen => _codingSessionListOpen;
  int get openSessionListRequest => _openSessionListRequest;
  CodingAdapterLoadState get adapterLoadState => _adapterLoadState;
  Object? get adapterLoadError => _adapterLoadError;
  AppSnapshot get data => _data;
  RoutePage get activeRoute => _activeRoute;
  bool get isOverlayActive => _activeRoute != RoutePage.tabs;

  void openOverlay(RoutePage route) {
    _activeRoute = route;
    notifyListeners();
  }

  void closeOverlay() {
    _activeRoute = RoutePage.tabs;
    notifyListeners();
  }

  void selectTab(int index) {
    final previousTab = _activeTab;
    _activeTab = index;
    _activeRoute = RoutePage.tabs;
    if (index == 1) {
      _codingSessionListOpen = true;
      _openSessionListRequest++;
    }
    notifyListeners();
    if (index == 1 && previousTab == 1) {
      unawaited(ensureCodingAdaptersLoaded());
    }
  }

  void setStreamOutput(bool value) {
    if (_streamOutput == value) return;
    _streamOutput = value;
    notifyListeners();
  }

  void setExpandThinking(bool value) {
    if (_expandThinking == value) return;
    _expandThinking = value;
    notifyListeners();
  }

  void setPermissionMode(String value) {
    if (_permissionMode == value) return;
    _permissionMode = value;
    notifyListeners();
  }

  void reportSessionListOpen(bool open) {
    if (_codingSessionListOpen == open) return;
    _codingSessionListOpen = open;
    notifyListeners();
  }

  void updateData(AppSnapshot data) {
    _data = data;
    notifyListeners();
  }

  void updateWorkspaceCatalog(List<WorkspaceSummary> workspaces) {
    _data = _snapshotWithWorkspaces(_data, List.unmodifiable(workspaces));
    notifyListeners();
  }

  void resetForNewClient({
    required AdapterRepository adapterRepository,
    required AppSnapshot data,
  }) {
    _adapterRepository = adapterRepository;
    _data = data;
    _adapterLoadGeneration++;
    _adapterLoadState = CodingAdapterLoadState.idle;
    _adapterLoadFuture = null;
    _adapterLoadError = null;
    notifyListeners();
    unawaited(ensureCodingAdaptersLoaded());
  }

  Future<void> ensureCodingAdaptersLoaded() async {
    if (_adapterLoadState == CodingAdapterLoadState.loaded) return;
    final existing = _adapterLoadFuture;
    if (existing != null) return existing;
    _adapterLoadState = CodingAdapterLoadState.loading;
    _adapterLoadError = null;
    notifyListeners();
    final generation = _adapterLoadGeneration;
    final load = _loadCodingAdapters(generation);
    _adapterLoadFuture = load;
    return load;
  }

  Future<void> _loadCodingAdapters(int generation) async {
    try {
      final adapters = await _adapterRepository.listAdapters();
      if (_disposed || generation != _adapterLoadGeneration) return;
      _data = _snapshotWithAdapters(_data, adapters);
      _adapterLoadState = CodingAdapterLoadState.loaded;
      _adapterLoadError = null;
      _adapterLoadFuture = null;
      notifyListeners();
    } catch (error) {
      if (_disposed || generation != _adapterLoadGeneration) return;
      _adapterLoadState = CodingAdapterLoadState.failed;
      _adapterLoadError = error;
      _adapterLoadFuture = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

AppSnapshot _snapshotWithAdapters(
        AppSnapshot snapshot, List<AdapterStatus> adapters) =>
    AppSnapshot(
      health: snapshot.health,
      workspaces: snapshot.workspaces,
      workspace: snapshot.workspace,
      overview: snapshot.overview,
      adapters: adapters,
      runs: snapshot.runs,
      conversations: snapshot.conversations,
      queue: snapshot.queue,
      templates: snapshot.templates,
      gitStatus: snapshot.gitStatus,
      diffs: snapshot.diffs,
      commits: snapshot.commits,
      fileTree: snapshot.fileTree,
      diagnostics: snapshot.diagnostics,
      extensions: snapshot.extensions,
    );

AppSnapshot _snapshotWithWorkspaces(
        AppSnapshot snapshot, List<WorkspaceSummary> workspaces) =>
    AppSnapshot(
      health: snapshot.health,
      workspaces: workspaces,
      workspace: snapshot.workspace,
      overview: snapshot.overview,
      adapters: snapshot.adapters,
      runs: snapshot.runs,
      conversations: snapshot.conversations,
      queue: snapshot.queue,
      templates: snapshot.templates,
      gitStatus: snapshot.gitStatus,
      diffs: snapshot.diffs,
      commits: snapshot.commits,
      fileTree: snapshot.fileTree,
      diagnostics: snapshot.diagnostics,
      extensions: snapshot.extensions,
    );
