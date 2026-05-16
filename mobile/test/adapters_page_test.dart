import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/app/app_localization.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/shell/app_snapshot.dart';
import 'package:lan_ai_cli_control/src/ui/core/theme/theme.dart' as theme;
import 'package:lan_ai_cli_control/src/ui/features/adapters/adapters.dart';

void main() {
  testWidgets('adapters page shows empty state and back action',
      (tester) async {
    var backed = false;
    await tester.pumpWidget(_Harness(
      snapshot: _snapshot(),
      onBack: () => backed = true,
    ));

    expect(find.text('daemon returned no adapters'), findsOneWidget);
    expect(find.text('No extension information'), findsOneWidget);

    await tester.tap(find.text('Back'));
    expect(backed, isTrue);
  });

  testWidgets('adapters page shows populated and unavailable states',
      (tester) async {
    await tester.pumpWidget(_Harness(
      snapshot: _snapshot(
        adapters: const <AdapterStatus>[
          AdapterStatus(
            adapter: 'codex',
            available: true,
            status: 'available',
            version: '1.0.0',
          ),
          AdapterStatus(
            adapter: 'claude',
            available: false,
            status: 'missing binary',
            error: 'missing binary',
          ),
        ],
        extensions: const <ExtensionSummary>[
          ExtensionSummary(
            id: 'ext_1',
            name: 'GitHub',
            version: '1.0.0',
            description: 'Issue sync',
            installed: false,
            status: 'missing',
          ),
        ],
      ),
    ));

    expect(find.text('codex'), findsOneWidget);
    expect(find.text('claude'), findsOneWidget);
    expect(find.textContaining('missing binary'), findsOneWidget);
    expect(find.text('GitHub'), findsOneWidget);
    expect(find.text('not installed'), findsOneWidget);
  });
}

class _Harness extends StatelessWidget {
  const _Harness({required this.snapshot, this.onBack});

  final AppSnapshot snapshot;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => MaterialApp(
        locale: const Locale('en', 'US'),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        theme: theme.buildAppTheme(),
        home: Scaffold(
          body: AdaptersPage(
            viewModel: AdaptersViewModel(snapshot: snapshot),
            onBack: onBack ?? () {},
          ),
        ),
      );
}

AppSnapshot _snapshot({
  List<AdapterStatus> adapters = const <AdapterStatus>[],
  List<ExtensionSummary> extensions = const <ExtensionSummary>[],
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
    adapters: adapters,
    runs: const <RunSummary>[],
    conversations: const <ConversationSummary>[],
    queue: const <QueueItem>[],
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
    extensions: extensions,
  );
}
