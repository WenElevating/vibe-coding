import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/app/app_localization.dart';
import 'package:lan_ai_cli_control/src/ui/core/theme/theme.dart' as theme;
import 'package:lan_ai_cli_control/src/ui/features/workbench/widgets/workbench_message_list.dart';
import 'package:lan_ai_cli_control/src/ui/features/workbench/workbench_messages.dart';

void main() {
  testWidgets('message list pending uses transcript transition layout',
      (WidgetTester tester) async {
    await tester.pumpWidget(_WorkbenchPendingHarness(
      pendingStatusText: '我先按项目说明和已有记忆快速确认一下。',
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));

    expect(find.byKey(const ValueKey('workbench-pending-transcript-divider')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('workbench-pending-transcript-elapsed')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('workbench-pending-transcript-status')),
        findsOneWidget);
    expect(find.text('已处理 5s'), findsOneWidget);
    expect(find.text('我先按项目说明和已有记忆快速确认一下。'), findsOneWidget);

    final elapsedText = tester.widget<Text>(find.text('已处理 5s'));
    expect(elapsedText.style?.fontSize, 13);
    expect(elapsedText.style?.fontWeight, FontWeight.w500);

    final statusText = tester.widget<Text>(find.text('我先按项目说明和已有记忆快速确认一下。'));
    expect(statusText.style?.fontSize, 15);
    expect(statusText.style?.fontWeight, FontWeight.w700);
  });

  testWidgets('transition-only pending status uses compact muted typography',
      (WidgetTester tester) async {
    await tester.pumpWidget(_WorkbenchPendingHarness(
      pendingStatusText: '正在生成回复...',
    ));
    await tester.pump();

    final statusText = tester.widget<Text>(find.text('正在生成回复...'));
    expect(statusText.style?.fontSize, 13);
    expect(statusText.style?.fontWeight, FontWeight.w600);
    expect(statusText.style?.color, const Color(0xFF9298A2));
  });

  testWidgets('message list pending does not render sweeping progress',
      (WidgetTester tester) async {
    await tester.pumpWidget(_WorkbenchPendingHarness(
      pendingStatusText: '正在等待下一个事件...',
    ));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
        find.byKey(const ValueKey('workbench-pending-status-sweep-progress')),
        findsNothing);
    expect(find.text('酝酿中...'), findsOneWidget);
  });
}

class _WorkbenchPendingHarness extends StatefulWidget {
  const _WorkbenchPendingHarness({
    required this.pendingStatusText,
  });

  final String pendingStatusText;

  @override
  State<_WorkbenchPendingHarness> createState() =>
      _WorkbenchPendingHarnessState();
}

class _WorkbenchPendingHarnessState extends State<_WorkbenchPendingHarness> {
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
              messages: const <WorkbenchMessage>[],
              adapter: 'codex',
              runId: 'run_pending_transition',
              eventCount: 0,
              terminal: false,
              runError: null,
              runErrorTraceId: null,
              pendingStatusText: widget.pendingStatusText,
              pendingStartedAt: null,
              pendingActions: const <String>[],
              expandThinking: false,
              expandToolDetails: false,
              useReverseTranscript: false,
              loadingOlderConversationEvents: false,
              showPendingDuringInitialConversationLoad: false,
              showStatus: false,
              showError: false,
              showPending: true,
              onApproval: (_, __) async {},
              onSuggestion: (_) {},
              onScrollNotification: (_) => false,
            ),
          ),
        ),
      );
}
