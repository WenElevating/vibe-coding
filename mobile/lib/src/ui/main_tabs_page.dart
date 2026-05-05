import 'package:flutter/material.dart';

import '../features/adapters/adapters.dart';
import '../features/diagnostics/diagnostics.dart';
import '../features/notifications/notifications.dart';
import '../features/run_detail/run_detail.dart';
import '../features/settings/settings.dart';
import '../services/daemon_client.dart';
import '../shell/app_route.dart';
import '../shell/app_snapshot.dart';
import '../widgets/widgets.dart';
import 'mobile_ui_frame.dart';
import 'pages/pages.dart';

class MainTabsPage extends StatefulWidget {
  const MainTabsPage({super.key, required this.data, required this.client});

  final AppSnapshot data;
  final DaemonClient client;

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
  RoutePage _route = RoutePage.tabs;

  void _open(RoutePage route) => setState(() => _route = route);
  void _back() => setState(() => _route = RoutePage.tabs);
  void _selectTab(int index) => setState(() {
        _tab = index;
        _route = RoutePage.tabs;
        if (index == 2) {
          _codingSessionListOpen = true;
          _codingSessionListOpenRequest++;
        }
      });

  final _items = const [
    NavSpec(Icons.home_rounded, '首页'),
    NavSpec(Icons.manage_search_rounded, '运行'),
    NavSpec(Icons.terminal_rounded, '编码'),
    NavSpec(Icons.format_list_bulleted_rounded, '设备'),
    NavSpec(Icons.settings_rounded, '设置'),
  ];


  @override
  Widget build(BuildContext context) {
    final data = widget.data;
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
    final overlay = switch (_route) {
      RoutePage.detail =>
        RunDetailPage(onBack: _back, data: data, client: widget.client),
      RoutePage.approval => ApprovalPage(onBack: _back),
      RoutePage.adapters => AdaptersPage(onBack: _back, data: data),
      RoutePage.notifications => NotificationsPage(onBack: _back),
      RoutePage.diagnostics =>
        DiagnosticsPage(onBack: _back, data: data, client: widget.client),
      RoutePage.tabs => null,
    };
    return Scaffold(
      body: MobileUiFrame(
        child: overlay ?? IndexedStack(index: _tab, children: pages),
      ),
      bottomNavigationBar:
          _route == RoutePage.tabs && (_tab != 2 || _codingSessionListOpen)
              ? BottomNav(selected: _tab, items: _items, onTap: _selectTab)
              : null,
      extendBody: true,
    );
  }
}
