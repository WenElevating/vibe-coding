import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/app/app_localization.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/ui/core/theme/theme.dart' as theme;
import 'package:lan_ai_cli_control/src/ui/features/workbench/widgets/workbench_message_list.dart';
import 'package:lan_ai_cli_control/src/ui/features/workbench/workbench_messages.dart';

void main() {
  testWidgets('message list shows themed older-history loading row',
      (WidgetTester tester) async {
    await tester.pumpWidget(const _WorkbenchMessageListLoadingHarness());
    await tester.pump();

    expect(find.byKey(const ValueKey('workbench-history-loading-row')),
        findsOneWidget);
    expect(find.text('正在加载更早的事件...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
  });
}

class _WorkbenchMessageListLoadingHarness extends StatefulWidget {
  const _WorkbenchMessageListLoadingHarness();

  @override
  State<_WorkbenchMessageListLoadingHarness> createState() =>
      _WorkbenchMessageListLoadingHarnessState();
}

class _WorkbenchMessageListLoadingHarnessState
    extends State<_WorkbenchMessageListLoadingHarness> {
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        locale: theme.zhHansCnLocale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        theme: theme.buildAppTheme(),
        home: Scaffold(
          backgroundColor: theme.bg,
          body: SizedBox(
            width: 420,
            height: 260,
            child: WorkbenchMessageList(
              controller: _controller,
              messages: <WorkbenchMessage>[
                _runningCommandMessage(seq: 1, body: 'dart analyze'),
              ],
              adapter: 'codex-app-server',
              runId: 'run_loading',
              eventCount: 1,
              terminal: false,
              runError: null,
              runErrorTraceId: null,
              pendingStatusText: '',
              pendingStartedAt: null,
              pendingActions: const <String>[],
              expandThinking: false,
              expandToolDetails: false,
              useReverseTranscript: false,
              loadingOlderConversationEvents: true,
              showPendingDuringInitialConversationLoad: false,
              showStatus: false,
              showError: false,
              showPending: false,
              onApproval: (_, __) async {},
              onSuggestion: (_) {},
              onScrollNotification: (_) => false,
            ),
          ),
        ),
      );
}

WorkbenchMessage _runningCommandMessage({
  required int seq,
  required String body,
}) =>
    WorkbenchMessage(
      'command',
      'Run command',
      body,
      event: AgentEvent(
        type: 'tool.started',
        seq: seq,
        runId: 'run_loading',
        createdAt: DateTime.parse('2026-06-05T00:00:01.000Z'),
        name: 'Bash',
        raw: <String, Object?>{
          'toolName': 'Bash',
          'input': <String, Object?>{'command': body},
        },
      ),
      runId: 'run_loading',
    );
