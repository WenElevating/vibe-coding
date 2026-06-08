import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../../models/protocol.dart';
import '../../../core/theme/theme.dart' as theme;
import '../workbench_messages.dart';
import '../workbench_transcript_display_items.dart';
import 'sweeping_status_text.dart';
import 'transcript_typography.dart';

const _commandShellSurface = Color(0xFF2C2D30);
const _commandShellPanelSurface = Color(0xFF25262A);

class SingleCommandRunCard extends StatelessWidget {
  const SingleCommandRunCard({
    super.key,
    required this.message,
    required this.expanded,
    required this.onToggleExpanded,
  });

  final WorkbenchMessage message;
  final bool expanded;
  final VoidCallback onToggleExpanded;

  @override
  Widget build(BuildContext context) => _CommandRunFrame(
        summary: _singleSummary(AppLocalizations.of(context), message),
        running: !message.completed && !message.isError,
        error: message.isError,
        icon: Icons.terminal_rounded,
        expanded: expanded,
        onToggleExpanded: onToggleExpanded,
        children: [_CommandShellBlock(message: message)],
      );
}

class CommandRunGroupCard extends StatelessWidget {
  const CommandRunGroupCard({
    super.key,
    required this.messages,
    required this.expanded,
    required this.onToggleExpanded,
  });

  final List<WorkbenchMessage> messages;
  final bool expanded;
  final VoidCallback onToggleExpanded;

  @override
  Widget build(BuildContext context) => _CommandRunFrame(
        summary: _groupSummary(AppLocalizations.of(context), messages),
        running:
            messages.any((message) => !message.completed && !message.isError),
        error: messages.any((message) => message.isError),
        icon: Icons.terminal_rounded,
        expanded: expanded,
        onToggleExpanded: onToggleExpanded,
        children: messages
            .map((message) => _CommandShellBlock(message: message))
            .toList(),
      );
}

class _CommandRunFrame extends StatefulWidget {
  const _CommandRunFrame({
    required this.summary,
    required this.running,
    required this.error,
    required this.icon,
    required this.expanded,
    required this.onToggleExpanded,
    required this.children,
  });

  final String summary;
  final bool running;
  final bool error;
  final IconData icon;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final List<Widget> children;

  @override
  State<_CommandRunFrame> createState() => _CommandRunFrameState();
}

class _CommandRunFrameState extends State<_CommandRunFrame> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final showToggle = widget.expanded || _hovered;
    final toggleIcon = widget.expanded
        ? Icons.keyboard_arrow_down_rounded
        : Icons.keyboard_arrow_right_rounded;
    return MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Container(
            margin: const EdgeInsets.only(left: 16),
            decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: widget.expanded
                    ? Border.all(color: Colors.white.withValues(alpha: .045))
                    : null),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onToggleExpanded,
                  child: Padding(
                      padding:
                          EdgeInsets.fromLTRB(2, 2, 2, widget.expanded ? 6 : 2),
                      child: Row(children: [
                        Container(
                            width: 21,
                            height: 21,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                                color: const Color(0xFF121418),
                                borderRadius: BorderRadius.circular(7)),
                            child: Icon(widget.icon,
                                color: const Color(0xFF7B818B), size: 13)),
                        const SizedBox(width: 9),
                        Expanded(
                            child: widget.running
                                ? SweepingStatusText(
                                    text: widget.summary,
                                    style: WorkbenchTranscriptTypography
                                        .commandSummaryActive,
                                    baseColor: const Color(0xFF747B86),
                                    highlightColor: const Color(0xFFC5CBD5),
                                    progressKey: const ValueKey(
                                        'workbench-command-run-sweep-progress'),
                                  )
                                : Text(widget.summary,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: WorkbenchTranscriptTypography
                                        .commandSummary)),
                        const SizedBox(width: 7),
                        AnimatedOpacity(
                            key: const ValueKey(
                                'workbench-command-run-toggle-opacity'),
                            opacity: showToggle ? 1 : 0,
                            duration: const Duration(milliseconds: 120),
                            curve: Curves.easeOutCubic,
                            child:
                                Icon(toggleIcon, color: theme.faint, size: 17)),
                      ]))),
              if (widget.expanded)
                Container(
                    key: const ValueKey('workbench-command-run-group-shell'),
                    padding: const EdgeInsets.fromLTRB(9, 0, 9, 10),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _withSpacing(widget.children))),
            ])));
  }
}

class _CommandShellBlock extends StatelessWidget {
  const _CommandShellBlock({required this.message});

  final WorkbenchMessage message;

  @override
  Widget build(BuildContext context) {
    final output = commandOutputText(message);
    final status = _exitStatusText(AppLocalizations.of(context), message);
    return Container(
        key: const ValueKey('workbench-command-shell-block'),
        width: double.infinity,
        decoration: BoxDecoration(
            color: _commandShellSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: .07))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 6),
              child: Row(children: [
                const Text('Shell',
                    style: WorkbenchTranscriptTypography.shellLabel),
                const Spacer(),
                IconButton(
                    constraints:
                        const BoxConstraints.tightFor(width: 28, height: 24),
                    padding: EdgeInsets.zero,
                    tooltip: 'Copy command and output',
                    onPressed: () => Clipboard.setData(ClipboardData(
                        text: output.isEmpty
                            ? commandDisplayTitle(message)
                            : '${commandDisplayTitle(message)}\n\n$output')),
                    icon: const Icon(Icons.copy_rounded,
                        color: theme.faint, size: 13)),
              ])),
          _MonospacePanel(
              key: const ValueKey('workbench-command-shell-command'),
              text: r'$ ' + commandDisplayTitle(message),
              maxLines: 4,
              style: WorkbenchTranscriptTypography.shellCommand),
          if (output.isNotEmpty) ...[
            const SizedBox(height: 7),
            ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(
                    padding: EdgeInsets.zero,
                    child: _MonospacePanel(
                        key: const ValueKey('workbench-command-shell-output'),
                        text: output,
                        style: WorkbenchTranscriptTypography.shellOutput))),
          ],
          Padding(
              padding: const EdgeInsets.fromLTRB(10, 7, 10, 9),
              child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(status,
                      style: TextStyle(
                          color: message.isError ? theme.red : theme.faint,
                          fontSize:
                              WorkbenchTranscriptTypography.toolMeta.fontSize,
                          height: 1,
                          fontFamily:
                              WorkbenchTranscriptTypography.toolMeta.fontFamily,
                          fontFamilyFallback: workbenchMonoFontFallback,
                          fontWeight: FontWeight.w700)))),
        ]));
  }
}

class _MonospacePanel extends StatelessWidget {
  const _MonospacePanel({
    super.key,
    required this.text,
    required this.style,
    this.maxLines,
  });

  final String text;
  final TextStyle style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) => Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
          color: _commandShellPanelSurface,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: Colors.white.withValues(alpha: .045))),
      child: SelectableText(text, maxLines: maxLines, style: style));
}

List<Widget> _withSpacing(List<Widget> children) {
  final spaced = <Widget>[];
  for (final child in children) {
    if (spaced.isNotEmpty) spaced.add(const SizedBox(height: 9));
    spaced.add(child);
  }
  return spaced;
}

String _singleSummary(AppLocalizations l10n, WorkbenchMessage message) {
  final command = commandDisplayTitle(message);
  if (!message.completed && !message.isError) {
    return l10n.workbenchCommandSummaryRunning(command);
  }
  if (message.isError) return l10n.workbenchCommandSummaryFailed(command);
  return l10n.workbenchCommandSummaryCompleted(command);
}

String _groupSummary(AppLocalizations l10n, List<WorkbenchMessage> messages) {
  final suffix =
      _usedCodeGraph(messages) ? l10n.workbenchCommandCodeGraphSuffix : '';
  if (messages.any((message) => !message.completed && !message.isError)) {
    return '${l10n.workbenchCommandGroupRunning(messages.length)}$suffix';
  }
  return '${l10n.workbenchCommandGroupCompleted(messages.length)}$suffix';
}

bool _usedCodeGraph(List<WorkbenchMessage> messages) => messages.any((message) {
      final title = commandDisplayTitle(message).toLowerCase();
      final toolName = message.event?.raw['toolName'];
      return title.contains('codegraph') ||
          (toolName is String && toolName.toLowerCase().contains('codegraph'));
    });

String _exitStatusText(AppLocalizations l10n, WorkbenchMessage message) {
  final exitCode = commandExitCode(message);
  if (exitCode != null) return l10n.workbenchCommandExitCode(exitCode);
  if (message.isError) return l10n.workbenchCommandStatusError;
  return commandStatusLabel(l10n, message);
}

@visibleForTesting
Widget buildSingleCommandPreview({bool failed = false, bool running = false}) {
  final message = WorkbenchMessage('command', 'Bash', 'dart analyze',
      event: AgentEvent(
          type: 'tool.completed',
          seq: 1,
          runId: 'run_preview',
          createdAt: DateTime.parse('2026-05-03T00:00:00.000Z'),
          name: 'Bash',
          raw: <String, Object?>{
            'toolName': 'Bash',
            'output': failed ? 'analysis failed' : 'No issues found.',
            'exitCode': failed ? 2 : 0,
          }),
      completed: !running,
      isError: failed);
  return _CommandPreviewHarness(
      child: _PreviewExpansionHost(
          child: (expanded, toggle) => SingleCommandRunCard(
              message: message, expanded: expanded, onToggleExpanded: toggle)));
}

@visibleForTesting
Widget buildCommandRunGroupPreview({bool running = false}) {
  final messages = <WorkbenchMessage>[
    WorkbenchMessage('command', 'Bash', 'Get-Content -Path pubspec.yaml',
        event: AgentEvent(
            type: 'tool.completed',
            seq: 1,
            runId: 'run_preview',
            createdAt: DateTime.parse('2026-05-03T00:00:00.000Z'),
            name: 'Bash',
            raw: const <String, Object?>{
              'toolName': 'Bash',
              'output': 'name: lan_ai_cli_control',
              'exitCode': 0,
            }),
        completed: !running),
    WorkbenchMessage('command', 'Bash', 'dart analyze',
        event: AgentEvent(
            type: 'tool.completed',
            seq: 2,
            runId: 'run_preview',
            createdAt: DateTime.parse('2026-05-03T00:00:01.000Z'),
            name: 'Bash',
            raw: const <String, Object?>{
              'toolName': 'Bash',
              'output': 'No issues found.',
              'exitCode': 0,
            }),
        completed: !running),
  ];
  return _CommandPreviewHarness(
      child: _PreviewExpansionHost(
          child: (expanded, toggle) => CommandRunGroupCard(
              messages: messages,
              expanded: expanded,
              onToggleExpanded: toggle)));
}

class _PreviewExpansionHost extends StatefulWidget {
  const _PreviewExpansionHost({required this.child});

  final Widget Function(bool expanded, VoidCallback toggle) child;

  @override
  State<_PreviewExpansionHost> createState() => _PreviewExpansionHostState();
}

class _PreviewExpansionHostState extends State<_PreviewExpansionHost> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) =>
      widget.child(_expanded, () => setState(() => _expanded = !_expanded));
}

class _CommandPreviewHarness extends StatelessWidget {
  const _CommandPreviewHarness({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
      locale: theme.zhHansCnLocale,
      supportedLocales: const [theme.zhHansCnLocale, Locale('en', 'US')],
      localizationsDelegates: theme.appLocalizationsDelegates,
      theme: ThemeData(
          brightness: Brightness.dark,
          fontFamily: 'Segoe UI',
          fontFamilyFallback: theme.appFontFallback,
          useMaterial3: true),
      home: Scaffold(
          backgroundColor: theme.bg,
          body: Padding(padding: const EdgeInsets.all(16), child: child)));
}
