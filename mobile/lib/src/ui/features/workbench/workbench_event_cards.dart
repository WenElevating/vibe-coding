import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../models/protocol.dart';
import '../../core/theme/theme.dart' as theme;
import 'conversation_reducer.dart';
import 'workbench_messages.dart';

const _codeCopySuccessBackground = Color(0xFFE7ECF8);
const _codeCopySuccessBorder = Color(0xFFF4F7FC);
const _codeCopySuccessIcon = Color(0xFF0B0C0E);
const _codeCopyFeedbackDuration = Duration(seconds: 2);

class WorkbenchInlineStatus extends StatelessWidget {
  const WorkbenchInlineStatus({
    super.key,
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
    final l10n = AppLocalizations.of(context);
    final text = runId == null
        ? l10n.workbenchInlineReady
        : terminal
            ? l10n.workbenchInlineCompleted(eventCount)
            : l10n.workbenchInlineConnecting(adapter ?? 'CLI', eventCount);
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
                  style: const TextStyle(color: theme.muted, fontSize: 12))),
        ]));
  }
}

class WorkbenchMessageCard extends StatelessWidget {
  const WorkbenchMessageCard(
      {super.key,
      required this.message,
      required this.onApproval,
      required this.onSuggestion,
      required this.expandThinking});
  final WorkbenchMessage message;
  final ValueChanged<String> onApproval;
  final ValueChanged<String> onSuggestion;
  final bool expandThinking;
  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final isApproval = message.role == 'approval';
    final isCommand = message.role == 'command';
    final isDiff = message.role == 'diff';
    final isFileChange = message.role == 'file_change';
    final isTool = isCommand || isDiff;
    if (message.role == 'task_progress') {
      return _TaskProgressCard(message: message);
    }
    if (isCommand) return _CommandEventCard(message: message);
    if (isDiff) return _DiffEventCard(message: message);
    if (isFileChange) return _FileChangeEventCard(message: message);
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
    if (isUser) return _UserMessageCard(message: message);
    final color = isApproval
        ? theme.amber
        : isTool
            ? theme.orange
            : theme.green;
    return Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
            widthFactor: 1,
            child: Container(
                padding: EdgeInsets.fromLTRB(16, isApproval ? 12 : 11, 16, 11),
                decoration: BoxDecoration(
                    color: isApproval
                        ? const Color(0xFF101113)
                        : message.role == 'assistant'
                            ? Colors.transparent
                            : const Color(0xFF101113),
                    borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(isApproval ? 14 : 18),
                        topRight: Radius.circular(isApproval ? 14 : 18),
                        bottomLeft: Radius.circular(isApproval ? 14 : 6),
                        bottomRight: Radius.circular(isApproval ? 14 : 18)),
                    border: Border.all(
                        color: isApproval
                            ? Colors.white.withValues(alpha: .08)
                            : message.role == 'assistant'
                                ? Colors.transparent
                                : theme.stroke)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (message.role != 'assistant') ...[
                        Row(children: [
                          Container(
                              width: isApproval ? 24 : 18,
                              height: isApproval ? 24 : 18,
                              alignment: Alignment.center,
                              decoration: isApproval
                                  ? BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      color: theme.amber.withValues(alpha: .10),
                                      border: Border.all(
                                          color: theme.amber
                                              .withValues(alpha: .22)))
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
                                      color: theme.text,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700))),
                        ]),
                        const SizedBox(height: 8),
                      ],
                      if (message.attachments.isNotEmpty) ...[
                        _MessageAttachmentStrip(
                            attachments: message.attachments, alignEnd: false),
                        if (message.body.trim().isNotEmpty)
                          const SizedBox(height: 8),
                      ],
                      if (message.body.trim().isNotEmpty) ...[
                        if (message.role == 'assistant')
                          AssistantMarkdownBody(markdown: message.body)
                        else
                          Text(message.body,
                              style: TextStyle(
                                  color: theme.muted,
                                  fontSize: 12.5,
                                  height: 1.55,
                                  fontWeight: FontWeight.w400)),
                      ],
                      if (isApproval) ...[
                        const SizedBox(height: 12),
                        if (message.event?.approvalId == null)
                          Text(
                              AppLocalizations.of(context)
                                  .workbenchApprovalMissingId,
                              style: TextStyle(color: theme.red, fontSize: 12))
                        else
                          Row(children: [
                            Expanded(
                                child: _ApprovalActionButton(
                                    AppLocalizations.of(context)
                                        .workbenchRejectAction,
                                    color: theme.red,
                                    onTap: () => onApproval('deny'))),
                            const SizedBox(width: 10),
                            Expanded(
                                child: _ApprovalActionButton(
                                    AppLocalizations.of(context)
                                        .workbenchApproveAction,
                                    color: theme.purple2,
                                    primary: true,
                                    onTap: () => onApproval('allow'))),
                          ])
                      ]
                    ]))));
  }
}

class _UserMessageCard extends StatelessWidget {
  const _UserMessageCard({required this.message});

  final WorkbenchMessage message;

  @override
  Widget build(BuildContext context) {
    final body = message.body.trim();
    final bubbles = <Widget>[];
    if (message.attachments.isNotEmpty) {
      final attachmentStrip = _MessageAttachmentStrip(
          attachments: message.attachments, alignEnd: true);
      if (_usesBorderlessImageAttachmentFrame(message.attachments)) {
        bubbles.add(KeyedSubtree(
            key: const Key('workbench-user-attachment-bubble'),
            child: attachmentStrip));
      } else {
        bubbles.add(_UserBubbleFrame(
          key: const Key('workbench-user-attachment-bubble'),
          child: attachmentStrip,
        ));
      }
    }
    if (body.isNotEmpty) {
      if (bubbles.isNotEmpty) bubbles.add(const SizedBox(height: 6));
      bubbles.add(_UserBubbleFrame(
        key: const Key('workbench-user-text-bubble'),
        child: Text(body,
            style: const TextStyle(
                color: Color(0xFFF4F4F4),
                fontSize: 14.5,
                height: 1.45,
                fontWeight: FontWeight.w500)),
      ));
    }
    if (bubbles.isEmpty) return const SizedBox.shrink();
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: bubbles);
  }
}

bool _usesBorderlessImageAttachmentFrame(
        List<CommittedAttachment> attachments) =>
    attachments.isNotEmpty &&
    attachments.every((attachment) => attachment.kind == AttachmentKind.image);

class _UserBubbleFrame extends StatelessWidget {
  const _UserBubbleFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
      alignment: Alignment.centerRight,
      child: FractionallySizedBox(
          widthFactor: .78,
          child: Container(
              padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
              decoration: BoxDecoration(
                  color: const Color(0xFF191A1E),
                  borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(18),
                      topRight: Radius.circular(18),
                      bottomLeft: Radius.circular(18),
                      bottomRight: Radius.circular(6)),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: .085))),
              child: child)));
}

class _MessageAttachmentStrip extends StatelessWidget {
  const _MessageAttachmentStrip({
    required this.attachments,
    required this.alignEnd,
  });

  final List<CommittedAttachment> attachments;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) => Align(
      alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      child: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: alignEnd ? WrapAlignment.end : WrapAlignment.start,
          children: attachments
              .map((attachment) =>
                  _MessageAttachmentPill(attachment: attachment))
              .toList(growable: false)));
}

class _MessageAttachmentPill extends StatelessWidget {
  const _MessageAttachmentPill({required this.attachment});

  final CommittedAttachment attachment;

  @override
  Widget build(BuildContext context) {
    if (attachment.kind == AttachmentKind.image) {
      return _MessageImageAttachmentPreview(attachment: attachment);
    }
    return Tooltip(
        message: attachment.name,
        child: Container(
            constraints: const BoxConstraints(maxWidth: 180),
            padding: const EdgeInsets.fromLTRB(6, 6, 9, 6),
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .045),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: Colors.white.withValues(alpha: .085))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(7)),
                  child: Icon(_attachmentIcon(attachment.kind),
                      color: theme.muted, size: 17)),
              const SizedBox(width: 8),
              Flexible(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(attachment.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: theme.text,
                            fontSize: 11.5,
                            height: 1.1,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0)),
                    const SizedBox(height: 3),
                    Text(_attachmentSizeLabel(attachment.sizeBytes),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: theme.muted,
                            fontSize: 10.5,
                            height: 1,
                            letterSpacing: 0)),
                  ])),
            ])));
  }
}

class _MessageImageAttachmentPreview extends StatelessWidget {
  const _MessageImageAttachmentPreview({required this.attachment});

  final CommittedAttachment attachment;

  @override
  Widget build(BuildContext context) => Semantics(
      button: true,
      child: Tooltip(
          message: attachment.name,
          child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _showImageAttachmentViewer(context, attachment),
              child: Container(
                  key: const Key('workbench-message-image-preview-shell'),
                  constraints:
                      const BoxConstraints(minWidth: 180, maxWidth: 260),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .045),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: .085))),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                            constraints: const BoxConstraints(maxHeight: 220),
                            width: double.infinity,
                            color: Colors.black.withValues(alpha: .22),
                            child: AspectRatio(
                              aspectRatio: 4 / 3,
                              child: _attachmentPreviewImage(
                                attachment,
                                key: const Key(
                                    'workbench-message-image-preview'),
                                fit: BoxFit.contain,
                                errorIconSize: 22,
                              ),
                            ))),
                    const SizedBox(height: 7),
                    Row(children: [
                      Icon(_attachmentIcon(attachment.kind),
                          color: theme.muted, size: 15),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(attachment.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: theme.text,
                                  fontSize: 11.5,
                                  height: 1.1,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0))),
                      const SizedBox(width: 8),
                      Text(_attachmentSizeLabel(attachment.sizeBytes),
                          style: const TextStyle(
                              color: theme.muted,
                              fontSize: 10.5,
                              height: 1,
                              letterSpacing: 0)),
                    ]),
                  ])))));
}

void _showImageAttachmentViewer(
    BuildContext context, CommittedAttachment attachment) {
  if (_cachedImagePreviewFile(attachment) == null) return;
  showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: const Color(0xF20B0C10),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, animation, secondaryAnimation) =>
          _ImageAttachmentViewer(attachment: attachment),
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(
              opacity: CurvedAnimation(
                  parent: animation, curve: Curves.easeOutCubic),
              child: child));
}

class _ImageAttachmentViewer extends StatelessWidget {
  const _ImageAttachmentViewer({required this.attachment});

  final CommittedAttachment attachment;

  @override
  Widget build(BuildContext context) => Material(
      key: const Key('workbench-message-image-viewer'),
      color: Colors.transparent,
      child: SafeArea(
          child: Stack(children: [
        Positioned.fill(
            child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 52, 12, 18),
                child: InteractiveViewer(
                    minScale: .75,
                    maxScale: 5,
                    boundaryMargin: const EdgeInsets.all(80),
                    child: Center(
                        child: _attachmentPreviewImage(
                      attachment,
                      key: const Key('workbench-message-image-viewer-image'),
                      fit: BoxFit.contain,
                      errorIconSize: 44,
                    ))))),
        Positioned(
            left: 16,
            top: 11,
            right: 64,
            child: Text(attachment.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: theme.text,
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0))),
        Positioned(
            right: 8,
            top: 4,
            child: Container(
                decoration: BoxDecoration(
                    color: const Color(0x1FE6E2D8),
                    borderRadius: BorderRadius.circular(20)),
                child: IconButton(
                    key: const Key('workbench-message-image-viewer-close'),
                    tooltip:
                        MaterialLocalizations.of(context).closeButtonTooltip,
                    icon: const Icon(Icons.close_rounded,
                        color: theme.text, size: 22),
                    onPressed: () => Navigator.of(context).maybePop()))),
      ])));
}

Widget _attachmentPreviewImage(
  CommittedAttachment attachment, {
  required Key key,
  required BoxFit fit,
  required double errorIconSize,
}) {
  Widget errorBuilder(
          BuildContext context, Object error, StackTrace? stackTrace) =>
      Icon(_attachmentIcon(attachment.kind),
          color: theme.muted, size: errorIconSize);

  final localFile = _cachedImagePreviewFile(attachment);
  if (localFile != null) {
    return Image.file(
      localFile,
      key: key,
      fit: fit,
      errorBuilder: errorBuilder,
    );
  }
  return Icon(_attachmentIcon(attachment.kind),
      key: key, color: theme.muted, size: errorIconSize);
}

File? _cachedImagePreviewFile(CommittedAttachment attachment) {
  if (attachment.kind != AttachmentKind.image) return null;
  final localPath = attachment.localPath;
  if (localPath == null) return null;
  final file = File(localPath);
  return file.existsSync() ? file : null;
}

IconData _attachmentIcon(AttachmentKind kind) => switch (kind) {
      AttachmentKind.image => Icons.image_outlined,
      AttachmentKind.pdf => Icons.picture_as_pdf_outlined,
      AttachmentKind.textDocument => Icons.description_outlined,
      AttachmentKind.unsupported => Icons.attach_file_rounded,
    };

String _attachmentSizeLabel(int sizeBytes) {
  if (sizeBytes <= 0) return '0 B';
  const units = <String>['B', 'KB', 'MB', 'GB'];
  var size = sizeBytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  final digits = unit == 0 || size >= 10 ? 0 : 1;
  return '${size.toStringAsFixed(digits)} ${units[unit]}';
}

class AssistantMarkdownBody extends StatefulWidget {
  const AssistantMarkdownBody({super.key, required this.markdown});
  final String markdown;

  @override
  State<AssistantMarkdownBody> createState() => _AssistantMarkdownBodyState();
}

class _AssistantMarkdownBodyState extends State<AssistantMarkdownBody> {
  String? _raw;
  String? _normalized;

  String get _cachedNormalized {
    if (_raw != widget.markdown) {
      _raw = widget.markdown;
      _normalized = normalizeAssistantMarkdown(widget.markdown);
    }
    return _normalized!;
  }

  @override
  Widget build(BuildContext context) => MarkdownBody(
      data: _cachedNormalized,
      builders: {'pre': _CopyableCodeBlockBuilder()},
      selectable: true,
      softLineBreak: true,
      styleSheet: buildAssistantMarkdownStyleSheet(context),
      imageBuilder: (_, __, ___) => const SizedBox.shrink(),
      onTapLink: (_, __, ___) {});
}

class _CopyableCodeBlockBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitText(dynamic text, TextStyle? preferredStyle) {
    final code = text.text;
    return _CopyableCodeBlock(
        code: code is String ? code : '', style: preferredStyle);
  }
}

class _CopyableCodeBlock extends StatefulWidget {
  const _CopyableCodeBlock({required this.code, required this.style});

  final String code;
  final TextStyle? style;

  @override
  State<_CopyableCodeBlock> createState() => _CopyableCodeBlockState();
}

class _CopyableCodeBlockState extends State<_CopyableCodeBlock>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  late final AnimationController _copyFeedbackController;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _copyFeedbackController =
        AnimationController(vsync: this, duration: _codeCopyFeedbackDuration)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed && mounted) {
              setState(() => _copied = false);
            }
          });
  }

  @override
  void dispose() {
    _copyFeedbackController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String get _copyText => _normalizeCodeBlockText(widget.code);

  Future<void> _copyCode(String copyText) async {
    await Clipboard.setData(ClipboardData(text: copyText));
    if (!mounted) return;
    setState(() => _copied = true);
    _copyFeedbackController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final copyText = _copyText;
    final shellColor = _copied
        ? _codeCopySuccessBackground
        : Colors.white.withValues(alpha: .055);
    final shellBorder =
        _copied ? _codeCopySuccessBorder : Colors.white.withValues(alpha: .105);
    final iconColor = _copied ? _codeCopySuccessIcon : theme.muted;
    final iconData = _copied ? Icons.check_rounded : Icons.copy_rounded;
    final textStyle = (widget.style ?? const TextStyle()).copyWith(
        color: const Color(0xFFE7ECF8),
        backgroundColor: Colors.transparent,
        fontFamily: 'Consolas',
        fontSize: 13,
        height: 1.45);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Align(
              alignment: Alignment.centerRight,
              child: AnimatedContainer(
                  key: const Key('workbench-markdown-code-copy-feedback'),
                  width: 28,
                  height: 28,
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                      color: shellColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: shellBorder)),
                  child: Tooltip(
                      message: _copied
                          ? AppLocalizations.of(context).workbenchCopiedSnack
                          : AppLocalizations.of(context)
                              .workbenchCopyCodeTooltip,
                      child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                              key: const Key('workbench-markdown-code-copy'),
                              borderRadius: BorderRadius.circular(8),
                              onTap: copyText.isEmpty
                                  ? null
                                  : () => _copyCode(copyText),
                              child: Center(
                                  child: AnimatedSwitcher(
                                      duration:
                                          const Duration(milliseconds: 160),
                                      switchInCurve: Curves.easeOutCubic,
                                      switchOutCurve: Curves.easeOutCubic,
                                      child: Icon(iconData,
                                          key: ValueKey<IconData>(iconData),
                                          color: iconColor,
                                          size: 15))))))))),
      Scrollbar(
          controller: _scrollController,
          child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
              child: SelectableText(copyText, style: textStyle)))
    ]);
  }
}

class _QuestionEventCard extends StatelessWidget {
  const _QuestionEventCard({required this.message, required this.onSuggestion});
  final WorkbenchMessage message;
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
                  color: theme.purple.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: theme.purple.withValues(alpha: .26))),
              child: const Icon(Icons.tune_rounded,
                  color: theme.purple2, size: 15)),
          const SizedBox(width: 10),
          Expanded(
              child: Text(AppLocalizations.of(context).workbenchQuestionTitle,
                  style: TextStyle(
                      color: theme.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 12),
        Text(message.body,
            style: const TextStyle(
                color: theme.muted, fontSize: 13.5, height: 1.55)),
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
  final WorkbenchMessage message;

  @override
  Widget build(BuildContext context) => _AgentEventCard(
      icon: Icons.info_outline_rounded,
      title: message.title,
      meta: 'non-blocking',
      trailing: null,
      child: Text(message.body,
          style: const TextStyle(
              color: theme.muted, fontSize: 12.5, height: 1.55)));
}

class _ThinkingEventCard extends StatelessWidget {
  const _ThinkingEventCard({required this.message, required this.expanded});
  final WorkbenchMessage message;
  final bool expanded;

  @override
  Widget build(BuildContext context) =>
      _ThinkingFoldout(message: message, initiallyExpanded: expanded);
}

class _ThinkingFoldout extends StatefulWidget {
  const _ThinkingFoldout(
      {required this.message, required this.initiallyExpanded});
  final WorkbenchMessage message;
  final bool initiallyExpanded;

  @override
  State<_ThinkingFoldout> createState() => _ThinkingFoldoutState();
}

class _ThinkingFoldoutState extends State<_ThinkingFoldout> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  void didUpdateWidget(covariant _ThinkingFoldout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.title != widget.message.title ||
        oldWidget.message.body != widget.message.body) {
      _expanded = widget.initiallyExpanded;
    }
  }

  @override
  Widget build(BuildContext context) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
                    child: Row(children: [
                      Expanded(
                          child: Text(
                              AppLocalizations.of(context)
                                  .workbenchThinkingProcessTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: theme.muted,
                                  fontSize: 12.4,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0))),
                      Icon(
                          _expanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          color: theme.faint,
                          size: 16),
                    ]))),
            if (_expanded)
              Padding(
                  padding: const EdgeInsets.only(top: 4, right: 10),
                  child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 11, vertical: 8),
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .025),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: .045))),
                      child: Text(widget.message.body,
                          softWrap: true,
                          overflow: TextOverflow.visible,
                          style: const TextStyle(
                              color: theme.muted,
                              fontSize: 12.5,
                              height: 1.55)))),
          ]);
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
                  color: primary ? theme.text : color,
                  fontSize: 13,
                  letterSpacing: 0,
                  fontWeight: FontWeight.w800))));
}

class _CommandEventCard extends StatelessWidget {
  const _CommandEventCard({required this.message});
  final WorkbenchMessage message;

  @override
  Widget build(BuildContext context) => _ToolLogFoldout(message: message);
}

class _TaskProgressCard extends StatelessWidget {
  const _TaskProgressCard({required this.message});

  final WorkbenchMessage message;

  @override
  Widget build(BuildContext context) {
    final completed = message.completedCount ??
        message.taskItems.where((item) => item.status == 'completed').length;
    final total = message.totalCount ?? message.taskItems.length;
    return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: const Color(0xFF101113).withValues(alpha: .92),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: .07)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: .18),
                  blurRadius: 18,
                  offset: const Offset(0, 8))
            ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: theme.green.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: theme.green.withValues(alpha: .22))),
                child: const Icon(Icons.checklist_rounded,
                    color: theme.green, size: 16)),
            const SizedBox(width: 9),
            const Expanded(
                child: Text('任务进度',
                    style: TextStyle(
                        color: theme.text,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0))),
            _TaskProgressBadge(completed: completed, total: total),
          ]),
          const SizedBox(height: 12),
          ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                  value: total <= 0 ? 0 : (completed / total).clamp(0.0, 1.0),
                  minHeight: 3,
                  backgroundColor: Colors.white.withValues(alpha: .045),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(theme.green))),
          const SizedBox(height: 14),
          ...message.taskItems.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _TaskProgressRow(item: item))),
          const SizedBox(height: 2),
          const _TaskProgressLegend(),
        ]));
  }
}

class _TaskProgressBadge extends StatelessWidget {
  const _TaskProgressBadge({required this.completed, required this.total});

  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: theme.green.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: theme.green.withValues(alpha: .22))),
      child: Text('$completed / $total 完成',
          style: const TextStyle(
              color: theme.green,
              fontSize: 11.5,
              fontWeight: FontWeight.w800)));
}

class _TaskProgressRow extends StatelessWidget {
  const _TaskProgressRow({required this.item});

  final TaskProgressItem item;

  @override
  Widget build(BuildContext context) {
    final status = _taskProgressStatus(item.status);
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .025),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: Colors.white.withValues(alpha: .045))),
        child: Row(children: [
          _TaskProgressDot(color: status.color),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: theme.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(status.label,
                    style: TextStyle(
                        color: status.color.withValues(alpha: .86),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700)),
              ])),
        ]));
  }
}

class _TaskProgressLegend extends StatelessWidget {
  const _TaskProgressLegend();

  @override
  Widget build(BuildContext context) =>
      Wrap(spacing: 10, runSpacing: 6, children: [
        _TaskProgressLegendItem(
            color: theme.green, label: _taskProgressStatus('completed').label),
        _TaskProgressLegendItem(
            color: theme.amber,
            label: _taskProgressStatus('in_progress').label),
        _TaskProgressLegendItem(
            color: theme.faint, label: _taskProgressStatus('pending').label),
      ]);
}

class _TaskProgressLegendItem extends StatelessWidget {
  const _TaskProgressLegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        _TaskProgressDot(color: color, small: true),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(
                color: theme.faint,
                fontSize: 10.5,
                fontWeight: FontWeight.w700)),
      ]);
}

class _TaskProgressDot extends StatelessWidget {
  const _TaskProgressDot({required this.color, this.small = false});

  final Color color;
  final bool small;

  @override
  Widget build(BuildContext context) => Container(
      width: small ? 7 : 9,
      height: small ? 7 : 9,
      decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(
                color: color.withValues(alpha: .25), blurRadius: small ? 5 : 8)
          ]));
}

({Color color, String label}) _taskProgressStatus(String status) =>
    switch (status) {
      'completed' => (color: theme.green, label: '完成'),
      'in_progress' => (color: theme.amber, label: '正在执行'),
      'pending' => (color: theme.faint, label: '等待执行'),
      _ => (color: theme.muted, label: status.isEmpty ? '等待执行' : status),
    };

String _commandTitle(WorkbenchMessage message) {
  final firstLine = message.body
      .split('\n')
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => message.title);
  return firstLine;
}

class _ToolLogFoldout extends StatefulWidget {
  const _ToolLogFoldout({required this.message});
  final WorkbenchMessage message;

  @override
  State<_ToolLogFoldout> createState() => _ToolLogFoldoutState();
}

class _ToolLogFoldoutState extends State<_ToolLogFoldout> {
  bool _expanded = true;

  @override
  void didUpdateWidget(covariant _ToolLogFoldout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.body != widget.message.body ||
        oldWidget.message.title != widget.message.title) {
      _expanded = true;
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
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                  child: Row(children: [
                    _ToolKindBadge(kind: _toolKindLabel(message)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(_toolTargetTitle(message),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: theme.text,
                                fontSize: 12.9,
                                fontWeight: FontWeight.w700,
                                height: 1.2))),
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
            Padding(
                padding: const EdgeInsets.fromLTRB(2, 6, 0, 4),
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
      constraints: const BoxConstraints(minWidth: 38),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
          color: _toolKindColor(kind).withValues(alpha: .105),
          borderRadius: BorderRadius.circular(7),
          border:
              Border.all(color: _toolKindColor(kind).withValues(alpha: .18))),
      child: Text(kind,
          style: TextStyle(
              color: _toolKindColor(kind),
              fontSize: 9.5,
              fontFamily: 'Consolas',
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
                    style: const TextStyle(
                        color: theme.faint,
                        fontSize: 9.5,
                        fontFamily: 'Consolas',
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0))),
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
                            color: Colors.white.withValues(alpha: .018),
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: .045))),
                        child: Row(children: [
                          Expanded(
                              child: Text(widget.text,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: true,
                                  style: const TextStyle(
                                      color: theme.muted,
                                      fontSize: 12,
                                      fontFamily: 'Consolas',
                                      height: 1.35))),
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
        style: const TextStyle(
            color: theme.faint, fontSize: 10.5, fontFamily: 'Consolas'));
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
                                fontFamily: 'Consolas')),
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
                                    color: theme.muted,
                                    fontSize: 12.5,
                                    fontFamily: 'Consolas',
                                    height: 1.45))))))
          ])));
}

@visibleForTesting
Widget buildCompletedCommandCardPreview() => MaterialApp(
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
            child: _CommandEventCard(
                message: const WorkbenchMessage(
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
              child: _CommandEventCard(message: message))));
}

@visibleForTesting
Widget buildTaskProgressCardPreview() {
  const message = WorkbenchMessage(
      'task_progress', 'Task progress', 'Task progress updated',
      runId: 'conversation',
      taskId: 'task_1',
      completedCount: 1,
      totalCount: 3,
      taskItems: <TaskProgressItem>[
        TaskProgressItem(
            id: 'task_1_item_1', title: '分析工作区结构', status: 'completed'),
        TaskProgressItem(
            id: 'task_1_item_2', title: '实现进度卡片', status: 'in_progress'),
        TaskProgressItem(
            id: 'task_1_item_3', title: '运行回归测试', status: 'pending'),
      ]);
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
              child: WorkbenchMessageCard(
                  message: message,
                  onApproval: (_) {},
                  onSuggestion: (_) {},
                  expandThinking: false))));
}

@visibleForTesting
Widget buildLargeOutputCommandCardPreview() {
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
              child: _CommandEventCard(message: message))));
}

@visibleForTesting
Widget buildPendingSentinelPreview() => MaterialApp(
    locale: theme.zhHansCnLocale,
    supportedLocales: const [theme.zhHansCnLocale, Locale('en', 'US')],
    localizationsDelegates: theme.appLocalizationsDelegates,
    theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'Segoe UI',
        fontFamilyFallback: theme.appFontFallback,
        useMaterial3: true),
    home: const Scaffold(
        backgroundColor: theme.bg,
        body: Padding(
            padding: EdgeInsets.all(16),
            child: PendingSentinel(
                adapter: 'claude',
                statusText: 'Receiving CLI output...',
                actions: <String>[
                  'Started claude session',
                  'Claude requesting'
                ]))));

String? _formatCommandDuration(Duration? duration) {
  if (duration == null) return null;
  final seconds = duration.inMilliseconds / 1000;
  if (seconds < 10) return '${seconds.toStringAsFixed(1)}s';
  return '${seconds.round()}s';
}

class _DiffEventCard extends StatelessWidget {
  const _DiffEventCard({required this.message});
  final WorkbenchMessage message;

  @override
  Widget build(BuildContext context) => _AgentEventCard(
      icon: Icons.call_split_rounded,
      title: 'Changed files',
      meta: 'diff summary',
      trailing: null,
      child: _EventCodeLine(text: message.body, ok: true));
}

class _FileChangeEventCard extends StatelessWidget {
  const _FileChangeEventCard({required this.message});
  final WorkbenchMessage message;

  @override
  Widget build(BuildContext context) {
    final changes = message.fileChanges;
    final title = changes.length == 1
        ? _fileChangeTitle(changes.single)
        : 'Edited ${changes.length} files';
    return _AgentEventCard(
        icon: Icons.edit_note_rounded,
        title: title,
        meta: 'workspace change',
        trailing: null,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: changes.isEmpty
                ? <Widget>[_FileChangeFallback(text: message.body)]
                : changes
                    .take(4)
                    .map<Widget>((change) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _FileChangeEntry(change: change)))
                    .followedBy(changes.length > 4
                        ? <Widget>[
                            Text('+${changes.length - 4} more file(s)',
                                style: const TextStyle(
                                    color: theme.faint,
                                    fontSize: 11,
                                    fontFamily: 'Consolas'))
                          ]
                        : const <Widget>[])
                    .toList(growable: false)));
  }

  static String _fileChangeTitle(ConversationFileChange change) {
    final kind = change.kind.toLowerCase();
    final verb = switch (kind) {
      'add' || 'added' => 'Added',
      'delete' || 'deleted' || 'remove' || 'removed' => 'Deleted',
      _ => 'Edited',
    };
    return '$verb ${_shortPathName(change.path)}';
  }
}

class _FileChangeEntry extends StatelessWidget {
  const _FileChangeEntry({required this.change});
  final ConversationFileChange change;

  @override
  Widget build(BuildContext context) {
    final diff = change.diff?.trim();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: _fileChangeColor(change.kind).withValues(alpha: .12),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                    color:
                        _fileChangeColor(change.kind).withValues(alpha: .22))),
            child: Icon(_fileChangeIcon(change.kind),
                size: 13, color: _fileChangeColor(change.kind))),
        const SizedBox(width: 9),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_fileChangeKindLabel(change.kind),
              style: const TextStyle(
                  color: theme.text,
                  fontSize: 11.5,
                  height: 1.1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0)),
          const SizedBox(height: 3),
          Text(change.path,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: theme.muted,
                  fontSize: 11.5,
                  height: 1.25,
                  fontFamily: 'Consolas',
                  letterSpacing: 0)),
        ])),
      ]),
      if (diff != null && diff.isNotEmpty) ...[
        const SizedBox(height: 8),
        _FileChangeDiffPreview(diff: diff),
      ],
    ]);
  }
}

class _FileChangeDiffPreview extends StatelessWidget {
  const _FileChangeDiffPreview({required this.diff});
  final String diff;

  @override
  Widget build(BuildContext context) {
    final lines = _previewDiffLines(diff);
    return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
            color: const Color(0xFF0B0C0E),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: .055))),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: lines
                .map((line) => Text(line.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: line.color,
                        fontSize: 11,
                        height: 1.35,
                        fontFamily: 'Consolas',
                        letterSpacing: 0)))
                .toList(growable: false)));
  }
}

class _FileChangeFallback extends StatelessWidget {
  const _FileChangeFallback({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => _EventCodeLine(text: text, ok: true);
}

class _DiffPreviewLine {
  const _DiffPreviewLine(this.text, this.color);
  final String text;
  final Color color;
}

List<_DiffPreviewLine> _previewDiffLines(String diff) {
  final normalized = diff.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final source = normalized
      .split('\n')
      .where((line) =>
          line.trim().isNotEmpty &&
          !line.startsWith('diff --git ') &&
          !line.startsWith('index ') &&
          !line.startsWith('--- ') &&
          !line.startsWith('+++ '))
      .toList(growable: false);
  final visible = source.take(14).map((line) {
    if (line.startsWith('+')) {
      return _DiffPreviewLine(line, theme.green);
    }
    if (line.startsWith('-')) {
      return _DiffPreviewLine(line, theme.red);
    }
    if (line.startsWith('@@')) {
      return _DiffPreviewLine(line, const Color(0xFF9CA7FF));
    }
    return _DiffPreviewLine(line, theme.muted);
  }).toList(growable: false);
  return visible.isEmpty
      ? const <_DiffPreviewLine>[]
      : List<_DiffPreviewLine>.unmodifiable(visible);
}

String _shortPathName(String path) {
  final parts = path.replaceAll('\\', '/').split('/');
  return parts.isEmpty ? path : parts.last;
}

String _fileChangeKindLabel(String kind) {
  switch (kind.toLowerCase()) {
    case 'add':
    case 'added':
      return 'Added';
    case 'delete':
    case 'deleted':
    case 'remove':
    case 'removed':
      return 'Deleted';
    case 'update':
    case 'updated':
    case 'modify':
    case 'modified':
      return 'Edited';
    default:
      return 'Changed';
  }
}

IconData _fileChangeIcon(String kind) {
  switch (kind.toLowerCase()) {
    case 'add':
    case 'added':
      return Icons.add_rounded;
    case 'delete':
    case 'deleted':
    case 'remove':
    case 'removed':
      return Icons.remove_rounded;
    default:
      return Icons.edit_rounded;
  }
}

Color _fileChangeColor(String kind) {
  switch (kind.toLowerCase()) {
    case 'add':
    case 'added':
      return theme.green;
    case 'delete':
    case 'deleted':
    case 'remove':
    case 'removed':
      return theme.red;
    default:
      return theme.amber;
  }
}

class _ApprovalEventCard extends StatelessWidget {
  const _ApprovalEventCard({required this.message, required this.onApproval});
  final WorkbenchMessage message;
  final ValueChanged<String> onApproval;

  @override
  Widget build(BuildContext context) => _AgentEventCard(
      icon: Icons.priority_high_rounded,
      title: AppLocalizations.of(context).workbenchApprovalCardTitle,
      meta: _approvalMeta(message.event),
      trailing: _eventTime(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(message.body,
            style: const TextStyle(
                color: theme.muted, fontSize: 12.5, height: 1.55)),
        const SizedBox(height: 12),
        if (message.event?.approvalId == null)
          Text(AppLocalizations.of(context).workbenchApprovalMissingId,
              style: TextStyle(color: theme.red, fontSize: 12))
        else
          Row(children: [
            Expanded(
                child: _ApprovalActionButton(
                    AppLocalizations.of(context).workbenchRejectAction,
                    color: theme.red,
                    onTap: () => onApproval('deny'))),
            const SizedBox(width: 10),
            Expanded(
                child: _ApprovalActionButton(
                    AppLocalizations.of(context).workbenchApproveAction,
                    color: theme.text,
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
              child: Icon(icon, color: theme.amber, size: 15)),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: const TextStyle(
                        color: theme.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: theme.faint,
                        fontSize: 10.5,
                        fontFamily: 'Consolas')),
              ])),
          if (trailing != null)
            Text(trailing!,
                style: const TextStyle(
                    color: theme.faint, fontSize: 10.5, fontFamily: 'Consolas'))
        ]),
        const SizedBox(height: 12),
        child,
      ]));
}

class _EventCodeLine extends StatelessWidget {
  const _EventCodeLine({required this.text, required this.ok});
  final String text;
  final bool ok;

  @override
  Widget build(BuildContext context) => Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
          color: const Color(0xFF0B0C0E),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: Colors.white.withValues(alpha: .055))),
      child: Row(children: [
        Expanded(
            child: Text(text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: theme.muted,
                    fontSize: 12,
                    fontFamily: 'Consolas',
                    height: 1.35))),
        if (ok) ...[
          const SizedBox(width: 8),
          const Text('ok',
              style: TextStyle(
                  color: theme.green,
                  fontSize: 11,
                  fontFamily: 'Consolas',
                  fontWeight: FontWeight.w800))
        ]
      ]));
}

String normalizeAssistantMarkdown(String markdown) {
  final withoutHtml = markdown.replaceAll(RegExp(r'<[^>]+>'), '');
  return withoutHtml
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

String _normalizeCodeBlockText(String code) {
  final normalized = code.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  if (normalized.endsWith('\n')) {
    return normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

MarkdownStyleSheet buildAssistantMarkdownStyleSheet(BuildContext context) {
  const codeBg = Color(0x66101824);
  const codeBorder = Color(0x22FFFFFF);
  final base = Theme.of(context).textTheme;
  return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: base.bodyMedium
          ?.copyWith(color: theme.muted, fontSize: 14.5, height: 1.68),
      strong: const TextStyle(color: theme.text, fontWeight: FontWeight.w700),
      em: const TextStyle(
          color: Color(0xFFD3DAE8), fontStyle: FontStyle.italic),
      h1: const TextStyle(
          color: theme.text,
          fontSize: 17,
          height: 1.35,
          fontWeight: FontWeight.w800),
      h2: const TextStyle(
          color: theme.text,
          fontSize: 15.5,
          height: 1.35,
          fontWeight: FontWeight.w800),
      h3: const TextStyle(
          color: theme.text,
          fontSize: 14,
          height: 1.4,
          fontWeight: FontWeight.w800),
      listBullet:
          const TextStyle(color: theme.green, fontSize: 12, height: 1.55),
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
          border: const Border(left: BorderSide(color: theme.purple, width: 3)),
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

class PendingSentinel extends StatefulWidget {
  const PendingSentinel({
    super.key,
    required this.adapter,
    required this.statusText,
    this.startedAt,
    this.now,
    this.actions = const <String>[],
  });

  final String adapter;
  final String statusText;
  final DateTime? startedAt;
  final DateTime Function()? now;
  final List<String> actions;

  @override
  State<PendingSentinel> createState() => _PendingSentinelState();
}

class _PendingSentinelState extends State<PendingSentinel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _elapsedTimer;
  var _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 850))
      ..repeat();
    _elapsedSeconds = _initialElapsedSeconds();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsedSeconds = widget.startedAt == null
            ? _elapsedSeconds + 1
            : _elapsedSecondsSince(widget.startedAt!);
      });
    });
  }

  @override
  void didUpdateWidget(covariant PendingSentinel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startedAt != widget.startedAt) {
      _elapsedSeconds = _initialElapsedSeconds();
    }
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
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
                    Text(AppLocalizations.of(context).workbenchPendingRunning,
                        style: TextStyle(
                            color: theme.text,
                            fontWeight: FontWeight.w800,
                            fontSize: 13)),
                    const SizedBox(height: 5),
                    AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        transitionBuilder: (child, animation) {
                          final slide = Tween<Offset>(
                                  begin: const Offset(0, .18), end: Offset.zero)
                              .animate(CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeOutCubic));
                          return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                  position: slide, child: child));
                        },
                        child: Text(widget.statusText,
                            key: ValueKey(widget.statusText),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: theme.muted,
                                fontSize: 12,
                                height: 1.3))),
                  ])),
              const SizedBox(width: 10),
              _ElapsedTimerPill(text: _formatPendingElapsed(_elapsedSeconds)),
              const SizedBox(width: 10),
              SizedBox(
                  width: 18,
                  height: 24,
                  child:
                      Center(child: _PulseBars(progress: _controller.value))),
            ]));
      });

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  int _initialElapsedSeconds() =>
      widget.startedAt == null ? 0 : _elapsedSecondsSince(widget.startedAt!);

  int _elapsedSecondsSince(DateTime startedAt) {
    final elapsed = _now().difference(startedAt).inSeconds;
    return elapsed < 0 ? 0 : elapsed;
  }
}

String _formatPendingElapsed(int seconds) {
  final normalized = seconds < 0 ? 0 : seconds;
  final hours = normalized ~/ 3600;
  final minutes = (normalized % 3600) ~/ 60;
  final remainingSeconds = normalized % 60;
  final twoDigitMinutes = minutes.toString().padLeft(2, '0');
  final twoDigitSeconds = remainingSeconds.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:$twoDigitMinutes:$twoDigitSeconds';
  }
  return '$twoDigitMinutes:$twoDigitSeconds';
}

class _ElapsedTimerPill extends StatelessWidget {
  const _ElapsedTimerPill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
      constraints: const BoxConstraints(minWidth: 44),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: theme.purple.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: theme.purple.withValues(alpha: .14))),
      child: Text(text,
          maxLines: 1,
          style: TextStyle(
              color: theme.text.withValues(alpha: .78),
              fontSize: 11,
              fontFeatures: const [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w700,
              height: 1)));
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
            color: theme.purple.withValues(alpha: .08 + pulse * .08),
            border: Border.all(color: theme.purple.withValues(alpha: .18))),
        child: Container(
            width: 7 + pulse * 2,
            height: 7 + pulse * 2,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.purple2.withValues(alpha: .75),
                boxShadow: [
                  BoxShadow(
                      color: theme.purple.withValues(alpha: .22 + pulse * .18),
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
                color: theme.purple.withValues(alpha: .28 + phase * .34),
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
          color: active ? theme.green : theme.faint,
          boxShadow: active
              ? [
                  BoxShadow(
                      color: theme.green.withValues(alpha: .45),
                      blurRadius: 12,
                      spreadRadius: 2)
                ]
              : null));
}
