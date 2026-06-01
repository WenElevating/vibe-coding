import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../core/theme/theme.dart' as theme;
import 'code_block.dart';

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
      builders: {'pre': CopyableCodeBlockBuilder()},
      selectable: true,
      softLineBreak: true,
      styleSheet: buildAssistantMarkdownStyleSheet(context),
      imageBuilder: (_, __, ___) => const SizedBox.shrink(),
      onTapLink: (_, __, ___) {});
}

String normalizeAssistantMarkdown(String markdown) {
  final withoutHtml = markdown.replaceAll(RegExp(r'<[^>]+>'), '');
  return withoutHtml
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
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
