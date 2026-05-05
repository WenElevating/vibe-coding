part of '../app/app.dart';

class MobileShell extends StatefulWidget {
  const MobileShell({super.key});

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> {
  int _tab = 0;
  bool _streamOutput = false;
  bool _expandThinking = false;
  String _permissionMode = 'default';
  bool _codingSessionListOpen = true;
  int _codingSessionListOpenRequest = 0;
  RoutePage _route = RoutePage.tabs;
  late final DaemonClient _client;
  late Future<AppSnapshot> _snapshot;

  @override
  void initState() {
    super.initState();
    _client = DaemonClient(
        baseUri: Uri.parse('http://127.0.0.1:4317'),
        tokenStore: MemoryTokenStore());
    _snapshot = AppSnapshot.load(_client);
  }

  void _refresh() => setState(() => _snapshot = AppSnapshot.load(_client));

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
    _NavSpec(Icons.home_rounded, '首页'),
    _NavSpec(Icons.manage_search_rounded, '运行'),
    _NavSpec(Icons.terminal_rounded, '编码'),
    _NavSpec(Icons.format_list_bulleted_rounded, '设备'),
    _NavSpec(Icons.settings_rounded, '设置'),
  ];

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppSnapshot>(
      future: _snapshot,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
              body: _PhoneFrame(
                  child: Center(
                      child: CircularProgressIndicator(color: _purple))));
        }
        if (snapshot.hasError) {
          return Scaffold(
              body: _PhoneFrame(
                  child: _ConnectionError(
                      error: snapshot.error.toString(), onRetry: _refresh)));
        }
        final data = snapshot.requireData;
        final pages = [
          _HomePage(open: _open, selectTab: _selectTab, data: data),
          _RunsPage(open: _open, data: data),
          _CodingWorkbenchPage(
              data: data,
              client: _client,
              onBack: () => _selectTab(0),
              onSessionListChanged: (open) =>
                  setState(() => _codingSessionListOpen = open),
              openSessionListRequest: _codingSessionListOpenRequest,
              streamOutput: _streamOutput,
              expandThinking: _expandThinking,
              permissionMode: _permissionMode),
          _QueuePage(data: data),
          _SettingsPage(
              open: _open,
              data: data,
              streamOutput: _streamOutput,
              expandThinking: _expandThinking,
              permissionMode: _permissionMode,
              onPermissionModeChanged: (value) =>
                  setState(() => _permissionMode = value),
              onStreamOutputChanged: (value) =>
                  setState(() => _streamOutput = value),
              onExpandThinkingChanged: (value) =>
                  setState(() => _expandThinking = value)),
        ];
        final overlay = switch (_route) {
          RoutePage.detail =>
            _RunDetailPage(onBack: _back, data: data, client: _client),
          RoutePage.approval => _ApprovalPage(onBack: _back),
          RoutePage.adapters => _AdaptersPage(onBack: _back, data: data),
          RoutePage.notifications => _NotificationsPage(onBack: _back),
          RoutePage.diagnostics =>
            _DiagnosticsPage(onBack: _back, data: data, client: _client),
          RoutePage.tabs => null,
        };
        return Scaffold(
          body: _PhoneFrame(
            child: overlay ?? IndexedStack(index: _tab, children: pages),
          ),
          bottomNavigationBar:
              _route == RoutePage.tabs && (_tab != 2 || _codingSessionListOpen)
                  ? _BottomNav(selected: _tab, items: _items, onTap: _selectTab)
                  : null,
          extendBody: true,
        );
      },
    );
  }
}

Color _statusColor(String status) {
  final lower = status.toLowerCase();
  if (lower.contains('fail') || lower.contains('error')) return _red;
  if (lower.contains('queue') || lower.contains('pending')) return _amber;
  if (lower.contains('running') || lower.contains('start')) return _green;
  return _purple;
}

Color _toolColor(String tool) {
  final lower = tool.toLowerCase();
  if (lower.contains('claude')) return _orange;
  if (lower.contains('codex')) return _purple;
  if (lower.contains('open')) return _green;
  return const Color(0xFF8BC7FF);
}

String _displayVersion(String? version) =>
    version == null || version.isEmpty ? 'unknown' : version;

class _ConnectionError extends StatelessWidget {
  const _ConnectionError({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => _PageScroll(children: [
        const _TopBar(title: '连接失败'),
        const SizedBox(height: 32),
        _GlassCard(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.wifi_off_rounded, color: _red, size: 34),
          const SizedBox(height: 14),
          const Text('无法连接到本机 daemon',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(error, style: const TextStyle(color: _muted, fontSize: 12)),
          const SizedBox(height: 16),
          _PrimaryButton('重试连接', onTap: onRetry),
        ])),
        const SizedBox(height: 14),
        const Text(
            '请在 D:\\AiProject\\vibe-coding 运行 start-daemon.bat。真实 e2e 使用临时端口，Windows 预览固定连接 http://127.0.0.1:4317。',
            style: TextStyle(color: _muted, fontSize: 12, height: 1.5)),
      ]);
}

class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF101113), Color(0xFF08090B)])),
      child: Stack(
        children: [
          Positioned(
              top: -160,
              right: -130,
              child: _Glow(size: 260, color: _green.withValues(alpha: .10))),
          Positioned(
              bottom: -170,
              left: -150,
              child: _Glow(size: 260, color: _purple.withValues(alpha: .08))),
          SafeArea(bottom: false, child: child),
        ],
      ),
    );
  }
}

class _HomePage extends StatelessWidget {
  const _HomePage(
      {required this.open, required this.selectTab, required this.data});
  final ValueChanged<RoutePage> open;
  final ValueChanged<int> selectTab;
  final AppSnapshot data;

  @override
  Widget build(BuildContext context) {
    return _PageScroll(
      children: [
        _TopBar(
            title: data.overview.name,
            subtitle:
                '${data.health.bindAddress}:${data.health.port}  ${data.health.status}',
            showScan: true),
        const SizedBox(height: 18),
        _SectionTitle('概览'),
        SizedBox(height: 10),
        Row(
          children: [
            Expanded(
                child: _MetricCard(
                    label: '运行中',
                    value: '${data.runningRuns.length}',
                    note: '活跃任务',
                    colors: [Color(0xFF322A8D), Color(0xFF18204C)])),
            const SizedBox(width: 8),
            Expanded(
                child: _MetricCard(
                    label: '待审批',
                    value: '${data.queue.length}',
                    note: '队列任务',
                    colors: [Color(0xFF073B32), Color(0xFF0B2728)])),
            const SizedBox(width: 8),
            Expanded(
                child: _MetricCard(
                    label: '已完成 (24h)',
                    value: '${data.overview.analysisScore}',
                    note:
                        '${data.overview.fileCount} 文件 · ${data.overview.codeLineCount} 行',
                    colors: [Color(0xFF18212D), Color(0xFF101721)])),
          ],
        ),
        const SizedBox(height: 18),
        _SectionTitle('最近运行', action: '查看全部', onAction: () => selectTab(1)),
        const SizedBox(height: 10),
        _GlassCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              if (data.runs.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('暂无运行记录', style: TextStyle(color: _muted)))
              else
                for (final run in data.runs.take(4).toList()) ...[
                  _CompactRun(
                      title: run.id,
                      tool: run.tool,
                      time: run.workspaceId,
                      status: run.status,
                      color: _statusColor(run.status),
                      iconColor: _toolColor(run.tool),
                      onTap: () => open(RoutePage.detail)),
                  if (run != data.runs.take(4).last) const _Hairline(),
                ],
            ],
          ),
        ),
        const SizedBox(height: 22),
        const _SectionTitle('快捷操作'),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
                child: _QuickAction(
                    icon: Icons.add_box_rounded,
                    title: '新建任务',
                    subtitle: '创建新任务',
                    color: _purple,
                    onTap: () => selectTab(1))),
            const SizedBox(width: 10),
            Expanded(
                child: _QuickAction(
                    icon: Icons.drive_file_move_rounded,
                    title: '命令模板',
                    subtitle: '执行预设命令',
                    color: _green,
                    onTap: () => selectTab(2))),
            const SizedBox(width: 10),
            Expanded(
                child: _QuickAction(
                    icon: Icons.view_list_rounded,
                    title: '查看队列',
                    subtitle: '查看排队任务',
                    color: _orange,
                    onTap: () => selectTab(3))),
          ],
        ),
        const SizedBox(height: 18),
        _ApprovalPreview(onTap: () => open(RoutePage.approval)),
      ],
    );
  }
}

class _RunsPage extends StatelessWidget {
  const _RunsPage({required this.open, required this.data});
  final ValueChanged<RoutePage> open;
  final AppSnapshot data;

  @override
  Widget build(BuildContext context) {
    return _PageScroll(
      floating: _FloatingPlus(onTap: () => open(RoutePage.detail)),
      children: [
        _TopBar(title: '运行列表'),
        const SizedBox(height: 20),
        Row(children: [
          _Pill('全部 ${data.runs.length}', selected: true),
          _Pill('运行中 ${data.runningRuns.length}'),
          _Pill('已完成 ${data.completedRuns.length}'),
          _Pill('失败 ${data.failedRuns.length}'),
        ]),
        const SizedBox(height: 14),
        const _SearchBar(),
        const SizedBox(height: 14),
        if (data.runs.isEmpty)
          const _GlassCard(
              child: Text('暂无运行。可从命令模板发起真实 AI CLI 任务。',
                  style: TextStyle(color: _muted)))
        else
          for (final run in data.runs) ...[
            _RunCard(
                title: run.id,
                tool: run.tool,
                time: 'workspace: ${run.workspaceId}',
                status: run.status,
                progress: run.status == 'completed' ? 1 : .48,
                statusColor: _statusColor(run.status),
                onTap: () => open(RoutePage.detail)),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _QueuePage extends StatelessWidget {
  const _QueuePage({required this.data});
  final AppSnapshot data;

  @override
  Widget build(BuildContext context) {
    final active =
        data.queue.where((item) => item.status == 'running').toList();
    final waiting =
        data.queue.where((item) => item.status != 'running').toList();
    return _PageScroll(
      children: [
        _TopBar(title: '运行队列', leading: true, action: '${data.queue.length} 项'),
        const SizedBox(height: 20),
        Row(children: [
          _Pill('运行中 ${active.length}', selected: true, green: true),
          _Pill('排队中 ${waiting.length}', amber: true),
          _Pill('总计 ${data.queue.length}')
        ]),
        const SizedBox(height: 22),
        const _Subhead('运行中'),
        _GlassCard(
          child: active.isEmpty
              ? const Text('暂无运行中队列', style: TextStyle(color: _muted))
              : Column(children: [
                  for (final item in active) ...[
                    _QueueRow(
                        title: item.runId,
                        tool: item.reason.isEmpty ? item.status : item.reason,
                        iconColor: _green),
                    if (item != active.last) const _Hairline(),
                  ],
                ]),
        ),
        const SizedBox(height: 24),
        const _Subhead('排队中'),
        _GlassCard(
          padding: EdgeInsets.zero,
          child: waiting.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('暂无等待任务', style: TextStyle(color: _muted)))
              : Column(children: [
                  for (final item in waiting) ...[
                    _WaitingRow(
                        index: '${item.position}',
                        title: item.runId,
                        tool: item.reason.isEmpty ? item.status : item.reason),
                    if (item != waiting.last) const _Hairline(),
                  ],
                ]),
        ),
        const SizedBox(height: 20),
        const Text('队列数据来自 daemon，任务按工作区顺序执行。',
            style: TextStyle(color: _muted, fontSize: 12)),
      ],
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.labels});
  final List<String> labels;
  @override
  Widget build(BuildContext context) => Row(children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
              child: Container(
                  padding: const EdgeInsets.only(bottom: 9),
                  decoration: BoxDecoration(
                      border: Border(
                          bottom: BorderSide(
                              color: i == 0 ? _purple : _stroke,
                              width: i == 0 ? 2 : 1))),
                  child: Text(labels[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: i == 0 ? _purple : _muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w800))))
      ]);
}
