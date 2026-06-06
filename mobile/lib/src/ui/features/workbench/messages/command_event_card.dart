import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../../models/protocol.dart';
import '../../../core/theme/theme.dart' as theme;
import '../conversation_reducer.dart';
import '../workbench_messages.dart';
import 'transcript_typography.dart';

class CommandEventCard extends StatelessWidget {
  const CommandEventCard(
      {super.key, required this.message, this.expandByDefault = false});
  final WorkbenchMessage message;
  final bool expandByDefault;

  @override
  Widget build(BuildContext context) =>
      _ToolLogFoldout(message: message, expandByDefault: expandByDefault);
}

class SubAgentCallCard extends StatefulWidget {
  const SubAgentCallCard(
      {super.key, required this.message, this.expandByDefault = false});

  final WorkbenchMessage message;
  final bool expandByDefault;

  @override
  State<SubAgentCallCard> createState() => SubAgentCallCardState();
}

class SubAgentCallCardState extends State<SubAgentCallCard> {
  late bool _expanded = widget.expandByDefault;

  @override
  void didUpdateWidget(covariant SubAgentCallCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.body != widget.message.body ||
        oldWidget.message.title != widget.message.title ||
        oldWidget.message.completed != widget.message.completed ||
        oldWidget.message.isError != widget.message.isError) {
      _expanded = widget.expandByDefault;
    } else if (oldWidget.expandByDefault != widget.expandByDefault) {
      _expanded = widget.expandByDefault;
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final accent = message.isError
        ? theme.red
        : message.completed
            ? theme.green
            : theme.purple2;
    final title = _subAgentTitle(message);
    final prompt = _subAgentPrompt(message);
    final output = _commandOutput(message);
    return Container(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
        decoration: BoxDecoration(
            color: const Color(0xFF0F1114),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: accent.withValues(alpha: .16))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _expanded = !_expanded),
              child: Row(children: [
                Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: accent.withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: accent.withValues(alpha: .22))),
                    child: Icon(Icons.account_tree_rounded,
                        color: accent, size: 15)),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WorkbenchTranscriptTypography.toolTitle),
                      const SizedBox(height: 3),
                      Text(_subAgentMeta(message),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WorkbenchTranscriptTypography.toolMeta),
                    ])),
                const SizedBox(width: 8),
                _SubAgentStatePill(message: message),
                const SizedBox(width: 4),
                Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: theme.faint,
                    size: 17),
              ])),
          if (_expanded) ...[
            const SizedBox(height: 10),
            if (prompt != null)
              _ToolDetailBlock(
                  label: 'handoff',
                  text: prompt,
                  onTap: () => _showCommandDetailSheet(
                      context: context,
                      title: 'Agent handoff',
                      subtitle: _subAgentMeta(message),
                      text: prompt)),
            if (prompt != null && output != null) const SizedBox(height: 7),
            if (output != null)
              _ToolDetailBlock(
                  label: 'result',
                  text: output,
                  onTap: () => _showCommandDetailSheet(
                      context: context,
                      title: 'Agent result',
                      subtitle: _subAgentMeta(message),
                      text: output)),
            if (prompt == null && output == null)
              const Text('Waiting for sub-agent output...',
                  style: TextStyle(
                      color: theme.muted, fontSize: 12.5, height: 1.45)),
          ],
        ]));
  }
}

class _SubAgentStatePill extends StatelessWidget {
  const _SubAgentStatePill({required this.message});

  final WorkbenchMessage message;

  @override
  Widget build(BuildContext context) {
    final color = message.isError
        ? theme.red
        : message.completed
            ? theme.green
            : theme.amber;
    final label = message.isError
        ? 'error'
        : message.completed
            ? 'complete'
            : 'running';
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
            color: color.withValues(alpha: .09),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: .22))),
        child: Text(label,
            style: TextStyle(
                color: color,
                fontSize: WorkbenchTranscriptTypography.toolMeta.fontSize,
                height: 1,
                fontWeight: FontWeight.w800,
                letterSpacing: 0)));
  }
}

String _commandTitle(WorkbenchMessage message) {
  final firstLine = message.body
      .split('\n')
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => message.title);
  return firstLine;
}

bool isSubAgentCommand(WorkbenchMessage message) {
  if (message.role != 'command') return false;
  final tool = _normalizeToolIdentity(_rawToolName(message));
  final title = _normalizeToolIdentity(_commandTitle(message));
  return tool == 'agent' || tool == 'subagent' || title == 'agent';
}

String _subAgentTitle(WorkbenchMessage message) {
  final input = _messageInputMap(message);
  final subject = input == null
      ? null
      : _firstNonEmptyNestedInputString(input, const <String>[
          'description',
          'subject',
          'title',
          'task',
          'goal',
          'objective',
          'prompt',
          'instruction',
          'instructions',
          'question',
          'message',
        ]);
  if (subject != null) return subject;
  final command = _commandTitle(message).trim();
  if (command.isNotEmpty && _normalizeToolIdentity(command) != 'agent') {
    return command;
  }
  return 'Delegated sub-agent';
}

String? _subAgentPrompt(WorkbenchMessage message) {
  final input = _messageInputMap(message);
  final prompt = input == null
      ? null
      : _firstNonEmptyNestedInputString(input, const <String>[
          'prompt',
          'message',
          'question',
          'content',
          'text',
          'input',
          'request',
          'instruction',
          'instructions',
          'goal',
          'objective',
          'description',
          'task',
        ]);
  if (prompt != null) return prompt;
  final body = message.body.trim();
  if (body.isEmpty || _normalizeToolIdentity(body) == 'agent') return null;
  return body;
}

String _subAgentMeta(WorkbenchMessage message) {
  final parts = <String>['sub-agent'];
  final duration = _formatCommandDuration(message.duration);
  if (duration != null) parts.add(duration);
  parts.add(message.isError
      ? 'error'
      : message.completed
          ? 'completed'
          : 'running');
  return parts.join(' / ');
}

Map<String, Object?>? _messageInputMap(WorkbenchMessage message) {
  final input = message.event?.raw['input'];
  if (input is Map) return Map<String, Object?>.from(input);
  return null;
}

String? _firstNonEmptyNestedInputString(
    Map<String, Object?> input, List<String> keys) {
  for (final key in keys) {
    final value = input[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  for (final value in input.values) {
    if (value is Map) {
      final nested = _firstNonEmptyNestedInputString(
          Map<String, Object?>.from(value), keys);
      if (nested != null) return nested;
    }
  }
  return null;
}

String _normalizeToolIdentity(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '').trim();

class _ToolLogFoldout extends StatefulWidget {
  const _ToolLogFoldout({required this.message, required this.expandByDefault});
  final WorkbenchMessage message;
  final bool expandByDefault;

  @override
  State<_ToolLogFoldout> createState() => _ToolLogFoldoutState();
}

class _ToolLogFoldoutState extends State<_ToolLogFoldout> {
  late bool _expanded = widget.expandByDefault;

  @override
  void didUpdateWidget(covariant _ToolLogFoldout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.body != widget.message.body ||
        oldWidget.message.title != widget.message.title) {
      _expanded = widget.expandByDefault;
    } else if (oldWidget.expandByDefault != widget.expandByDefault) {
      _expanded = widget.expandByDefault;
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final output = _commandOutput(message);
    final ok = message.completed && !message.isError;
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
              key: const ValueKey('workbench-tool-foldout-row'),
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _expanded = !_expanded),
              child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 1, vertical: 5),
                  child: Row(children: [
                    _ToolKindBadge(kind: _toolKindLabel(message)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(_toolTargetTitle(message),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: WorkbenchTranscriptTypography.toolTitle)),
                    if (ok || message.isError) ...[
                      const SizedBox(width: 7),
                      _InlineEventTrailing(ok: ok, error: message.isError),
                    ],
                    const SizedBox(width: 3),
                    Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: theme.faint,
                        size: 17),
                  ]))),
          if (_expanded)
            Container(
                key: const ValueKey('workbench-tool-foldout-expanded'),
                padding: const EdgeInsets.fromLTRB(1, 8, 0, 4),
                decoration: BoxDecoration(
                    border: Border(
                        top: BorderSide(
                            color: Colors.white.withValues(alpha: .052)))),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _CommandExpandedMeta(message: message),
                      const SizedBox(height: 7),
                      _ToolDetailBlock(
                          label: 'input',
                          text: message.body,
                          onTap: () => _showCommandDetailSheet(
                              context: context,
                              title: AppLocalizations.of(context)
                                  .workbenchCommandDetailTitle,
                              subtitle: _commandDetailSubtitle(message),
                              text: message.body)),
                      if (output != null) ...[
                        const SizedBox(height: 7),
                        _ToolDetailBlock(
                            label: 'output',
                            text: output,
                            onTap: () => _showCommandDetailSheet(
                                context: context,
                                title: AppLocalizations.of(context)
                                    .workbenchOutputDetailTitle,
                                subtitle: _commandDetailSubtitle(message),
                                text: output)),
                      ]
                    ])),
        ]);
  }
}

class _ToolKindBadge extends StatelessWidget {
  const _ToolKindBadge({required this.kind});
  final String kind;

  @override
  Widget build(BuildContext context) => Container(
      height: 24,
      constraints: const BoxConstraints(minWidth: 42),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
          color: const Color(0xFF121419),
          borderRadius: BorderRadius.circular(8),
          border:
              Border.all(color: _toolKindColor(kind).withValues(alpha: .14))),
      child: Text(kind,
          style: TextStyle(
              color: _toolKindColor(kind),
              fontSize: WorkbenchTranscriptTypography.shellLabel.fontSize,
              fontFamily: WorkbenchTranscriptTypography.shellLabel.fontFamily,
              fontFamilyFallback: workbenchMonoFontFallback,
              fontWeight: FontWeight.w900,
              letterSpacing: 0)));
}

class _ToolDetailBlock extends StatefulWidget {
  const _ToolDetailBlock(
      {required this.label, required this.text, required this.onTap});
  final String label;
  final String text;
  final VoidCallback onTap;

  @override
  State<_ToolDetailBlock> createState() => _ToolDetailBlockState();
}

class _ToolDetailBlockState extends State<_ToolDetailBlock> {
  @override
  Widget build(BuildContext context) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
                padding: const EdgeInsets.only(left: 1, bottom: 4),
                child: Text(widget.label,
                    style: WorkbenchTranscriptTypography.shellLabel)),
            Material(
                color: Colors.transparent,
                child: InkWell(
                    onTap: widget.onTap,
                    borderRadius: BorderRadius.circular(9),
                    child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                            color: const Color(0xFF121316),
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: .052))),
                        child: Row(children: [
                          Expanded(
                              child: Text(widget.text,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: true,
                                  style: WorkbenchTranscriptTypography
                                      .shellOutput
                                      .copyWith(fontSize: 12))),
                          const SizedBox(width: 8),
                          const Icon(Icons.open_in_full_rounded,
                              color: theme.faint, size: 12),
                        ])))),
          ]);
}

String _toolKindLabel(WorkbenchMessage message) {
  final tool = _rawToolName(message).toLowerCase();
  final title = _commandTitle(message).toLowerCase();
  if (tool.contains('read') || title.startsWith('read ')) return 'READ';
  if (tool.contains('glob') || title.startsWith('glob ')) return 'GLOB';
  if (tool == 'ls' || tool.contains('list') || title.startsWith('ls ')) {
    return 'LS';
  }
  if (tool.contains('grep') || title.startsWith('grep ')) return 'GREP';
  if (tool.contains('write')) return 'WRITE';
  if (tool.contains('edit')) return 'EDIT';
  if (tool.contains('bash') || tool.contains('shell')) return 'CMD';
  return 'TOOL';
}

String _toolTargetTitle(WorkbenchMessage message) {
  final title = _commandTitle(message);
  final lower = title.toLowerCase();
  for (final prefix in const ['read ', 'glob ', 'ls ', 'grep ']) {
    if (lower.startsWith(prefix)) return title.substring(prefix.length).trim();
  }
  return title;
}

String _rawToolName(WorkbenchMessage message) {
  final direct = message.event?.raw['toolName'] ?? message.event?.raw['name'];
  if (direct is String && direct.trim().isNotEmpty) return direct.trim();
  final name = message.event?.name;
  if (name != null && name.trim().isNotEmpty) return name.trim();
  return message.title;
}

Color _toolKindColor(String kind) => switch (kind) {
      'READ' => theme.purple2,
      'GLOB' => theme.purple,
      'LS' => const Color(0xFF7DD3C7),
      'GREP' => const Color(0xFF93C5FD),
      'WRITE' => theme.amber,
      'EDIT' => theme.amber,
      'CMD' => theme.orange,
      _ => theme.faint,
    };

String _commandMeta(BuildContext context, WorkbenchMessage message) {
  final l10n = AppLocalizations.of(context);
  if (message.title.trim().isEmpty) return l10n.workbenchCommandMetaEmpty;
  return l10n.workbenchCommandMetaWithTitle(message.title);
}

class _CommandExpandedMeta extends StatelessWidget {
  const _CommandExpandedMeta({required this.message});
  final WorkbenchMessage message;

  @override
  Widget build(BuildContext context) {
    final duration = _formatCommandDuration(message.duration);
    final parts = <String>[_commandMeta(context, message)];
    if (duration != null) parts.add('duration $duration');
    parts.add(message.isError
        ? 'error'
        : message.completed
            ? 'completed'
            : 'running');
    return Text(parts.join(' / '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: WorkbenchTranscriptTypography.toolMeta);
  }
}

class _InlineEventTrailing extends StatelessWidget {
  const _InlineEventTrailing({required this.ok, required this.error});
  final bool ok;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final color = error ? theme.red : theme.green;
    return Icon(error ? Icons.close_rounded : Icons.check_rounded,
        key: ValueKey(error ? 'tool-status-error' : 'tool-status-ok'),
        color: color,
        size: 15);
  }
}

String? _commandOutput(WorkbenchMessage message) {
  final output = message.event?.raw['output'];
  if (output is String && output.trim().isNotEmpty) return output.trim();
  return null;
}

String _commandDetailSubtitle(WorkbenchMessage message) {
  final parts = <String>[];
  final toolName = message.event?.raw['toolName'];
  if (toolName is String && toolName.trim().isNotEmpty) parts.add(toolName);
  final duration = _formatCommandDuration(message.duration);
  if (duration != null) parts.add(duration);
  parts.add(message.completed ? 'completed' : 'running');
  return parts.join(' · ');
}

void _showCommandDetailSheet({
  required BuildContext context,
  required String title,
  required String subtitle,
  required String text,
}) {
  showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CommandDetailSheet(
          title: title, subtitle: subtitle, text: text.trimRight()));
}

class _CommandDetailSheet extends StatelessWidget {
  const _CommandDetailSheet(
      {required this.title, required this.subtitle, required this.text});
  final String title;
  final String subtitle;
  final String text;

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
      initialChildSize: .86,
      minChildSize: .45,
      maxChildSize: .96,
      expand: false,
      builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
              color: Color(0xFF101113),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(
                child: Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(top: 10, bottom: 14),
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .22),
                        borderRadius: BorderRadius.circular(999)))),
            Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 10, 12),
                child: Row(children: [
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(title,
                            style: const TextStyle(
                                color: theme.text,
                                fontSize: 18,
                                fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        Text(subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: theme.faint,
                                fontSize: 11,
                                fontFamily: 'Cascadia Mono',
                                fontFamilyFallback: workbenchMonoFontFallback)),
                      ])),
                  IconButton(
                      tooltip:
                          AppLocalizations.of(context).workbenchCopyAllTooltip,
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: text));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(AppLocalizations.of(context)
                                .workbenchCopiedSnack)));
                      },
                      icon: const Icon(Icons.copy_rounded, color: theme.muted)),
                  IconButton(
                      tooltip:
                          AppLocalizations.of(context).workbenchCloseTooltip,
                      onPressed: () => Navigator.of(context).pop(),
                      icon:
                          const Icon(Icons.close_rounded, color: theme.muted)),
                ])),
            Expanded(
                child: Container(
                    margin: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                    decoration: BoxDecoration(
                        color: const Color(0xFF0B0C0E),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: .07))),
                    child: Scrollbar(
                        controller: scrollController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                            controller: scrollController,
                            padding: const EdgeInsets.all(14),
                            scrollDirection: Axis.vertical,
                            child: SelectableText(text,
                                textWidthBasis: TextWidthBasis.parent,
                                style: const TextStyle(
                                    color: Color(0xFFB7BEC9),
                                    fontSize: 12.5,
                                    fontFamily: 'Cascadia Mono',
                                    fontFamilyFallback:
                                        workbenchMonoFontFallback,
                                    height: 1.45))))))
          ])));
}

@visibleForTesting
Widget buildCompletedCommandCardPreview({bool expandToolDetails = false}) =>
    MaterialApp(
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
            body: Padding(
                padding: const EdgeInsets.all(16),
                child: CommandEventCard(
                    expandByDefault: expandToolDetails,
                    message: const WorkbenchMessage(
                        'command',
                        'cwd resolved · permissions checked',
                        'npm run lint && npm test',
                        runId: 'run_1',
                        completed: true,
                        duration: Duration(milliseconds: 2100))))));

@visibleForTesting
Widget buildConversationCommandCardPreview({bool expandToolDetails = false}) {
  final startedAt = DateTime.parse('2026-05-03T00:00:01.000Z');
  final completedAt = DateTime.parse('2026-05-03T00:00:03.000Z');
  final message = workbenchMessageFromConversation(ConversationMessage(
      role: 'command',
      text: 'python intro.py',
      eventSeq: 2,
      approvalId: 'approval_1',
      completed: true,
      startedAt: startedAt,
      completedAt: completedAt,
      output: 'hello from intro'));
  return MaterialApp(
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
          body: Padding(
              padding: const EdgeInsets.all(16),
              child: CommandEventCard(
                  message: message, expandByDefault: expandToolDetails))));
}

@visibleForTesting
Widget buildSubAgentCallCardPreview({bool expandToolDetails = false}) {
  final event = AgentEvent(
      type: 'raw.output',
      seq: 2,
      runId: 'conversation',
      createdAt: DateTime.parse('2026-05-03T00:00:01.000Z'),
      text: 'Agent',
      name: 'Agent',
      raw: const <String, Object?>{
        'toolName': 'Agent',
        'input': <String, Object?>{
          'description': 'Review the repository changes',
          'prompt': 'Check the current diff and report risks.'
        },
        'output': 'No blocking issues found.'
      });
  return MaterialApp(
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
          body: Padding(
              padding: const EdgeInsets.all(16),
              child: SubAgentCallCard(
                  expandByDefault: expandToolDetails,
                  message: WorkbenchMessage('command', 'Run command', 'Agent',
                      event: event,
                      runId: 'conversation',
                      completed: true,
                      duration: const Duration(milliseconds: 2300))))));
}

@visibleForTesting
Widget buildLargeOutputCommandCardPreview({bool expandToolDetails = false}) {
  final largeOutput =
      List<String>.generate(205, (index) => 'line $index').join('\n');
  final message = workbenchMessageFromConversation(ConversationMessage(
      role: 'command',
      text: 'cat huge.log',
      eventSeq: 2,
      completed: true,
      output: largeOutput));
  return MaterialApp(
      locale: const Locale('en', 'US'),
      supportedLocales: const [theme.zhHansCnLocale, Locale('en', 'US')],
      localizationsDelegates: theme.appLocalizationsDelegates,
      theme: ThemeData(
          brightness: Brightness.dark,
          fontFamily: 'Segoe UI',
          fontFamilyFallback: theme.appFontFallback,
          useMaterial3: true),
      home: Scaffold(
          backgroundColor: theme.bg,
          body: Padding(
              padding: const EdgeInsets.all(16),
              child: CommandEventCard(
                  message: message, expandByDefault: expandToolDetails))));
}

String? _formatCommandDuration(Duration? duration) {
  if (duration == null) return null;
  final seconds = duration.inMilliseconds / 1000;
  if (seconds < 10) return '${seconds.toStringAsFixed(1)}s';
  return '${seconds.round()}s';
}
