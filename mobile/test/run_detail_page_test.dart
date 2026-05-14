import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/app/app_localization.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/run_repository.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/ui/core/theme/theme.dart' as theme;
import 'package:lan_ai_cli_control/src/ui/features/run_detail/run_detail.dart';

void main() {
  group('RunDetailPage', () {
    testWidgets('empty repository state shows real run metadata and no mocks',
        (tester) async {
      final viewModel = RunDetailViewModel(
        run: _run,
        runRepository: _FakeRunRepository(),
      );

      await tester.pumpWidget(_RunDetailHarness(viewModel: viewModel));
      await tester.pumpAndSettle();

      expect(find.text('run_real_1'), findsOneWidget);
      expect(find.text('codex'), findsOneWidget);
      expect(find.text('queued'), findsOneWidget);
      expect(find.text('No events yet'), findsOneWidget);

      expect(find.text('Fix login API test failure'), findsNothing);
      expect(find.textContaining('tests/login_test.dart'), findsNothing);
      expect(
          find.textContaining('lib/services/auth_service.dart'), findsNothing);
      expect(find.text('Claude Code'), findsNothing);
    });

    testWidgets('repository events render actual event data', (tester) async {
      final viewModel = RunDetailViewModel(
        run: _run,
        runRepository: _FakeRunRepository(events: [_event()]),
      );

      await tester.pumpWidget(_RunDetailHarness(viewModel: viewModel));
      await tester.pumpAndSettle();

      expect(find.text('Actual tool event'), findsOneWidget);
      expect(find.text('Read mobile/lib/src/app/app.dart'), findsOneWidget);
      expect(find.text('No events yet'), findsNothing);
      expect(find.textContaining('tests/login_test.dart'), findsNothing);
    });
  });
}

const _run = RunSummary(
  id: 'run_real_1',
  tool: 'codex',
  workspaceId: 'workspace_1',
  status: 'queued',
);

AgentEvent _event() {
  return AgentEvent(
    type: 'tool.file.read',
    seq: 1,
    runId: _run.id,
    createdAt: DateTime.utc(2026, 5, 14, 8, 15),
    name: 'Actual tool event',
    text: 'Read mobile/lib/src/app/app.dart',
  );
}

class _RunDetailHarness extends StatelessWidget {
  const _RunDetailHarness({required this.viewModel});

  final RunDetailViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: const Locale('en', 'US'),
      supportedLocales: appSupportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
      theme: theme.buildAppTheme(),
      home: Scaffold(
        body: RunDetailPage(
          viewModel: viewModel,
          onBack: () {},
        ),
      ),
    );
  }
}

class _FakeRunRepository implements RunRepository {
  _FakeRunRepository({this.events = const <AgentEvent>[]});

  final List<AgentEvent> events;

  @override
  Future<RunSummary> cancelRun(String runId) {
    throw UnimplementedError();
  }

  @override
  Future<RunSummary> createRun({
    required String tool,
    required String workspaceId,
    String? prompt,
    String? shortcutId,
    String permissionMode = 'default',
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<AgentEvent>> fetchEvents(String runId, {int afterSeq = 0}) async {
    return events;
  }

  @override
  Future<RunSummary> invokeCommandTemplate({
    required String templateId,
    required String workspaceId,
    String tool = 'claude',
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<QueueItem>> listQueue() {
    throw UnimplementedError();
  }

  @override
  Future<List<RunSummary>> listRuns({
    String? tool,
    String? workspaceId,
    String? status,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> respondApproval(String approvalId, String decision) {
    throw UnimplementedError();
  }

  @override
  Future<RunSummary> sendRunInput(
    String runId,
    String prompt, {
    String permissionMode = 'default',
  }) {
    throw UnimplementedError();
  }
}
