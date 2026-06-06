import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../core/theme/theme.dart' as theme;
import 'transcript_typography.dart';

const _codeCopySuccessBackground = Color(0xFFE7ECF8);
const _codeCopySuccessBorder = Color(0xFFF4F7FC);
const _codeCopySuccessIcon = Color(0xFF0B0C0E);
const _codeCopyFeedbackDuration = Duration(seconds: 2);
const _codeCopyButtonSize = 24.0;
const _codeCopyButtonRadius = 7.0;

class CopyableCodeBlockBuilder extends MarkdownElementBuilder {
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
    final textStyle = (widget.style ?? const TextStyle()).merge(
      WorkbenchTranscriptTypography.shellCommand.copyWith(
        backgroundColor: Colors.transparent,
        fontSize: 13,
        height: 1.48,
      ),
    );
    return Column(
        key: const Key('workbench-markdown-code-block'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Align(
                  alignment: Alignment.centerRight,
                  child: AnimatedContainer(
                      key: const Key('workbench-markdown-code-copy-feedback'),
                      width: _codeCopyButtonSize,
                      height: _codeCopyButtonSize,
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutCubic,
                      decoration: BoxDecoration(
                          color: shellColor,
                          borderRadius:
                              BorderRadius.circular(_codeCopyButtonRadius),
                          border: Border.all(color: shellBorder)),
                      child: Tooltip(
                          message: _copied
                              ? AppLocalizations.of(context)
                                  .workbenchCopiedSnack
                              : AppLocalizations.of(context)
                                  .workbenchCopyCodeTooltip,
                          child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                  key:
                                      const Key('workbench-markdown-code-copy'),
                                  borderRadius: BorderRadius.circular(
                                      _codeCopyButtonRadius),
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
                                              size: 13))))))))),
          Scrollbar(
              controller: _scrollController,
              child: SingleChildScrollView(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 36),
                  child: SelectableText(copyText,
                      key: const Key('workbench-markdown-code-text'),
                      style: textStyle)))
        ]);
  }
}

String _normalizeCodeBlockText(String code) {
  final normalized = code.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  if (normalized.endsWith('\n')) {
    return normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}
