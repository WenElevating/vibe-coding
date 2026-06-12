import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/l10n/app_localizations.dart';
import 'package:lan_ai_cli_control/src/app/app_localization.dart';
import 'package:lan_ai_cli_control/src/ui/core/theme/theme.dart' as theme;
import 'package:lan_ai_cli_control/src/ui/features/workbench/messages/sweeping_status_text.dart';
import 'package:lan_ai_cli_control/src/ui/features/workbench/messages/transcript_typography.dart';
import 'package:lan_ai_cli_control/src/ui/features/workbench/widgets/workbench_inline_status.dart';
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

    final statusText = tester.widget<SweepingStatusText>(
      find.byType(SweepingStatusText),
    );
    expect(statusText.text, '正在生成回复...');
    expect(statusText.style?.fontSize, 13);
    expect(statusText.style?.fontWeight, FontWeight.w500);
    expect(statusText.baseColor, const Color(0xFF737983));
    expect(statusText.highlightColor, const Color(0xFFBBC3CE));
    expect(find.byKey(const ValueKey('workbench-pending-transcript-elapsed')),
        findsNothing);
    expect(find.byKey(const ValueKey('workbench-pending-transcript-divider')),
        findsNothing);
  });

  testWidgets('reading-context pending status only shows thinking text',
      (WidgetTester tester) async {
    final l10n = lookupAppLocalizations(theme.zhHansCnLocale);

    await tester.pumpWidget(_WorkbenchPendingHarness(
      pendingStatusText: l10n.workbenchPendingReadingContext,
    ));
    await tester.pump();

    final sweepingText = tester.widget<SweepingStatusText>(
      find.byType(SweepingStatusText),
    );
    expect(sweepingText.text, '正在思考');
    expect(sweepingText.style?.fontSize, 13);
    expect(sweepingText.style?.fontWeight, FontWeight.w500);
    expect(sweepingText.baseColor, const Color(0xFF737983));
    expect(sweepingText.highlightColor, const Color(0xFFBBC3CE));
    expect(find.text(l10n.workbenchPendingReadingContext), findsNothing);
    expect(find.byKey(const ValueKey('workbench-pending-transcript-elapsed')),
        findsNothing);
    expect(find.byKey(const ValueKey('workbench-pending-transcript-divider')),
        findsNothing);

    final progressFinder =
        find.byKey(const ValueKey('workbench-pending-status-sweep-progress'));
    expect(progressFinder, findsOneWidget);
    final progress = tester.getSize(progressFinder).width;

    await tester.pump(const Duration(milliseconds: 900));

    expect(tester.getSize(progressFinder).width, greaterThan(progress));

    final statusLeft = tester.getTopLeft(find.text('正在思考').first).dx;

    expect(statusLeft, 32);
  });

  testWidgets('pending thinking aligns with assistant prose column',
      (WidgetTester tester) async {
    final l10n = lookupAppLocalizations(theme.zhHansCnLocale);
    const assistantText = '助手正文左边距基准';

    await tester.pumpWidget(_WorkbenchPendingHarness(
      messages: const <WorkbenchMessage>[
        WorkbenchMessage('assistant', 'CLI assistant', assistantText),
      ],
      pendingStatusText: l10n.workbenchPendingReadingContext,
    ));
    await tester.pump();

    final assistantLeft = tester.getTopLeft(find.text(assistantText)).dx;
    final pendingLeft = tester.getTopLeft(find.text('正在思考').first).dx;
    final sweepingText = tester.widget<SweepingStatusText>(
      find.byType(SweepingStatusText),
    );

    expect(pendingLeft, assistantLeft);
    expect(sweepingText.style?.height, 1.28);
    expect(
      _luminance(sweepingText.baseColor!),
      lessThan(_luminance(WorkbenchTranscriptTypography.assistantBody.color!)),
    );
  });

  testWidgets('running tool pending hides the thinking tail',
      (WidgetTester tester) async {
    final l10n = lookupAppLocalizations(theme.zhHansCnLocale);

    await tester.pumpWidget(_WorkbenchPendingHarness(
      pendingStatusText: l10n.workbenchPendingRunningTool('command_execution'),
      pendingStartedAt: DateTime(2026, 6, 12, 10),
      now: () => DateTime(2026, 6, 12, 10, 0, 7),
    ));
    await tester.pump();

    expect(find.text('已处理 7s'), findsOneWidget);
    expect(find.byKey(const ValueKey('workbench-pending-transcript-divider')),
        findsOneWidget);
    expect(
        find.byWidgetPredicate(
          (widget) => widget is SweepingStatusText && widget.text == '正在思考',
        ),
        findsNothing);
    expect(find.byKey(const ValueKey('workbench-pending-transcript-status')),
        findsNothing);
    expect(find.text('正在运行 command_execution...'), findsNothing);
    expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              widget.data != null &&
              widget.data!.startsWith('已处理 '),
        ),
        findsOneWidget);
  });

  testWidgets('active command cards suppress the thinking tail',
      (WidgetTester tester) async {
    final l10n = lookupAppLocalizations(theme.zhHansCnLocale);

    await tester.pumpWidget(_WorkbenchPendingHarness(
      messages: const <WorkbenchMessage>[
        WorkbenchMessage('user', 'You', '看下这个项目是干嘛的'),
        WorkbenchMessage('assistant', 'CLI assistant', '我先看一下仓库结构。'),
        WorkbenchMessage('command', 'Run command', 'dart analyze'),
      ],
      pendingStatusText: l10n.workbenchPendingWaitingNextEvent,
      pendingStartedAt: DateTime(2026, 6, 12, 10),
      now: () => DateTime(2026, 6, 12, 10, 0, 7),
    ));
    await tester.pump();

    expect(find.text('已处理 7s'), findsOneWidget);
    expect(
        find.byWidgetPredicate(
          (widget) => widget is SweepingStatusText && widget.text == '正在思考',
        ),
        findsNothing);
    expect(find.byKey(const ValueKey('workbench-pending-transcript-status')),
        findsNothing);
    expect(find.text('正在运行 dart analyze'), findsWidgets);
  });

  testWidgets('pending elapsed starts active response after the user prompt',
      (WidgetTester tester) async {
    final l10n = lookupAppLocalizations(theme.zhHansCnLocale);
    const userText = '这个项目是干嘛的?';
    const assistantText = '我会先按本仓库的项目说明做一次轻量定位。';

    await tester.pumpWidget(_WorkbenchPendingHarness(
      messages: const <WorkbenchMessage>[
        WorkbenchMessage('user', 'You', userText),
        WorkbenchMessage('assistant', 'CLI assistant', assistantText),
        WorkbenchMessage(
          'command',
          'Run command',
          'dart analyze',
          completed: true,
        ),
      ],
      pendingStatusText: l10n.workbenchPendingWaitingNextEvent,
      pendingStartedAt: DateTime(2026, 6, 12, 10),
      now: () => DateTime(2026, 6, 12, 10, 0, 7),
      showStatus: true,
    ));
    await tester.pump();

    final elapsedFinder = find.text('已处理 7s');
    expect(elapsedFinder, findsOneWidget);
    expect(find.byType(WorkbenchInlineStatus), findsOneWidget);
    expect(
        find.byWidgetPredicate(
          (widget) => widget is SweepingStatusText && widget.text == '正在思考',
        ),
        findsOneWidget);
    expect(
      tester.getTopLeft(elapsedFinder).dy,
      greaterThan(tester.getTopLeft(find.text(userText)).dy),
    );
    expect(
      tester.getTopLeft(elapsedFinder).dy,
      lessThan(tester.getTopLeft(find.text(assistantText)).dy),
    );
    expect(
      tester.getTopLeft(find.byType(WorkbenchInlineStatus)).dy,
      lessThan(tester.getTopLeft(find.text(userText)).dy),
    );
  });

  testWidgets(
      'pending elapsed starts active response for first-message reverse transcript',
      (WidgetTester tester) async {
    final l10n = lookupAppLocalizations(theme.zhHansCnLocale);
    const userText = '第一条消息之后开始执行命令';

    await tester.pumpWidget(_WorkbenchPendingHarness(
      messages: const <WorkbenchMessage>[
        WorkbenchMessage('user', 'You', userText),
        WorkbenchMessage('command', 'Run command', 'dart analyze'),
      ],
      pendingStatusText: l10n.workbenchPendingWaitingNextEvent,
      pendingStartedAt: DateTime(2026, 6, 12, 10),
      now: () => DateTime(2026, 6, 12, 10, 0, 7),
      useReverseTranscript: true,
    ));
    await tester.pump();

    final elapsedFinder = find.text('已处理 7s');

    expect(elapsedFinder, findsOneWidget);
    expect(
      tester.getTopLeft(elapsedFinder).dy,
      greaterThan(tester.getTopLeft(find.text(userText)).dy),
    );
    expect(
      tester.getTopLeft(elapsedFinder).dy,
      lessThan(tester.getTopLeft(find.text('正在运行 dart analyze').first).dy),
    );
    expect(
        find.byWidgetPredicate(
          (widget) => widget is SweepingStatusText && widget.text == '正在思考',
        ),
        findsNothing);
    expect(find.byKey(const ValueKey('workbench-pending-transcript-status')),
        findsNothing);
  });

  testWidgets('running tool elapsed renders above command cards only',
      (WidgetTester tester) async {
    final l10n = lookupAppLocalizations(theme.zhHansCnLocale);

    await tester.pumpWidget(_WorkbenchPendingHarness(
      messages: const <WorkbenchMessage>[
        WorkbenchMessage('command', 'Run command', 'dart analyze'),
      ],
      pendingStatusText: l10n.workbenchPendingRunningTool('command_execution'),
      pendingStartedAt: DateTime(2026, 6, 12, 10),
      now: () => DateTime(2026, 6, 12, 10, 0, 7),
    ));
    await tester.pump();

    final elapsedFinder = find.text('已处理 7s');
    expect(elapsedFinder, findsOneWidget);
    expect(
      tester.getTopLeft(elapsedFinder).dy,
      lessThan(tester.getTopLeft(find.text('正在运行 dart analyze').first).dy),
    );
    expect(
        find.byWidgetPredicate(
          (widget) => widget is SweepingStatusText && widget.text == '正在思考',
        ),
        findsNothing);
    expect(find.byKey(const ValueKey('workbench-pending-transcript-status')),
        findsNothing);
    expect(find.text('正在运行 command_execution...'), findsNothing);
  });

  testWidgets('cancelled elapsed segment remains visible after pending stops',
      (WidgetTester tester) async {
    final startedAt = DateTime(2026, 6, 12, 10);

    await tester.pumpWidget(_WorkbenchPendingHarness(
      messages: <WorkbenchMessage>[
        WorkbenchMessage('user', 'You', '这个项目是干嘛的?', eventSeq: 2),
        const WorkbenchMessage(
          'command',
          'Run command',
          'dart analyze',
          completed: true,
          eventSeq: 3,
        ),
      ],
      pendingStatusText: '',
      elapsedSegments: <ConversationElapsedSegment>[
        ConversationElapsedSegment(
          afterSeq: 2,
          startedAt: startedAt,
          endedAt: startedAt.add(const Duration(seconds: 18)),
        ),
      ],
      showPending: false,
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('已处理 18s'), findsOneWidget);
    expect(find.byKey(const ValueKey('workbench-pending-transcript-status')),
        findsNothing);
  });

  testWidgets('continued turn elapsed segments stay with their own user prompt',
      (WidgetTester tester) async {
    final firstStartedAt = DateTime(2026, 6, 12, 10);
    final secondStartedAt = firstStartedAt.add(const Duration(seconds: 20));

    await tester.pumpWidget(_WorkbenchPendingHarness(
      messages: <WorkbenchMessage>[
        WorkbenchMessage('user', 'You', '这个项目是干嘛的?', eventSeq: 2),
        WorkbenchMessage('assistant', 'CLI assistant', '我会先看仓库。', eventSeq: 4),
        const WorkbenchMessage(
          'command',
          'Run command',
          'rg --files',
          completed: true,
          eventSeq: 5,
        ),
        WorkbenchMessage('user', 'You', '继续', eventSeq: 8),
        const WorkbenchMessage(
          'command',
          'Run command',
          'dart analyze',
          eventSeq: 9,
        ),
      ],
      pendingStatusText: '正在等待下一个事件...',
      elapsedSegments: <ConversationElapsedSegment>[
        ConversationElapsedSegment(
          afterSeq: 2,
          startedAt: firstStartedAt,
          endedAt: firstStartedAt.add(const Duration(seconds: 18)),
        ),
        ConversationElapsedSegment(
          afterSeq: 8,
          startedAt: secondStartedAt,
        ),
      ],
      now: () => secondStartedAt.add(const Duration(seconds: 7)),
    ));
    await tester.pump();

    final firstElapsed = find.text('已处理 18s');
    final secondElapsed = find.text('已处理 7s');
    expect(firstElapsed, findsOneWidget);
    expect(secondElapsed, findsOneWidget);
    expect(
      tester.getTopLeft(firstElapsed).dy,
      greaterThan(tester.getTopLeft(find.text('这个项目是干嘛的?')).dy),
    );
    expect(
      tester.getTopLeft(firstElapsed).dy,
      lessThan(tester.getTopLeft(find.text('我会先看仓库。')).dy),
    );
    expect(
      tester.getTopLeft(secondElapsed).dy,
      greaterThan(tester.getTopLeft(find.text('继续')).dy),
    );
    expect(
      tester.getTopLeft(secondElapsed).dy,
      lessThan(tester.getTopLeft(find.text('正在运行 dart analyze').first).dy),
    );
  });

  testWidgets('message list pending does not render sweeping progress',
      (WidgetTester tester) async {
    await tester.pumpWidget(_WorkbenchPendingHarness(
      pendingStatusText: '正在等待下一个事件...',
    ));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
        find.byKey(const ValueKey('workbench-pending-status-sweep-progress')),
        findsOneWidget);
    expect(
        find.byWidgetPredicate(
          (widget) => widget is SweepingStatusText && widget.text == '正在思考',
        ),
        findsOneWidget);
    expect(find.byKey(const ValueKey('workbench-pending-transcript-elapsed')),
        findsNothing);
  });
}

class _WorkbenchPendingHarness extends StatefulWidget {
  const _WorkbenchPendingHarness({
    required this.pendingStatusText,
    this.messages = const <WorkbenchMessage>[],
    this.pendingStartedAt,
    this.elapsedSegments = const <ConversationElapsedSegment>[],
    this.now,
    this.showStatus = false,
    this.showPending = true,
    this.useReverseTranscript = false,
  });

  final String pendingStatusText;
  final List<WorkbenchMessage> messages;
  final DateTime? pendingStartedAt;
  final List<ConversationElapsedSegment> elapsedSegments;
  final DateTime Function()? now;
  final bool showStatus;
  final bool showPending;
  final bool useReverseTranscript;

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
            height: 420,
            child: WorkbenchMessageList(
              controller: _controller,
              messages: widget.messages,
              adapter: 'codex',
              runId: 'run_pending_transition',
              eventCount: 0,
              terminal: false,
              runError: null,
              runErrorTraceId: null,
              pendingStatusText: widget.pendingStatusText,
              pendingStartedAt: widget.pendingStartedAt,
              elapsedSegments: widget.elapsedSegments,
              pendingActions: const <String>[],
              expandThinking: false,
              expandToolDetails: false,
              useReverseTranscript: widget.useReverseTranscript,
              loadingOlderConversationEvents: false,
              showPendingDuringInitialConversationLoad: false,
              showStatus: widget.showStatus,
              showError: false,
              showPending: widget.showPending,
              now: widget.now,
              onApproval: (_, __) async {},
              onSuggestion: (_) {},
              onScrollNotification: (_) => false,
            ),
          ),
        ),
      );
}

double _luminance(Color color) => color.computeLuminance();
