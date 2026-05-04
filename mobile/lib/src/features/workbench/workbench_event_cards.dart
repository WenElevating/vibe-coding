part of '../../app/app.dart';

class _WorkbenchInlineStatus extends StatelessWidget {
  const _WorkbenchInlineStatus({
    required this.adapter,
    required this.runId,
    required this.eventCount,
    required this.terminal,
  });
  final String? adapter;
  final String? runId;
  final int eventCount;
  final bool terminal;

  @override
  Widget build(BuildContext context) {
    final text = runId == null
        ? '准备好接收编码任务'
        : terminal
            ? '本次 CLI 会话已完成 · $eventCount 个事件已处理'
            : '正在连接 ${adapter ?? 'CLI'} · 已处理 $eventCount 个事件';
    return Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            color: const Color(0x66111B2A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: .075))),
        child: Row(children: [
          _PulseDot(active: runId != null && !terminal),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 12))),
        ]));
  }
}

class _WorkbenchMessageCard extends StatelessWidget {
  const _WorkbenchMessageCard(
      {required this.message,
      required this.onApproval,
      required this.onSuggestion,
      required this.expandThinking});
  final _WorkbenchMessage message;
  final ValueChanged<String> onApproval;
  final ValueChanged<String> onSuggestion;
  final bool expandThinking;
  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final isApproval = message.role == 'approval';
    final isCommand = message.role == 'command';
    final isDiff = message.role == 'diff';
    final isTool = isCommand || isDiff;
    if (isCommand) return _CommandEventCard(message: message);
    if (isDiff) return _DiffEventCard(message: message);
    if (message.role == 'thinking') {
      return _ThinkingEventCard(message: message, expanded: expandThinking);
    }
    if (isApproval) {
      return _ApprovalEventCard(message: message, onApproval: onApproval);
    }
    if (message.role == 'question') {
      return _QuestionEventCard(message: message, onSuggestion: onSuggestion);
    }
    if (message.role == 'notice') {
      return _SystemNoticeEventCard(message: message);
    }
    final color = isUser
        ? _purple2
        : isApproval
            ? _amber
            : isTool
                ? _orange
                : _green;
    return Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: FractionallySizedBox(
            widthFactor: isUser ? .78 : 1,
            child: Container(
                padding: EdgeInsets.fromLTRB(isUser ? 13 : 16,
                    isApproval ? 12 : 11, isUser ? 13 : 16, 11),
                decoration: BoxDecoration(
                    gradient: isUser ? null : null,
                    color: isUser
                        ? const Color(0xFF191A1E)
                        : isApproval
                            ? const Color(0xFF101113)
                            : message.role == 'assistant'
                                ? Colors.transparent
                                : const Color(0xFF101113),
                    borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(isApproval ? 14 : 18),
                        topRight: Radius.circular(isApproval ? 14 : 18),
                        bottomLeft: Radius.circular(isUser
                            ? 18
                            : isApproval
                                ? 14
                                : 6),
                        bottomRight: Radius.circular(isUser
                            ? 6
                            : isApproval
                                ? 14
                                : 18)),
                    border: Border.all(
                        color: isUser
                            ? Colors.white.withValues(alpha: .085)
                            : isApproval
                                ? Colors.white.withValues(alpha: .08)
                                : message.role == 'assistant'
                                    ? Colors.transparent
                                    : _stroke)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!isUser && message.role != 'assistant') ...[
                        Row(children: [
                          Container(
                              width: isApproval ? 24 : 18,
                              height: isApproval ? 24 : 18,
                              alignment: Alignment.center,
                              decoration: isApproval
                                  ? BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      color: _amber.withValues(alpha: .10),
                                      border: Border.all(
                                          color: _amber.withValues(alpha: .22)))
                                  : null,
                              child: Icon(
                                  isApproval
                                      ? Icons.shield_outlined
                                      : isTool
                                          ? Icons.build_circle_rounded
                                          : Icons.auto_awesome_rounded,
                                  color: color,
                                  size: isApproval ? 15 : 16)),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(message.title,
                                  style: const TextStyle(
                                      color: _text,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700))),
                        ]),
                        const SizedBox(height: 8),
                      ],
                      if (message.role == 'assistant')
                        _AssistantMarkdownBody(markdown: message.body)
                      else
                        Text(message.body,
                            style: TextStyle(
                                color:
                                    isUser ? const Color(0xFFF4F4F4) : _muted,
                                fontSize: isUser ? 14.5 : 12.5,
                                height: isUser ? 1.45 : 1.55,
                                fontWeight: isUser
                                    ? FontWeight.w500
                                    : FontWeight.w400)),
                      if (isApproval) ...[
                        const SizedBox(height: 12),
                        if (message.event?.approvalId == null)
                          const Text('daemon 未提供 approvalId，无法在移动端处理。',
                              style: TextStyle(color: _red, fontSize: 12))
                        else
                          Row(children: [
                            Expanded(
                                child: _ApprovalActionButton('拒绝',
                                    color: _red,
                                    onTap: () => onApproval('deny'))),
                            const SizedBox(width: 10),
                            Expanded(
                                child: _ApprovalActionButton('批准',
                                    color: _purple2,
                                    primary: true,
                                    onTap: () => onApproval('allow'))),
                          ])
                      ]
                    ]))));
  }
}

class _AssistantMarkdownBody extends StatelessWidget {
  const _AssistantMarkdownBody({required this.markdown});
  final String markdown;

  @override
  Widget build(BuildContext context) => MarkdownBody(
      data: _normalizeAssistantMarkdown(markdown),
      selectable: true,
      softLineBreak: true,
      styleSheet: _buildAssistantMarkdownStyleSheet(context),
      imageBuilder: (_, __, ___) => const SizedBox.shrink(),
      onTapLink: (_, __, ___) {});
}

class _QuestionEventCard extends StatelessWidget {
  const _QuestionEventCard({required this.message, required this.onSuggestion});
  final _WorkbenchMessage message;
  final ValueChanged<String> onSuggestion;

  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: const Color(0xFF101113),
          border: Border.all(color: Colors.white.withValues(alpha: .075))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: _purple.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _purple.withValues(alpha: .26))),
              child: const Icon(Icons.tune_rounded, color: _purple2, size: 15)),
          const SizedBox(width: 10),
          const Expanded(
              child: Text('需要你补充方向',
                  style: TextStyle(
                      color: _text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 12),
        Text(message.body,
            style:
                const TextStyle(color: _muted, fontSize: 13.5, height: 1.55)),
        if (message.suggestions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
              spacing: 8,
              runSpacing: 8,
              children: message.suggestions
                  .map((item) => _QuestionSuggestionChip(
                      text: item, onTap: () => onSuggestion(item)))
                  .toList(growable: false)),
        ]
      ]));
}

class _SystemNoticeEventCard extends StatelessWidget {
  const _SystemNoticeEventCard({required this.message});
  final _WorkbenchMessage message;

  @override
  Widget build(BuildContext context) => _AgentEventCard(
      icon: Icons.info_outline_rounded,
      title: message.title,
      meta: 'non-blocking',
      trailing: null,
      child: Text(message.body,
          style: const TextStyle(color: _muted, fontSize: 12.5, height: 1.55)));
}

class _ThinkingEventCard extends StatelessWidget {
  const _ThinkingEventCard({required this.message, required this.expanded});
  final _WorkbenchMessage message;
  final bool expanded;

  @override
  Widget build(BuildContext context) =>
      _ExpandableThinkingCard(message: message, initiallyExpanded: expanded);
}

class _ExpandableThinkingCard extends StatefulWidget {
  const _ExpandableThinkingCard(
      {required this.message, required this.initiallyExpanded});
  final _WorkbenchMessage message;
  final bool initiallyExpanded;

  @override
  State<_ExpandableThinkingCard> createState() =>
      _ExpandableThinkingCardState();
}

class _ExpandableThinkingCardState extends State<_ExpandableThinkingCard> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  void didUpdateWidget(covariant _ExpandableThinkingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.body != widget.message.body) {
      _expanded = widget.initiallyExpanded;
    }
  }

  @override
  Widget build(BuildContext context) => InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      borderRadius: BorderRadius.circular(16),
      child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: const Color(0xFF0E1013),
              border: Border.all(color: Colors.white.withValues(alpha: .06))),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.psychology_alt_rounded,
                  color: _purple2.withValues(alpha: .92), size: 16),
              const SizedBox(width: 8),
              const Expanded(
                  child: Text('思考过程',
                      style: TextStyle(
                          color: _text,
                          fontSize: 13,
                          fontWeight: FontWeight.w800))),
              Text(_expanded ? '收起' : '展开',
                  style: const TextStyle(color: _muted, fontSize: 11)),
            ]),
            if (_expanded) ...[
              const SizedBox(height: 10),
              Text(widget.message.body,
                  style: const TextStyle(
                      color: _muted, fontSize: 12.5, height: 1.55)),
            ]
          ])));
}

class _QuestionSuggestionChip extends StatelessWidget {
  const _QuestionSuggestionChip({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: Colors.white.withValues(alpha: .045),
              border: Border.all(color: Colors.white.withValues(alpha: .10))),
          child: Text(text,
              style: const TextStyle(
                  color: Color(0xFFDCE2EE),
                  fontSize: 12,
                  fontWeight: FontWeight.w700))));
}

class _ApprovalActionButton extends StatelessWidget {
  const _ApprovalActionButton(this.text,
      {required this.color, required this.onTap, this.primary = false});
  final String text;
  final Color color;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              gradient: primary
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF2F3034), Color(0xFF1A1B1E)])
                  : null,
              color: primary ? null : color.withValues(alpha: .045),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: primary
                      ? Colors.white.withValues(alpha: .14)
                      : color.withValues(alpha: .34))),
          child: Text(text,
              style: TextStyle(
                  color: primary ? _text : color,
                  fontSize: 13,
                  letterSpacing: .4,
                  fontWeight: FontWeight.w800))));
}

class _CommandEventCard extends StatelessWidget {
  const _CommandEventCard({required this.message});
  final _WorkbenchMessage message;

  @override
  Widget build(BuildContext context) {
    final output = _commandOutput(message);
    final ok = message.completed && !message.isError;
    return _AgentEventCard(
        icon: Icons.chevron_right_rounded,
        title: 'Ran command',
        meta: message.title,
        trailing: _formatCommandDuration(message.duration),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _EventCodeLine(
              text: message.body,
              ok: ok,
              error: message.isError,
              onTap: () => _showCommandDetailSheet(
                  context: context,
                  title: '命令详情',
                  subtitle: _commandDetailSubtitle(message),
                  text: message.body)),
          if (output != null) ...[
            const SizedBox(height: 10),
            _EventCodeLine(
                text: output,
                ok: ok,
                error: message.isError,
                onTap: () => _showCommandDetailSheet(
                    context: context,
                    title: '输出详情',
                    subtitle: _commandDetailSubtitle(message),
                    text: output)),
          ]
        ]));
  }
}

String? _commandOutput(_WorkbenchMessage message) {
  final output = message.event?.raw['output'];
  if (output is String && output.trim().isNotEmpty) return output.trim();
  return null;
}

String _commandDetailSubtitle(_WorkbenchMessage message) {
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
                                color: _text,
                                fontSize: 18,
                                fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        Text(subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: _faint,
                                fontSize: 11,
                                fontFamily: 'Consolas')),
                      ])),
                  IconButton(
                      tooltip: '复制全文',
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: text));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已复制到剪贴板')));
                      },
                      icon: const Icon(Icons.copy_rounded, color: _muted)),
                  IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, color: _muted)),
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
                            child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: SelectableText(text,
                                    style: const TextStyle(
                                        color: _muted,
                                        fontSize: 12.5,
                                        fontFamily: 'Consolas',
                                        height: 1.45)))))))
          ])));
}

@visibleForTesting
Widget buildCompletedCommandCardPreview() => MaterialApp(
    locale: _zhHansCnLocale,
    supportedLocales: const [_zhHansCnLocale, Locale('en', 'US')],
    localizationsDelegates: _appLocalizationsDelegates,
    theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'Segoe UI',
        fontFamilyFallback: _appFontFallback,
        useMaterial3: true),
    home: Scaffold(
        backgroundColor: _bg,
        body: Padding(
            padding: const EdgeInsets.all(16),
            child: _CommandEventCard(
                message: const _WorkbenchMessage(
                    'command',
                    'cwd resolved · permissions checked',
                    'npm run lint && npm test',
                    runId: 'run_1',
                    completed: true,
                    duration: Duration(milliseconds: 2100))))));

@visibleForTesting
Widget buildConversationCommandCardPreview() {
  final startedAt = DateTime.parse('2026-05-03T00:00:01.000Z');
  final completedAt = DateTime.parse('2026-05-03T00:00:03.000Z');
  final message = _workbenchMessageFromConversation(ConversationMessage(
      role: 'command',
      text: 'python intro.py',
      eventSeq: 2,
      approvalId: 'approval_1',
      completed: true,
      startedAt: startedAt,
      completedAt: completedAt,
      output: 'hello from intro'));
  return MaterialApp(
      locale: _zhHansCnLocale,
      supportedLocales: const [_zhHansCnLocale, Locale('en', 'US')],
      localizationsDelegates: _appLocalizationsDelegates,
      theme: ThemeData(
          brightness: Brightness.dark,
          fontFamily: 'Segoe UI',
          fontFamilyFallback: _appFontFallback,
          useMaterial3: true),
      home: Scaffold(
          backgroundColor: _bg,
          body: Padding(
              padding: const EdgeInsets.all(16),
              child: _CommandEventCard(message: message))));
}

@visibleForTesting
Widget buildPendingSentinelPreview() => MaterialApp(
    locale: _zhHansCnLocale,
    supportedLocales: const [_zhHansCnLocale, Locale('en', 'US')],
    localizationsDelegates: _appLocalizationsDelegates,
    theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'Segoe UI',
        fontFamilyFallback: _appFontFallback,
        useMaterial3: true),
    home: const Scaffold(
        backgroundColor: _bg,
        body: Padding(
            padding: EdgeInsets.all(16),
            child: _PendingSentinel(
                adapter: 'claude',
                statusText: '正在接收 CLI 输出...',
                actions: <String>['已启动 claude 会话', 'Claude requesting']))));

String? _formatCommandDuration(Duration? duration) {
  if (duration == null) return null;
  final seconds = duration.inMilliseconds / 1000;
  if (seconds < 10) return '${seconds.toStringAsFixed(1)}s';
  return '${seconds.round()}s';
}

class _DiffEventCard extends StatelessWidget {
  const _DiffEventCard({required this.message});
  final _WorkbenchMessage message;

  @override
  Widget build(BuildContext context) => _AgentEventCard(
      icon: Icons.call_split_rounded,
      title: 'Changed files',
      meta: 'diff summary',
      trailing: null,
      child: _EventCodeLine(text: message.body, ok: true));
}

class _ApprovalEventCard extends StatelessWidget {
  const _ApprovalEventCard({required this.message, required this.onApproval});
  final _WorkbenchMessage message;
  final ValueChanged<String> onApproval;

  @override
  Widget build(BuildContext context) => _AgentEventCard(
      icon: Icons.priority_high_rounded,
      title: '需要审批',
      meta: _approvalMeta(message.event),
      trailing: _eventTime(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(message.body,
            style:
                const TextStyle(color: _muted, fontSize: 12.5, height: 1.55)),
        const SizedBox(height: 12),
        if (message.event?.approvalId == null)
          const Text('daemon 未提供 approvalId，无法在移动端处理。',
              style: TextStyle(color: _red, fontSize: 12))
        else
          Row(children: [
            Expanded(
                child: _ApprovalActionButton('拒绝',
                    color: _red, onTap: () => onApproval('deny'))),
            const SizedBox(width: 10),
            Expanded(
                child: _ApprovalActionButton('批准',
                    color: _text,
                    primary: true,
                    onTap: () => onApproval('allow'))),
          ])
      ]));

  static String _approvalMeta(AgentEvent? event) {
    if (event == null) return 'permission request';
    return '${event.name ?? 'Tool'} · write access';
  }

  static String _eventTime() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }
}

class _AgentEventCard extends StatelessWidget {
  const _AgentEventCard(
      {required this.icon,
      required this.title,
      required this.meta,
      required this.child,
      this.trailing});
  final IconData icon;
  final String title;
  final String meta;
  final Widget child;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: const Color(0xFF101113),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: .075))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: const Color(0xFF191A1D),
                  borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, color: _amber, size: 15)),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: const TextStyle(
                        color: _text,
                        fontSize: 13,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: _faint, fontSize: 10.5, fontFamily: 'Consolas')),
              ])),
          if (trailing != null)
            Text(trailing!,
                style: const TextStyle(
                    color: _faint, fontSize: 10.5, fontFamily: 'Consolas'))
        ]),
        const SizedBox(height: 12),
        child,
      ]));
}

class _EventCodeLine extends StatelessWidget {
  const _EventCodeLine(
      {required this.text, required this.ok, this.error = false, this.onTap});
  final String text;
  final bool ok;
  final bool error;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
      color: Colors.transparent,
      child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                  color: const Color(0xFF0B0C0E),
                  borderRadius: BorderRadius.circular(11),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: .055))),
              child: Row(children: [
                Expanded(
                    child: Text(text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: _muted,
                            fontSize: 12,
                            fontFamily: 'Consolas',
                            height: 1.35))),
                if (onTap != null) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.open_in_full_rounded,
                      color: _faint, size: 13),
                ],
                if (error) ...[
                  const SizedBox(width: 8),
                  const Text('error',
                      style: TextStyle(
                          color: _red,
                          fontSize: 11,
                          fontFamily: 'Consolas',
                          fontWeight: FontWeight.w800))
                ] else if (ok) ...[
                  const SizedBox(width: 8),
                  const Text('ok',
                      style: TextStyle(
                          color: _green,
                          fontSize: 11,
                          fontFamily: 'Consolas',
                          fontWeight: FontWeight.w800))
                ]
              ]))));
}

String _normalizeAssistantMarkdown(String markdown) {
  final withoutHtml = markdown.replaceAll(RegExp(r'<[^>]+>'), '');
  return withoutHtml
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

MarkdownStyleSheet _buildAssistantMarkdownStyleSheet(BuildContext context) {
  const codeBg = Color(0x66101824);
  const codeBorder = Color(0x22FFFFFF);
  final base = Theme.of(context).textTheme;
  return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: base.bodyMedium?.copyWith(color: _muted, fontSize: 14.5, height: 1.68),
      strong: const TextStyle(color: _text, fontWeight: FontWeight.w700),
      em: const TextStyle(
          color: Color(0xFFD3DAE8), fontStyle: FontStyle.italic),
      h1: const TextStyle(
          color: _text,
          fontSize: 17,
          height: 1.35,
          fontWeight: FontWeight.w800),
      h2: const TextStyle(
          color: _text,
          fontSize: 15.5,
          height: 1.35,
          fontWeight: FontWeight.w800),
      h3: const TextStyle(
          color: _text, fontSize: 14, height: 1.4, fontWeight: FontWeight.w800),
      listBullet: const TextStyle(color: _green, fontSize: 12, height: 1.55),
      code: const TextStyle(
          color: Color(0xFFE7ECF8),
          backgroundColor: Color(0xFF18191C),
          fontFamily: 'Consolas',
          fontSize: 13,
          height: 1.45),
      codeblockDecoration: BoxDecoration(
          color: codeBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: codeBorder)),
      blockquote: const TextStyle(color: Color(0xFFBBC5D6), fontSize: 13),
      blockquoteDecoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .04),
          border: const Border(left: BorderSide(color: _purple, width: 3)),
          borderRadius: BorderRadius.circular(8)),
      a: const TextStyle(color: Color(0xFF7C8CFF), fontWeight: FontWeight.w800),
      horizontalRuleDecoration: BoxDecoration(
          border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: .08)))),
      pPadding: const EdgeInsets.only(bottom: 8),
      h1Padding: const EdgeInsets.only(top: 2, bottom: 8),
      h2Padding: const EdgeInsets.only(top: 2, bottom: 7),
      h3Padding: const EdgeInsets.only(top: 2, bottom: 6),
      listIndent: 18,
      blockSpacing: 8,
      codeblockPadding: const EdgeInsets.all(10));
}

class _PendingSentinel extends StatefulWidget {
  const _PendingSentinel({
    required this.adapter,
    required this.statusText,
    this.actions = const <String>[],
  });

  final String adapter;
  final String statusText;
  final List<String> actions;

  @override
  State<_PendingSentinel> createState() => _PendingSentinelState();
}

class _PendingSentinelState extends State<_PendingSentinel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 850))
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
            margin: const EdgeInsets.only(top: 2, bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: .07)),
                gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xF2141517), Color(0xEE0E0F11)])),
            child: Row(children: [
              _RunningOrb(progress: _controller.value),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const Text('正在运行',
                        style: TextStyle(
                            color: _text,
                            fontWeight: FontWeight.w800,
                            fontSize: 13)),
                    const SizedBox(height: 5),
                    AnimatedSwitcher(
                        duration: const Duration(milliseconds: 240),
                        child: Text(widget.statusText,
                            key: ValueKey(widget.statusText),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: _muted, fontSize: 12, height: 1.3))),
                  ])),
              _PulseBars(progress: _controller.value),
            ]));
      });
}

class _RunningOrb extends StatelessWidget {
  const _RunningOrb({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    final pulse = progress < .5 ? progress * 2 : (1 - progress) * 2;
    return Container(
        width: 18,
        height: 18,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _purple.withValues(alpha: .08 + pulse * .08),
            border: Border.all(color: _purple.withValues(alpha: .18))),
        child: Container(
            width: 7 + pulse * 2,
            height: 7 + pulse * 2,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _purple2.withValues(alpha: .75),
                boxShadow: [
                  BoxShadow(
                      color: _purple.withValues(alpha: .22 + pulse * .18),
                      blurRadius: 8 + pulse * 8)
                ])));
  }
}

class _PulseBars extends StatelessWidget {
  const _PulseBars({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) => Row(
          children: List.generate(3, (index) {
        final phase = (progress + index * .22) % 1;
        final height = 6 + (phase < .5 ? phase : 1 - phase) * 18;
        return Container(
            margin: const EdgeInsets.only(left: 3),
            width: 3,
            height: height,
            decoration: BoxDecoration(
                color: _purple.withValues(alpha: .28 + phase * .34),
                borderRadius: BorderRadius.circular(999)));
      }));
}

class _PulseDot extends StatelessWidget {
  const _PulseDot({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) => Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? _green : _faint,
          boxShadow: active
              ? [
                  BoxShadow(
                      color: _green.withValues(alpha: .45),
                      blurRadius: 12,
                      spreadRadius: 2)
                ]
              : null));
}
