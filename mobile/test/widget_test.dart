import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/lan_ai_cli_control.dart';
import 'package:lan_ai_cli_control/l10n/app_localizations.dart';
import 'package:lan_ai_cli_control/src/app/app_localization.dart';
import 'package:lan_ai_cli_control/src/app/language_controller.dart';
import 'package:lan_ai_cli_control/src/app/language_mode.dart';
import 'package:lan_ai_cli_control/src/app/language_scope.dart';
import 'package:lan_ai_cli_control/src/features/sessions/sessions.dart';
import 'package:lan_ai_cli_control/src/features/settings/settings_page.dart'
    as settings_feature;
import 'package:lan_ai_cli_control/src/features/workspace_picker/workspace_picker_sheet.dart';
import 'package:lan_ai_cli_control/src/services/daemon_connection_config.dart';
import 'package:lan_ai_cli_control/src/services/daemon_connection_config_store.dart';
import 'package:lan_ai_cli_control/src/shell/app_snapshot.dart';
import 'package:lan_ai_cli_control/src/state/daemon_connection_controller.dart';
import 'package:lan_ai_cli_control/src/theme/theme.dart' as theme;
import 'package:lan_ai_cli_control/src/widgets/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _LocalizedSettingsLabelApp extends StatefulWidget {
  const _LocalizedSettingsLabelApp();

  @override
  State<_LocalizedSettingsLabelApp> createState() =>
      _LocalizedSettingsLabelAppState();
}

class _LocalizedSettingsLabelAppState
    extends State<_LocalizedSettingsLabelApp> {
  late final LanguageController _languageController;

  @override
  void initState() {
    super.initState();
    _languageController = LanguageController()..load();
  }

  @override
  void dispose() {
    _languageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _languageController,
      builder: (context, _) => LanguageScope(
          controller: _languageController,
          child: MaterialApp(
              locale: _languageController.locale,
              supportedLocales: appSupportedLocales,
              localizationsDelegates: appLocalizationsDelegates,
              localeResolutionCallback: (locale, supportedLocales) =>
                  resolveSupportedLocale(locale, supportedLocales),
              home: Builder(
                  builder: (context) =>
                      Text(AppLocalizations.of(context).navSettings)))));
}

class _LocalizedSettingsPageApp extends StatefulWidget {
  const _LocalizedSettingsPageApp();

  @override
  State<_LocalizedSettingsPageApp> createState() =>
      _LocalizedSettingsPageAppState();
}

class _LocalizedSettingsPageAppState extends State<_LocalizedSettingsPageApp> {
  late final LanguageController _languageController;

  @override
  void initState() {
    super.initState();
    _languageController = LanguageController()..load();
  }

  @override
  void dispose() {
    _languageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _languageController,
      builder: (context, _) => LanguageScope(
          controller: _languageController,
          child: MaterialApp(
              locale: _languageController.locale,
              supportedLocales: appSupportedLocales,
              localizationsDelegates: appLocalizationsDelegates,
              localeResolutionCallback: (locale, supportedLocales) =>
                  resolveSupportedLocale(locale, supportedLocales),
              home: Scaffold(
                  body: settings_feature.SettingsPage(
                      open: (_) {},
                      data: _testSnapshot(),
                      connectionConfig: const DaemonConnectionConfig(
                          addressInput: '192.168.1.20:4317',
                          proxyMode: DaemonProxyMode.manual,
                          manualProxyInput: 'http://proxy.local:8080'),
                      streamOutput: false,
                      expandThinking: false,
                      permissionMode: 'default',
                      onPermissionModeChanged: (_) {},
                      onStreamOutputChanged: (_) {},
                      onExpandThinkingChanged: (_) {})))));
}

class _LocalizedHomePageApp extends StatefulWidget {
  const _LocalizedHomePageApp({this.snapshot});

  final AppSnapshot? snapshot;

  @override
  State<_LocalizedHomePageApp> createState() => _LocalizedHomePageAppState();
}

class _LocalizedHomePageAppState extends State<_LocalizedHomePageApp> {
  late final LanguageController _languageController;

  @override
  void initState() {
    super.initState();
    _languageController = LanguageController()..load();
  }

  @override
  void dispose() {
    _languageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _languageController,
      builder: (context, _) => LanguageScope(
          controller: _languageController,
          child: MaterialApp(
              locale: _languageController.locale,
              supportedLocales: appSupportedLocales,
              localizationsDelegates: appLocalizationsDelegates,
              localeResolutionCallback: (locale, supportedLocales) =>
                  resolveSupportedLocale(locale, supportedLocales),
              home: Scaffold(
                  body: HomePage(
                      open: (_) {},
                      selectTab: (_) {},
                      data: widget.snapshot ?? _testSnapshot())))));
}

class _MainTabsHarness extends StatefulWidget {
  const _MainTabsHarness({required this.client});

  final DaemonClient client;

  @override
  State<_MainTabsHarness> createState() => _MainTabsHarnessState();
}

class _MainTabsHarnessState extends State<_MainTabsHarness> {
  late final LanguageController _languageController;

  @override
  void initState() {
    super.initState();
    _languageController = LanguageController()..load();
  }

  @override
  void dispose() {
    _languageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _languageController,
      builder: (context, _) => LanguageScope(
          controller: _languageController,
          child: MaterialApp(
              locale: _languageController.locale,
              supportedLocales: appSupportedLocales,
              localizationsDelegates: appLocalizationsDelegates,
              localeResolutionCallback: (locale, supportedLocales) =>
                  resolveSupportedLocale(locale, supportedLocales),
              theme: theme.buildAppTheme(),
              home: MainTabsPage(
                  data: _testSnapshot(),
                  client: widget.client,
                  connectionConfig: const DaemonConnectionConfig(
                      addressInput: '127.0.0.1:4317',
                      proxyMode: DaemonProxyMode.system,
                      manualProxyInput: '')))));
}

class _AdapterRefreshClient extends DaemonClient {
  _AdapterRefreshClient()
      : super(
            baseUri: Uri.parse('http://127.0.0.1:4317'),
            tokenStore: MemoryTokenStore());

  int listAdaptersCalls = 0;

  @override
  Future<List<AdapterStatus>> listAdapters() async {
    listAdaptersCalls++;
    return const <AdapterStatus>[
      AdapterStatus(adapter: 'codex', available: true, status: 'available'),
      AdapterStatus(
          adapter: 'synthetic-jsonl',
          available: true,
          status: 'available',
          version: 'synthetic'),
      AdapterStatus(
          adapter: 'synthetic-text',
          available: true,
          status: 'available',
          version: 'synthetic')
    ];
  }
}

class _PendingAdapterClient extends DaemonClient {
  _PendingAdapterClient()
      : super(
            baseUri: Uri.parse('http://127.0.0.1:4317'),
            tokenStore: MemoryTokenStore());

  int listAdaptersCalls = 0;
  Completer<List<AdapterStatus>> adaptersCompleter =
      Completer<List<AdapterStatus>>();

  @override
  Future<List<AdapterStatus>> listAdapters() {
    listAdaptersCalls++;
    return adaptersCompleter.future;
  }

  void completeWithAdapters() {
    adaptersCompleter.complete(const <AdapterStatus>[
      AdapterStatus(adapter: 'codex', available: true, status: 'available'),
    ]);
  }

  void completeWithError() {
    adaptersCompleter.completeError(Exception('adapter probe failed'));
  }

  void resetCompleter() {
    adaptersCompleter = Completer<List<AdapterStatus>>();
  }
}

AppSnapshot _testSnapshot({
  List<WorkspaceSummary>? workspaces,
  List<RunSummary> runs = const <RunSummary>[],
  List<ConversationSummary> conversations = const <ConversationSummary>[],
  List<QueueItem> queue = const <QueueItem>[],
  List<RecentFileSummary> recentFiles = const <RecentFileSummary>[],
  GitStatusSummary? gitStatus,
  CodeDiagnosticsSummary diagnostics = const CodeDiagnosticsSummary(
      workspaceId: 'workspace_1',
      available: true,
      diagnostics: <CodeDiagnostic>[]),
}) {
  const workspace = WorkspaceSummary(
      id: 'workspace_1',
      name: 'Current Project',
      path: r'D:\AiProject\vibe-coding');
  final resolvedWorkspaces = workspaces ?? const <WorkspaceSummary>[workspace];
  return AppSnapshot(
      health: DaemonHealth.fromJson(const <String, Object?>{
        'status': 'ok',
        'daemonVersion': 'test',
        'mode': 'test',
        'lanMode': false,
        'bindAddress': '127.0.0.1',
        'port': 4317,
        'security': {'tokenRequired': false}
      }),
      workspaces: resolvedWorkspaces,
      workspace: workspace,
      overview: ProjectOverview(
          workspaceId: 'workspace_1',
          name: 'vibe-coding',
          path: r'D:\AiProject\vibe-coding',
          fileCount: 0,
          codeLineCount: 0,
          symbolCount: 0,
          analysisScore: 0,
          recentFiles: recentFiles),
      adapters: const <AdapterStatus>[],
      runs: runs,
      conversations: conversations,
      queue: queue,
      templates: const <CommandTemplate>[],
      gitStatus: gitStatus ??
          const GitStatusSummary(
              workspaceId: 'workspace_1',
              clean: true,
              files: <GitStatusFile>[]),
      diffs: const <DiffSummary>[],
      commits: const <GitCommitSummary>[],
      fileTree: const FileTreeResponse(
          workspaceId: 'workspace_1', root: '', entries: <FileTreeEntry>[]),
      diagnostics: diagnostics,
      extensions: const <ExtensionSummary>[]);
}

ConversationSummary _conversationSummary({
  required String id,
  required String workspaceId,
  required String status,
  String? cliSessionId,
  String sessionBinding = 'unknown',
  int userMessageCount = 0,
  ConversationCapabilities? capabilities,
  ConversationBlockingItem? blockingItem,
}) =>
    ConversationSummary(
      id: id,
      workspaceId: workspaceId,
      adapter: 'codex',
      status: status,
      cliSessionId: cliSessionId,
      sessionBinding: sessionBinding,
      userMessageCount: userMessageCount,
      capabilities: capabilities ??
          ConversationCapabilities.fromJson(const <String, Object?>{}),
      createdAt: '2026-05-06T10:00:00.000Z',
      updatedAt: '2026-05-06T10:01:00.000Z',
      blockingItem: blockingItem,
    );

void main() {
  testWidgets('app renders English when forced to English',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});

    await tester.pumpWidget(const _LocalizedSettingsLabelApp());
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsWidgets);
  });

  testWidgets('app renders Chinese when forced to Simplified Chinese',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'zh-Hans-CN'});

    await tester.pumpWidget(const _LocalizedSettingsLabelApp());
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsWidgets);
  });

  testWidgets(
      'home command deck renders Chinese when forced to Simplified Chinese',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'zh-Hans-CN'});

    await tester.pumpWidget(const _LocalizedHomePageApp());
    await tester.pumpAndSettle();

    expect(find.text('当前焦点'), findsOneWidget);
    expect(find.text('当前工作区无阻塞'), findsOneWidget);
    expect(find.text('工作区信号'), findsOneWidget);
    expect(find.text('命令模板'), findsOneWidget);
    expect(find.text('已连接'), findsNothing);
    expect(find.text('vibe-coding'), findsOneWidget);
    expect(find.text('Command templates'), findsNothing);
    expect(find.text('Needs your approval'), findsNothing);
    expect(find.text('Modify file'), findsNothing);
    expect(find.text('online'), findsNothing);
  });

  testWidgets('home command deck hides connection controls',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});

    await tester.pumpWidget(const _LocalizedHomePageApp());
    await tester.pumpAndSettle();

    expect(find.text('Connected'), findsNothing);
    expect(find.text('127.0.0.1:4317'), findsNothing);
    expect(find.byIcon(Icons.qr_code_scanner_rounded), findsNothing);
  });

  testWidgets('home command deck shows overflow and deduplicates now item',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final snapshot = _testSnapshot(
      runs: const <RunSummary>[
        RunSummary(
            id: 'run_failed',
            tool: 'codex',
            workspaceId: 'workspace_1',
            status: 'failed'),
      ],
      conversations: <ConversationSummary>[
        _conversationSummary(
          id: 'conv_approval',
          workspaceId: 'workspace_1',
          status: 'waiting_approval',
          blockingItem: const ConversationBlockingItem(
            type: 'approval_request',
            approvalId: 'ap1',
            summary: 'Modify file',
          ),
        ),
      ],
    );

    await tester.pumpWidget(_LocalizedHomePageApp(snapshot: snapshot));
    await tester.pumpAndSettle();

    expect(find.text('+1 more'), findsOneWidget);
    expect(find.text('Modify file'), findsOneWidget);
    expect(find.textContaining('run_failed'), findsOneWidget);
  });

  testWidgets(
      'home command deck shows other workspace running only while current is idle',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final snapshot = _testSnapshot(
      workspaces: const <WorkspaceSummary>[
        WorkspaceSummary(
            id: 'workspace_1',
            name: 'Current Project',
            path: r'D:\AiProject\vibe-coding'),
        WorkspaceSummary(
            id: 'workspace_2', name: 'daemon', path: r'D:\AiProject\daemon'),
      ],
      runs: const <RunSummary>[
        RunSummary(
            id: 'run_other',
            tool: 'claude',
            workspaceId: 'workspace_2',
            status: 'running'),
      ],
    );

    await tester.pumpWidget(_LocalizedHomePageApp(snapshot: snapshot));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -260));
    await tester.pumpAndSettle();

    expect(find.textContaining('daemon'), findsWidgets);
  });

  testWidgets('settings language picker shows self-identifying language names',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});

    await tester.pumpWidget(const _LocalizedSettingsPageApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();

    expect(find.text('System default'), findsOneWidget);
    expect(find.text('简体中文'), findsOneWidget);
    expect(find.text('English'), findsWidgets);
  });

  testWidgets('settings shows active daemon address and proxy mode',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});

    await tester.pumpWidget(const _LocalizedSettingsPageApp());
    await tester.pumpAndSettle();

    expect(find.text('Daemon address'), findsOneWidget);
    expect(find.text('192.168.1.20:4317'), findsOneWidget);
    expect(find.text('Proxy mode'), findsOneWidget);
    expect(find.text('Manual proxy'), findsOneWidget);
  });

  testWidgets('renders assistant markdown instead of raw syntax',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildAssistantMarkdownPreview(
        'Hello\n\n- **Code and debug**\n- `inline code`\n\n<script>alert(1)</script>'));
    await tester.pumpAndSettle();

    expect(find.text('Code and debug'), findsOneWidget);
    expect(find.text('inline code'), findsOneWidget);
    expect(find.textContaining('**Code and debug**'), findsNothing);
    expect(find.textContaining('<script>'), findsNothing);
  });

  testWidgets('app starts on editable connection page without bottom nav',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(const LanAiCliControlApp());
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Connection'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('System proxy'), findsOneWidget);
    expect(find.byType(BottomNav), findsNothing);
  });

  testWidgets(
      'connection page renders Chinese when forced to Simplified Chinese',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'zh-Hans-CN'});

    await tester.pumpWidget(const LanAiCliControlApp());
    await tester.pumpAndSettle();

    expect(find.text('\u8fde\u63a5'), findsWidgets);
    expect(find.text('\u8fde\u63a5\u5730\u5740'), findsOneWidget);
    expect(find.text('\u7f51\u7edc\u4ee3\u7406'), findsOneWidget);
    expect(find.text('\u76f4\u8fde'), findsWidgets);
    expect(find.text('\u672a\u8fde\u63a5'), findsOneWidget);
    expect(find.text('\u76ee\u6807'), findsOneWidget);
    expect(find.text('\u4ee3\u7406'), findsOneWidget);
    expect(find.text('Connection'), findsNothing);
    expect(find.text('Network proxy'), findsNothing);
    expect(find.text('Not connected'), findsNothing);
  });

  testWidgets('connection page keeps address and proxy editable after failure',
      (WidgetTester tester) async {
    final controller = DaemonConnectionController(
      store: DaemonConnectionConfigStore(),
      tokenStore: MemoryTokenStore(),
      snapshotLoader: (_) async => throw StateError('not used'),
      healthProbe: (_) async {
        throw const DaemonClientException(502, <String, Object?>{
          'error': 'invalid_response',
          'message': 'daemon returned an empty response body',
        });
      },
    );
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await controller.load();

    await tester.pumpWidget(MaterialApp(
      supportedLocales: appSupportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
      localeResolutionCallback: (locale, supportedLocales) =>
          resolveSupportedLocale(locale, supportedLocales),
      theme: theme.buildAppTheme(),
      home: MobileConnectionPage(controller: controller),
    ));

    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(find.text('Connection failed'), findsOneWidget);
    expect(find.textContaining('proxy or gateway'), findsOneWidget);
    expect(find.byType(TextField), findsWidgets);
    expect(find.text('System proxy'), findsOneWidget);
    expect(find.text('Manual proxy'), findsOneWidget);
    expect(find.text('Reconnect'), findsOneWidget);
    expect(find.byType(BottomNav), findsNothing);
  });

  testWidgets('MobileUiFrame renders supplied child',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MobileUiFrame(child: Text('frame child')),
    ));

    expect(find.text('frame child'), findsOneWidget);
  });

  testWidgets('coding composer exposes voice input semantics',
      (WidgetTester tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CodingComposer(
                controller: controller,
                adapter: 'codex',
                workspace: const WorkspaceSummary(
                    id: 'workspace_1',
                    name: 'Current Project',
                    path: r'D:\AiProject\vibe-coding'),
                running: false,
                canSend: false,
                sending: false,
                voiceState: VoiceInputState.idle,
                voiceEnabled: true,
                voiceError: null,
                onModelTap: () {},
                onVoiceStart: () {},
                onVoiceStop: () {},
                onVoiceCancel: () {},
                onTextChanged: (_) {},
                onSend: () {},
                onCancel: () {}))));

    expect(find.bySemanticsLabel('Voice input'), findsOneWidget);
  });

  testWidgets('coding composer does not send when voice pointer is released',
      (WidgetTester tester) async {
    var sends = 0;
    final controller = TextEditingController(text: 'hello');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CodingComposer(
                controller: controller,
                adapter: 'codex',
                workspace: const WorkspaceSummary(
                    id: 'workspace_1',
                    name: 'Current Project',
                    path: r'D:\AiProject\vibe-coding'),
                running: false,
                canSend: true,
                sending: false,
                voiceState: VoiceInputState.listening,
                voiceEnabled: true,
                voiceError: null,
                onModelTap: () {},
                onVoiceStart: () {},
                onVoiceStop: () {},
                onVoiceCancel: () {},
                onTextChanged: (_) {},
                onSend: () => sends++,
                onCancel: () {}))));

    await tester.tap(find.bySemanticsLabel('Voice input'));
    await tester.pumpAndSettle();

    expect(sends, 0);
  });

  testWidgets('coding composer shows listening state while recording',
      (WidgetTester tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CodingComposer(
                controller: controller,
                adapter: 'codex',
                workspace: const WorkspaceSummary(
                    id: 'workspace_1',
                    name: 'Current Project',
                    path: r'D:\AiProject\vibe-coding'),
                running: false,
                canSend: false,
                sending: false,
                voiceState: VoiceInputState.listening,
                voiceEnabled: true,
                voiceError: null,
                onModelTap: () {},
                onVoiceStart: () {},
                onVoiceStop: () {},
                onVoiceCancel: () {},
                onTextChanged: (_) {},
                onSend: () {},
                onCancel: () {}))));

    expect(find.textContaining('Listening'), findsOneWidget);
  });

  testWidgets('coding composer reports text edits while voice is listening',
      (WidgetTester tester) async {
    String? editedText;
    final controller = TextEditingController();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CodingComposer(
                controller: controller,
                adapter: 'codex',
                workspace: const WorkspaceSummary(
                    id: 'workspace_1',
                    name: 'Current Project',
                    path: r'D:\AiProject\vibe-coding'),
                running: false,
                canSend: false,
                sending: false,
                voiceState: VoiceInputState.listening,
                voiceEnabled: true,
                voiceError: null,
                onModelTap: () {},
                onVoiceStart: () {},
                onVoiceStop: () {},
                onVoiceCancel: () {},
                onTextChanged: (text) => editedText = text,
                onSend: () {},
                onCancel: () {}))));

    await tester.enterText(find.byType(TextField), 'manual edit');

    expect(editedText, 'manual edit');
  });

  testWidgets('coding composer does not render voice errors inline',
      (WidgetTester tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CodingComposer(
                controller: controller,
                adapter: 'codex',
                workspace: const WorkspaceSummary(
                    id: 'workspace_1',
                    name: 'Current Project',
                    path: r'D:\AiProject\vibe-coding'),
                running: false,
                canSend: false,
                sending: false,
                voiceState: VoiceInputState.failed,
                voiceEnabled: true,
                voiceError: '未检测到可用麦克风，请连接或启用录音设备后重试。',
                onModelTap: () {},
                onVoiceStart: () {},
                onVoiceStop: () {},
                onVoiceCancel: () {},
                onTextChanged: (_) {},
                onSend: () {},
                onCancel: () {}))));

    expect(find.textContaining('未检测到可用麦克风'), findsNothing);
  });

  testWidgets('coding back target renders workspace list',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildCodingSessionListPreview());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('workspace-list')), findsOneWidget);
    expect(find.text('Current Project'), findsOneWidget);
    expect(find.text('Other Project'), findsOneWidget);
  });

  testWidgets('coding entry defaults to workspace list',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildCodingWorkbenchEntryPreview());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('workspace-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('coding-session-list')), findsNothing);
    expect(find.byKey(const ValueKey('coding-workbench-detail')), findsNothing);
  });

  testWidgets('connected app preloads adapters before new session',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final client = _AdapterRefreshClient();

    await tester.pumpWidget(_MainTabsHarness(client: client));
    await tester.pumpAndSettle();

    expect(client.listAdaptersCalls, 1);

    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();

    expect(client.listAdaptersCalls, 1);

    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New Session'));
    await tester.pumpAndSettle();

    expect(find.text('codex'), findsWidgets);
    expect(find.text('No available CLI adapter'), findsNothing);

    await tester.tap(find.text('codex').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('adapter-picker-sheet')), findsOneWidget);
    expect(find.text('synthetic-jsonl'), findsNothing);
    expect(find.text('synthetic-text'), findsNothing);
  });

  testWidgets('coding waits for pending adapter preload',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final client = _PendingAdapterClient();

    await tester.pumpWidget(_MainTabsHarness(client: client));
    await tester.pump();

    expect(client.listAdaptersCalls, 1);

    await tester.tap(find.text('Coding'));
    await tester.pump();

    expect(find.text('Loading CLI...'), findsOneWidget);
    expect(find.byKey(const ValueKey('workspace-list')), findsNothing);
    expect(find.byKey(const ValueKey('coding-session-list')), findsNothing);
    expect(find.text('New Session'), findsNothing);
    expect(client.listAdaptersCalls, 1);

    client.completeWithAdapters();
    await tester.pumpAndSettle();

    expect(find.text('Loading CLI...'), findsNothing);
    expect(find.byKey(const ValueKey('workspace-list')), findsOneWidget);
  });

  testWidgets('coding adapter preload failure can retry',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final client = _PendingAdapterClient();

    await tester.pumpWidget(_MainTabsHarness(client: client));
    await tester.pump();
    client.completeWithError();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();

    expect(find.text('Unable to load CLI adapters'), findsOneWidget);
    expect(find.text('Retry loading CLI'), findsOneWidget);

    client.resetCompleter();
    await tester.tap(find.text('Retry loading CLI'));
    await tester.pump();

    expect(find.text('Loading CLI...'), findsOneWidget);
    expect(client.listAdaptersCalls, 2);

    client.completeWithAdapters();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('workspace-list')), findsOneWidget);
    expect(find.text('Unable to load CLI adapters'), findsNothing);
  });

  testWidgets('adapter picker scrolls on compact screens',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(375, 440);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
        theme: theme.buildAppTheme(),
        home: Scaffold(
            backgroundColor: theme.bg,
            body: AdapterPickerSheet(
                selected: 'codex',
                onSelected: (_) {},
                adapters: const <AdapterStatus>[
                  AdapterStatus(
                      adapter: 'claude',
                      available: true,
                      status: 'available',
                      version: '2.1.112 (Claude Code)'),
                  AdapterStatus(
                      adapter: 'codex',
                      available: true,
                      status: 'available',
                      version: 'codex-cli 0.128.0'),
                  AdapterStatus(
                      adapter: 'opencode',
                      available: true,
                      status: 'available',
                      version: '0.9.0'),
                  AdapterStatus(
                      adapter: 'custom-a',
                      available: true,
                      status: 'available',
                      version: '1.0.0'),
                  AdapterStatus(
                      adapter: 'custom-b',
                      available: true,
                      status: 'available',
                      version: '1.0.0'),
                ]))));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('adapter-picker-sheet')), findsOneWidget);
  });

  testWidgets('tapping current project opens workspace session list',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildCodingWorkbenchEntryPreview());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('coding-session-list')), findsOneWidget);
    expect(find.textContaining(RegExp('New Session|\u65b0\u5efa\u4f1a\u8bdd')),
        findsOneWidget);
    expect(find.text('Select workspace for this coding session'), findsNothing);
  });

  testWidgets('returning to coding tab shows workspace list',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    await tester.pumpWidget(_MainTabsHarness(client: _AdapterRefreshClient()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('coding-session-list')), findsOneWidget);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('workspace-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('coding-session-list')), findsNothing);
  });

  testWidgets('system back walks coding nested navigator before home',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    await tester.pumpWidget(_MainTabsHarness(client: _AdapterRefreshClient()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New Session'));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('coding-workbench-detail')), findsOneWidget);
    expect(find.byType(BottomNav), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('coding-session-list')), findsOneWidget);
    expect(find.byType(BottomNav), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('workspace-list')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Current Project'), findsWidgets);
    expect(find.byKey(const ValueKey('workspace-list')), findsNothing);
  });

  testWidgets('system back returns conversation to sessions',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    await tester.pumpWidget(_MainTabsHarness(client: _AdapterRefreshClient()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New Session'));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('coding-workbench-detail')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('coding-session-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('coding-workbench-detail')), findsNothing);
  });

  testWidgets('new coding session title uses active locale',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildCodingWorkbenchEntryPreview());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();
    await tester.tap(
        find.textContaining(RegExp('New Session|\u65b0\u5efa\u4f1a\u8bdd')));
    await tester.pumpAndSettle();

    expect(find.text('新的编码会话'), findsOneWidget);
    expect(find.text('New coding session'), findsNothing);
  });

  testWidgets('session list shows only selected workspace sessions',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildWorkspaceScopedSessionPreview());
    await tester.pumpAndSettle();

    expect(find.textContaining('current-1'), findsWidgets);
    expect(find.textContaining('other-1'), findsNothing);
  });

  testWidgets('missing selected workspace falls back to workspace list',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildMissingWorkspaceFallbackPreview());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('workspace-list')), findsOneWidget);
    expect(find.text('Current Project'), findsOneWidget);
    expect(find.text('Stale Workspace'), findsNothing);
  });

  test('newly created coding runs appear before snapshot runs', () {
    const created = RunSummary(
        id: 'run_created',
        tool: 'claude',
        workspaceId: 'workspace_1',
        status: 'running');
    const staleCreated = RunSummary(
        id: 'run_created',
        tool: 'claude',
        workspaceId: 'workspace_1',
        status: 'completed');
    const older = RunSummary(
        id: 'run_older',
        tool: 'codex',
        workspaceId: 'workspace_1',
        status: 'completed');

    expect(
        debugMergeSessionRunIds(const <RunSummary>[created],
            const <RunSummary>[staleCreated, older]),
        const <String>['run_created', 'run_older']);
  });

  test('persisted coding conversations appear after Flutter restart', () {
    const local = RunSummary(
        id: 'conv_local',
        tool: 'claude',
        workspaceId: 'workspace_1',
        status: 'running');
    const persisted = ConversationSummary(
        id: 'conv_persisted',
        workspaceId: 'workspace_1',
        adapter: 'claude',
        status: 'interrupted',
        capabilities: ConversationCapabilities(
            longLivedProcess: true,
            waitingInput: true,
            waitingApproval: true,
            resume: true,
            partialOutput: true),
        createdAt: '2026-05-03T00:00:00.000Z',
        updatedAt: '2026-05-03T00:00:01.000Z',
        cliSessionId: 'claude-session');
    const emptyDraft = ConversationSummary(
        id: 'conv_empty',
        workspaceId: 'workspace_1',
        adapter: 'claude',
        status: 'idle',
        capabilities: ConversationCapabilities(
            longLivedProcess: true,
            waitingInput: true,
            waitingApproval: true,
            resume: true,
            partialOutput: true),
        createdAt: '2026-05-03T00:00:00.000Z',
        updatedAt: '2026-05-03T00:00:01.000Z');
    const legacyRun = RunSummary(
        id: 'run_legacy',
        tool: 'codex',
        workspaceId: 'workspace_1',
        status: 'completed');

    expect(
        debugMergeSessionIds(
            const <RunSummary>[local],
            const <ConversationSummary>[persisted, emptyDraft],
            const <RunSummary>[legacyRun]),
        const <String>['conv_local', 'conv_persisted', 'run_legacy']);
  });

  test(
      'cancelled failed and interrupted conversations stay conversation backed in session list',
      () {
    const capabilities = ConversationCapabilities(
      longLivedProcess: true,
      waitingInput: true,
      waitingApproval: true,
      resume: true,
      partialOutput: true,
    );
    final conversations = <ConversationSummary>[
      _conversationSummary(
        id: 'conv_cancelled',
        workspaceId: 'workspace_1',
        status: 'cancelled',
        cliSessionId: 'claude-session-1',
        sessionBinding: 'confirmed',
        capabilities: capabilities,
      ),
      _conversationSummary(
        id: 'conv_failed',
        workspaceId: 'workspace_1',
        status: 'failed',
        cliSessionId: 'claude-session-2',
        sessionBinding: 'confirmed',
        capabilities: capabilities,
      ),
      _conversationSummary(
        id: 'conv_interrupted',
        workspaceId: 'workspace_1',
        status: 'interrupted',
        sessionBinding: 'unknown',
        userMessageCount: 1,
        capabilities: capabilities,
      ),
    ];

    final items = mergeSessionItems(
      const <SessionItem>[],
      conversations,
      const <RunSummary>[],
    );

    expect(
      items.map((item) => item.id),
      <String>['conv_cancelled', 'conv_failed', 'conv_interrupted'],
    );
    expect(items.every((item) => item.conversation != null), isTrue);
    expect(items.last.run.status, 'interrupted');
  });

  test('idle empty draft without messages remains hidden from session list',
      () {
    final items = mergeSessionItems(
      const <SessionItem>[],
      <ConversationSummary>[
        _conversationSummary(
          id: 'conv_empty',
          workspaceId: 'workspace_1',
          status: 'idle',
          sessionBinding: 'unknown',
          userMessageCount: 0,
        ),
      ],
      const <RunSummary>[],
    );

    expect(items, isEmpty);
  });

  test('approval response resumes polling only for active conversations', () {
    const capabilities = ConversationCapabilities(
      longLivedProcess: true,
      waitingInput: true,
      waitingApproval: true,
      resume: true,
      partialOutput: true,
    );
    const running = ConversationSummary(
      id: 'conv_running',
      workspaceId: 'workspace_1',
      adapter: 'claude',
      status: 'running',
      capabilities: capabilities,
      createdAt: '2026-05-03T00:00:00.000Z',
      updatedAt: '2026-05-03T00:00:01.000Z',
    );
    const idle = ConversationSummary(
      id: 'conv_idle',
      workspaceId: 'workspace_1',
      adapter: 'claude',
      status: 'idle',
      capabilities: capabilities,
      createdAt: '2026-05-03T00:00:00.000Z',
      updatedAt: '2026-05-03T00:00:01.000Z',
    );

    expect(debugShouldPollAfterApproval(running), isTrue);
    expect(debugShouldPollAfterApproval(idle), isFalse);
  });

  test('historical sessions do not count as explicit workspace selection', () {
    expect(
        debugHasExplicitWorkspaceSelection(
          workspaceConfirmedForSession: false,
          activeRunId: null,
          hasLocalSessions: true,
        ),
        isFalse);
    expect(
        debugHasExplicitWorkspaceSelection(
          workspaceConfirmedForSession: true,
          activeRunId: null,
          hasLocalSessions: false,
        ),
        isTrue);
    expect(
        debugHasExplicitWorkspaceSelection(
          workspaceConfirmedForSession: false,
          activeRunId: 'conv_1',
          hasLocalSessions: false,
        ),
        isTrue);
  });

  test('approval cards only show the current blocking approval', () {
    const capabilities = ConversationCapabilities(
      longLivedProcess: true,
      waitingInput: true,
      waitingApproval: true,
      resume: true,
      partialOutput: true,
    );
    const conversation = ConversationSummary(
      id: 'conv_1',
      workspaceId: 'workspace_1',
      adapter: 'claude',
      status: 'waiting_approval',
      capabilities: capabilities,
      createdAt: '2026-05-03T00:00:00.000Z',
      updatedAt: '2026-05-03T00:00:02.000Z',
      blockingItem: ConversationBlockingItem(
        type: 'approval_request',
        approvalId: 'ap2',
        toolName: 'Bash',
        summary: 'python intro.py',
      ),
    );
    final events = <Map<String, Object?>>[
      const <String, Object?>{
        'seq': 1,
        'conversationId': 'conv_1',
        'type': 'approval.requested',
        'createdAt': '2026-05-03T00:00:00.000Z',
        'approvalId': 'ap1',
        'toolName': 'Write',
        'summary': r'C:\Users\W2830\intro.py'
      },
      const <String, Object?>{
        'seq': 2,
        'conversationId': 'conv_1',
        'type': 'approval.requested',
        'createdAt': '2026-05-03T00:00:01.000Z',
        'approvalId': 'ap2',
        'toolName': 'Bash',
        'summary': r'python intro.py'
      },
    ];

    expect(debugVisibleApprovalIdsForConversation(events, conversation),
        const <String>['ap2']);
  });

  testWidgets('running composer shows stop action instead of send',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildRunningComposerPreview());
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
  });

  testWidgets('new coding session workspace preview shows workspace list',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildNewSessionWorkspacePickerPreview());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('workspace-list')), findsOneWidget);
    expect(find.text('Current Project'), findsOneWidget);
  });

  test('workspace list presentation deduplicates duplicate paths', () {
    final visible = dedupeWorkspacesByPath(const <WorkspaceSummary>[
      WorkspaceSummary(
          id: 'workspace_a', name: 'Agent', path: r'D:\AiProject\Agent'),
      WorkspaceSummary(
          id: 'workspace_b', name: 'Agent copy', path: r'D:\AiProject\Agent'),
      WorkspaceSummary(
          id: 'workspace_c', name: 'cli-ui', path: r'D:\AiProject\cli-ui'),
    ]);

    expect(visible.map((workspace) => workspace.id),
        const <String>['workspace_a', 'workspace_c']);
  });

  testWidgets('workspace search placeholder uses active locale',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildNewSessionWorkspacePickerPreview());
    await tester.pumpAndSettle();

    expect(find.text('搜索会话、命令或文件路径...'), findsOneWidget);
    expect(find.text('Search sessions, commands, file paths...'), findsNothing);
  });

  testWidgets('add workspace sheet uses active locale',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
        locale: theme.zhHansCnLocale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        localeResolutionCallback: (locale, supportedLocales) =>
            resolveSupportedLocale(locale, supportedLocales),
        theme: theme.buildAppTheme(),
        home: Scaffold(
            body: AddWorkspaceSheet(
                client: DaemonClient(
                    baseUri: Uri.parse('http://127.0.0.1:4317'),
                    tokenStore: MemoryTokenStore())))));

    expect(find.text('添加工作区'), findsOneWidget);
    expect(find.text('浏览'), findsOneWidget);
    expect(find.text('选择或输入文件夹路径'), findsOneWidget);
    expect(find.text('名称（可选）'), findsOneWidget);
    expect(find.text('创建并使用'), findsOneWidget);
    expect(find.text('Add workspace'), findsNothing);
    expect(find.text('Browse'), findsNothing);
  });

  testWidgets('completed command card shows duration and success status icon',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildCompletedCommandCardPreview());
    await tester.pumpAndSettle();

    expect(find.text('npm run lint && npm test'), findsWidgets);
    expect(find.textContaining('执行 1 条命令'), findsOneWidget);
    expect(find.textContaining('cwd resolved'), findsOneWidget);
    expect(find.textContaining('2.1s'), findsOneWidget);
    expect(find.byKey(const ValueKey('tool-status-ok')), findsOneWidget);
  });

  testWidgets('command output opens a full detail sheet',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildConversationCommandCardPreview());
    await tester.pumpAndSettle();

    await tester.tap(find.text('hello from intro').first);
    await tester.pumpAndSettle();

    expect(find.text('输出详情'), findsOneWidget);
    expect(find.byTooltip('复制全文'), findsOneWidget);
    expect(find.text('hello from intro'), findsWidgets);
  });

  testWidgets(
      'pending sentinel is compact and does not show adapter or action list',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildPendingSentinelPreview());
    await tester.pump();

    expect(find.text('claude running'), findsNothing);
    expect(find.text('Claude requesting'), findsNothing);
  });

  testWidgets('thinking card title uses active locale',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
        locale: theme.zhHansCnLocale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        localeResolutionCallback: (locale, supportedLocales) =>
            resolveSupportedLocale(locale, supportedLocales),
        theme: theme.buildAppTheme(),
        home: Scaffold(
            backgroundColor: theme.bg,
            body: Padding(
                padding: const EdgeInsets.all(16),
                child: WorkbenchMessageCard(
                    message: const WorkbenchMessage(
                        'thinking', 'Thinking process', '正在分析上下文'),
                    onApproval: (_) {},
                    onSuggestion: (_) {},
                    expandThinking: false)))));

    expect(find.text('思考过程'), findsOneWidget);
    expect(find.text('Thinking process'), findsNothing);
  });

  test('conversation pending status text uses active locale', () {
    final event = ConversationEvent.fromJson(const <String, Object?>{
      'seq': 1,
      'conversationId': 'conv_1',
      'type': 'conversation.started',
      'createdAt': '2026-05-03T00:00:00.000Z',
    });

    expect(
        debugConversationPendingStatusText('running',
            locale: const Locale('zh', 'CN'),
            events: <ConversationEvent>[event]),
        'CLI 会话已启动，正在读取上下文...');
    expect(
        debugConversationPendingStatusText('running',
            locale: const Locale('en', 'US'),
            events: <ConversationEvent>[event]),
        'CLI session started. Reading context...');
  });

  test('conversation pending status text surfaces reconnect notices', () {
    final event = ConversationEvent.fromJson(const <String, Object?>{
      'seq': 1,
      'conversationId': 'conv_1',
      'type': 'system.notice',
      'createdAt': '2026-05-09T00:00:00.000Z',
      'text': 'Reconnecting... 1/5 (stream disconnected before completion)'
    });

    expect(
        debugConversationPendingStatusText('running',
            locale: const Locale('en', 'US'),
            events: <ConversationEvent>[event]),
        'Reconnecting... 1/5 (stream disconnected before completion)');
  });

  test('ASR model download dialog strings use active locale', () {
    final zh = lookupAppLocalizations(theme.zhHansCnLocale);
    final en = lookupAppLocalizations(const Locale('en', 'US'));

    expect(zh.asrModelDialogTitle, '语音模型');
    expect(zh.asrModelDownloading('zipformer'), '正在下载 zipformer');
    expect(zh.asrModelPauseAction, '暂停');
    expect(zh.asrModelCancelAction, '取消');
    expect(en.asrModelDialogTitle, 'Voice model');
    expect(en.asrModelDownloading('zipformer'), 'Downloading zipformer');
  });

  test('duplicate approvals collapse and approval response becomes command',
      () {
    final events = <Map<String, Object?>>[
      const <String, Object?>{
        'type': 'approval.required',
        'seq': 1,
        'runId': 'run_1',
        'createdAt': '2026-05-03T00:00:00.000Z',
        'approvalId': 'approval_1',
        'toolName': 'Bash',
        'input': {'command': 'npm test'}
      },
      const <String, Object?>{
        'type': 'approval.required',
        'seq': 2,
        'runId': 'run_1',
        'createdAt': '2026-05-03T00:00:01.000Z',
        'approvalId': 'approval_1',
        'toolName': 'Bash',
        'input': {'command': 'npm test'}
      },
      const <String, Object?>{
        'type': 'approval.responded',
        'seq': 3,
        'runId': 'run_1',
        'createdAt': '2026-05-03T00:00:02.000Z',
        'approvalId': 'approval_1',
        'decision': 'allow',
        'toolName': 'Write',
        'input': {'command': 'Write'}
      },
      const <String, Object?>{
        'type': 'tool.started',
        'seq': 4,
        'runId': 'run_1',
        'createdAt': '2026-05-03T00:00:03.000Z',
        'toolName': 'Write',
        'input': {'command': r'Write C:\Users\W2830\python_intro.py'}
      },
    ];

    expect(debugWorkbenchMessageRolesAfterEvents(events),
        const <String>[r'command:Write C:\Users\W2830\python_intro.py']);
  });

  test('conversation approval resolution becomes a command card', () {
    const capabilities = ConversationCapabilities(
      longLivedProcess: true,
      waitingInput: true,
      waitingApproval: true,
      resume: true,
      partialOutput: true,
    );
    const conversation = ConversationSummary(
      id: 'conv_1',
      workspaceId: 'workspace_1',
      adapter: 'claude',
      status: 'running',
      capabilities: capabilities,
      createdAt: '2026-05-03T00:00:00.000Z',
      updatedAt: '2026-05-03T00:00:02.000Z',
    );
    final events = <Map<String, Object?>>[
      const <String, Object?>{
        'seq': 1,
        'conversationId': 'conv_1',
        'type': 'approval.requested',
        'createdAt': '2026-05-03T00:00:00.000Z',
        'approvalId': 'approval_1',
        'toolName': 'Bash',
        'input': {'command': 'python intro.py'},
        'summary': 'python intro.py'
      },
      const <String, Object?>{
        'seq': 2,
        'conversationId': 'conv_1',
        'type': 'approval.resolved',
        'createdAt': '2026-05-03T00:00:01.000Z',
        'approvalId': 'approval_1',
        'decision': 'allow',
        'toolName': 'Bash',
        'input': {'command': 'python intro.py'},
        'summary': 'python intro.py'
      },
    ];

    expect(
        debugWorkbenchMessageRolesForConversationEvents(events, conversation),
        const <String>['command:python intro.py']);
  });

  test('conversation approval preserves command metadata from blocking item',
      () {
    const capabilities = ConversationCapabilities(
      longLivedProcess: true,
      waitingInput: true,
      waitingApproval: true,
      resume: true,
      partialOutput: true,
    );
    const conversation = ConversationSummary(
      id: 'conv_1',
      workspaceId: 'workspace_1',
      adapter: 'claude',
      status: 'running',
      capabilities: capabilities,
      createdAt: '2026-05-03T00:00:00.000Z',
      updatedAt: '2026-05-03T00:00:02.000Z',
    );
    final events = <Map<String, Object?>>[
      const <String, Object?>{
        'seq': 1,
        'conversationId': 'conv_1',
        'type': 'approval.requested',
        'createdAt': '2026-05-03T00:00:00.000Z',
        'approvalId': 'approval_1',
        'toolUseId': 'toolu_1',
        'toolName': 'Write',
        'input': {
          'file_path': r'D:\AiProject\vibe-coding\python_concurrency_learn.py'
        },
        'summary': r'D:\AiProject\vibe-coding\python_concurrency_learn.py'
      },
      const <String, Object?>{
        'seq': 2,
        'conversationId': 'conv_1',
        'type': 'approval.resolved',
        'createdAt': '2026-05-03T00:00:01.000Z',
        'approvalId': 'approval_1',
        'toolUseId': 'toolu_1',
        'decision': 'allow',
        'toolName': 'Write',
        'input': {
          'file_path': r'D:\AiProject\vibe-coding\python_concurrency_learn.py'
        },
        'summary': r'D:\AiProject\vibe-coding\python_concurrency_learn.py'
      },
    ];

    expect(
        debugWorkbenchMessageRolesForConversationEvents(events, conversation),
        const <String>[
          r'command:D:\AiProject\vibe-coding\python_concurrency_learn.py'
        ]);
  });

  testWidgets('conversation command card shows output and duration',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildConversationCommandCardPreview());
    await tester.pumpAndSettle();

    expect(find.text('python intro.py'), findsWidgets);
    expect(find.textContaining('执行 1 条命令'), findsOneWidget);
    expect(find.text('hello from intro'), findsOneWidget);
    expect(find.textContaining('2.0s'), findsOneWidget);
    expect(find.byKey(const ValueKey('tool-status-ok')), findsOneWidget);
  });

  test('empty completed conversation shows diagnostic warning', () {
    const capabilities = ConversationCapabilities(
      longLivedProcess: true,
      waitingInput: true,
      waitingApproval: true,
      resume: true,
      partialOutput: true,
    );
    const conversation = ConversationSummary(
      id: 'conv_empty',
      workspaceId: 'workspace_1',
      adapter: 'claude',
      status: 'idle',
      capabilities: capabilities,
      createdAt: '2026-05-03T00:00:00.000Z',
      updatedAt: '2026-05-03T00:00:02.000Z',
    );
    final diagnostic = debugEmptyConversationCompletionDiagnostic(
      const <Map<String, Object?>>[
        <String, Object?>{
          'seq': 1,
          'conversationId': 'conv_empty',
          'type': 'conversation.started',
          'createdAt': '2026-05-03T00:00:00.000Z'
        },
        <String, Object?>{
          'seq': 2,
          'conversationId': 'conv_empty',
          'type': 'protocol.warning',
          'createdAt': '2026-05-03T00:00:01.000Z',
          'text': 'Claude exited before returning content'
        },
        <String, Object?>{
          'seq': 3,
          'conversationId': 'conv_empty',
          'type': 'conversation.completed',
          'createdAt': '2026-05-03T00:00:02.000Z'
        },
      ],
      conversation,
    );

    expect(diagnostic, contains('CLI returned no content'));
    expect(diagnostic, contains('Claude exited before returning content'));
  });

  test('cancelled run does not render a visible status card', () {
    final body = debugVisibleWorkbenchBodyFromEvent(const <String, Object?>{
      'type': 'run.cancelled',
      'seq': 9,
      'runId': 'run_1',
      'createdAt': '2026-05-03T00:00:04.000Z',
      'reason': 'user_cancelled'
    });

    expect(body, isNull);
  });

  test('AskUserQuestion command card shows the actual question', () {
    final body = debugVisibleWorkbenchBodyFromEvent(const <String, Object?>{
      'type': 'tool.started',
      'seq': 10,
      'runId': 'run_ask',
      'createdAt': '2026-05-03T00:00:05.000Z',
      'toolName': 'AskUserQuestion',
      'input': {'question': 'Which script direction do you want?'}
    });

    expect(body, 'Which script direction do you want?');
    expect(body, isNot('AskUserQuestion'));
  });

  test('AskUserQuestion approval card shows the actual question', () {
    final body = debugVisibleWorkbenchBodyFromEvent(const <String, Object?>{
      'type': 'approval.required',
      'seq': 11,
      'runId': 'run_ask',
      'createdAt': '2026-05-03T00:00:06.000Z',
      'approvalId': 'approval_ask',
      'toolName': 'AskUserQuestion',
      'input': {
        'question': 'Which advanced features should the script include?'
      }
    });

    expect(
        body, contains('Which advanced features should the script include?'));
    expect(body, isNot('AskUserQuestion'));
  });

  test('AskUserQuestion approval reads nested control request input', () {
    final body = debugVisibleWorkbenchBodyFromEvent(const <String, Object?>{
      'type': 'approval.required',
      'seq': 12,
      'runId': 'run_ask',
      'createdAt': '2026-05-03T00:00:07.000Z',
      'approvalId': 'approval_nested',
      'toolName': 'AskUserQuestion',
      'raw': {
        'request': {
          'subtype': 'can_use_tool',
          'tool_name': 'AskUserQuestion',
          'input': {'question': 'Files, network, or concurrency?'}
        }
      }
    });

    expect(body, contains('Files, network, or concurrency?'));
  });

  test(
      'AskUserQuestion approval without input does not infer from assistant text',
      () {
    final events = <Map<String, Object?>>[
      const <String, Object?>{
        'type': 'assistant.delta',
        'seq': 1,
        'runId': 'run_ask',
        'createdAt': '2026-05-03T00:00:05.000Z',
        'raw': {'type': 'result', 'result': 'What should this script do?'}
      },
      const <String, Object?>{
        'type': 'approval.required',
        'seq': 2,
        'runId': 'run_ask',
        'createdAt': '2026-05-03T00:00:06.000Z',
        'approvalId': 'approval_ask',
        'toolName': 'AskUserQuestion'
      },
    ];

    expect(debugWorkbenchMessageRolesAfterEvents(events).first,
        'assistant:What should this script do?');
    expect(debugWorkbenchMessageRolesAfterEvents(events).last,
        contains('AskUserQuestion'));
  });

  test('assistant question event shows suggestions without approval', () {
    final events = <Map<String, Object?>>[
      const <String, Object?>{
        'type': 'assistant.question',
        'seq': 1,
        'runId': 'run_ask',
        'createdAt': '2026-05-03T00:00:05.000Z',
        'text': 'Which direction should this Python script take?',
        'suggestions': ['automation', 'async', 'logs']
      },
    ];

    expect(debugWorkbenchMessageRolesAfterEvents(events), const <String>[
      'question:Which direction should this Python script take?'
    ]);
    expect(debugVisibleWorkbenchBodyFromEvent(events.first),
        'Which direction should this Python script take?');
  });

  test('final assistant result replaces partial same-run response', () {
    final events = <Map<String, Object?>>[
      const <String, Object?>{
        'type': 'assistant.delta',
        'seq': 1,
        'runId': 'run_1',
        'createdAt': '2026-05-03T00:00:05.000Z',
        'raw': {
          'type': 'assistant',
          'message': {
            'role': 'assistant',
            'content': [
              {'type': 'text', 'text': 'I need more detail.'}
            ]
          }
        }
      },
      const <String, Object?>{
        'type': 'assistant.delta',
        'seq': 2,
        'runId': 'run_1',
        'createdAt': '2026-05-03T00:00:06.000Z',
        'raw': {
          'type': 'result',
          'result':
              'Advanced script is broad. What should it do?\n\n1. automation\n2. async\n3. logs'
        }
      },
    ];

    expect(debugWorkbenchMessageRolesAfterEvents(events), const <String>[
      'assistant:Advanced script is broad. What should it do?\n\n1. automation\n2. async\n3. logs'
    ]);
  });

  test('final assistant result removes temporary question card', () {
    final events = <Map<String, Object?>>[
      const <String, Object?>{
        'type': 'assistant.question',
        'seq': 1,
        'runId': 'run_1',
        'createdAt': '2026-05-03T00:00:05.000Z',
        'text': 'Need more info.',
        'suggestions': ['automation', 'async']
      },
      const <String, Object?>{
        'type': 'assistant.delta',
        'seq': 2,
        'runId': 'run_1',
        'createdAt': '2026-05-03T00:00:06.000Z',
        'raw': {
          'type': 'result',
          'result':
              'Advanced Python script can mean many things. Pick a direction:\n\n- web scraping\n- CLI tool\n- data processing\n- automation\n- API service\n- AI integration'
        }
      },
    ];

    expect(debugWorkbenchMessageRolesAfterEvents(events), const <String>[
      'assistant:Advanced Python script can mean many things. Pick a direction:\n\n- web scraping\n- CLI tool\n- data processing\n- automation\n- API service\n- AI integration'
    ]);
  });

  test('filters escaped Claude protocol payloads from assistant bubbles', () {
    final body = debugVisibleWorkbenchBodyFromEvent(const <String, Object?>{
      'type': 'assistant.delta',
      'seq': 12,
      'runId': 'run_1',
      'createdAt': '2026-05-02T00:00:00.000Z',
      'raw': {
        'type': 'assistant',
        'message': {
          'role': 'assistant',
          'content': [
            {
              'type': 'text',
              'text':
                  '\\n"Fix this bug" -> debugging first, then domain-specific skills.\\n\\n## Skill Types\\n\\nRigid (TDD, debugging): Follow exactly.'
            }
          ]
        },
        'parent_tool_use_id': null,
        'session_id': 'leaked-session'
      }
    });

    expect(body, isNull);
  });
}
