import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/app/app_localization.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/shell/app_route.dart';
import 'package:lan_ai_cli_control/src/shell/app_snapshot.dart';
import 'package:lan_ai_cli_control/src/ui/core/theme/theme.dart' as theme;
import 'package:lan_ai_cli_control/src/ui/pages/queue_page.dart';
import 'package:lan_ai_cli_control/src/ui/pages/runs_page.dart';

void main() {
  testWidgets('runs page shows empty state and invokes detail callback',
      (tester) async {
    final opened = <RoutePage>[];
    await tester.pumpWidget(_Harness(
      child: RunsPage(data: _snapshot(), open: opened.add),
    ));

    expect(
      find.text(
          'No runs yet. Start a real AI CLI task from command templates.'),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(Icons.add_rounded));
    expect(opened, <RoutePage>[RoutePage.detail]);
  });

  testWidgets('runs page search placeholder uses active locale',
      (tester) async {
    await tester.pumpWidget(_Harness(
      locale: const Locale.fromSubtags(
          languageCode: 'zh', scriptCode: 'Hans', countryCode: 'CN'),
      child: RunsPage(data: _snapshot(), open: (_) {}),
    ));

    expect(find.text('搜索运行、工作区或工具...'), findsOneWidget);
    expect(find.text('Search tasks, descriptions, tools...'), findsNothing);
  });

  testWidgets('runs page shows populated rows and opens detail',
      (tester) async {
    final opened = <RoutePage>[];
    await tester.pumpWidget(_Harness(
      child: RunsPage(
        data: _snapshot(runs: const <RunSummary>[
          RunSummary(
            id: 'run_1',
            tool: 'codex',
            workspaceId: 'workspace_1',
            status: 'running',
          ),
        ]),
        open: opened.add,
      ),
    ));

    expect(find.text('run_1'), findsOneWidget);
    expect(find.text('codex'), findsOneWidget);

    await tester.tap(find.text('run_1'));
    expect(opened, <RoutePage>[RoutePage.detail]);
  });

  testWidgets('queue page shows empty and populated states', (tester) async {
    await tester.pumpWidget(_Harness(child: QueuePage(data: _snapshot())));

    expect(find.text('No running queue items'), findsOneWidget);
    expect(find.text('No waiting tasks'), findsOneWidget);

    await tester.pumpWidget(_Harness(
      child: QueuePage(
        data: _snapshot(queue: const <QueueItem>[
          QueueItem(
            runId: 'run_active',
            workspaceId: 'workspace_1',
            status: 'running',
            reason: 'active',
            position: 0,
          ),
          QueueItem(
            runId: 'run_waiting',
            workspaceId: 'workspace_1',
            status: 'queued',
            reason: 'waiting',
            position: 2,
          ),
        ]),
      ),
    ));

    expect(find.text('run_active'), findsOneWidget);
    expect(find.text('run_waiting'), findsOneWidget);
    expect(find.text('active'), findsOneWidget);
    expect(find.text('waiting'), findsOneWidget);
    expect(find.text('Queued'), findsWidgets);
    expect(find.text('Waiting'), findsNothing);
  });
}

class _Harness extends StatelessWidget {
  const _Harness({required this.child, this.locale = const Locale('en', 'US')});

  final Widget child;
  final Locale locale;

  @override
  Widget build(BuildContext context) => MaterialApp(
        locale: locale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        theme: theme.buildAppTheme(),
        home: Scaffold(body: child),
      );
}

AppSnapshot _snapshot({
  List<RunSummary> runs = const <RunSummary>[],
  List<QueueItem> queue = const <QueueItem>[],
}) {
  const workspace = WorkspaceSummary(
    id: 'workspace_1',
    name: 'Current Project',
    path: r'D:\AiProject\vibe-coding',
  );
  return AppSnapshot(
    health: DaemonHealth.fromJson(const <String, Object?>{
      'status': 'ok',
      'daemonVersion': 'test',
      'mode': 'test',
      'lanMode': false,
      'bindAddress': '127.0.0.1',
      'port': 4317,
      'security': {'tokenRequired': false},
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
      recentFiles: <RecentFileSummary>[],
    ),
    adapters: const <AdapterStatus>[],
    runs: runs,
    conversations: const <ConversationSummary>[],
    queue: queue,
    templates: const <CommandTemplate>[],
    gitStatus: const GitStatusSummary(
      workspaceId: 'workspace_1',
      clean: true,
      files: <GitStatusFile>[],
    ),
    diffs: const <DiffSummary>[],
    commits: const <GitCommitSummary>[],
    fileTree: const FileTreeResponse(
      workspaceId: 'workspace_1',
      root: '',
      entries: <FileTreeEntry>[],
    ),
    diagnostics: const CodeDiagnosticsSummary(
      workspaceId: 'workspace_1',
      available: true,
      diagnostics: <CodeDiagnostic>[],
    ),
    extensions: const <ExtensionSummary>[],
  );
}
