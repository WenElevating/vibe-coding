import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/lan_ai_cli_control.dart';
import 'package:lan_ai_cli_control/l10n/app_localizations.dart';
import 'package:lan_ai_cli_control/src/app/app_localization.dart';
import 'package:lan_ai_cli_control/src/app/language_controller.dart';
import 'package:lan_ai_cli_control/src/app/language_mode.dart';
import 'package:lan_ai_cli_control/src/app/language_scope.dart';
import 'package:lan_ai_cli_control/src/shell/app_snapshot.dart';
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
                  builder: (context) => Text(
                      AppLocalizations.of(context).navSettings)))));
}

class _LocalizedMainTabsApp extends StatefulWidget {
  const _LocalizedMainTabsApp();

  @override
  State<_LocalizedMainTabsApp> createState() => _LocalizedMainTabsAppState();
}

class _LocalizedMainTabsAppState extends State<_LocalizedMainTabsApp> {
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
              home: MainTabsPage(
                  data: _testSnapshot(),
                  client: DaemonClient(
                      baseUri: Uri.parse('http://127.0.0.1:4317'),
                      tokenStore: MemoryTokenStore())))));
}

AppSnapshot _testSnapshot() {
  const workspace = WorkspaceSummary(
      id: 'workspace_1',
      name: 'Current Project',
      path: r'D:\AiProject\vibe-coding');
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
      workspaces: const <WorkspaceSummary>[workspace],
      workspace: workspace,
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
}

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

  testWidgets('settings language picker shows self-identifying language names',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});

    await tester.pumpWidget(const _LocalizedMainTabsApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();

    expect(find.text('System default'), findsOneWidget);
    expect(find.text('简体中文'), findsOneWidget);
    expect(find.text('English'), findsWidgets);
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

  testWidgets(
      'shows connection error when daemon is unavailable in widget tests',
      (WidgetTester tester) async {
    await tester.pumpWidget(const LanAiCliControlApp());
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('MobileUiFrame renders supplied child',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MobileUiFrame(child: Text('frame child')),
    ));

    expect(find.text('frame child'), findsOneWidget);
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

  testWidgets('tapping current project opens workspace session list',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildCodingWorkbenchEntryPreview());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('coding-session-list')), findsOneWidget);
    expect(find.text('New Session'), findsOneWidget);
    expect(find.text('Select workspace for this coding session'), findsNothing);
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

    expect(diagnostic, contains('CLI 未返回内容'));
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
