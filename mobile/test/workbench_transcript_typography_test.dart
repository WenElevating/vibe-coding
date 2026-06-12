import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/ui/core/theme/theme.dart' as theme;
import 'package:lan_ai_cli_control/src/ui/features/workbench/messages/assistant_markdown_body.dart';
import 'package:lan_ai_cli_control/src/ui/features/workbench/messages/codex_command_run_card.dart';
import 'package:lan_ai_cli_control/src/ui/features/workbench/messages/sweeping_status_text.dart';
import 'package:lan_ai_cli_control/src/ui/features/workbench/messages/transcript_typography.dart';

void main() {
  testWidgets('assistant prose is visually distinct from command status text',
      (WidgetTester tester) async {
    await tester.pumpWidget(_styleHarness(const SizedBox.shrink()));

    final styleSheet = buildAssistantMarkdownStyleSheet(
      tester.element(find.byType(SizedBox)),
    );
    final assistantStyle = styleSheet.p!;
    final commandStyle = WorkbenchTranscriptTypography.commandSummary;

    expect(assistantStyle.fontSize, greaterThan(commandStyle.fontSize!));
    expect(assistantStyle.fontWeight, isNot(commandStyle.fontWeight));
    expect(assistantStyle.color, isNot(commandStyle.color));
    expect(_luminance(commandStyle.color!),
        lessThan(_luminance(assistantStyle.color!)));
    expect(_luminance(WorkbenchTranscriptTypography.toolTitle.color!),
        lessThan(_luminance(assistantStyle.color!)));
    expect(styleSheet.a?.color, const Color(0xFF3A96DD));
    expect(styleSheet.a?.fontWeight, FontWeight.w800);
  });

  testWidgets('running command status uses compact muted typography',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildCommandRunGroupPreview(running: true));
    await tester.pump();

    final sweepingText = tester.widget<SweepingStatusText>(
      find.byType(SweepingStatusText),
    );

    expect(sweepingText.style?.fontSize,
        WorkbenchTranscriptTypography.commandSummaryActive.fontSize);
    expect(sweepingText.baseColor, const Color(0xFF747B86));
    expect(sweepingText.highlightColor, const Color(0xFFC5CBD5));
  });

  testWidgets('expanded shell command uses brighter monospace than output',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildCommandRunGroupPreview());
    await tester.pumpAndSettle();

    await tester.tap(find.text('已运行 2 条命令'));
    await tester.pumpAndSettle();

    final commandText = _selectableTextInside(
      tester,
      const ValueKey('workbench-command-shell-command'),
    );
    final outputText = _selectableTextInside(
      tester,
      const ValueKey('workbench-command-shell-output'),
    );

    expect(commandText.style?.fontFamily, 'Cascadia Mono');
    expect(commandText.data, startsWith(r'$ '));
    expect(commandText.style?.color,
        WorkbenchTranscriptTypography.shellCommand.color);
    expect(outputText.style?.color,
        WorkbenchTranscriptTypography.shellOutput.color);
    expect(outputText.style?.color, isNot(commandText.style?.color));
  });
}

Widget _styleHarness(Widget child) => MaterialApp(
      locale: theme.zhHansCnLocale,
      supportedLocales: const [theme.zhHansCnLocale, Locale('en', 'US')],
      localizationsDelegates: theme.appLocalizationsDelegates,
      theme: theme.buildAppTheme(),
      home: Scaffold(body: child),
    );

SelectableText _selectableTextInside(WidgetTester tester, Key key) {
  final finder = find.descendant(
    of: find.byKey(key).first,
    matching: find.byType(SelectableText),
  );
  return tester.widget<SelectableText>(finder.first);
}

double _luminance(Color color) => color.computeLuminance();
