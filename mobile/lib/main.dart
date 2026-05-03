import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'lan_ai_cli_control.dart';

const _bg = Color(0xFF0A0B0D);
const _panel = Color(0xE6111214);
const _panelHi = Color(0xF2161719);
const _stroke = Color(0x16FFFFFF);
const _purple = Color(0xFFA78BFA);
const _purple2 = Color(0xFF8AB4FF);
const _green = Color(0xFF32D583);
const _amber = Color(0xFFF2C572);
const _red = Color(0xFFFF6B6B);
const _orange = Color(0xFFF2C572);
const _text = Color(0xFFEDEDED);
const _muted = Color(0xFFA9ADB5);
const _faint = Color(0xFF747982);
const _zhHansCnLocale = Locale.fromSubtags(
    languageCode: 'zh', scriptCode: 'Hans', countryCode: 'CN');
const _appFontFallback = <String>[
  'PingFang SC',
  'Microsoft YaHei UI',
  'Noto Sans CJK SC',
  'Noto Sans SC',
  'sans-serif',
];
const _appTextStyle = TextStyle(
    fontFamily: 'Segoe UI',
    fontFamilyFallback: _appFontFallback,
    locale: _zhHansCnLocale);
const _appLocalizationsDelegates = <LocalizationsDelegate<Object>>[
  GlobalMaterialLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];

void main() => runApp(const LanAiCliControlApp());

class LanAiCliControlApp extends StatelessWidget {
  const LanAiCliControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AI CLI 控制台',
      locale: _zhHansCnLocale,
      supportedLocales: const [_zhHansCnLocale, Locale('en', 'US')],
      localizationsDelegates: _appLocalizationsDelegates,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _bg,
        fontFamily: 'Segoe UI',
        fontFamilyFallback: _appFontFallback,
        colorScheme: const ColorScheme.dark(
            primary: _purple, surface: _panel, onSurface: _text),
        textTheme: const TextTheme(
            bodyMedium: _appTextStyle,
            bodyLarge: _appTextStyle,
            bodySmall: _appTextStyle),
        useMaterial3: true,
      ),
      home: const MobileShell(),
    );
  }
}

@visibleForTesting
Widget buildAssistantMarkdownPreview(String markdown) => MaterialApp(
    locale: _zhHansCnLocale,
    supportedLocales: const [_zhHansCnLocale, Locale('en', 'US')],
    localizationsDelegates: _appLocalizationsDelegates,
    theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _bg,
        fontFamily: 'Segoe UI',
        fontFamilyFallback: _appFontFallback,
        textTheme: const TextTheme(bodyMedium: TextStyle(color: _text)),
        useMaterial3: true),
    home: Scaffold(
        body: Padding(
            padding: const EdgeInsets.all(16),
            child: _AssistantMarkdownBody(markdown: markdown))));

@visibleForTesting
String? debugVisibleWorkbenchBodyFromEvent(Map<String, Object?> json,
        {bool streamOutput = false}) =>
    _WorkbenchMessage.fromEvent(AgentEvent.fromJson(json), streamOutput)?.body;

@visibleForTesting
List<String> debugMergeSessionRunIds(
    List<RunSummary> localRuns, List<RunSummary> snapshotRuns) {
  final ids = <String>[];
  final seen = <String>{};
  for (final run in localRuns) {
    if (seen.add(run.id)) ids.add(run.id);
  }
  for (final run in snapshotRuns) {
    if (seen.add(run.id)) ids.add(run.id);
  }
  return ids;
}

@visibleForTesting
List<String> debugMergeSessionIds(List<RunSummary> localRuns,
        List<ConversationSummary> snapshotConversations,
        List<RunSummary> snapshotRuns) =>
    _mergeSessionItems(
            localRuns.map((run) => _SessionItem(run: run)).toList(),
            snapshotConversations,
            snapshotRuns)
        .map((item) => item.id)
        .toList(growable: false);

@visibleForTesting
String debugConversationPendingStatusText(String status) =>
    _conversationPendingStatusText(status, const <ConversationEvent>[]);

@visibleForTesting
bool debugShouldPollAfterApproval(ConversationSummary conversation) =>
    _shouldPollAfterApproval(conversation);

@visibleForTesting
bool debugHasExplicitWorkspaceSelection({
  required bool workspaceConfirmedForSession,
  required String? activeRunId,
  required bool hasLocalSessions,
}) =>
    _hasExplicitWorkspaceSelectionState(
      workspaceConfirmedForSession: workspaceConfirmedForSession,
      activeRunId: activeRunId,
      hasLocalSessions: hasLocalSessions,
    );

@visibleForTesting
List<String> debugVisibleApprovalIdsForConversation(
    List<Map<String, Object?>> events, ConversationSummary conversation) {
  final state = const ConversationViewState().apply(events
      .map((event) => ConversationEvent.fromJson(event))
      .toList(growable: false));
  return _messagesForConversationSnapshot(state.messages, conversation)
      .where((message) => message.role == 'approval')
      .map((message) => message.approvalId ?? '')
      .toList(growable: false);
}

@visibleForTesting
Widget buildRunningComposerPreview() => MaterialApp(
    locale: _zhHansCnLocale,
    supportedLocales: const [_zhHansCnLocale, Locale('en', 'US')],
    localizationsDelegates: _appLocalizationsDelegates,
    theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'Segoe UI',
        fontFamilyFallback: _appFontFallback,
        useMaterial3: true),
    home: Scaffold(
        backgroundColor: _bg,
        body: _CodingComposer(
            controller: TextEditingController(),
            adapter: 'claude',
            workspace: const WorkspaceSummary(
                id: 'workspace_1', name: 'vibe-coding', path: ''),
            running: true,
            canSend: true,
            sending: false,
            onModelTap: () {},
            onSend: () {},
            onCancel: () {})));

@visibleForTesting
Widget buildNewSessionWorkspacePickerPreview() {
  const workspace = WorkspaceSummary(
      id: 'workspace_1',
      name: 'vibe-coding',
      path: r'D:\AiProject\vibe-coding');
  final client = DaemonClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenStore: MemoryTokenStore());
  return MaterialApp(
      locale: _zhHansCnLocale,
      supportedLocales: const [_zhHansCnLocale, Locale('en', 'US')],
      localizationsDelegates: _appLocalizationsDelegates,
      theme: ThemeData(
          brightness: Brightness.dark,
          fontFamily: 'Segoe UI',
          fontFamilyFallback: _appFontFallback,
          useMaterial3: true),
      home: Scaffold(
          backgroundColor: _bg,
          body: Builder(
              builder: (context) => Center(
                  child: _SessionNewButton(
                      onTap: () => showModalBottomSheet<WorkspaceSummary>(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (context) => _FirstRunWorkspaceSheet(
                              workspaces: const <WorkspaceSummary>[workspace],
                              selected: workspace,
                              client: client)))))));
}

@visibleForTesting
List<String> debugWorkbenchMessageRolesAfterEvents(
    List<Map<String, Object?>> events) {
  final messages = <_WorkbenchMessage>[];
  final resolvedApprovalIds = <String>{};
  for (final json in events) {
    final event = AgentEvent.fromJson(json);
    if (event.type == 'approval.responded') {
      final approvalId = event.approvalId ?? event.raw['approvalId'] as String?;
      if (approvalId != null && approvalId.isNotEmpty) {
        resolvedApprovalIds.add(approvalId);
        messages.removeWhere((item) =>
            item.role == 'approval' && item.event?.approvalId == approvalId);
      }
      final decision = event.raw['decision'];
      final input = event.raw['input'];
      final command = input is Map<String, Object?> ? input['command'] : null;
      if (decision == 'allow' &&
          command is String &&
          command.trim().isNotEmpty) {
        final duplicateIndex = messages.indexWhere((item) =>
            item.role == 'command' &&
            item.runId == event.runId &&
            debugSameCommandDisplay(item.body.trim(), command.trim()));
        if (duplicateIndex >= 0) {
          final current = messages[duplicateIndex];
          messages[duplicateIndex] = current.copyWith(
              body: debugPreferDetailedCommand(
                  current.body.trim(), command.trim()));
        } else {
          messages.add(_WorkbenchMessage(
              'command', 'cwd resolved · permissions checked', command.trim(),
              event: event, runId: event.runId));
        }
      }
      continue;
    }
    final message = _WorkbenchMessage.fromEvent(event, false);
    if (message == null) continue;
    if (message.role == 'approval') {
      final approvalId = message.event?.approvalId;
      if (approvalId != null && resolvedApprovalIds.contains(approvalId)) {
        continue;
      }
      final key = approvalId ?? message.body.trim();
      final existingIndex = messages.indexWhere((item) {
        if (item.role != 'approval') return false;
        return (item.event?.approvalId ?? item.body.trim()) == key;
      });
      if (existingIndex >= 0) {
        messages[existingIndex] = message;
      } else {
        messages.add(message);
      }
      continue;
    }
    if (message.role == 'command') {
      final duplicateIndex = messages.indexWhere((item) =>
          item.role == 'command' &&
          item.runId == message.runId &&
          debugSameCommandDisplay(item.body.trim(), message.body.trim()));
      if (duplicateIndex >= 0) {
        final current = messages[duplicateIndex];
        messages[duplicateIndex] = current.copyWith(
            body: debugPreferDetailedCommand(
                current.body.trim(), message.body.trim()));
      } else {
        messages.add(message);
      }
      continue;
    }
    if (message.role == 'question') {
      messages.removeWhere((item) =>
          item.role == 'assistant_stream' && item.runId == event.runId);
      if (messages.any(
          (item) => item.role == 'assistant' && item.runId == event.runId)) {
        continue;
      }
      messages.removeWhere(
          (item) => item.role == 'question' && item.runId == event.runId);
      messages.add(message);
      continue;
    }
    if (message.role == 'assistant') {
      messages.removeWhere((item) =>
          item.role == 'assistant_stream' && item.runId == event.runId);
      messages.removeWhere(
          (item) => item.role == 'question' && item.runId == event.runId);
      final sameRunIndex = messages.lastIndexWhere(
          (item) => item.role == 'assistant' && item.runId == event.runId);
      if (sameRunIndex >= 0) {
        messages[sameRunIndex] = message;
      } else {
        messages.add(message);
      }
      continue;
    }
    messages.add(message);
  }
  return messages.map((message) => '${message.role}:${message.body}').toList();
}

@visibleForTesting
bool debugSameCommandDisplay(String current, String incoming) {
  if (current == incoming) return true;
  if (current.isEmpty || incoming.isEmpty) return false;
  final currentHead = current.split(RegExp(r'\s+')).first;
  final incomingHead = incoming.split(RegExp(r'\s+')).first;
  return currentHead == incomingHead &&
      (incoming.startsWith('$current ') || current.startsWith('$incoming '));
}

@visibleForTesting
String debugPreferDetailedCommand(String current, String incoming) =>
    incoming.length > current.length ? incoming : current;

String _conversationPendingStatusText(
    String status, Iterable<ConversationEvent> events) {
  if (status == 'interrupted') return '会话已中断，可继续发送新消息恢复上下文';
  if (status == 'waiting_input') return '等待你回复问题…';
  if (status == 'waiting_approval') return '等待你确认权限请求…';
  final list = events.toList(growable: false);
  if (list.isEmpty) return '正在启动 CLI 会话…';
  for (final event in list.reversed) {
    if (event.type == 'assistant.partial') return '正在生成回复…';
    if (event.type == 'tool.started') {
      return '正在执行 ${event.toolName ?? '工具调用'}…';
    }
    if (event.type == 'tool.output') return '正在接收工具输出…';
    if (event.type == 'diff.summary') return '正在汇总文件变更…';
    if (event.type == 'conversation.started') {
      return 'CLI 会话已启动，正在读取上下文…';
    }
  }
  return '等待下一条事件…';
}

@visibleForTesting
Widget buildCodingSessionListPreview() {
  const current = WorkspaceSummary(
      id: 'workspace_1',
      name: 'vibe-coding',
      path: r'D:\AiProject\vibe-coding');
  const other = WorkspaceSummary(
      id: 'workspace_2',
      name: 'ts-learning',
      path: r'D:\AiProject\ts-learning');
  final data = _AppSnapshot(
      health: DaemonHealth.fromJson(const <String, Object?>{
        'status': 'ok',
        'daemonVersion': 'test',
        'mode': 'test',
        'lanMode': false,
        'bindAddress': '127.0.0.1',
        'port': 4317,
        'security': {'tokenRequired': false}
      }),
      workspaces: const <WorkspaceSummary>[current, other],
      workspace: current,
      overview: const ProjectOverview(
          workspaceId: 'workspace_1',
          name: 'vibe-coding',
          path: r'D:\AiProject\vibe-coding',
          fileCount: 0,
          codeLineCount: 0,
          symbolCount: 0,
          analysisScore: 0,
          recentFiles: <RecentFileSummary>[]),
      adapters: const <AdapterStatus>[],
      runs: const <RunSummary>[
        RunSummary(
            id: 'run_approval',
            tool: 'claude',
            workspaceId: 'workspace_1',
            status: 'pending',
            cliSessionId: 'session-approval'),
        RunSummary(
            id: 'run_live',
            tool: 'codex',
            workspaceId: 'workspace_1',
            status: 'running'),
        RunSummary(
            id: 'run_done',
            tool: 'claude',
            workspaceId: 'workspace_2',
            status: 'completed'),
      ],
      conversations: const <ConversationSummary>[],
      queue: const <QueueItem>[],
      templates: const <CommandTemplate>[],
      gitStatus: const GitStatusSummary(
          workspaceId: 'workspace_1', clean: true, files: <GitStatusFile>[]),
      diffs: const <DiffSummary>[],
      commits: const <GitCommitSummary>[],
      fileTree: const FileTreeResponse(
          workspaceId: 'workspace_1', root: '', entries: <FileTreeEntry>[]),
      diagnostics: const CodeDiagnosticsSummary(
          workspaceId: 'workspace_1',
          available: true,
          diagnostics: <CodeDiagnostic>[]),
      extensions: const <ExtensionSummary>[]);
  return MaterialApp(
      locale: _zhHansCnLocale,
      supportedLocales: const [_zhHansCnLocale, Locale('en', 'US')],
      localizationsDelegates: _appLocalizationsDelegates,
      theme: ThemeData(
          brightness: Brightness.dark,
          fontFamily: 'Segoe UI',
          fontFamilyFallback: _appFontFallback,
          useMaterial3: true),
      home: Scaffold(
          backgroundColor: _bg,
          body: _CodingSessionListPage(
              data: data,
              items: _mergeSessionItems(const <_SessionItem>[],
                  data.conversations, data.runs),
              currentWorkspace: current,
              onNewSession: () {},
              onSelectItem: (_) {})));
}

@visibleForTesting
Widget buildCodingWorkbenchEntryPreview() {
  const current = WorkspaceSummary(
      id: 'workspace_1',
      name: 'vibe-coding',
      path: r'D:\AiProject\vibe-coding');
  final data = _AppSnapshot(
      health: DaemonHealth.fromJson(const <String, Object?>{
        'status': 'ok',
        'daemonVersion': 'test',
        'mode': 'test',
        'lanMode': false,
        'bindAddress': '127.0.0.1',
        'port': 4317,
        'security': {'tokenRequired': false}
      }),
      workspaces: const <WorkspaceSummary>[current],
      workspace: current,
      overview: const ProjectOverview(
          workspaceId: 'workspace_1',
          name: 'vibe-coding',
          path: r'D:\AiProject\vibe-coding',
          fileCount: 0,
          codeLineCount: 0,
          symbolCount: 0,
          analysisScore: 0,
          recentFiles: <RecentFileSummary>[]),
      adapters: const <AdapterStatus>[],
      runs: const <RunSummary>[],
      conversations: const <ConversationSummary>[],
      queue: const <QueueItem>[],
      templates: const <CommandTemplate>[],
      gitStatus: const GitStatusSummary(
          workspaceId: 'workspace_1', clean: true, files: <GitStatusFile>[]),
      diffs: const <DiffSummary>[],
      commits: const <GitCommitSummary>[],
      fileTree: const FileTreeResponse(
          workspaceId: 'workspace_1', root: '', entries: <FileTreeEntry>[]),
      diagnostics: const CodeDiagnosticsSummary(
          workspaceId: 'workspace_1',
          available: true,
          diagnostics: <CodeDiagnostic>[]),
      extensions: const <ExtensionSummary>[]);
  return MaterialApp(
      locale: _zhHansCnLocale,
      supportedLocales: const [_zhHansCnLocale, Locale('en', 'US')],
      localizationsDelegates: _appLocalizationsDelegates,
      theme: ThemeData(
          brightness: Brightness.dark,
          fontFamily: 'Segoe UI',
          fontFamilyFallback: _appFontFallback,
          useMaterial3: true),
      home: Scaffold(
          backgroundColor: _bg,
          body: _CodingWorkbenchPage(
              data: data,
              client: DaemonClient(
                  baseUri: Uri.parse('http://127.0.0.1:4317'),
                  tokenStore: MemoryTokenStore()),
              onBack: () {},
              onSessionListChanged: (_) {},
              openSessionListRequest: 0,
              streamOutput: false,
              expandThinking: false,
              permissionMode: 'default')));
}

class MobileShell extends StatefulWidget {
  const MobileShell({super.key});

  @override
  State<MobileShell> createState() => _MobileShellState();
}

enum _RoutePage { tabs, detail, approval, adapters, notifications, diagnostics }

class _MobileShellState extends State<MobileShell> {
  int _tab = 0;
  bool _streamOutput = false;
  bool _expandThinking = false;
  String _permissionMode = 'default';
  bool _codingSessionListOpen = true;
  int _codingSessionListOpenRequest = 0;
  _RoutePage _route = _RoutePage.tabs;
  late final DaemonClient _client;
  late Future<_AppSnapshot> _snapshot;

  @override
  void initState() {
    super.initState();
    _client = DaemonClient(
        baseUri: Uri.parse('http://127.0.0.1:4317'),
        tokenStore: MemoryTokenStore());
    _snapshot = _AppSnapshot.load(_client);
  }

  void _refresh() => setState(() => _snapshot = _AppSnapshot.load(_client));

  void _open(_RoutePage route) => setState(() => _route = route);
  void _back() => setState(() => _route = _RoutePage.tabs);
  void _selectTab(int index) => setState(() {
        _tab = index;
        _route = _RoutePage.tabs;
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
    return FutureBuilder<_AppSnapshot>(
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
          _RoutePage.detail =>
            _RunDetailPage(onBack: _back, data: data, client: _client),
          _RoutePage.approval => _ApprovalPage(onBack: _back),
          _RoutePage.adapters => _AdaptersPage(onBack: _back, data: data),
          _RoutePage.notifications => _NotificationsPage(onBack: _back),
          _RoutePage.diagnostics =>
            _DiagnosticsPage(onBack: _back, data: data, client: _client),
          _RoutePage.tabs => null,
        };
        return Scaffold(
          body: _PhoneFrame(
            child: overlay ?? IndexedStack(index: _tab, children: pages),
          ),
          bottomNavigationBar:
              _route == _RoutePage.tabs && (_tab != 2 || _codingSessionListOpen)
                  ? _BottomNav(selected: _tab, items: _items, onTap: _selectTab)
                  : null,
          extendBody: true,
        );
      },
    );
  }
}

class _AppSnapshot {
  const _AppSnapshot(
      {required this.health,
      required this.workspaces,
      required this.workspace,
      required this.overview,
      required this.adapters,
      required this.runs,
      required this.conversations,
      required this.queue,
      required this.templates,
      required this.gitStatus,
      required this.diffs,
      required this.commits,
      required this.fileTree,
      required this.diagnostics,
      required this.extensions});

  final DaemonHealth health;
  final List<WorkspaceSummary> workspaces;
  final WorkspaceSummary workspace;
  final ProjectOverview overview;
  final List<AdapterStatus> adapters;
  final List<RunSummary> runs;
  final List<ConversationSummary> conversations;
  final List<QueueItem> queue;
  final List<CommandTemplate> templates;
  final GitStatusSummary? gitStatus;
  final List<DiffSummary> diffs;
  final List<GitCommitSummary> commits;
  final FileTreeResponse fileTree;
  final CodeDiagnosticsSummary diagnostics;
  final List<ExtensionSummary> extensions;

  List<RunSummary> get runningRuns => runs
      .where((run) => run.status == 'running' || run.status == 'starting')
      .toList();
  List<RunSummary> get completedRuns =>
      runs.where((run) => run.status == 'completed').toList();
  List<RunSummary> get failedRuns =>
      runs.where((run) => run.status == 'failed').toList();

  static Future<_AppSnapshot> load(DaemonClient client) async {
    final health = await client.health();
    final pairingCode = await client.createPairingCode();
    await client.pair(code: pairingCode, label: 'Windows preview');
    final workspaces = await client.listWorkspaces();
    final workspace = workspaces.first;
    final results = await Future.wait<Object?>([
      _loadStep('overview', () => client.projectOverview(workspace.id)),
      _loadStep('adapters', client.listAdapters),
      _loadStep('runs', () => client.listRuns(workspaceId: workspace.id)),
      _loadStep('conversations', client.listConversations),
      _loadStep('queue', client.listQueue),
      _loadStep('command templates', client.listCommandTemplates),
      _tryOrNull(() => client.gitStatus(workspace.id)),
      client.gitDiff(workspace.id).catchError((_) => <DiffSummary>[]),
      client.gitCommits(workspace.id).catchError((_) => <GitCommitSummary>[]),
      _loadStep('file tree', () => client.fileTree(workspace.id, maxDepth: 6)),
      _loadStep('code diagnostics', () => client.codeDiagnostics(workspace.id)),
      _loadStep('extensions', client.listExtensions),
    ]);
    return _AppSnapshot(
      health: health,
      workspaces: workspaces,
      workspace: workspace,
      overview: results[0] as ProjectOverview,
      adapters: results[1] as List<AdapterStatus>,
      runs: results[2] as List<RunSummary>,
      conversations: results[3] as List<ConversationSummary>,
      queue: results[4] as List<QueueItem>,
      templates: results[5] as List<CommandTemplate>,
      gitStatus: results[6] as GitStatusSummary?,
      diffs: results[7] as List<DiffSummary>,
      commits: results[8] as List<GitCommitSummary>,
      fileTree: results[9] as FileTreeResponse,
      diagnostics: results[10] as CodeDiagnosticsSummary,
      extensions: results[11] as List<ExtensionSummary>,
    );
  }
}

Future<T> _loadStep<T>(String label, Future<T> Function() load) async {
  try {
    return await load();
  } catch (error) {
    throw StateError('$label: $error');
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

Future<T?> _tryOrNull<T>(Future<T> Function() load) async {
  try {
    return await load();
  } catch (_) {
    return null;
  }
}

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
  final ValueChanged<_RoutePage> open;
  final ValueChanged<int> selectTab;
  final _AppSnapshot data;

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
                      onTap: () => open(_RoutePage.detail)),
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
        _ApprovalPreview(onTap: () => open(_RoutePage.approval)),
      ],
    );
  }
}

class _RunsPage extends StatelessWidget {
  const _RunsPage({required this.open, required this.data});
  final ValueChanged<_RoutePage> open;
  final _AppSnapshot data;

  @override
  Widget build(BuildContext context) {
    return _PageScroll(
      floating: _FloatingPlus(onTap: () => open(_RoutePage.detail)),
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
                onTap: () => open(_RoutePage.detail)),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _CodingWorkbenchPage extends StatefulWidget {
  const _CodingWorkbenchPage(
      {required this.data,
      required this.client,
      required this.onBack,
      required this.onSessionListChanged,
      required this.openSessionListRequest,
      required this.streamOutput,
      required this.expandThinking,
      required this.permissionMode});
  final _AppSnapshot data;
  final DaemonClient client;
  final VoidCallback onBack;
  final ValueChanged<bool> onSessionListChanged;
  final int openSessionListRequest;
  final bool streamOutput;
  final bool expandThinking;
  final String permissionMode;

  @override
  State<_CodingWorkbenchPage> createState() => _CodingWorkbenchPageState();
}

class _CodingWorkbenchPageState extends State<_CodingWorkbenchPage> {
  final _prompt = TextEditingController();
  final _scrollController = ScrollController();
  final List<_WorkbenchMessage> _messages = <_WorkbenchMessage>[];
  final List<AgentEvent> _events = <AgentEvent>[];
  final List<ConversationEvent> _conversationEvents = <ConversationEvent>[];
  final List<_SessionItem> _localSessions = <_SessionItem>[];
  late List<WorkspaceSummary> _workspaces;
  Timer? _poller;
  String? _activeRunId;
  String? _activeConversationId;
  ConversationSummary? _activeConversation;
  ConversationViewState _conversationState = const ConversationViewState();
  String? _selectedAdapter;
  late WorkspaceSummary _selectedWorkspace;
  int _lastSeq = 0;
  bool _sending = false;
  String? _error;
  bool _workspaceConfirmedForSession = false;
  final Set<String> _resolvedApprovalIds = <String>{};
  bool _showSessionList = true;
  late int _handledOpenSessionListRequest;

  List<_SessionItem> get _sessionItems => _mergeSessionItems(
      _localSessions, widget.data.conversations, widget.data.runs);

  void _setSessionListOpen(bool open) {
    if (_showSessionList == open) return;
    setState(() => _showSessionList = open);
    widget.onSessionListChanged(open);
  }

  void _rememberRun(RunSummary run) {
    _localSessions.removeWhere((item) => item.id == run.id);
    _localSessions.insert(0, _SessionItem(run: run));
  }

  void _rememberConversation(ConversationSummary conversation) {
    _localSessions.removeWhere((item) => item.id == conversation.id);
    _localSessions.insert(0, _SessionItem(
        run: _runSummaryFromConversation(conversation), conversation: conversation));
  }

  void _resetConversationState() {
    _messages.clear();
    _events.clear();
    _conversationEvents.clear();
    _conversationState = const ConversationViewState();
    _resolvedApprovalIds.clear();
    _activeRunId = null;
    _activeConversationId = null;
    _activeConversation = null;
    _lastSeq = 0;
  }

  Future<void> _openSession(_SessionItem item) async {
    _poller?.cancel();
    setState(() {
      _resetConversationState();
      _activeRunId = item.run.id;
      _activeConversationId = item.conversation?.id;
      _activeConversation = item.conversation;
      _selectedWorkspace = _workspaceForId(item.run.workspaceId);
      _workspaceConfirmedForSession = true;
      _error = null;
      _showSessionList = false;
    });
    widget.onSessionListChanged(false);
    if (item.conversation == null) return;
    await _pollEvents();
  }

  WorkspaceSummary _workspaceForId(String workspaceId) {
    for (final workspace in _workspaces) {
      if (workspace.id == workspaceId) return workspace;
    }
    return _selectedWorkspace;
  }

  Future<void> _cancelActiveRun() async {
    final runId = _activeRunId;
    final conversationId = _activeConversationId;
    if ((runId == null && conversationId == null) || _sending) return;
    setState(() => _sending = true);
    try {
      RunSummary? run;
      if (conversationId != null) {
        final conversation =
            await widget.client.cancelConversation(conversationId);
        run = _runSummaryFromConversation(conversation);
      } else if (runId != null) {
        run = await widget.client.cancelRun(runId);
      }
      if (!mounted) return;
      setState(() {
        if (run != null) _rememberRun(run);
        _conversationState = const ConversationViewState(status: 'cancelled');
        _activeRunId = null;
        _activeConversationId = null;
        _activeConversation = null;
        _lastSeq = 0;
      });
      _poller?.cancel();
    } catch (err) {
      if (mounted) setState(() => _error = err.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _handledOpenSessionListRequest = widget.openSessionListRequest;
    _selectedAdapter = _preferredAdapter()?.adapter;
    _workspaces = List<WorkspaceSummary>.of(widget.data.workspaces);
    _selectedWorkspace = widget.data.workspace;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onSessionListChanged(_showSessionList);
    });
  }

  @override
  void didUpdateWidget(covariant _CodingWorkbenchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.openSessionListRequest == _handledOpenSessionListRequest) return;
    _handledOpenSessionListRequest = widget.openSessionListRequest;
    if (_showSessionList) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _setSessionListOpen(true);
    });
  }

  @override
  void dispose() {
    _poller?.cancel();
    _scrollController.dispose();
    _prompt.dispose();
    super.dispose();
  }

  AdapterStatus? _preferredAdapter() {
    for (final name in const ['claude', 'codex', 'opencode']) {
      final found =
          widget.data.adapters.where((a) => a.adapter == name && a.available);
      if (found.isNotEmpty) return found.first;
    }
    final available = widget.data.adapters.where((a) => a.available);
    return available.isEmpty ? null : available.first;
  }

  bool get _isTerminal {
    final status = _activeConversation?.status ?? _conversationState.status;
    return status == 'idle' ||
        status == 'failed' ||
        status == 'cancelled' ||
        status == 'interrupted' ||
        status == 'expired';
  }

  bool get _isRunningCli =>
      _activeConversationId != null &&
      (_activeConversation?.status ?? _conversationState.status) == 'running';

  bool get _isBusyCli =>
      _activeConversationId != null &&
      !_isTerminal &&
      (_activeConversation?.status ?? _conversationState.status) !=
          'waiting_input' &&
      (_activeConversation?.status ?? _conversationState.status) !=
          'waiting_approval';

  List<AdapterStatus> get _availableAdapters =>
      widget.data.adapters.where((adapter) => adapter.available).toList();

  void _showAdapterPicker() {
    final adapters = _availableAdapters;
    if (adapters.isEmpty || _isRunningCli) return;
    showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (context) => _AdapterPickerSheet(
            adapters: adapters,
            selected: _selectedAdapter,
            onSelected: (adapter) {
              setState(() => _selectedAdapter = adapter);
              Navigator.of(context).pop();
            }));
  }

  void _showWorkspacePicker() {
    if (_isRunningCli) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('CLI 运行中，当前工作区暂不可切换'), duration: Duration(seconds: 2)));
      return;
    }
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => _WorkspacePickerSheet(
            workspaces: _workspaces,
            selected: _selectedWorkspace,
            client: widget.client,
            onSelected: (workspace) {
              setState(() {
                _selectedWorkspace = workspace;
                _resetConversationState();
                _error = null;
                _workspaceConfirmedForSession = true;
              });
              Navigator.of(context).pop();
            },
            onCreated: (workspace) {
              setState(() {
                if (!_workspaces.any((item) => item.id == workspace.id)) {
                  _workspaces.add(workspace);
                }
                _selectedWorkspace = workspace;
                _resetConversationState();
                _error = null;
                _workspaceConfirmedForSession = true;
              });
            }));
  }

  String get _pendingStatusText => _conversationPendingStatusText(
      _activeConversation?.status ?? _conversationState.status,
      _conversationEvents);

  List<String> get _recentActionSummaries {
    return const <String>[];
  }

  // ignore: unused_element
  String? _eventActionSummary(AgentEvent event) {
    if (event.type == 'run.started') {
      return '已启动 ${event.raw['tool'] ?? _selectedAdapter ?? 'CLI'} 会话';
    }
    if (event.type == 'approval.required') return '等待权限确认';
    if (event.type == 'tool.started') {
      final name = event.name ?? _toolNameFromRaw(event) ?? '工具';
      final target = _toolTargetFromRaw(event);
      return target == null ? '调用 $name' : '调用 $name：$target';
    }
    if (event.type == 'tool.output') {
      final target = _toolTargetFromRaw(event);
      return target == null ? '工具返回结果' : '处理完成：$target';
    }
    if (event.type == 'diff.summary' && event.diff != null) {
      return '修改 ${event.diff!.filePath}  +${event.diff!.additions} -${event.diff!.deletions}';
    }
    if (event.type == 'raw.output') {
      final text = event.text?.trim();
      if (text == null || text.isEmpty || text.startsWith('{')) return null;
      return text.length > 64 ? '${text.substring(0, 64)}…' : text;
    }
    if (event.type == 'run.completed') return '本轮运行完成';
    if (event.type == 'run.failed') return '运行失败';
    return null;
  }

  String? _toolNameFromRaw(AgentEvent event) {
    final raw = event.raw['raw'];
    if (raw is Map<String, Object?>) {
      final name = raw['name'] ?? raw['tool'] ?? raw['command'];
      if (name is String && name.trim().isNotEmpty) return name;
    }
    return null;
  }

  String? _toolTargetFromRaw(AgentEvent event) {
    final raw = event.raw['raw'];
    if (raw is Map<String, Object?>) {
      final input = raw['input'];
      if (input is Map<String, Object?>) {
        final file = input['file_path'] ?? input['path'] ?? input['filename'];
        if (file is String && file.trim().isNotEmpty) {
          return file.split('\\').last;
        }
      }
    }
    return null;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _sendPrompt() async {
    final prompt = _prompt.text.trim();
    final adapter = _selectedAdapter;
    if (prompt.isEmpty || adapter == null || _sending) return;
    final pendingQuestion = _conversationState.messages
        .cast<ConversationMessage?>()
        .lastWhere(
            (message) =>
                message?.role == 'question' ||
                message?.role == 'question_hidden',
            orElse: () => null);
    final pendingQuestionId = pendingQuestion?.questionId;
    if (_activeRunId == null && !_hasExplicitWorkspaceSelection) {
      await _confirmWorkspaceBeforeFirstRun();
      if (!_hasExplicitWorkspaceSelection || !mounted) return;
    }
    setState(() {
      _sending = true;
      _error = null;
      _messages.add(_WorkbenchMessage.user(prompt));
      _prompt.clear();
    });
    _scrollToBottom();
    try {
      final existingConversationId = _activeConversationId;
      if (existingConversationId == null) {
        final conversation = await widget.client.createConversation(
            workspaceId: _selectedWorkspace.id,
            adapter: adapter,
            permissionMode: widget.permissionMode);
        final run = _runSummaryFromConversation(conversation);
        setState(() {
          _activeConversation = conversation;
          _rememberConversation(conversation);
          _activeRunId = run.id;
          _activeConversationId = conversation.id;
          _lastSeq = 0;
          _events.clear();
          _resolvedApprovalIds.clear();
        });
        final updated = await widget.client
            .sendConversationMessage(conversation.id, prompt);
        if (mounted) setState(() => _activeConversation = updated);
      } else if (pendingQuestionId != null && pendingQuestionId.isNotEmpty) {
        final conversation = await widget.client.answerConversationQuestion(
            existingConversationId, pendingQuestionId, prompt);
        setState(() {
          _activeConversation = conversation;
          _rememberConversation(conversation);
          _messages.removeWhere((message) => message.role == 'question');
        });
      } else {
        if (_isRunningCli) return;
        final conversation = await widget.client
            .sendConversationMessage(existingConversationId, prompt);
        setState(() {
          _activeConversation = conversation;
          _rememberConversation(conversation);
          _events.removeWhere((event) => event.type == 'run.completed');
        });
      }
      _scrollToBottom();
      await _restartConversationPolling();
    } catch (err) {
      setState(() => _error = err.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pollEvents() async {
    final runId = _activeRunId;
    final conversationId = _activeConversationId;
    if (runId == null || conversationId == null) {
      _poller?.cancel();
      return;
    }
    try {
      final conversationEvents = await widget.client
          .fetchConversationEvents(conversationId, afterSeq: _lastSeq);
      if (conversationEvents.isEmpty || !mounted) return;
      setState(() {
        for (final event in conversationEvents) {
          _conversationEvents.add(event);
          if (event.seq > _lastSeq) _lastSeq = event.seq;
          _applyConversationStatusEvent(event);
        }
        _conversationState = _conversationState.apply(conversationEvents,
            streamOutput: widget.streamOutput);
        _messages
          ..clear()
          ..addAll(_messagesForConversationSnapshot(
                  _conversationState.messages, _activeConversation)
              .where((message) => message.role != 'question_hidden')
              .map(_workbenchMessageFromConversation));
      });
      _scrollToBottom();
      if (!_isRunningCli) _poller?.cancel();
    } catch (err) {
      if (mounted) setState(() => _error = err.toString());
    }
  }

  Future<void> _restartConversationPolling() async {
    _poller?.cancel();
    await _pollEvents();
    if (!mounted || _activeConversationId == null || _isTerminal) return;
    _poller = Timer.periodic(
        const Duration(milliseconds: 900), (_) => _pollEvents());
  }

  void _applyConversationStatusEvent(ConversationEvent event) {
    final current = _activeConversation;
    if (current == null) return;
    var status = current.status;
    ConversationBlockingItem? blockingItem = current.blockingItem;
    if (event.type == 'conversation.status_changed') {
      status = event.raw['status'] as String? ?? status;
    } else if (event.type == 'assistant.message') {
      status = 'idle';
      blockingItem = null;
    } else if (event.type == 'assistant.question') {
      status = 'waiting_input';
      blockingItem = ConversationBlockingItem(
          type: 'input_request',
          questionId: event.questionId,
          text: event.text,
          suggestions: event.suggestions);
    } else if (event.type == 'approval.requested') {
      status = 'waiting_approval';
      blockingItem = ConversationBlockingItem(
          type: 'approval_request',
          approvalId: event.approvalId,
          toolName: event.toolName,
          summary: event.summary,
          input: event.input);
    } else if (event.type == 'approval.resolved') {
      status = 'running';
      blockingItem = null;
    } else if (event.type == 'conversation.cancelled') {
      status = 'cancelled';
      blockingItem = null;
    } else if (event.type == 'run.error') {
      status = 'failed';
      blockingItem = null;
    }
    _activeConversation =
        _copyConversationStatus(current, status, blockingItem: blockingItem);
  }

  // ignore: unused_element
  void _mergeEventMessage(AgentEvent event) {
    if (event.type == 'approval.responded') {
      final approvalId = event.approvalId ?? event.raw['approvalId'] as String?;
      if (approvalId != null && approvalId.isNotEmpty) {
        _resolvedApprovalIds.add(approvalId);
        _messages.removeWhere((item) =>
            item.role == 'approval' && item.event?.approvalId == approvalId);
      }
      final command = _approvalResolvedCommand(event);
      if (command != null) {
        final exists = _messages.any((item) =>
            item.role == 'command' &&
            item.runId == event.runId &&
            item.body.trim() == command.trim());
        if (!exists) {
          _upsertCommandMessage(_WorkbenchMessage(
              'command', 'cwd resolved · permissions checked', command,
              event: event, runId: event.runId));
        }
      }
      return;
    }
    if (isTerminalAgentEventType(event.type)) {
      _markCommandMessagesCompleted(event);
    }
    final message = _WorkbenchMessage.fromEvent(event, widget.streamOutput);
    if (message == null) return;
    if (message.role == 'approval' &&
        message.event?.approvalId != null &&
        _resolvedApprovalIds.contains(message.event!.approvalId)) {
      return;
    }
    if (message.role == 'approval') {
      final approvalId = message.event?.approvalId;
      final messageKey = approvalId ?? message.body.trim();
      final existingIndex = _messages.indexWhere((item) {
        if (item.role != 'approval') return false;
        final itemKey = item.event?.approvalId ?? item.body.trim();
        return itemKey == messageKey;
      });
      if (existingIndex >= 0) {
        _messages[existingIndex] = message;
      } else {
        _messages.add(message);
      }
      return;
    }
    if (message.role == 'assistant_stream') {
      final lastIndex = _messages.lastIndexWhere((item) =>
          item.role == 'assistant_stream' && item.runId == event.runId);
      if (lastIndex >= 0) {
        final current = _messages[lastIndex];
        _messages[lastIndex] =
            current.copyWith(body: current.body + message.body);
      } else {
        _messages.add(message);
      }
      return;
    }
    if (message.role == 'assistant') {
      _messages.removeWhere((item) =>
          item.role == 'assistant_stream' && item.runId == event.runId);
      _messages.removeWhere(
          (item) => item.role == 'question' && item.runId == event.runId);
      final sameRunIndex = _messages.lastIndexWhere(
          (item) => item.role == 'assistant' && item.runId == event.runId);
      if (sameRunIndex >= 0) {
        _messages[sameRunIndex] = message;
      } else {
        final exists = _messages.any((item) =>
            item.role == 'assistant' &&
            item.body.trim() == message.body.trim());
        if (!exists) _messages.add(message);
      }
      return;
    }
    if (message.role == 'question') {
      final hasAssistantForRun = _messages
          .any((item) => item.role == 'assistant' && item.runId == event.runId);
      if (hasAssistantForRun) return;
      _messages.removeWhere((item) =>
          item.role == 'assistant_stream' && item.runId == event.runId);
      _messages.removeWhere(
          (item) => item.role == 'question' && item.runId == event.runId);
      _messages.add(message);
      return;
    }
    if (message.role == 'command') {
      _upsertCommandMessage(message.copyWith(
          completed: _isTerminal,
          duration: _commandDurationFor(
              message.runId ?? event.runId, event.createdAt)));
      return;
    }
    _messages.add(message);
  }

  void _upsertCommandMessage(_WorkbenchMessage message) {
    final command = message.body.trim();
    final existingIndex = _messages.indexWhere((item) =>
        item.role == 'command' &&
        item.runId == message.runId &&
        _sameCommandDisplay(item.body.trim(), command));
    if (existingIndex >= 0) {
      final current = _messages[existingIndex];
      final body = _preferDetailedCommand(current.body.trim(), command);
      _messages[existingIndex] = current.copyWith(
          body: body,
          completed: current.completed || message.completed,
          duration: message.duration ?? current.duration);
    } else {
      _messages.add(message);
    }
  }

  bool _sameCommandDisplay(String current, String incoming) {
    return debugSameCommandDisplay(current, incoming);
  }

  String _preferDetailedCommand(String current, String incoming) {
    return debugPreferDetailedCommand(current, incoming);
  }

  void _markCommandMessagesCompleted(AgentEvent terminalEvent) {
    for (var index = 0; index < _messages.length; index += 1) {
      final message = _messages[index];
      if (message.role != 'command' || message.runId != terminalEvent.runId) {
        continue;
      }
      _messages[index] = message.copyWith(
          completed: true,
          duration:
              _commandDurationFor(message.runId, terminalEvent.createdAt));
    }
  }

  Duration? _commandDurationFor(String? runId, DateTime completedAt) {
    if (runId == null) return null;
    AgentEvent? started;
    for (final event in _events) {
      if (event.runId == runId && event.type == 'run.started') {
        started = event;
        break;
      }
    }
    started ??= _events
        .cast<AgentEvent?>()
        .firstWhere((event) => event?.runId == runId, orElse: () => null);
    if (started == null || completedAt.isBefore(started.createdAt)) return null;
    return completedAt.difference(started.createdAt);
  }

  bool get _hasExplicitWorkspaceSelection {
    return _hasExplicitWorkspaceSelectionState(
      workspaceConfirmedForSession: _workspaceConfirmedForSession,
      activeRunId: _activeRunId,
      hasLocalSessions: _localSessions.isNotEmpty,
    );
  }

  Future<void> _confirmWorkspaceBeforeFirstRun() async {
    final selected = await _pickFirstRunWorkspace();
    if (selected == null || !mounted) return;
    setState(() {
      if (!_workspaces.any((item) => item.id == selected.id)) {
        _workspaces.add(selected);
      }
      _selectedWorkspace = selected;
      _workspaceConfirmedForSession = true;
    });
  }

  Future<WorkspaceSummary?> _pickFirstRunWorkspace() =>
      showModalBottomSheet<WorkspaceSummary>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => _FirstRunWorkspaceSheet(
              workspaces: _workspaces,
              selected: _selectedWorkspace,
              client: widget.client));

  Future<void> _startNewSessionFromList() async {
    final selected = await _pickFirstRunWorkspace();
    if (selected == null || !mounted) return;
    setState(() {
      if (!_workspaces.any((item) => item.id == selected.id)) {
        _workspaces.add(selected);
      }
      _selectedWorkspace = selected;
      _showSessionList = false;
      _resetConversationState();
      _error = null;
      _workspaceConfirmedForSession = true;
      _prompt.clear();
    });
    widget.onSessionListChanged(false);
  }

  String? _approvalResolvedCommand(AgentEvent event) {
    final decision = event.raw['decision'];
    if (decision != 'allow') return null;
    final input = event.raw['input'];
    if (input is Map<String, Object?>) {
      final command = input['command'];
      if (command is String && command.trim().isNotEmpty) return command.trim();
      final target = input['file_path'] ?? input['path'] ?? input['filename'];
      if (target is String && target.trim().isNotEmpty) {
        return '${event.name ?? 'Tool'} ${target.trim()}';
      }
    }
    final text = event.text;
    return text == null || text.trim().isEmpty ? null : text.trim();
  }

  Future<void> _respondApproval(AgentEvent event, String decision) async {
    final approvalId = event.approvalId;
    if (approvalId == null || approvalId.isEmpty) return;
    try {
      final conversationId = _activeConversationId;
      if (conversationId != null) {
        final conversation = await widget.client
            .respondConversationApproval(conversationId, approvalId, decision);
        _activeConversation = conversation;
        _rememberConversation(conversation);
      } else {
        await widget.client.respondApproval(approvalId, decision);
      }
      setState(() {
        _resolvedApprovalIds.add(approvalId);
        _messages.removeWhere((item) =>
            item.role == 'approval' && item.event?.approvalId == approvalId);
        if (decision == 'allow') {
          _upsertCommandMessage(_WorkbenchMessage(
              'command',
              'cwd resolved · permissions checked',
              _WorkbenchMessage._toolEventBody(event),
              event: event,
              runId: event.runId));
        } else {
          _messages.add(_WorkbenchMessage.status('已拒绝权限请求'));
        }
      });
      final conversation = _activeConversation;
      if (conversation != null && _shouldPollAfterApproval(conversation)) {
        await _restartConversationPolling();
      }
    } catch (err) {
      setState(() => _error = err.toString());
    }
  }

  void _useQuestionSuggestion(String text) {
    _prompt.text = text;
    _prompt.selection = TextSelection.collapsed(offset: text.length);
  }

  @override
  Widget build(BuildContext context) {
    if (_showSessionList) {
      return _CodingSessionListPage(
          data: widget.data,
          items: _sessionItems,
          currentWorkspace: _selectedWorkspace,
          onNewSession: _startNewSessionFromList,
          onSelectItem: _openSession);
    }
    final adapter = _selectedAdapter;
    final canSend = adapter != null && !_sending;
    return Column(key: const ValueKey('coding-workbench-detail'), children: [
      Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 9),
          decoration: BoxDecoration(
              color: const Color(0xEE0A0B0D),
              border: Border(
                  bottom:
                      BorderSide(color: Colors.white.withValues(alpha: .075)))),
          child: _CodingHeader(
              title: _conversationTitle,
              workspace: _selectedWorkspace,
              adapter: adapter,
              running: _isRunningCli,
              onBack: () => _setSessionListOpen(true))),
      Expanded(
          child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(15, 16, 15, 16),
        children: [
          if (_activeRunId != null) ...[
            _WorkbenchInlineStatus(
                adapter: adapter,
                runId: _activeRunId,
                eventCount: _conversationEvents.length,
                terminal: _isTerminal),
            const SizedBox(height: 12),
          ],
          for (final message in _messages) ...[
            _WorkbenchMessageCard(
                message: message,
                expandThinking: widget.expandThinking,
                onSuggestion: (text) => _useQuestionSuggestion(text),
                onApproval: (decision) =>
                    _respondApproval(message.event!, decision)),
            const SizedBox(height: 10),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            _GlassCard(
                child: Text('运行错误：$_error',
                    style: const TextStyle(
                        color: _red, fontSize: 12, height: 1.45))),
          ],
          if (_isBusyCli) ...[
            const SizedBox(height: 10),
            _PendingSentinel(
                adapter: adapter ?? 'CLI',
                statusText: _pendingStatusText,
                actions: _recentActionSummaries),
          ],
        ],
      )),
      _CodingComposer(
          controller: _prompt,
          adapter: adapter,
          workspace: _selectedWorkspace,
          running: _isRunningCli,
          canSend: canSend,
          sending: _sending,
          onModelTap: _showAdapterPicker,
          onSend: _sendPrompt,
          onCancel: _cancelActiveRun),
      _ComposerWorkspaceCloud(
          workspace: _selectedWorkspace,
          running: _isRunningCli,
          onTap: _showWorkspacePicker),
    ]);
  }

  String get _conversationTitle {
    final userMessage = _messages.where((message) => message.role == 'user');
    if (userMessage.isEmpty) return '新的编码会话';
    final text = userMessage.last.body.trim();
    if (text.length <= 18) return text;
    return '${text.substring(0, 18)}…';
  }
}

class _CodingHeader extends StatelessWidget {
  const _CodingHeader(
      {required this.title,
      required this.workspace,
      required this.adapter,
      required this.running,
      required this.onBack});
  final String title;
  final WorkspaceSummary workspace;
  final String? adapter;
  final bool running;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Row(children: [
        InkWell(
            onTap: onBack,
            borderRadius: BorderRadius.circular(11),
            child: Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: const Color(0xFF141518),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: _stroke)),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: _muted, size: 16))),
        const SizedBox(width: 12),
        Expanded(
            child: Text(title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: _text,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.15))),
        const SizedBox(width: 46),
      ]);
}

class _CodingSessionListPage extends StatelessWidget {
  const _CodingSessionListPage(
      {required this.data,
      required this.items,
      required this.currentWorkspace,
      required this.onNewSession,
      required this.onSelectItem});
  final _AppSnapshot data;
  final List<_SessionItem> items;
  final WorkspaceSummary currentWorkspace;
  final VoidCallback onNewSession;
  final ValueChanged<_SessionItem> onSelectItem;

  @override
  Widget build(BuildContext context) {
    final currentItems = items
        .where((item) => item.run.workspaceId == currentWorkspace.id)
        .toList(growable: false);
    final otherWorkspaces = data.workspaces
        .where((workspace) => workspace.id != currentWorkspace.id)
        .toList(growable: false);
    return Column(key: const ValueKey('coding-session-list'), children: [
      Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
              color: const Color(0xEE0A0B0D),
              border: Border(
                  bottom:
                      BorderSide(color: Colors.white.withValues(alpha: .07)))),
          child: Row(children: [
            const SizedBox(width: 36),
            Expanded(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  const Text('会话列表',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: _text,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.15)),
                  const SizedBox(height: 3),
                  Text(
                      '${_workspaceDisplayName(currentWorkspace)} · ${_compactWorkspacePath(currentWorkspace.path)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: _faint,
                          fontSize: 10.5,
                          fontFamily: 'Consolas')),
                ])),
            _SessionNewButton(onTap: onNewSession),
          ])),
      Expanded(
          child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
              children: [
            const _SessionSearchBox(),
            const SizedBox(height: 14),
            _SessionGroupHeader(
                title: '当前项目', meta: _workspaceDisplayName(currentWorkspace)),
            const SizedBox(height: 6),
            if (currentItems.isEmpty)
              const _EmptySessionStack()
            else
              _SessionStack(
                  children: currentItems
                      .map((item) => _SessionRunRow(
                          run: item.run, onTap: () => onSelectItem(item)))
                      .toList(growable: false)),
            const SizedBox(height: 16),
            const _SessionGroupHeader(title: '其它项目', meta: '最近'),
            const SizedBox(height: 6),
            for (final workspace in otherWorkspaces) ...[
              _ProjectSessionCard(
                  workspace: workspace,
                  runCount: items
                      .where((item) => item.run.workspaceId == workspace.id)
                      .length),
              const SizedBox(height: 8),
            ],
            const Padding(
                padding: EdgeInsets.fromLTRB(4, 6, 4, 0),
                child: Text('会话列表只展示归属和状态；文件 diff、命令输出、审批详情进入具体会话后再展开。',
                    style: TextStyle(
                        color: Color(0xFF666D77),
                        fontSize: 11.5,
                        height: 1.5))),
          ])),
    ]);
  }
}

class _SessionNewButton extends StatelessWidget {
  const _SessionNewButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: const Color(0xFFF0F0F0),
              borderRadius: BorderRadius.circular(13)),
          child: const Icon(Icons.add_rounded,
              color: Color(0xFF08090B), size: 22)));
}

class _SessionSearchBox extends StatelessWidget {
  const _SessionSearchBox();

  @override
  Widget build(BuildContext context) => Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
          color: const Color(0xFF101113),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: .075))),
      child: const Text('搜索会话、命令、文件路径…',
          style: TextStyle(color: Color(0xFF737983), fontSize: 13)));
}

class _SessionGroupHeader extends StatelessWidget {
  const _SessionGroupHeader({required this.title, required this.meta});
  final String title;
  final String meta;

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(children: [
        Text(title,
            style: const TextStyle(
                color: Color(0xFFD8D8D8),
                fontSize: 12.5,
                fontWeight: FontWeight.w800)),
        const Spacer(),
        Text(meta,
            style: const TextStyle(
                color: Color(0xFF6F757E),
                fontSize: 10.5,
                fontFamily: 'Consolas')),
      ]));
}

class _SessionStack extends StatelessWidget {
  const _SessionStack({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
      decoration: BoxDecoration(
          color: const Color(0xFF101113),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: .075))),
      child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(children: children)));
}

class _EmptySessionStack extends StatelessWidget {
  const _EmptySessionStack();

  @override
  Widget build(BuildContext context) => _SessionStack(children: const [
        Padding(
            padding: EdgeInsets.all(14),
            child: Align(
                alignment: Alignment.centerLeft,
                child: Text('暂无会话。点击右上角 + 新建编码会话。',
                    style: TextStyle(color: _muted, fontSize: 12.5))))
      ]);
}

class _SessionRunRow extends StatelessWidget {
  const _SessionRunRow({required this.run, required this.onTap});
  final RunSummary run;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final state = _sessionRunState(run.status);
    return InkWell(
        onTap: onTap,
        child: Container(
            constraints: const BoxConstraints(minHeight: 66),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(
                        color: Colors.white.withValues(alpha: .045)))),
            child: Row(children: [
              Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: const Color(0xFF18191C),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(state.icon,
                      style: TextStyle(
                          color: state.color,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'Consolas'))),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    Text(_sessionRunTitle(run),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Color(0xFFE9E9E9),
                            fontSize: 12.7,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                        '${_toolDisplayName(run.tool)} · ${run.cliSessionId ?? run.id} · ${state.label}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Color(0xFF858A94),
                            fontSize: 10.5,
                            fontFamily: 'Consolas')),
                  ])),
              const SizedBox(width: 10),
              Text(state.badge,
                  style: TextStyle(
                      color: state.color,
                      fontSize: 10.5,
                      fontFamily: 'Consolas')),
            ])));
  }
}

class _ProjectSessionCard extends StatelessWidget {
  const _ProjectSessionCard({required this.workspace, required this.runCount});
  final WorkspaceSummary workspace;
  final int runCount;

  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
          color: const Color(0xFF101113),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: .075))),
      child: Row(children: [
        Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: const Color(0xFF18191C),
                borderRadius: BorderRadius.circular(9)),
            child: const Icon(Icons.keyboard_command_key_rounded,
                color: _muted, size: 14)),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_workspaceDisplayName(workspace),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: _text, fontSize: 12.8, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(_compactWorkspacePath(workspace.path),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Color(0xFF858A94),
                  fontSize: 10.5,
                  fontFamily: 'Consolas')),
        ])),
        Text('$runCount',
            style: const TextStyle(
                color: Color(0xFF6F757E),
                fontSize: 10.5,
                fontFamily: 'Consolas')),
      ]));
}

class _SessionRunVisualState {
  const _SessionRunVisualState(
      {required this.icon,
      required this.label,
      required this.badge,
      required this.color});
  final String icon;
  final String label;
  final String badge;
  final Color color;
}

_SessionRunVisualState _sessionRunState(String status) {
  final lower = status.toLowerCase();
  if (lower.contains('approval') || lower.contains('pending')) {
    return const _SessionRunVisualState(
        icon: '!', label: '等待审批', badge: '待处理', color: _amber);
  }
  if (lower.contains('running') || lower.contains('start')) {
    return const _SessionRunVisualState(
        icon: '●', label: '运行中', badge: 'live', color: _green);
  }
  if (lower.contains('fail') || lower.contains('error')) {
    return const _SessionRunVisualState(
        icon: '×', label: '失败', badge: '失败', color: _red);
  }
  return const _SessionRunVisualState(
      icon: '✓', label: '完成', badge: '完成', color: Color(0xFFA0A0A0));
}

String _sessionRunTitle(RunSummary run) {
  if (run.cliSessionId != null && run.cliSessionId!.isNotEmpty) {
    return '${_toolDisplayName(run.tool)} 会话 ${run.cliSessionId!.split('-').first}';
  }
  return '${_toolDisplayName(run.tool)} 任务 ${run.id.split('_').last}';
}

String _toolDisplayName(String tool) {
  if (tool.isEmpty) return 'CLI';
  return tool[0].toUpperCase() + tool.substring(1);
}

class _AdapterPickerSheet extends StatelessWidget {
  const _AdapterPickerSheet(
      {required this.adapters,
      required this.selected,
      required this.onSelected});
  final List<AdapterStatus> adapters;
  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => SafeArea(
      top: false,
      child: Container(
          margin: const EdgeInsets.all(12),
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * .68),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
              color: const Color(0xFF0D131D),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: Colors.white.withValues(alpha: .08)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: .45),
                    blurRadius: 28,
                    offset: const Offset(0, 18))
              ]),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('选择模型 / CLI',
                    style: TextStyle(
                        color: _text,
                        fontSize: 16,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                const Text('会用于下一次真实 daemon run，运行中不可切换。',
                    style: TextStyle(color: _muted, fontSize: 12)),
                const SizedBox(height: 12),
                for (final adapter in adapters)
                  _AdapterChoiceRow(
                      adapter: adapter,
                      selected: adapter.adapter == selected,
                      onTap: () => onSelected(adapter.adapter)),
              ])));
}

class _AdapterChoiceRow extends StatelessWidget {
  const _AdapterChoiceRow(
      {required this.adapter, required this.selected, required this.onTap});
  final AdapterStatus adapter;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: selected
                  ? _purple.withValues(alpha: .16)
                  : Colors.white.withValues(alpha: .035),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: selected ? _purple.withValues(alpha: .45) : _stroke)),
          child: Row(children: [
            _AgentIcon(color: _toolColor(adapter.adapter)),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(adapter.adapter,
                      style: const TextStyle(
                          color: _text, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 3),
                  Text(_displayVersion(adapter.version),
                      style: const TextStyle(color: _muted, fontSize: 12))
                ])),
            if (selected)
              const Icon(Icons.check_circle_rounded, color: _purple, size: 19)
          ])));
}

class _WorkspacePickerSheet extends StatefulWidget {
  const _WorkspacePickerSheet(
      {required this.workspaces,
      required this.selected,
      required this.client,
      required this.onSelected,
      required this.onCreated});
  final List<WorkspaceSummary> workspaces;
  final WorkspaceSummary selected;
  final DaemonClient client;
  final ValueChanged<WorkspaceSummary> onSelected;
  final ValueChanged<WorkspaceSummary> onCreated;

  @override
  State<_WorkspacePickerSheet> createState() => _WorkspacePickerSheetState();
}

class _WorkspacePickerSheetState extends State<_WorkspacePickerSheet> {
  final _path = TextEditingController();
  final _name = TextEditingController();
  bool _creating = false;
  String? _error;

  @override
  void dispose() {
    _path.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _browse() async {
    final selectedPath = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => _DirectoryBrowserSheet(client: widget.client));
    if (selectedPath != null && selectedPath.isNotEmpty) {
      setState(() => _path.text = selectedPath);
    }
  }

  Future<void> _create() async {
    final path = _path.text.trim();
    if (path.isEmpty || _creating) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final workspace =
          await widget.client.createWorkspace(path: path, name: _name.text);
      widget.onCreated(workspace);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
      top: false,
      child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
              color: const Color(0xFF0D131D),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: Colors.white.withValues(alpha: .08)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: .45),
                    blurRadius: 28,
                    offset: const Offset(0, 18))
              ]),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('工作区',
                    style: TextStyle(
                        color: _text,
                        fontSize: 16,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                const Text('切换已有工作区，或输入路径/浏览文件夹添加新的工作区。',
                    style:
                        TextStyle(color: _muted, fontSize: 12, height: 1.35)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: _MiniInput(controller: _path, hint: '输入或浏览文件夹路径')),
                  const SizedBox(width: 8),
                  _TinyActionButton('浏览', onTap: _browse),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                      child: _MiniInput(controller: _name, hint: '名称（可选）')),
                  const SizedBox(width: 8),
                  _TinyActionButton(_creating ? '创建中' : '创建',
                      onTap: _creating ? null : _create, primary: true),
                ]),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _red, fontSize: 11)),
                ],
                const SizedBox(height: 12),
                const Text('已有工作区',
                    style: TextStyle(
                        color: _muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Flexible(
                    child: ListView(shrinkWrap: true, children: [
                  for (final workspace in widget.workspaces)
                    _WorkspaceChoiceRow(
                        workspace: workspace,
                        selected: workspace.id == widget.selected.id,
                        onTap: () => widget.onSelected(workspace)),
                ])),
              ])));
}

class _FirstRunWorkspaceSheet extends StatelessWidget {
  const _FirstRunWorkspaceSheet(
      {required this.workspaces, required this.selected, required this.client});
  final List<WorkspaceSummary> workspaces;
  final WorkspaceSummary selected;
  final DaemonClient client;

  Future<void> _createWorkspace(BuildContext context) async {
    final workspace = await showModalBottomSheet<WorkspaceSummary>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => _CreateFirstRunWorkspaceSheet(client: client));
    if (workspace != null && context.mounted) {
      Navigator.of(context).pop(workspace);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
      top: false,
      child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
              color: const Color(0xFF0D0E10),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: Colors.white.withValues(alpha: .08)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: .45),
                    blurRadius: 28,
                    offset: const Offset(0, 18))
              ]),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('选择本次编码工作区',
                    style: TextStyle(
                        color: _text,
                        fontSize: 16,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                const Text('新会话会在你选定的文件夹内调用真实 CLI，避免落到用户目录。',
                    style:
                        TextStyle(color: _muted, fontSize: 12, height: 1.35)),
                const SizedBox(height: 12),
                _TinyActionButton('添加 / 浏览文件夹',
                    onTap: () => _createWorkspace(context), primary: true),
                const SizedBox(height: 10),
                Flexible(
                    child: ListView(shrinkWrap: true, children: [
                  for (final workspace in workspaces)
                    _WorkspaceChoiceRow(
                        workspace: workspace,
                        selected: workspace.id == selected.id,
                        onTap: () => Navigator.of(context).pop(workspace)),
                ])),
              ])));
}

class _CreateFirstRunWorkspaceSheet extends StatefulWidget {
  const _CreateFirstRunWorkspaceSheet({required this.client});
  final DaemonClient client;

  @override
  State<_CreateFirstRunWorkspaceSheet> createState() =>
      _CreateFirstRunWorkspaceSheetState();
}

class _CreateFirstRunWorkspaceSheetState
    extends State<_CreateFirstRunWorkspaceSheet> {
  final _path = TextEditingController();
  final _name = TextEditingController();
  bool _creating = false;
  String? _error;

  @override
  void dispose() {
    _path.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _browse() async {
    final selectedPath = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => _DirectoryBrowserSheet(client: widget.client));
    if (selectedPath != null && selectedPath.isNotEmpty) {
      setState(() => _path.text = selectedPath);
    }
  }

  Future<void> _create() async {
    final path = _path.text.trim();
    if (path.isEmpty || _creating) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final workspace =
          await widget.client.createWorkspace(path: path, name: _name.text);
      if (mounted) Navigator.of(context).pop(workspace);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
      top: false,
      child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
              color: const Color(0xFF0D131D),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: .08))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              const Expanded(
                  child: Text('添加工作区',
                      style: TextStyle(
                          color: _text,
                          fontSize: 16,
                          fontWeight: FontWeight.w900))),
              _TinyActionButton('浏览', onTap: _browse),
            ]),
            const SizedBox(height: 10),
            _MiniInput(controller: _path, hint: '选择或输入文件夹路径'),
            const SizedBox(height: 8),
            _MiniInput(controller: _name, hint: '名称（可选）'),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _red, fontSize: 11)),
            ],
            const SizedBox(height: 12),
            SizedBox(
                width: double.infinity,
                child: _TinyActionButton(_creating ? '创建中' : '创建并使用',
                    onTap: _creating ? null : _create, primary: true)),
          ])));
}

class _WorkspaceChoiceRow extends StatelessWidget {
  const _WorkspaceChoiceRow(
      {required this.workspace, required this.selected, required this.onTap});
  final WorkspaceSummary workspace;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: selected
                  ? _purple.withValues(alpha: .16)
                  : Colors.white.withValues(alpha: .035),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: selected ? _purple.withValues(alpha: .45) : _stroke)),
          child: Row(children: [
            Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: _purple.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _purple.withValues(alpha: .22))),
                child:
                    const Icon(Icons.folder_rounded, color: _purple, size: 17)),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(workspace.name.isEmpty ? workspace.id : workspace.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: _text, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 3),
                  Text(workspace.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted, fontSize: 12))
                ])),
            if (selected)
              const Icon(Icons.check_circle_rounded, color: _purple, size: 19)
          ])));
}

class _DirectoryBrowserSheet extends StatefulWidget {
  const _DirectoryBrowserSheet({required this.client});
  final DaemonClient client;

  @override
  State<_DirectoryBrowserSheet> createState() => _DirectoryBrowserSheetState();
}

class _DirectoryBrowserSheetState extends State<_DirectoryBrowserSheet> {
  Future<Object>? _future;
  String? _currentPath;

  @override
  void initState() {
    super.initState();
    _future = widget.client.listFileSystemRoots();
  }

  void _open(String path) => setState(() {
        _currentPath = path;
        _future = widget.client.listDirectory(path);
      });

  @override
  Widget build(BuildContext context) => SafeArea(
      top: false,
      child: Container(
          margin: const EdgeInsets.all(12),
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * .78),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
              color: const Color(0xFF0D131D),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: Colors.white.withValues(alpha: .08))),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(
                  child: Text('选择文件夹',
                      style: TextStyle(
                          color: _text,
                          fontSize: 16,
                          fontWeight: FontWeight.w900))),
              if (_currentPath != null)
                _TinyActionButton('选择当前',
                    onTap: () => Navigator.of(context).pop(_currentPath),
                    primary: true),
            ]),
            const SizedBox(height: 6),
            Text(_currentPath ?? '选择磁盘或根目录后继续进入文件夹',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _muted, fontSize: 12)),
            const SizedBox(height: 12),
            Expanded(
                child: FutureBuilder<Object>(
                    future: _future,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(
                            child: CircularProgressIndicator(color: _purple));
                      }
                      if (snapshot.hasError) {
                        return Text(snapshot.error.toString(),
                            style: const TextStyle(color: _red, fontSize: 12));
                      }
                      final data = snapshot.requireData;
                      final entries = data is DirectoryListing
                          ? data.directories
                          : (data as List<DirectoryEntrySummary>);
                      final parent =
                          data is DirectoryListing ? data.parent : null;
                      return ListView(children: [
                        if (parent != null)
                          _DirectoryRow(
                              name: '..',
                              path: parent,
                              onTap: () => _open(parent)),
                        for (final entry in entries)
                          _DirectoryRow(
                              name: entry.name,
                              path: entry.path,
                              onTap: () => _open(entry.path)),
                      ]);
                    }))
          ])));
}

class _DirectoryRow extends StatelessWidget {
  const _DirectoryRow(
      {required this.name, required this.path, required this.onTap});
  final String name;
  final String path;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(children: [
            const Icon(Icons.folder_rounded, color: _purple, size: 17),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: _text, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _faint, fontSize: 11)),
                ])),
            const Icon(Icons.chevron_right_rounded, color: _muted, size: 18)
          ])));
}

class _MiniInput extends StatelessWidget {
  const _MiniInput({required this.controller, required this.hint});
  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) => TextField(
      controller: controller,
      style: _appTextStyle.copyWith(color: _text, fontSize: 12.5),
      decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: _appTextStyle.copyWith(color: _faint, fontSize: 12),
          filled: true,
          fillColor: Colors.white.withValues(alpha: .035),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _stroke)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _stroke)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 10)));
}

class _TinyActionButton extends StatelessWidget {
  const _TinyActionButton(this.label,
      {required this.onTap, this.primary = false});
  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
          height: 38,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
              color: primary
                  ? _purple.withValues(alpha: .24)
                  : Colors.white.withValues(alpha: .04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: primary ? _purple.withValues(alpha: .42) : _stroke)),
          child: Text(label,
              style: TextStyle(
                  color: primary ? _text : _muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w900))));
}

String _compactWorkspacePath(String path) {
  if (path.isEmpty) return '未设置路径';
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/').where((part) => part.isNotEmpty).toList();
  if (parts.length <= 2) return path;
  return '…/${parts[parts.length - 2]}/${parts.last}';
}

String _workspaceDisplayName(WorkspaceSummary workspace) {
  if (workspace.name.trim().isNotEmpty &&
      workspace.name.toLowerCase() != 'current project') {
    return workspace.name;
  }
  final normalized = workspace.path.replaceAll('\\', '/');
  final parts = normalized.split('/').where((part) => part.isNotEmpty).toList();
  return parts.isEmpty ? '当前工作区' : parts.last;
}

class _CodingComposer extends StatelessWidget {
  const _CodingComposer(
      {required this.controller,
      required this.adapter,
      required this.workspace,
      required this.running,
      required this.canSend,
      required this.sending,
      required this.onModelTap,
      required this.onSend,
      required this.onCancel});
  final TextEditingController controller;
  final String? adapter;
  final WorkspaceSummary workspace;
  final bool running;
  final bool canSend;
  final bool sending;
  final VoidCallback onModelTap;
  final VoidCallback onSend;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      decoration: BoxDecoration(
          color: const Color(0xF608090B),
          border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: .06))),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: .28),
                blurRadius: 24,
                offset: const Offset(0, -10))
          ]),
      child: SafeArea(
          top: false,
          child: Container(
              padding: const EdgeInsets.fromLTRB(13, 9, 8, 7),
              decoration: BoxDecoration(
                  color: const Color(0xFF161719),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: .085))),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 3,
                  style: _appTextStyle.copyWith(
                      color: _text,
                      fontSize: 15,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0),
                  decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: adapter == null
                          ? '没有可用 CLI adapter'
                          : running
                              ? '要求后续变更…'
                              : 'Add feedback...',
                      hintStyle: _appTextStyle.copyWith(
                          color: _faint,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w400),
                      contentPadding: EdgeInsets.zero),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) {
                    if (canSend) onSend();
                  },
                ),
                const SizedBox(height: 8),
                Row(children: [
                  InkWell(
                      onTap: running ? null : onModelTap,
                      borderRadius: BorderRadius.circular(999),
                      child: _ComposerModelPill(adapter: adapter)),
                  const Spacer(),
                  const _ComposerIcon(Icons.add_rounded),
                  const SizedBox(width: 12),
                  const _ComposerIcon(Icons.keyboard_command_key_rounded),
                  const SizedBox(width: 12),
                  _SendPromptButton(
                      enabled: canSend,
                      busy: sending,
                      running: running,
                      onTap: running ? onCancel : (canSend ? onSend : null)),
                ])
              ]))));
}

class _ComposerWorkspaceCloud extends StatelessWidget {
  const _ComposerWorkspaceCloud(
      {required this.workspace, required this.running, required this.onTap});
  final WorkspaceSummary workspace;
  final bool running;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
      width: double.infinity,
      color: const Color(0xF608090B),
      padding: const EdgeInsets.fromLTRB(23, 0, 28, 7),
      child: SafeArea(
          top: false,
          child: Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                  onTap: running ? null : onTap,
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 4),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.cloud_outlined,
                            color: _muted, size: 16),
                        const SizedBox(width: 10),
                        Text(_workspaceDisplayName(workspace),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: _muted,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500)),
                      ]))))));
}

class _SendPromptButton extends StatelessWidget {
  const _SendPromptButton(
      {required this.enabled,
      required this.busy,
      required this.running,
      required this.onTap});
  final bool enabled;
  final bool busy;
  final bool running;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final active = enabled || running;
    final glow =
        active ? Colors.white.withValues(alpha: .10) : Colors.transparent;
    return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                gradient: active
                    ? const LinearGradient(
                        colors: [Color(0xFFF7F7F7), Color(0xFFE8E8E8)])
                    : const LinearGradient(
                        colors: [Color(0xFF141518), Color(0xFF101113)]),
                shape: BoxShape.circle,
                border: Border.all(
                    color:
                        active ? Colors.white.withValues(alpha: .18) : _stroke),
                boxShadow: [
                  BoxShadow(
                      color: glow,
                      blurRadius: active ? 14 : 0,
                      spreadRadius: -7,
                      offset: const Offset(0, 6)),
                ]),
            child: Center(
                child: busy
                    ? SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                active ? const Color(0xFF08090B) : _faint)))
                    : running
                        ? Icon(Icons.stop_rounded,
                            color: active ? const Color(0xFF08090B) : _faint,
                            size: 17)
                        : _SendGlyph(
                            color:
                                active ? const Color(0xFF08090B) : _faint))));
  }
}

class _ComposerModelPill extends StatelessWidget {
  const _ComposerModelPill({required this.adapter});
  final String? adapter;

  @override
  Widget build(BuildContext context) => Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
          color: const Color(0xFF111214),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: .075))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.code_rounded, color: _muted, size: 14),
        const SizedBox(width: 7),
        Text(adapter ?? 'CLI',
            style: const TextStyle(
                color: _text,
                fontSize: 11.5,
                fontFamily: 'Consolas',
                fontWeight: FontWeight.w800)),
      ]));
}

class _ComposerIcon extends StatelessWidget {
  const _ComposerIcon(this.icon);
  final IconData icon;

  @override
  Widget build(BuildContext context) => Icon(icon, color: _muted, size: 19);
}

class _SendGlyph extends StatelessWidget {
  const _SendGlyph({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(14, 14), painter: _SendGlyphPainter(color));
}

class _SendGlyphPainter extends CustomPainter {
  const _SendGlyphPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.65
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(size.width * .50, size.height * .82)
      ..lineTo(size.width * .50, size.height * .20)
      ..moveTo(size.width * .24, size.height * .45)
      ..lineTo(size.width * .50, size.height * .20)
      ..lineTo(size.width * .76, size.height * .45);
    canvas.drawPath(path, paint);
    final railPaint = Paint()
      ..color = color.withValues(alpha: .42)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(size.width * .27, size.height * .86),
        Offset(size.width * .73, size.height * .86), railPaint);
  }

  @override
  bool shouldRepaint(covariant _SendGlyphPainter oldDelegate) =>
      oldDelegate.color != color;
}

RunSummary _runSummaryFromConversation(ConversationSummary conversation) {
  return RunSummary(
      id: conversation.id,
      tool: conversation.adapter,
      workspaceId: conversation.workspaceId,
      status: _runStatusFromConversation(conversation.status),
      cliSessionId: conversation.cliSessionId);
}

class _SessionItem {
  const _SessionItem({required this.run, this.conversation});
  final RunSummary run;
  final ConversationSummary? conversation;

  String get id => conversation?.id ?? run.id;
}

List<_SessionItem> _mergeSessionItems(List<_SessionItem> localSessions,
    List<ConversationSummary> snapshotConversations, List<RunSummary> snapshotRuns) {
  final items = <_SessionItem>[];
  final seen = <String>{};
  for (final item in localSessions) {
    if (seen.add(item.id)) items.add(item);
  }
  for (final conversation in snapshotConversations) {
    if (conversation.status == 'idle' && conversation.cliSessionId == null) {
      continue;
    }
    if (seen.add(conversation.id)) {
      items.add(_SessionItem(
          run: _runSummaryFromConversation(conversation),
          conversation: conversation));
    }
  }
  for (final run in snapshotRuns) {
    if (seen.add(run.id)) items.add(_SessionItem(run: run));
  }
  return items;
}

String _runStatusFromConversation(String status) {
  if (status == 'idle') return 'completed';
  if (status == 'cancelled' || status == 'failed') return status;
  return 'running';
}

bool _shouldPollAfterApproval(ConversationSummary conversation) =>
    conversation.status == 'running' || conversation.status == 'waiting_input';

bool _hasExplicitWorkspaceSelectionState({
  required bool workspaceConfirmedForSession,
  required String? activeRunId,
  required bool hasLocalSessions,
}) =>
    workspaceConfirmedForSession || activeRunId != null;

List<ConversationMessage> _messagesForConversationSnapshot(
    List<ConversationMessage> messages, ConversationSummary? conversation) {
  final blockingItem = conversation?.blockingItem;
  if (conversation?.status != 'waiting_approval' ||
      blockingItem?.type != 'approval_request') {
    return messages
        .where((message) => message.role != 'approval')
        .toList(growable: false);
  }
  final currentApprovalId = blockingItem?.approvalId;
  return messages
      .where((message) =>
          message.role != 'approval' ||
          (currentApprovalId != null &&
              message.approvalId == currentApprovalId))
      .toList(growable: false);
}

ConversationSummary _copyConversationStatus(
    ConversationSummary conversation, String status,
    {ConversationBlockingItem? blockingItem}) {
  return ConversationSummary(
      id: conversation.id,
      workspaceId: conversation.workspaceId,
      adapter: conversation.adapter,
      status: status,
      capabilities: conversation.capabilities,
      createdAt: conversation.createdAt,
      updatedAt: conversation.updatedAt,
      cliSessionId: conversation.cliSessionId,
      blockingItem: blockingItem,
      idleExpiresAt: conversation.idleExpiresAt);
}

_WorkbenchMessage _workbenchMessageFromConversation(
    ConversationMessage message) {
  final event = AgentEvent(
      type: message.role == 'approval'
          ? 'approval.required'
          : message.role == 'question'
              ? 'assistant.question'
              : message.role == 'thinking'
                  ? 'assistant.thinking'
                  : message.role == 'assistant_stream'
                      ? 'assistant.delta'
                      : message.role == 'assistant'
                          ? 'assistant.delta'
                          : 'raw.output',
      seq: message.eventSeq ?? 0,
      runId: 'conversation',
      createdAt: DateTime.now(),
      text: message.text,
      approvalId: message.approvalId,
      raw: <String, Object?>{
        'questionId': message.questionId,
        'suggestions': message.suggestions,
        if (message.role == 'assistant') 'result': message.text,
      });
  switch (message.role) {
    case 'user':
      return _WorkbenchMessage.user(message.text);
    case 'assistant':
      return _WorkbenchMessage('assistant', 'CLI 助手', message.text,
          event: event, runId: 'conversation');
    case 'thinking':
      return _WorkbenchMessage('thinking', '思考过程', message.text,
          event: event, runId: 'conversation');
    case 'assistant_stream':
      return _WorkbenchMessage('assistant_stream', 'CLI 助手', message.text,
          event: event, runId: 'conversation');
    case 'question':
      return _WorkbenchMessage('question', '需要你选择方向', message.text,
          event: event,
          runId: 'conversation',
          suggestions: message.suggestions);
    case 'approval':
      return _WorkbenchMessage('approval', '权限确认', message.text,
          event: event, runId: 'conversation');
    default:
      return _WorkbenchMessage.status(message.text);
  }
}

// ignore: unused_element
AgentEvent _agentEventFromConversation(ConversationEvent event, String runId) {
  final raw = <String, Object?>{...event.raw, 'runId': runId};
  final type = switch (event.type) {
    'conversation.started' => 'run.started',
    'conversation.status_changed' =>
      event.raw['status'] == 'idle' ? 'run.completed' : 'raw.output',
    'assistant.partial' => 'assistant.delta',
    'assistant.message' => 'assistant.delta',
    'approval.requested' => 'approval.required',
    'approval.resolved' => 'approval.responded',
    'conversation.cancelled' => 'run.cancelled',
    'run.error' => 'run.failed',
    _ => event.type,
  };
  if (event.type == 'assistant.message' && event.text != null) {
    raw['result'] = event.text;
  }
  return AgentEvent(
      type: type,
      seq: event.seq,
      runId: runId,
      createdAt: event.createdAt,
      text: event.text ?? event.summary,
      name: event.toolName,
      approvalId: event.approvalId,
      raw: raw);
}

class _WorkbenchMessage {
  const _WorkbenchMessage(this.role, this.title, this.body,
      {this.event,
      this.runId,
      this.completed = false,
      this.duration,
      this.suggestions = const <String>[]});
  final String role;
  final String title;
  final String body;
  final AgentEvent? event;
  final String? runId;
  final bool completed;
  final Duration? duration;
  final List<String> suggestions;
  factory _WorkbenchMessage.user(String text) =>
      _WorkbenchMessage('user', '你', text);
  factory _WorkbenchMessage.status(String text) =>
      _WorkbenchMessage('status', '运行状态', text);
  _WorkbenchMessage copyWith(
          {String? body, bool? completed, Duration? duration}) =>
      _WorkbenchMessage(role, title, body ?? this.body,
          event: event,
          runId: runId,
          completed: completed ?? this.completed,
          duration: duration ?? this.duration,
          suggestions: suggestions);

  static _WorkbenchMessage? fromEvent(AgentEvent event, bool streamOutput) {
    final parsed = _parseVisibleText(event);
    final visibleText = parsed?.text;
    if (event.type == 'approval.required') {
      final toolName = event.name ?? '工具';
      final target = _approvalTarget(event);
      final body =
          target == null ? '$toolName 请求权限（未提供参数）。' : '$toolName 请求访问：$target';
      return _WorkbenchMessage('approval', '权限确认', visibleText ?? body,
          event: event, runId: event.runId);
    }
    if (event.type == 'assistant.question') {
      final question = visibleText ?? event.text ?? _toolEventBody(event);
      return _WorkbenchMessage('question', '需要你选择方向', question.trim(),
          event: event,
          runId: event.runId,
          suggestions: _eventSuggestions(event));
    }
    if (visibleText != null && visibleText.trim().isNotEmpty) {
      if (parsed?.kind == _VisibleTextKind.delta) {
        if (!streamOutput) return null;
        return _WorkbenchMessage('assistant_stream', 'CLI 助手', visibleText,
            event: event, runId: event.runId);
      }
      if (parsed?.kind == _VisibleTextKind.finalMessage) {
        return _WorkbenchMessage('assistant', 'CLI 助手', visibleText.trim(),
            event: event, runId: event.runId);
      }
    }
    if (event.type == 'tool.started') {
      return _WorkbenchMessage('command', '运行命令', _toolEventBody(event),
          event: event, runId: event.runId);
    }
    if (event.type == 'diff.summary' && event.diff != null) {
      final diff = event.diff!;
      return _WorkbenchMessage('diff', '文件变更',
          '${diff.filePath}  +${diff.additions} -${diff.deletions}',
          event: event, runId: event.runId);
    }
    if (event.type == 'run.cancelled') return null;
    if (event.type == 'run.failed') {
      return _WorkbenchMessage('status', '运行结束', visibleText ?? event.type,
          event: event, runId: event.runId);
    }
    return null;
  }

  static String? _approvalTarget(AgentEvent event) {
    final input = _eventInput(event);
    if (input is Map<String, Object?>) {
      final question = _firstNonEmptyInputString(input, const [
        'question',
        'prompt',
        'message',
        'content',
        'text',
        'query',
        'description'
      ]);
      if (question != null) return question;
      final target = input['file_path'] ??
          input['path'] ??
          input['command'] ??
          input['pattern'] ??
          input['description'];
      if (target is String && target.trim().isNotEmpty) return target;
    }
    return null;
  }

  static _VisibleText? _parseVisibleText(AgentEvent event) {
    if (_isInternalProtocolObject(event.raw) ||
        _isInternalProtocolObject(event.raw['raw'])) {
      return null;
    }
    if (!_canExposeAsAssistantText(event)) return null;
    final nested = _parseRawObject(event.raw['raw']);
    if (nested != null) return nested;
    final topLevel = _parseRawObject(event.raw);
    if (topLevel != null) return topLevel;
    final text = event.text;
    if (text == null || text.trim().isEmpty) return null;
    final trimmed = text.trim();
    if (!trimmed.startsWith('{')) {
      return event.type.startsWith('assistant')
          ? _VisibleText(_VisibleTextKind.delta, trimmed)
          : null;
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, dynamic>) return null;
      if (_isInternalProtocolObject(decoded)) return null;
      final directMessage = decoded['message'];
      if (directMessage is Map<String, dynamic>) {
        final content = directMessage['content'];
        final extracted = _extractContent(content);
        if (extracted != null) {
          return _VisibleText(_VisibleTextKind.finalMessage, extracted);
        }
      }
      final eventPayload = decoded['event'];
      if (eventPayload is Map<String, dynamic>) {
        final content = eventPayload['content'];
        final extracted = _extractContent(content);
        if (extracted != null) {
          return _VisibleText(_VisibleTextKind.finalMessage, extracted);
        }
        final delta = eventPayload['delta'];
        if (delta is Map<String, dynamic>) {
          final deltaText = delta['text'];
          if (deltaText is String && deltaText.trim().isNotEmpty) {
            return _VisibleText(_VisibleTextKind.delta, deltaText);
          }
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static bool _canExposeAsAssistantText(AgentEvent event) {
    return event.type.startsWith('assistant') ||
        event.type == 'run.failed' ||
        event.type == 'run.cancelled';
  }

  static bool _isInternalProtocolObject(Object? value) {
    if (value is! Map<String, Object?> && value is! Map<String, dynamic>) {
      return false;
    }
    final raw = Map<String, dynamic>.from(value as Map);
    final type = raw['type'];
    final subtype = raw['subtype'];
    if (type == 'control_request' ||
        type == 'control_response' ||
        type == 'control_cancel_request' ||
        type == 'transcript_mirror') {
      return true;
    }
    if (raw.containsKey('hookSpecificOutput') ||
        raw.containsKey('suppressOutput') ||
        raw.containsKey('callback_id') ||
        raw.containsKey('hookEventName') ||
        raw.containsKey('hook_event_name')) {
      return true;
    }
    if (raw.containsKey('continue') && raw.containsKey('suppressOutput')) {
      return true;
    }
    if (type == 'system' &&
        (subtype == 'hook_callback' ||
            subtype == 'session_start' ||
            subtype == 'session_end')) {
      return true;
    }
    return false;
  }

  static _VisibleText? _parseRawObject(Object? value) {
    if (value is! Map<String, Object?> && value is! Map<String, dynamic>) {
      return null;
    }
    final raw = Map<String, dynamic>.from(value as Map);
    final result = raw['result'];
    if (result is String && result.trim().isNotEmpty) {
      if (_looksLikeProtocolLeak(result)) return null;
      return _VisibleText(_VisibleTextKind.finalMessage, result);
    }
    final output = raw['output'];
    if (output is String && output.trim().isNotEmpty) {
      if (_looksLikeProtocolLeak(output)) return null;
      return _VisibleText(_VisibleTextKind.finalMessage, output);
    }
    final message = raw['message'];
    if (message is String && message.trim().isNotEmpty) {
      if (_looksLikeProtocolLeak(message)) return null;
      return _VisibleText(_VisibleTextKind.finalMessage, message);
    }
    if (message is Map<String, dynamic>) {
      final extracted = _extractContent(message['content']);
      if (extracted != null) {
        return _VisibleText(_VisibleTextKind.finalMessage, extracted);
      }
    }
    final content = raw['content'];
    final contentText = _extractContent(content);
    if (contentText != null) {
      final type = raw['type'];
      final kind = type is String && type.contains('delta')
          ? _VisibleTextKind.delta
          : _VisibleTextKind.finalMessage;
      return _VisibleText(kind, contentText);
    }
    final delta = raw['delta'];
    if (delta is String && delta.trim().isNotEmpty) {
      return _VisibleText(_VisibleTextKind.delta, delta);
    }
    if (delta is Map<String, dynamic>) {
      final deltaText = delta['text'];
      if (deltaText is String && deltaText.trim().isNotEmpty) {
        return _VisibleText(_VisibleTextKind.delta, deltaText);
      }
    }
    return null;
  }

  static String? _extractContent(Object? content) {
    if (content is String && content.trim().isNotEmpty) {
      if (_looksLikeProtocolLeak(content)) return null;
      return content;
    }
    if (content is List) {
      final parts = <String>[];
      for (final item in content) {
        if (item is Map<String, dynamic>) {
          if (item['type'] != null && item['type'] != 'text') continue;
          final text = item['text'];
          if (text is String &&
              text.trim().isNotEmpty &&
              !_looksLikeProtocolLeak(text)) {
            parts.add(text.trim());
          }
        }
      }
      if (parts.isNotEmpty) return parts.join('\n\n');
    }
    return null;
  }

  static String _toolEventBody(AgentEvent event) {
    final input = _eventInput(event);
    if (input is Map<String, Object?>) {
      final question = _firstNonEmptyInputString(input, const [
        'question',
        'prompt',
        'message',
        'content',
        'text',
        'query',
        'description'
      ]);
      if (question != null) return question;
      final command = input['command'];
      if (command is String && command.trim().isNotEmpty) return command.trim();
      final file = input['file_path'] ?? input['path'] ?? input['filename'];
      if (file is String && file.trim().isNotEmpty) return file.trim();
    }
    return event.name ?? 'CLI 工具调用中';
  }

  static Object? _eventInput(AgentEvent event) {
    final direct = event.raw['input'];
    if (direct != null) return direct;
    final raw = event.raw['raw'];
    if (raw is Map<String, Object?>) {
      final rawInput = raw['input'];
      if (rawInput != null) return rawInput;
      final request = raw['request'];
      if (request is Map<String, Object?>) return request['input'];
    }
    return null;
  }

  static List<String> _eventSuggestions(AgentEvent event) {
    final raw = event.raw['suggestions'];
    if (raw is! List) return const <String>[];
    return raw
        .map((item) => item is String ? item.trim() : '')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static String? _firstNonEmptyInputString(
      Map<String, Object?> input, List<String> keys) {
    for (final key in keys) {
      final value = input[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    for (final value in input.values) {
      if (value is Map<String, Object?>) {
        final nested = _firstNonEmptyInputString(value, keys);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  static bool _looksLikeProtocolLeak(String text) {
    final trimmed = text.trimLeft();
    if (trimmed.startsWith(r'\n"') ||
        trimmed.contains(r'\n\n## Skill Types') ||
        trimmed.contains(r'\n\n## User Instructions')) {
      return true;
    }
    final sample = trimmed.length > 1400 ? trimmed.substring(0, 1400) : trimmed;
    final normalized = sample
        .replaceAll('\\n', '\n')
        .replaceAll('\\"', '"')
        .replaceAll("'", '"');
    if (normalized.contains('"type":"control_') ||
        normalized.contains('"type": "control_') ||
        normalized.contains('"suppressOutput"') ||
        normalized.contains('"hookSpecificOutput"') ||
        normalized.contains('"parent_tool_use_id"') ||
        normalized.contains('"session_id"') &&
            normalized.contains('"message"') &&
            normalized.contains('"role"')) {
      return true;
    }
    if ((normalized.startsWith('{') || normalized.startsWith('"{')) &&
        normalized.contains('"type"') &&
        normalized.contains('"message"')) {
      return true;
    }
    return false;
  }
}

enum _VisibleTextKind { delta, finalMessage }

class _VisibleText {
  const _VisibleText(this.kind, this.text);
  final _VisibleTextKind kind;
  final String text;
}

class _WorkbenchInlineStatus extends StatelessWidget {
  const _WorkbenchInlineStatus({
    required this.adapter,
    required this.runId,
    required this.eventCount,
    required this.terminal,
  });
  final String? adapter;
  final String? runId;
  final int eventCount;
  final bool terminal;

  @override
  Widget build(BuildContext context) {
    final text = runId == null
        ? '准备好接收编码任务'
        : terminal
            ? '本次 CLI 会话已完成 · $eventCount 个事件已处理'
            : '正在连接 ${adapter ?? 'CLI'} · 已处理 $eventCount 个事件';
    return Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            color: const Color(0x66111B2A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: .075))),
        child: Row(children: [
          _PulseDot(active: runId != null && !terminal),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 12))),
        ]));
  }
}

class _WorkbenchMessageCard extends StatelessWidget {
  const _WorkbenchMessageCard(
      {required this.message,
      required this.onApproval,
      required this.onSuggestion,
      required this.expandThinking});
  final _WorkbenchMessage message;
  final ValueChanged<String> onApproval;
  final ValueChanged<String> onSuggestion;
  final bool expandThinking;
  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final isApproval = message.role == 'approval';
    final isCommand = message.role == 'command';
    final isDiff = message.role == 'diff';
    final isTool = isCommand || isDiff;
    if (isCommand) return _CommandEventCard(message: message);
    if (isDiff) return _DiffEventCard(message: message);
    if (message.role == 'thinking') {
      return _ThinkingEventCard(message: message, expanded: expandThinking);
    }
    if (isApproval) {
      return _ApprovalEventCard(message: message, onApproval: onApproval);
    }
    if (message.role == 'question') {
      return _QuestionEventCard(message: message, onSuggestion: onSuggestion);
    }
    final color = isUser
        ? _purple2
        : isApproval
            ? _amber
            : isTool
                ? _orange
                : _green;
    return Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: FractionallySizedBox(
            widthFactor: isUser ? .78 : 1,
            child: Container(
                padding: EdgeInsets.fromLTRB(isUser ? 13 : 16,
                    isApproval ? 12 : 11, isUser ? 13 : 16, 11),
                decoration: BoxDecoration(
                    gradient: isUser ? null : null,
                    color: isUser
                        ? const Color(0xFF191A1E)
                        : isApproval
                            ? const Color(0xFF101113)
                            : message.role == 'assistant'
                                ? Colors.transparent
                                : const Color(0xFF101113),
                    borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(isApproval ? 14 : 18),
                        topRight: Radius.circular(isApproval ? 14 : 18),
                        bottomLeft: Radius.circular(isUser
                            ? 18
                            : isApproval
                                ? 14
                                : 6),
                        bottomRight: Radius.circular(isUser
                            ? 6
                            : isApproval
                                ? 14
                                : 18)),
                    border: Border.all(
                        color: isUser
                            ? Colors.white.withValues(alpha: .085)
                            : isApproval
                                ? Colors.white.withValues(alpha: .08)
                                : message.role == 'assistant'
                                    ? Colors.transparent
                                    : _stroke)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!isUser && message.role != 'assistant') ...[
                        Row(children: [
                          Container(
                              width: isApproval ? 24 : 18,
                              height: isApproval ? 24 : 18,
                              alignment: Alignment.center,
                              decoration: isApproval
                                  ? BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      color: _amber.withValues(alpha: .10),
                                      border: Border.all(
                                          color: _amber.withValues(alpha: .22)))
                                  : null,
                              child: Icon(
                                  isApproval
                                      ? Icons.shield_outlined
                                      : isTool
                                          ? Icons.build_circle_rounded
                                          : Icons.auto_awesome_rounded,
                                  color: color,
                                  size: isApproval ? 15 : 16)),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(message.title,
                                  style: const TextStyle(
                                      color: _text,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700))),
                        ]),
                        const SizedBox(height: 8),
                      ],
                      if (message.role == 'assistant')
                        _AssistantMarkdownBody(markdown: message.body)
                      else
                        Text(message.body,
                            style: TextStyle(
                                color:
                                    isUser ? const Color(0xFFF4F4F4) : _muted,
                                fontSize: isUser ? 14.5 : 12.5,
                                height: isUser ? 1.45 : 1.55,
                                fontWeight: isUser
                                    ? FontWeight.w500
                                    : FontWeight.w400)),
                      if (isApproval) ...[
                        const SizedBox(height: 12),
                        if (message.event?.approvalId == null)
                          const Text('daemon 未提供 approvalId，无法在移动端处理。',
                              style: TextStyle(color: _red, fontSize: 12))
                        else
                          Row(children: [
                            Expanded(
                                child: _ApprovalActionButton('拒绝',
                                    color: _red,
                                    onTap: () => onApproval('deny'))),
                            const SizedBox(width: 10),
                            Expanded(
                                child: _ApprovalActionButton('批准',
                                    color: _purple2,
                                    primary: true,
                                    onTap: () => onApproval('allow'))),
                          ])
                      ]
                    ]))));
  }
}

class _AssistantMarkdownBody extends StatelessWidget {
  const _AssistantMarkdownBody({required this.markdown});
  final String markdown;

  @override
  Widget build(BuildContext context) => MarkdownBody(
      data: _normalizeAssistantMarkdown(markdown),
      selectable: true,
      softLineBreak: true,
      styleSheet: _buildAssistantMarkdownStyleSheet(context),
      imageBuilder: (_, __, ___) => const SizedBox.shrink(),
      onTapLink: (_, __, ___) {});
}

class _QuestionEventCard extends StatelessWidget {
  const _QuestionEventCard({required this.message, required this.onSuggestion});
  final _WorkbenchMessage message;
  final ValueChanged<String> onSuggestion;

  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: const Color(0xFF101113),
          border: Border.all(color: Colors.white.withValues(alpha: .075))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: _purple.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _purple.withValues(alpha: .26))),
              child: const Icon(Icons.tune_rounded, color: _purple2, size: 15)),
          const SizedBox(width: 10),
          const Expanded(
              child: Text('需要你补充方向',
                  style: TextStyle(
                      color: _text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 12),
        Text(message.body,
            style:
                const TextStyle(color: _muted, fontSize: 13.5, height: 1.55)),
        if (message.suggestions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
              spacing: 8,
              runSpacing: 8,
              children: message.suggestions
                  .map((item) => _QuestionSuggestionChip(
                      text: item, onTap: () => onSuggestion(item)))
                  .toList(growable: false)),
        ]
      ]));
}

class _ThinkingEventCard extends StatelessWidget {
  const _ThinkingEventCard({required this.message, required this.expanded});
  final _WorkbenchMessage message;
  final bool expanded;

  @override
  Widget build(BuildContext context) =>
      _ExpandableThinkingCard(message: message, initiallyExpanded: expanded);
}

class _ExpandableThinkingCard extends StatefulWidget {
  const _ExpandableThinkingCard(
      {required this.message, required this.initiallyExpanded});
  final _WorkbenchMessage message;
  final bool initiallyExpanded;

  @override
  State<_ExpandableThinkingCard> createState() =>
      _ExpandableThinkingCardState();
}

class _ExpandableThinkingCardState extends State<_ExpandableThinkingCard> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  void didUpdateWidget(covariant _ExpandableThinkingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.body != widget.message.body) {
      _expanded = widget.initiallyExpanded;
    }
  }

  @override
  Widget build(BuildContext context) => InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      borderRadius: BorderRadius.circular(16),
      child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: const Color(0xFF0E1013),
              border: Border.all(color: Colors.white.withValues(alpha: .06))),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.psychology_alt_rounded,
                  color: _purple2.withValues(alpha: .92), size: 16),
              const SizedBox(width: 8),
              const Expanded(
                  child: Text('思考过程',
                      style: TextStyle(
                          color: _text,
                          fontSize: 13,
                          fontWeight: FontWeight.w800))),
              Text(_expanded ? '收起' : '展开',
                  style: const TextStyle(color: _muted, fontSize: 11)),
            ]),
            if (_expanded) ...[
              const SizedBox(height: 10),
              Text(widget.message.body,
                  style: const TextStyle(
                      color: _muted, fontSize: 12.5, height: 1.55)),
            ]
          ])));
}

class _QuestionSuggestionChip extends StatelessWidget {
  const _QuestionSuggestionChip({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: Colors.white.withValues(alpha: .045),
              border: Border.all(color: Colors.white.withValues(alpha: .10))),
          child: Text(text,
              style: const TextStyle(
                  color: Color(0xFFDCE2EE),
                  fontSize: 12,
                  fontWeight: FontWeight.w700))));
}

class _ApprovalActionButton extends StatelessWidget {
  const _ApprovalActionButton(this.text,
      {required this.color, required this.onTap, this.primary = false});
  final String text;
  final Color color;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              gradient: primary
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF2F3034), Color(0xFF1A1B1E)])
                  : null,
              color: primary ? null : color.withValues(alpha: .045),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: primary
                      ? Colors.white.withValues(alpha: .14)
                      : color.withValues(alpha: .34))),
          child: Text(text,
              style: TextStyle(
                  color: primary ? _text : color,
                  fontSize: 13,
                  letterSpacing: .4,
                  fontWeight: FontWeight.w800))));
}

class _CommandEventCard extends StatelessWidget {
  const _CommandEventCard({required this.message});
  final _WorkbenchMessage message;

  @override
  Widget build(BuildContext context) => _AgentEventCard(
      icon: Icons.chevron_right_rounded,
      title: 'Ran command',
      meta: message.title,
      trailing: _formatCommandDuration(message.duration),
      child: _EventCodeLine(text: message.body, ok: message.completed));
}

@visibleForTesting
Widget buildCompletedCommandCardPreview() => MaterialApp(
    locale: _zhHansCnLocale,
    supportedLocales: const [_zhHansCnLocale, Locale('en', 'US')],
    localizationsDelegates: _appLocalizationsDelegates,
    theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'Segoe UI',
        fontFamilyFallback: _appFontFallback,
        useMaterial3: true),
    home: Scaffold(
        backgroundColor: _bg,
        body: Padding(
            padding: const EdgeInsets.all(16),
            child: _CommandEventCard(
                message: const _WorkbenchMessage(
                    'command',
                    'cwd resolved · permissions checked',
                    'npm run lint && npm test',
                    runId: 'run_1',
                    completed: true,
                    duration: Duration(milliseconds: 2100))))));

@visibleForTesting
Widget buildPendingSentinelPreview() => MaterialApp(
    locale: _zhHansCnLocale,
    supportedLocales: const [_zhHansCnLocale, Locale('en', 'US')],
    localizationsDelegates: _appLocalizationsDelegates,
    theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'Segoe UI',
        fontFamilyFallback: _appFontFallback,
        useMaterial3: true),
    home: const Scaffold(
        backgroundColor: _bg,
        body: Padding(
            padding: EdgeInsets.all(16),
            child: _PendingSentinel(
                adapter: 'claude',
                statusText: '正在接收 CLI 输出...',
                actions: <String>['已启动 claude 会话', 'Claude requesting']))));

String? _formatCommandDuration(Duration? duration) {
  if (duration == null) return null;
  final seconds = duration.inMilliseconds / 1000;
  if (seconds < 10) return '${seconds.toStringAsFixed(1)}s';
  return '${seconds.round()}s';
}

class _DiffEventCard extends StatelessWidget {
  const _DiffEventCard({required this.message});
  final _WorkbenchMessage message;

  @override
  Widget build(BuildContext context) => _AgentEventCard(
      icon: Icons.call_split_rounded,
      title: 'Changed files',
      meta: 'diff summary',
      trailing: null,
      child: _EventCodeLine(text: message.body, ok: true));
}

class _ApprovalEventCard extends StatelessWidget {
  const _ApprovalEventCard({required this.message, required this.onApproval});
  final _WorkbenchMessage message;
  final ValueChanged<String> onApproval;

  @override
  Widget build(BuildContext context) => _AgentEventCard(
      icon: Icons.priority_high_rounded,
      title: '需要审批',
      meta: _approvalMeta(message.event),
      trailing: _eventTime(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(message.body,
            style:
                const TextStyle(color: _muted, fontSize: 12.5, height: 1.55)),
        const SizedBox(height: 12),
        if (message.event?.approvalId == null)
          const Text('daemon 未提供 approvalId，无法在移动端处理。',
              style: TextStyle(color: _red, fontSize: 12))
        else
          Row(children: [
            Expanded(
                child: _ApprovalActionButton('拒绝',
                    color: _red, onTap: () => onApproval('deny'))),
            const SizedBox(width: 10),
            Expanded(
                child: _ApprovalActionButton('批准',
                    color: _text,
                    primary: true,
                    onTap: () => onApproval('allow'))),
          ])
      ]));

  static String _approvalMeta(AgentEvent? event) {
    if (event == null) return 'permission request';
    return '${event.name ?? 'Tool'} · write access';
  }

  static String _eventTime() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }
}

class _AgentEventCard extends StatelessWidget {
  const _AgentEventCard(
      {required this.icon,
      required this.title,
      required this.meta,
      required this.child,
      this.trailing});
  final IconData icon;
  final String title;
  final String meta;
  final Widget child;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: const Color(0xFF101113),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: .075))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: const Color(0xFF191A1D),
                  borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, color: _amber, size: 15)),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: const TextStyle(
                        color: _text,
                        fontSize: 13,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: _faint, fontSize: 10.5, fontFamily: 'Consolas')),
              ])),
          if (trailing != null)
            Text(trailing!,
                style: const TextStyle(
                    color: _faint, fontSize: 10.5, fontFamily: 'Consolas'))
        ]),
        const SizedBox(height: 12),
        child,
      ]));
}

class _EventCodeLine extends StatelessWidget {
  const _EventCodeLine({required this.text, required this.ok});
  final String text;
  final bool ok;

  @override
  Widget build(BuildContext context) => Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
          color: const Color(0xFF0B0C0E),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: Colors.white.withValues(alpha: .055))),
      child: Row(children: [
        Expanded(
            child: Text(text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: _muted,
                    fontSize: 12,
                    fontFamily: 'Consolas',
                    height: 1.35))),
        if (ok) ...[
          const SizedBox(width: 8),
          const Text('ok',
              style: TextStyle(
                  color: _green,
                  fontSize: 11,
                  fontFamily: 'Consolas',
                  fontWeight: FontWeight.w800))
        ]
      ]));
}

String _normalizeAssistantMarkdown(String markdown) {
  final withoutHtml = markdown.replaceAll(RegExp(r'<[^>]+>'), '');
  return withoutHtml
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

MarkdownStyleSheet _buildAssistantMarkdownStyleSheet(BuildContext context) {
  const codeBg = Color(0x66101824);
  const codeBorder = Color(0x22FFFFFF);
  final base = Theme.of(context).textTheme;
  return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: base.bodyMedium?.copyWith(color: _muted, fontSize: 14.5, height: 1.68),
      strong: const TextStyle(color: _text, fontWeight: FontWeight.w700),
      em: const TextStyle(
          color: Color(0xFFD3DAE8), fontStyle: FontStyle.italic),
      h1: const TextStyle(
          color: _text,
          fontSize: 17,
          height: 1.35,
          fontWeight: FontWeight.w800),
      h2: const TextStyle(
          color: _text,
          fontSize: 15.5,
          height: 1.35,
          fontWeight: FontWeight.w800),
      h3: const TextStyle(
          color: _text, fontSize: 14, height: 1.4, fontWeight: FontWeight.w800),
      listBullet: const TextStyle(color: _green, fontSize: 12, height: 1.55),
      code: const TextStyle(
          color: Color(0xFFE7ECF8),
          backgroundColor: Color(0xFF18191C),
          fontFamily: 'Consolas',
          fontSize: 13,
          height: 1.45),
      codeblockDecoration: BoxDecoration(
          color: codeBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: codeBorder)),
      blockquote: const TextStyle(color: Color(0xFFBBC5D6), fontSize: 13),
      blockquoteDecoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .04),
          border: const Border(left: BorderSide(color: _purple, width: 3)),
          borderRadius: BorderRadius.circular(8)),
      a: const TextStyle(color: Color(0xFF7C8CFF), fontWeight: FontWeight.w800),
      horizontalRuleDecoration: BoxDecoration(
          border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: .08)))),
      pPadding: const EdgeInsets.only(bottom: 8),
      h1Padding: const EdgeInsets.only(top: 2, bottom: 8),
      h2Padding: const EdgeInsets.only(top: 2, bottom: 7),
      h3Padding: const EdgeInsets.only(top: 2, bottom: 6),
      listIndent: 18,
      blockSpacing: 8,
      codeblockPadding: const EdgeInsets.all(10));
}

class _PendingSentinel extends StatefulWidget {
  const _PendingSentinel({
    required this.adapter,
    required this.statusText,
    this.actions = const <String>[],
  });

  final String adapter;
  final String statusText;
  final List<String> actions;

  @override
  State<_PendingSentinel> createState() => _PendingSentinelState();
}

class _PendingSentinelState extends State<_PendingSentinel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 850))
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
            margin: const EdgeInsets.only(top: 2, bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: .07)),
                gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xF2141517), Color(0xEE0E0F11)])),
            child: Row(children: [
              _RunningOrb(progress: _controller.value),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const Text('正在运行',
                        style: TextStyle(
                            color: _text,
                            fontWeight: FontWeight.w800,
                            fontSize: 13)),
                    const SizedBox(height: 5),
                    AnimatedSwitcher(
                        duration: const Duration(milliseconds: 240),
                        child: Text(widget.statusText,
                            key: ValueKey(widget.statusText),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: _muted, fontSize: 12, height: 1.3))),
                  ])),
              _PulseBars(progress: _controller.value),
            ]));
      });
}

class _RunningOrb extends StatelessWidget {
  const _RunningOrb({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    final pulse = progress < .5 ? progress * 2 : (1 - progress) * 2;
    return Container(
        width: 18,
        height: 18,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _purple.withValues(alpha: .08 + pulse * .08),
            border: Border.all(color: _purple.withValues(alpha: .18))),
        child: Container(
            width: 7 + pulse * 2,
            height: 7 + pulse * 2,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _purple2.withValues(alpha: .75),
                boxShadow: [
                  BoxShadow(
                      color: _purple.withValues(alpha: .22 + pulse * .18),
                      blurRadius: 8 + pulse * 8)
                ])));
  }
}

class _PulseBars extends StatelessWidget {
  const _PulseBars({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) => Row(
          children: List.generate(3, (index) {
        final phase = (progress + index * .22) % 1;
        final height = 6 + (phase < .5 ? phase : 1 - phase) * 18;
        return Container(
            margin: const EdgeInsets.only(left: 3),
            width: 3,
            height: height,
            decoration: BoxDecoration(
                color: _purple.withValues(alpha: .28 + phase * .34),
                borderRadius: BorderRadius.circular(999)));
      }));
}

class _PulseDot extends StatelessWidget {
  const _PulseDot({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) => Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? _green : _faint,
          boxShadow: active
              ? [
                  BoxShadow(
                      color: _green.withValues(alpha: .45),
                      blurRadius: 12,
                      spreadRadius: 2)
                ]
              : null));
}

class _QueuePage extends StatelessWidget {
  const _QueuePage({required this.data});
  final _AppSnapshot data;

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

class _SettingsPage extends StatelessWidget {
  const _SettingsPage(
      {required this.open,
      required this.data,
      required this.streamOutput,
      required this.expandThinking,
      required this.permissionMode,
      required this.onPermissionModeChanged,
      required this.onStreamOutputChanged,
      required this.onExpandThinkingChanged});
  final ValueChanged<_RoutePage> open;
  final _AppSnapshot data;
  final bool streamOutput;
  final bool expandThinking;
  final String permissionMode;
  final ValueChanged<String> onPermissionModeChanged;
  final ValueChanged<bool> onStreamOutputChanged;
  final ValueChanged<bool> onExpandThinkingChanged;

  @override
  Widget build(BuildContext context) {
    return _PageScroll(
      children: [
        const _TopBar(title: '设置'),
        SizedBox(height: 18),
        _Subhead('连接'),
        _SettingsCard(children: [
          _SettingsRow(
              title: '当前设备',
              value: data.workspace.name,
              subtitle: data.workspace.path,
              ok: true),
          _SettingsRow(title: '切换设备', value: '›'),
        ]),
        SizedBox(height: 18),
        _Subhead('安全'),
        _SettingsCard(children: [
          _SettingsRow(
              title: '安全模式',
              value: data.health.mode,
              subtitle: 'LAN: ${data.health.lanMode}'),
        ]),
        SizedBox(height: 18),
        _Subhead('编码'),
        _SettingsCard(children: [
          _PermissionModeRow(
              value: permissionMode, onChanged: onPermissionModeChanged),
          _SettingsSwitchRow(
              title: '流式输出',
              subtitle: '关闭时只显示最终回复，避免 delta 与完整消息重复。',
              value: streamOutput,
              onChanged: onStreamOutputChanged),
          _SettingsSwitchRow(
              title: '显示思考过程',
              subtitle: '开启后默认展开模型 thinking；关闭时折叠显示。',
              value: expandThinking,
              onChanged: onExpandThinkingChanged),
        ]),
        SizedBox(height: 18),
        _Subhead('隐私与数据'),
        _SettingsCard(children: [
          _SettingsRow(
              title: '代码诊断', value: '${data.diagnostics.diagnostics.length} 条'),
          _SettingsRow(
              title: 'Git 状态',
              value: data.gitStatus?.clean == true
                  ? '干净'
                  : '${data.gitStatus?.files.length ?? 0} 文件'),
        ]),
        SizedBox(height: 18),
        _Subhead('关于'),
        _SettingsCard(children: [
          _SettingsRow(title: 'daemon', value: data.health.daemonVersion),
          _SettingsRow(title: '扩展', value: '${data.extensions.length} 个'),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
              child: _PrimaryButton('适配器状态',
                  onTap: () => open(_RoutePage.adapters))),
          const SizedBox(width: 8),
          Expanded(
              child: _PrimaryButton('通知',
                  onTap: () => open(_RoutePage.notifications))),
        ]),
        const SizedBox(height: 8),
        _GhostButton('生成诊断信息',
            color: _purple, onTap: () => open(_RoutePage.diagnostics)),
      ],
    );
  }
}

class _PageScroll extends StatelessWidget {
  const _PageScroll({required this.children, this.floating});
  final List<Widget> children;
  final Widget? floating;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 104),
          children: children,
        ),
        if (floating != null)
          Positioned(right: 18, bottom: 92, child: floating!),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar(
      {required this.title,
      this.subtitle,
      this.showScan = false,
      this.leading = false,
      this.action});
  final String title;
  final String? subtitle;
  final bool showScan;
  final bool leading;
  final String? action;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (leading) ...[
              const Icon(Icons.chevron_left_rounded, color: _text, size: 26),
              const SizedBox(width: 8)
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Row(children: [
                      Text(subtitle!.replaceAll('在线', ''),
                          style: const TextStyle(
                              color: _muted, fontSize: 12, letterSpacing: .5)),
                      const Text('在线',
                          style: TextStyle(
                              color: _green,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(width: 4),
                      const _Dot(color: _green, size: 5),
                    ]),
                  ],
                ],
              ),
            ),
            if (action != null)
              Text(action!,
                  style: const TextStyle(
                      color: _purple, fontWeight: FontWeight.w700)),
            if (showScan)
              const Icon(Icons.center_focus_weak_rounded,
                  color: _muted, size: 24),
            if (!showScan && action == null)
              const Icon(Icons.more_horiz_rounded, color: _muted, size: 26),
          ],
        ),
      ],
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav(
      {required this.selected, required this.items, required this.onTap});
  final int selected;
  final List<_NavSpec> items;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xE6080D15),
        border: Border(top: BorderSide(color: _stroke)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 18),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (var i = 0; i < items.length; i++)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onTap(i),
                child: SizedBox(
                  width: 58,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(items[i].icon,
                          color: i == selected ? _purple : _muted, size: 22),
                      const SizedBox(height: 4),
                      Text(items[i].label,
                          style: TextStyle(
                              color: i == selected ? _purple : _muted,
                              fontSize: 11,
                              fontWeight: i == selected
                                  ? FontWeight.w800
                                  : FontWeight.w500)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(
      {required this.label,
      required this.value,
      required this.note,
      required this.colors});
  final String label;
  final String value;
  final String note;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 110,
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 11),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _stroke),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: _text, fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(value,
            style: const TextStyle(
                fontSize: 28, fontWeight: FontWeight.w300, height: 1)),
        const SizedBox(height: 4),
        Text(note,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _muted, fontSize: 11, height: 1)),
      ]),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard(
      {required this.child, this.padding = const EdgeInsets.all(14)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _stroke),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: .28),
              blurRadius: 22,
              offset: const Offset(0, 12))
        ],
      ),
      child: child,
    );
  }
}

class _CompactRun extends StatelessWidget {
  const _CompactRun(
      {required this.title,
      required this.tool,
      required this.time,
      required this.status,
      required this.color,
      required this.iconColor,
      this.onTap});
  final String title;
  final String tool;
  final String time;
  final String status;
  final Color color;
  final Color iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          _AgentIcon(color: iconColor),
          const SizedBox(width: 9),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Row(children: [
                  Text(tool,
                      style: const TextStyle(color: _muted, fontSize: 12)),
                  const SizedBox(width: 6),
                  Text('· $status',
                      style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(width: 4),
                  _Dot(color: color, size: 4)
                ]),
              ])),
          Text(time, style: const TextStyle(color: _muted, fontSize: 12)),
        ]),
      ),
    );
  }
}

class _RunCard extends StatelessWidget {
  const _RunCard(
      {required this.title,
      required this.tool,
      required this.time,
      required this.status,
      required this.progress,
      required this.statusColor,
      this.onTap});
  final String title;
  final String tool;
  final String time;
  final String status;
  final double progress;
  final Color statusColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: _GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800))),
            _StatusBadge(status, color: statusColor),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _AgentIcon(color: _purple),
            const SizedBox(width: 6),
            Text(tool, style: const TextStyle(color: _muted, fontSize: 12))
          ]),
          const SizedBox(height: 8),
          Text(time, style: const TextStyle(color: _muted, fontSize: 12)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                backgroundColor: Colors.white.withValues(alpha: .06),
                color: statusColor == _red ? _red : _purple),
          ),
        ]),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.color,
      this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 92,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color.withValues(alpha: .32), _panelHi]),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: .22)),
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 25),
          const Spacer(),
          Text(title,
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 3),
          Text(subtitle, style: const TextStyle(color: _muted, fontSize: 10)),
        ]),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text,
      {this.selected = false, this.green = false, this.amber = false});
  final String text;
  final bool selected;
  final bool green;
  final bool amber;

  @override
  Widget build(BuildContext context) {
    final color = green
        ? _green
        : amber
            ? _amber
            : _purple;
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: selected || green || amber
            ? color.withValues(alpha: .28)
            : _panelHi,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
            color: (selected || green || amber)
                ? color.withValues(alpha: .22)
                : _stroke),
      ),
      child: Text(text,
          style: TextStyle(
              color: selected ? Colors.white : _muted,
              fontSize: 12,
              fontWeight: FontWeight.w800)),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar();

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
              color: _panelHi,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _stroke)),
          child: const Row(children: [
            Icon(Icons.search_rounded, color: _muted, size: 18),
            SizedBox(width: 8),
            Text('搜索任务、描述、工具...', style: TextStyle(color: _faint, fontSize: 13))
          ]),
        ),
      ),
      const SizedBox(width: 9),
      Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
              color: _panelHi,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _stroke)),
          child: const Icon(Icons.filter_alt_rounded, color: _text, size: 18)),
    ]);
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow(
      {required this.title, required this.tool, required this.iconColor});
  final String title;
  final String tool;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        _AgentIcon(color: iconColor),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          Text(tool, style: const TextStyle(color: _muted, fontSize: 12))
        ])),
        const SizedBox(
            width: 17,
            height: 17,
            child: CircularProgressIndicator(strokeWidth: 2, color: _green))
      ]),
    );
  }
}

class _WaitingRow extends StatelessWidget {
  const _WaitingRow(
      {required this.index, required this.title, required this.tool});
  final String index;
  final String title;
  final String tool;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Text(index, style: const TextStyle(color: _muted, fontSize: 18)),
        const SizedBox(width: 15),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          Text(tool, style: const TextStyle(color: _muted, fontSize: 12))
        ])),
        _StatusBadge('等待中', color: _amber)
      ]),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        for (var i = 0; i < children.length; i++) ...[
          children[i],
          if (i != children.length - 1) const _Hairline()
        ],
      ]),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow(
      {required this.title,
      required this.value,
      this.subtitle,
      this.ok = false});
  final String title;
  final String value;
  final String? subtitle;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!, style: const TextStyle(color: _muted, fontSize: 12))
          ]
        ])),
        Text(value,
            style: TextStyle(
                color: ok ? _green : _muted,
                fontSize: 12,
                fontWeight: FontWeight.w700)),
        if (ok)
          const Padding(
              padding: EdgeInsets.only(left: 5),
              child: _Dot(color: _green, size: 5)),
      ]),
    );
  }
}

class _PermissionModeRow extends StatelessWidget {
  const _PermissionModeRow({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        const Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('权限模式',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
          SizedBox(height: 4),
          Text('默认模式会弹出 CLI 权限确认；自动模式由 CLI 自动处理。',
              style: TextStyle(color: _muted, fontSize: 12, height: 1.35)),
        ])),
        const SizedBox(width: 12),
        _PermissionChip(
            label: '默认',
            selected: value == 'default',
            onTap: () => onChanged('default')),
        const SizedBox(width: 8),
        _PermissionChip(
            label: '自动',
            selected: value == 'auto',
            onTap: () => onChanged('auto')),
      ]));
}

class _PermissionChip extends StatelessWidget {
  const _PermissionChip(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: selected
                  ? _purple.withValues(alpha: .22)
                  : Colors.white.withValues(alpha: .04),
              border: Border.all(
                  color: selected ? _purple.withValues(alpha: .48) : _stroke)),
          child: Text(label,
              style: TextStyle(
                  color: selected ? _text : _muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w900))));
}

class _SettingsSwitchRow extends StatelessWidget {
  const _SettingsSwitchRow(
      {required this.title,
      required this.subtitle,
      required this.value,
      required this.onChanged});
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(color: _muted, fontSize: 12))
        ])),
        Switch(
            value: value,
            activeThumbColor: _purple,
            activeTrackColor: _purple.withValues(alpha: .35),
            inactiveThumbColor: _faint,
            inactiveTrackColor: _panelHi,
            onChanged: onChanged),
      ]),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      const Spacer(),
      if (action != null)
        GestureDetector(
          onTap: onAction,
          child: Text(action!,
              style: const TextStyle(
                  color: _purple, fontSize: 12, fontWeight: FontWeight.w800)),
        )
    ]);
  }
}

class _Subhead extends StatelessWidget {
  const _Subhead(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: const TextStyle(fontWeight: FontWeight.w800, color: _text)));
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge(this.text, {required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .13),
          borderRadius: BorderRadius.circular(7)),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w900)),
    );
  }
}

class _AgentIcon extends StatelessWidget {
  const _AgentIcon({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient:
                LinearGradient(colors: [color, color.withValues(alpha: .45)])),
        child: const Icon(Icons.auto_awesome_rounded,
            size: 10, color: Colors.white));
  }
}

class _FloatingPlus extends StatelessWidget {
  const _FloatingPlus({this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(colors: [_purple, _purple2]),
              boxShadow: [
                BoxShadow(color: _purple.withValues(alpha: .42), blurRadius: 24)
              ]),
          child: const Icon(Icons.add_rounded, size: 34, color: Colors.white),
        ));
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline();
  @override
  Widget build(BuildContext context) => Container(height: 1, color: _stroke);
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, this.size = 6});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: .45), blurRadius: 8)
          ]));
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => IgnorePointer(
      child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                color.withValues(alpha: .18),
                color.withValues(alpha: .04),
                Colors.transparent
              ]))));
}

class _NavSpec {
  const _NavSpec(this.icon, this.label);
  final IconData icon;
  final String label;
}

class _RunDetailPage extends StatelessWidget {
  const _RunDetailPage(
      {required this.onBack, required this.data, required this.client});
  final VoidCallback onBack;
  final _AppSnapshot data;
  final DaemonClient client;

  @override
  Widget build(BuildContext context) {
    return _PageScroll(children: [
      _TopBar(title: '运行详情', leading: true, action: '⋯'),
      const SizedBox(height: 14),
      const _GlassCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text('修复登录接口测试失败',
                  style: TextStyle(fontWeight: FontWeight.w800))),
          _StatusBadge('运行中', color: _green)
        ]),
        SizedBox(height: 8),
        Row(children: [
          _AgentIcon(color: _orange),
          SizedBox(width: 6),
          Text('Claude Code', style: TextStyle(color: _muted, fontSize: 12))
        ]),
        SizedBox(height: 8),
        Text('10:32 开始 · 运行时长 12m 45s',
            style: TextStyle(color: _muted, fontSize: 12)),
      ])),
      const SizedBox(height: 14),
      const _Tabs(labels: ['概览', '事件', '文件变更', '配置']),
      const SizedBox(height: 12),
      const _Timeline('用户提示', '修复登录接口测试失败，并添加边界条件测试。', '10:32',
          Icons.person_rounded, _purple),
      const _Timeline('Claude 开始思考', '正在分析问题和相关代码...', '10:32',
          Icons.auto_awesome_rounded, _purple),
      const _Timeline('读取文件', 'tests/login_test.dart                 +128 -45',
          '10:33', Icons.file_open_rounded, _green),
      const _Timeline('搜索代码', 'search: "login failure test"\n找到 12 个结果',
          '10:34', Icons.search_rounded, _muted),
      const _Timeline('编辑文件', 'lib/services/auth_service.dart       +32 -8',
          '10:35', Icons.edit_document, _green),
      const _Timeline('运行命令', 'dart test tests/login_test.dart      运行中 ●',
          '10:36', Icons.terminal_rounded, _green),
      const SizedBox(height: 8),
      _GhostButton('返回', color: _purple, onTap: onBack),
    ]);
  }
}

class _ApprovalPage extends StatelessWidget {
  const _ApprovalPage({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return _PageScroll(children: [
      _TopBar(title: '需要你审批', leading: true, action: '⋯'),
      const SizedBox(height: 14),
      const _GlassCard(
          child: Row(children: [
        Icon(Icons.warning_amber_rounded, color: _amber),
        SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('修改文件', style: TextStyle(fontWeight: FontWeight.w800)),
          SizedBox(height: 6),
          Text('lib/services/auth_service.dart     +32 -8',
              style: TextStyle(color: _muted, fontSize: 12))
        ])),
        Text('10:35', style: TextStyle(color: _muted, fontSize: 12))
      ])),
      const SizedBox(height: 12),
      const _Tabs(labels: ['差异', '文件内容']),
      const SizedBox(height: 10),
      const _CodeDiff(),
      const SizedBox(height: 18),
      const _SectionTitle('审批操作'),
      const _GlassCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Claude 建议的变更', style: TextStyle(fontWeight: FontWeight.w800)),
        SizedBox(height: 8),
        Text('修复空响应导致的测试失败问题', style: TextStyle(color: _muted, fontSize: 12))
      ])),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _GhostButton('拒绝', color: _red, onTap: onBack)),
        const SizedBox(width: 10),
        Expanded(child: _PrimaryButton('批准', onTap: onBack))
      ]),
    ]);
  }
}

class _AdaptersPage extends StatelessWidget {
  const _AdaptersPage({required this.onBack, required this.data});
  final VoidCallback onBack;
  final _AppSnapshot data;

  @override
  Widget build(BuildContext context) => _PageScroll(children: [
        _TopBar(
            title: '适配器状态', leading: true, action: '${data.adapters.length} 个'),
        const SizedBox(height: 14),
        if (data.adapters.isEmpty)
          const _GlassCard(
              child: Text('daemon 未返回适配器', style: TextStyle(color: _muted)))
        else
          for (final adapter in data.adapters)
            _AdapterRow(adapter.adapter, adapter.statusText,
                _displayVersion(adapter.version), _toolColor(adapter.adapter)),
        const SizedBox(height: 16),
        const _Subhead('扩展'),
        if (data.extensions.isEmpty)
          const _GlassCard(
              child: Text('暂无扩展信息', style: TextStyle(color: _muted)))
        else
          for (final extension in data.extensions)
            _AdapterRow(
                extension.name,
                extension.description,
                extension.installed ? extension.status : 'not installed',
                _purple),
        const SizedBox(height: 16),
        _PrimaryButton('返回', onTap: onBack),
      ]);
}

class _NotificationsPage extends StatelessWidget {
  const _NotificationsPage({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => _PageScroll(children: [
        _TopBar(title: '通知', leading: true, action: '⋯'),
        const SizedBox(height: 14),
        const _Tabs(labels: ['全部', '未读', '@我']),
        const SizedBox(height: 12),
        const _Notice(
            Icons.warning_rounded,
            '需要审批',
            'Claude Code 请求修改\nlib/services/auth_service.dart',
            '10:58',
            _amber),
        const _Notice(
            Icons.done_rounded,
            '任务完成',
            'Add unit tests for user service\n运行完成，耗时 28m 15s',
            '09:44',
            _green),
        const _Notice(Icons.error_rounded, '任务失败', '优化数据同步逻辑\n运行失败，查看详情',
            '昨天 14:22', _red),
        const _Notice(
            Icons.sync_rounded, '队列更新', '优化缓存策略\n已开始运行', '昨天 13:15', _purple),
        const _Notice(Icons.notifications_rounded, '系统消息', '已连接到 DESKTOP-DEV',
            '昨天 10:01', _purple),
        const SizedBox(height: 8),
        _GhostButton('返回', color: _purple, onTap: onBack),
      ]);
}

class _DiagnosticsPage extends StatelessWidget {
  const _DiagnosticsPage(
      {required this.onBack, required this.data, required this.client});
  final VoidCallback onBack;
  final _AppSnapshot data;
  final DaemonClient client;

  @override
  Widget build(BuildContext context) => _PageScroll(children: [
        _TopBar(title: '诊断信息', leading: true, action: '⋯'),
        const SizedBox(height: 10),
        const Text('导出诊断包用于问题排查（已脱敏）',
            style: TextStyle(color: _muted, fontSize: 12)),
        const SizedBox(height: 14),
        const _GlassCard(
            child: Column(children: [
          _DiagRow('系统信息', '1.2 KB'),
          _Hairline(),
          _DiagRow('适配器状态', '2.4 KB'),
          _Hairline(),
          _DiagRow('运行日志 (最近 7 天)', '512 KB'),
          _Hairline(),
          _DiagRow('事件记录 (最近 7 天)', '3.1 MB'),
          _Hairline(),
          _DiagRow('配置信息', '1.8 KB')
        ])),
        const SizedBox(height: 18),
        const Row(children: [
          Text('预计大小', style: TextStyle(color: _muted, fontSize: 12)),
          Spacer(),
          Text('5.1 MB', style: TextStyle(fontWeight: FontWeight.w800))
        ]),
        const SizedBox(height: 18),
        _PrimaryButton('生成诊断包', onTap: onBack),
      ]);
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

class _Timeline extends StatelessWidget {
  const _Timeline(this.title, this.body, this.time, this.icon, this.color);
  final String title, body, time;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => _GlassCard(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
                shape: BoxShape.circle, color: color.withValues(alpha: .18)),
            child: Icon(icon, color: color, size: 15)),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 7),
          Text(body,
              style: const TextStyle(color: _muted, fontSize: 12, height: 1.45))
        ])),
        Text(time, style: const TextStyle(color: _muted, fontSize: 12))
      ]));
}

class _CodeDiff extends StatelessWidget {
  const _CodeDiff();
  @override
  Widget build(BuildContext context) => _GlassCard(
      child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: const Color(0xFF081018),
              borderRadius: BorderRadius.circular(6)),
          child: const Text(
              '@@ -48,7 +48,13 @@ Future<User?> login(String email)\n\n-  throw Exception(\'Login failed\');\n+  // 处理边界情况\n+  if (response.body == null ||\n+      response.body.isEmpty) {\n+    throw Exception(\'Empty response\');\n+  }\n+\n   final data = jsonDecode(response.body);',
              style: TextStyle(
                  fontFamily: 'monospace',
                  color: Color(0xFF66E69A),
                  fontSize: 11,
                  height: 1.55))));
}

class _ApprovalPreview extends StatelessWidget {
  const _ApprovalPreview({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      child: const _GlassCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.warning_amber_rounded, color: _amber, size: 18),
          SizedBox(width: 8),
          Text('需要你审批', style: TextStyle(fontWeight: FontWeight.w800)),
          Spacer(),
          Text('10:35', style: TextStyle(color: _muted, fontSize: 12))
        ]),
        SizedBox(height: 8),
        Text('修改文件', style: TextStyle(fontWeight: FontWeight.w800)),
        SizedBox(height: 4),
        Text('lib/services/auth_service.dart   +32 -8',
            style: TextStyle(color: _muted, fontSize: 12))
      ])));
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton(this.text, {required this.onTap});
  final String text;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_purple, _purple2]),
              borderRadius: BorderRadius.circular(8)),
          child:
              Text(text, style: const TextStyle(fontWeight: FontWeight.w900))));
}

class _GhostButton extends StatelessWidget {
  const _GhostButton(this.text, {required this.color, required this.onTap});
  final String text;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: .35))),
          child: Text(text,
              style: TextStyle(color: color, fontWeight: FontWeight.w900))));
}

class _AdapterRow extends StatelessWidget {
  const _AdapterRow(this.name, this.protocol, this.version, this.color);
  final String name, protocol, version;
  final Color color;
  @override
  Widget build(BuildContext context) => _GlassCard(
          child: Row(children: [
        _AgentIcon(color: color),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('状态                         正常\n能力\n$protocol',
              style: const TextStyle(color: _muted, fontSize: 12, height: 1.45))
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(version, style: const TextStyle(color: _muted, fontSize: 12)),
          const SizedBox(height: 8),
          const _Dot(color: _green, size: 5)
        ])
      ]));
}

class _Notice extends StatelessWidget {
  const _Notice(this.icon, this.title, this.body, this.time, this.color);
  final IconData icon;
  final String title, body, time;
  final Color color;
  @override
  Widget build(BuildContext context) => _GlassCard(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            width: 25,
            height: 25,
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(7),
                color: color.withValues(alpha: .22)),
            child: Icon(icon, color: color, size: 16)),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(body,
              style: const TextStyle(color: _muted, fontSize: 12, height: 1.45))
        ])),
        Text(time, style: const TextStyle(color: _muted, fontSize: 12))
      ]));
}

class _DiagRow extends StatelessWidget {
  const _DiagRow(this.title, this.size);
  final String title, size;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(children: [
        const Icon(Icons.check_circle_rounded, color: _green, size: 17),
        const SizedBox(width: 9),
        Expanded(
            child: Text(title,
                style: const TextStyle(fontWeight: FontWeight.w800))),
        Text(size, style: const TextStyle(color: _muted, fontSize: 12))
      ]));
}
