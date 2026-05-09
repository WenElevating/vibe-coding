import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../features/workbench/workbench.dart';
import '../models/protocol.dart';
import '../services/daemon_client.dart';
import '../services/daemon_connection_config.dart';
import '../shell/app_route.dart';
import '../shell/app_snapshot.dart';
import '../widgets/widgets.dart';
import 'main_tab_items.dart';
import 'main_route_overlay.dart';
import 'mobile_ui_frame.dart';
import 'pages/pages.dart';

enum _CodingAdapterLoadState { idle, loading, loaded, failed }

class MainTabsPage extends StatefulWidget {
  const MainTabsPage(
      {super.key,
      required this.data,
      required this.client,
      required this.connectionConfig});

  final AppSnapshot data;
  final DaemonClient client;
  final DaemonConnectionConfig connectionConfig;

  @override
  State<MainTabsPage> createState() => _MainTabsPageState();
}

class _MainTabsPageState extends State<MainTabsPage> {
  int _tab = 0;
  bool _streamOutput = false;
  bool _expandThinking = false;
  String _permissionMode = 'default';
  bool _codingSessionListOpen = true;
  int _codingSessionListOpenRequest = 0;
  final _codingWorkbenchKey = GlobalKey<CodingWorkbenchPageState>();
  _CodingAdapterLoadState _codingAdapterLoadState =
      _CodingAdapterLoadState.idle;
  Future<void>? _codingAdapterLoadFuture;
  Object? _codingAdapterLoadError;
  late AppSnapshot _data;
  RoutePage _route = RoutePage.tabs;

  @override
  void initState() {
    super.initState();
    _data = widget.data;
    unawaited(_ensureCodingAdaptersLoaded());
  }

  @override
  void didUpdateWidget(covariant MainTabsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) {
      _codingAdapterLoadState = _CodingAdapterLoadState.idle;
      _codingAdapterLoadFuture = null;
      _codingAdapterLoadError = null;
      _data = widget.data;
      unawaited(_ensureCodingAdaptersLoaded());
      return;
    }
    if (oldWidget.data != widget.data &&
        _codingAdapterLoadState != _CodingAdapterLoadState.loaded) {
      _data = widget.data;
    }
  }

  void _open(RoutePage route) => setState(() => _route = route);
  void _back() => setState(() => _route = RoutePage.tabs);
  void _selectTab(int index) {
    final previousTab = _tab;
    setState(() {
      _tab = index;
      _route = RoutePage.tabs;
      if (index == 2) {
        _codingSessionListOpen = true;
        _codingSessionListOpenRequest++;
      }
    });
    if (index == 2 && previousTab == 2) {
      unawaited(_ensureCodingAdaptersLoaded());
    }
  }

  Future<void> _handleSystemBack() async {
    if (_route != RoutePage.tabs) {
      _back();
      return;
    }
    if (_tab == 2) {
      final consumed =
          await (_codingWorkbenchKey.currentState?.handleSystemBack() ??
              Future<bool>.value(false));
      if (consumed) return;
      _selectTab(0);
      return;
    }
    if (_tab != 0) {
      _selectTab(0);
      return;
    }
    await SystemNavigator.pop();
  }

  Future<void> _ensureCodingAdaptersLoaded() async {
    if (_codingAdapterLoadState == _CodingAdapterLoadState.loaded) return;
    final existingLoad = _codingAdapterLoadFuture;
    if (existingLoad != null) return existingLoad;
    setState(() {
      _codingAdapterLoadState = _CodingAdapterLoadState.loading;
      _codingAdapterLoadError = null;
    });
    final load = _loadCodingAdapters();
    _codingAdapterLoadFuture = load;
    return load;
  }

  Future<void> _loadCodingAdapters() async {
    try {
      final adapters = await widget.client.listAdapters();
      if (!mounted) return;
      setState(() {
        _data = _snapshotWithAdapters(_data, adapters);
        _codingAdapterLoadState = _CodingAdapterLoadState.loaded;
        _codingAdapterLoadError = null;
        _codingAdapterLoadFuture = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _codingAdapterLoadState = _CodingAdapterLoadState.failed;
        _codingAdapterLoadError = error;
        _codingAdapterLoadFuture = null;
      });
    }
  }

  Widget _buildCodingTab() {
    if (_codingAdapterLoadState == _CodingAdapterLoadState.loaded) {
      return CodingPage(
        data: _data,
        client: widget.client,
        workbenchKey: _codingWorkbenchKey,
        onBack: () => _selectTab(0),
        onSessionListChanged: (open) =>
            setState(() => _codingSessionListOpen = open),
        openSessionListRequest: _codingSessionListOpenRequest,
        streamOutput: _streamOutput,
        expandThinking: _expandThinking,
        permissionMode: _permissionMode,
      );
    }
    return _CodingAdapterGate(
      failed: _codingAdapterLoadState == _CodingAdapterLoadState.failed,
      error: _codingAdapterLoadError,
      onRetry: () => unawaited(_ensureCodingAdaptersLoaded()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final data = _data;
    final pages = [
      HomePage(open: _open, selectTab: _selectTab, data: data),
      RunsPage(open: _open, data: data),
      _buildCodingTab(),
      QueuePage(data: data),
      SettingsPage(
        open: _open,
        data: data,
        connectionConfig: widget.connectionConfig,
        streamOutput: _streamOutput,
        expandThinking: _expandThinking,
        permissionMode: _permissionMode,
        onPermissionModeChanged: (value) =>
            setState(() => _permissionMode = value),
        onStreamOutputChanged: (value) => setState(() => _streamOutput = value),
        onExpandThinkingChanged: (value) =>
            setState(() => _expandThinking = value),
      ),
    ];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_handleSystemBack());
      },
      child: Scaffold(
        body: MobileUiFrame(
          child: _route == RoutePage.tabs
              ? IndexedStack(index: _tab, children: pages)
              : MainRouteOverlay(
                  route: _route,
                  data: data,
                  client: widget.client,
                  onBack: _back,
                ),
        ),
        bottomNavigationBar:
            _route == RoutePage.tabs && (_tab != 2 || _codingSessionListOpen)
                ? BottomNav(
                    selected: _tab,
                    items: mainTabItems(l10n),
                    onTap: _selectTab)
                : null,
        extendBody: true,
      ),
    );
  }
}

class _CodingAdapterGate extends StatelessWidget {
  const _CodingAdapterGate({
    required this.failed,
    required this.error,
    required this.onRetry,
  });

  final bool failed;
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!failed) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Loading CLI...'),
            ] else ...[
              const Icon(Icons.error_outline, size: 42),
              const SizedBox(height: 12),
              const Text('Unable to load CLI adapters'),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text('$error', textAlign: TextAlign.center),
              ],
              const SizedBox(height: 16),
              PrimaryButton('Retry loading CLI', onTap: onRetry),
            ],
          ],
        ),
      ),
    );
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
