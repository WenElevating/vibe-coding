import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../core/theme/theme.dart' as theme;
import '../conversation_reducer.dart';
import 'event_card_frame.dart';

class PatchTranscriptFile extends StatelessWidget {
  const PatchTranscriptFile({super.key, required this.change});
  final ConversationFileChange change;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final parsed = _ParsedPatch.fromDiff(change.diff);
    return Container(
        decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .018),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: .06))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: _fileChangeColor(change.kind)
                            .withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                            color: _fileChangeColor(change.kind)
                                .withValues(alpha: .22))),
                    child: Icon(_fileChangeIcon(change.kind),
                        size: 13, color: _fileChangeColor(change.kind))),
                const SizedBox(width: 9),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(_fileChangeKindLabel(l10n, change.kind),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: theme.text,
                              fontSize: 11.5,
                              height: 1.1,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0)),
                      const SizedBox(height: 4),
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
                if (parsed.hasDiff) ...[
                  const SizedBox(width: 8),
                  Text('+${parsed.additions} -${parsed.deletions}',
                      style: const TextStyle(
                          color: theme.faint,
                          fontSize: 11,
                          fontFamily: 'Consolas',
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0)),
                ],
              ])),
          if (parsed.hasDiff)
            _PatchTranscriptPanel(parsed: parsed)
          else
            Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: FileChangeFallback(text: change.path)),
        ]));
  }
}

class _PatchTranscriptPanel extends StatefulWidget {
  const _PatchTranscriptPanel({required this.parsed});
  final _ParsedPatch parsed;

  @override
  State<_PatchTranscriptPanel> createState() => _PatchTranscriptPanelState();
}

class _PatchTranscriptPanelState extends State<_PatchTranscriptPanel> {
  static const _collapsedLineCount = 81;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lines = _expanded
        ? widget.parsed.lines
        : widget.parsed.lines.take(_collapsedLineCount).toList(growable: false);
    final overflow = widget.parsed.lines.length > _collapsedLineCount;
    return Container(
        width: double.infinity,
        decoration: const BoxDecoration(
            color: Color(0xFF0B0C0E),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(8))),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          LayoutBuilder(builder: (context, constraints) {
            return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: lines
                            .map((line) => _PatchTranscriptLine(line: line))
                            .toList(growable: false))));
          }),
          if (overflow && !_expanded)
            TextButton(
                onPressed: () => setState(() => _expanded = true),
                style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    foregroundColor: theme.text),
                child: Text(l10n.workbenchFileChangeShowFullDiff,
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0))),
        ]));
  }
}

class _PatchTranscriptLine extends StatelessWidget {
  const _PatchTranscriptLine({required this.line});
  final _PatchLine line;

  @override
  Widget build(BuildContext context) {
    return Container(
        color: line.background,
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _PatchGutterText(line.displayLineNumber),
          SizedBox(
              width: 18,
              child: Text(line.marker,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: line.foreground,
                      fontSize: 11,
                      height: 1.35,
                      fontFamily: 'Consolas',
                      letterSpacing: 0))),
          Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(line.text.isEmpty ? ' ' : line.text,
                  style: TextStyle(
                      color: line.foreground,
                      fontSize: 11,
                      height: 1.35,
                      fontFamily: 'Consolas',
                      letterSpacing: 0))),
        ]));
  }
}

class _PatchGutterText extends StatelessWidget {
  const _PatchGutterText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => SizedBox(
      width: 34,
      child: Text(text,
          textAlign: TextAlign.right,
          style: const TextStyle(
              color: theme.faint,
              fontSize: 10.5,
              height: 1.42,
              fontFamily: 'Consolas',
              letterSpacing: 0)));
}

class FileChangeFallback extends StatelessWidget {
  const FileChangeFallback({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => EventCodeLine(text: text, ok: true);
}

class _ParsedPatch {
  const _ParsedPatch({
    required this.lines,
    required this.additions,
    required this.deletions,
  });

  final List<_PatchLine> lines;
  final int additions;
  final int deletions;

  bool get hasDiff => lines.isNotEmpty;

  static _ParsedPatch fromDiff(String? diff) {
    final text = diff?.trim();
    if (text == null || text.isEmpty) {
      return const _ParsedPatch(
          lines: <_PatchLine>[], additions: 0, deletions: 0);
    }
    final lines = <_PatchLine>[];
    var oldLine = 0;
    var newLine = 0;
    var inHunk = false;
    var additions = 0;
    var deletions = 0;

    for (final rawLine
        in text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n')) {
      if (rawLine.startsWith('@@')) {
        final hunk = _parseHunkHeader(rawLine);
        oldLine = hunk.oldStart;
        newLine = hunk.newStart;
        inHunk = true;
        lines.add(_PatchLine.hunk(rawLine));
        continue;
      }
      if (!inHunk || _isDiffMetadata(rawLine)) {
        lines.add(_PatchLine.metadata(rawLine));
        continue;
      }
      if (rawLine.startsWith('+')) {
        additions += 1;
        lines.add(
            _PatchLine.added(newLine: newLine, text: rawLine.substring(1)));
        newLine += 1;
        continue;
      }
      if (rawLine.startsWith('-')) {
        deletions += 1;
        lines.add(
            _PatchLine.removed(oldLine: oldLine, text: rawLine.substring(1)));
        oldLine += 1;
        continue;
      }
      final body = rawLine.startsWith(' ') ? rawLine.substring(1) : rawLine;
      lines.add(
          _PatchLine.context(oldLine: oldLine, newLine: newLine, text: body));
      oldLine += 1;
      newLine += 1;
    }

    final visible = lines
        .where((line) =>
            line.kind != _PatchLineKind.metadata || line.text.trim().isNotEmpty)
        .toList(growable: false);
    return _ParsedPatch(
        lines: List<_PatchLine>.unmodifiable(visible),
        additions: additions,
        deletions: deletions);
  }
}

class _PatchLine {
  const _PatchLine._({
    required this.kind,
    required this.text,
    required this.marker,
    this.oldLine,
    this.newLine,
  });

  factory _PatchLine.hunk(String text) =>
      _PatchLine._(kind: _PatchLineKind.hunk, text: text, marker: '');

  factory _PatchLine.metadata(String text) =>
      _PatchLine._(kind: _PatchLineKind.metadata, text: text, marker: '');

  factory _PatchLine.added({required int newLine, required String text}) =>
      _PatchLine._(
          kind: _PatchLineKind.added,
          text: text,
          marker: '+',
          newLine: newLine);

  factory _PatchLine.removed({required int oldLine, required String text}) =>
      _PatchLine._(
          kind: _PatchLineKind.removed,
          text: text,
          marker: '-',
          oldLine: oldLine);

  factory _PatchLine.context(
          {required int oldLine, required int newLine, required String text}) =>
      _PatchLine._(
          kind: _PatchLineKind.context,
          text: text,
          marker: '',
          oldLine: oldLine,
          newLine: newLine);

  final _PatchLineKind kind;
  final int? oldLine;
  final int? newLine;
  final String text;
  final String marker;

  String get displayLineNumber {
    final line = switch (kind) {
      _PatchLineKind.removed => oldLine,
      _ => newLine ?? oldLine,
    };
    return line?.toString() ?? '';
  }

  Color get background {
    return switch (kind) {
      _PatchLineKind.added => theme.green.withValues(alpha: .10),
      _PatchLineKind.removed => theme.red.withValues(alpha: .11),
      _PatchLineKind.hunk => const Color(0xFF151821),
      _ => Colors.transparent,
    };
  }

  Color get foreground {
    return switch (kind) {
      _PatchLineKind.added => const Color(0xFF7CE6A3),
      _PatchLineKind.removed => const Color(0xFFFF8E8E),
      _PatchLineKind.hunk => const Color(0xFFA7B0FF),
      _PatchLineKind.metadata => theme.faint,
      _ => theme.muted,
    };
  }
}

enum _PatchLineKind { added, removed, context, hunk, metadata }

class _HunkStart {
  const _HunkStart({required this.oldStart, required this.newStart});
  final int oldStart;
  final int newStart;
}

_HunkStart _parseHunkHeader(String line) {
  final match =
      RegExp(r'^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@').firstMatch(line);
  if (match == null) return const _HunkStart(oldStart: 1, newStart: 1);
  return _HunkStart(
      oldStart: int.tryParse(match.group(1) ?? '') ?? 1,
      newStart: int.tryParse(match.group(2) ?? '') ?? 1);
}

bool _isDiffMetadata(String line) {
  return line.startsWith('diff --git ') ||
      line.startsWith('index ') ||
      line.startsWith('--- ') ||
      line.startsWith('+++ ') ||
      line.startsWith('new file mode ') ||
      line.startsWith('deleted file mode ') ||
      line.startsWith('similarity index ') ||
      line.startsWith('rename from ') ||
      line.startsWith('rename to ');
}

String shortPathName(String path) {
  final parts = path.replaceAll('\\', '/').split('/');
  return parts.isEmpty ? path : parts.last;
}

String _fileChangeKindLabel(AppLocalizations l10n, String kind) {
  switch (kind.toLowerCase()) {
    case 'add':
    case 'added':
      return l10n.workbenchFileChangeAddedLabel;
    case 'delete':
    case 'deleted':
    case 'remove':
    case 'removed':
      return l10n.workbenchFileChangeDeletedLabel;
    case 'update':
    case 'updated':
    case 'modify':
    case 'modified':
      return l10n.workbenchFileChangeEditedLabel;
    default:
      return l10n.workbenchFileChangeChangedLabel;
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
