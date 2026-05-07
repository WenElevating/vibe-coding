import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
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
  bool _codingAdaptersLoaded = false;
  bool _codingAdaptersLoading = false;
  late AppSnapshot _data;
  RoutePage _route = RoutePage.tabs;

  @override
  void initState() {
    super.initState();
    _data = widget.data;
  }

  @override
  void didUpdateWidget(covariant MainTabsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data && !_codingAdaptersLoaded) {
      _data = widget.data;
    }
  }

  void _open(RoutePage route) => setState(() => _route = route);
  void _back() => setState(() => _route = RoutePage.tabs);
  void _selectTab(int index) {
    setState(() {
      _tab = index;
      _route = RoutePage.tabs;
      if (index == 2) {
        _codingSessionListOpen = true;
        _codingSessionListOpenRequest++;
      }
    });
    if (index == 2) _ensureCodingAdaptersLoaded();
  }

  Future<void> _ensureCodingAdaptersLoaded() async {
    if (_codingAdaptersLoaded || _codingAdaptersLoading) return;
    _codingAdaptersLoading = true;
    try {
      final adapters = await widget.client.listAdapters();
      if (!mounted) return;
      setState(() {
        _data = _snapshotWithAdapters(_data, adapters);
        _codingAdaptersLoaded = true;
        _codingAdaptersLoading = false;
      });
    } catch (_) {
      _codingAdaptersLoading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final data = _data;
    final pages = [
      HomePage(open: _open, selectTab: _selectTab, data: data),
      RunsPage(open: _open, data: data),
      CodingPage(
        data: data,
        client: widget.client,
        onBack: () => _selectTab(0),
        onSessionListChanged: (open) =>
            setState(() => _codingSessionListOpen = open),
        openSessionListRequest: _codingSessionListOpenRequest,
        streamOutput: _streamOutput,
        expandThinking: _expandThinking,
        permissionMode: _permissionMode,
      ),
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
    return Scaffold(
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
                  selected: _tab, items: mainTabItems(l10n), onTap: _selectTab)
              : null,
      extendBody: true,
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
