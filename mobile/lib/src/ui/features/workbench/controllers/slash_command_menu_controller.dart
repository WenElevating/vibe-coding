import 'package:flutter/services.dart';

class SlashCommandToken {
  const SlashCommandToken({
    required this.start,
    required this.end,
    required this.query,
  });

  final int start;
  final int end;
  final String query;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SlashCommandToken &&
          other.start == start &&
          other.end == end &&
          other.query == query;

  @override
  int get hashCode => Object.hash(start, end, query);
}

class SlashCommandMenuController {
  const SlashCommandMenuController._();

  static SlashCommandToken? activeTokenFor(TextEditingValue value) {
    final selection = value.selection;
    if (!selection.isValid || !selection.isCollapsed) return null;
    final cursor = selection.baseOffset;
    if (cursor < 0 || cursor > value.text.length) return null;
    final beforeCursor = value.text.substring(0, cursor);
    final slash = beforeCursor.lastIndexOf('/');
    if (slash < 0) return null;
    if (slash > 0 &&
        !_isSlashTokenBoundary(beforeCursor.codeUnitAt(slash - 1))) {
      return null;
    }
    for (var index = slash; index < beforeCursor.length; index += 1) {
      if (_isSlashTokenBoundary(beforeCursor.codeUnitAt(index))) return null;
    }
    return SlashCommandToken(
      start: slash,
      end: cursor,
      query: beforeCursor.substring(slash + 1),
    );
  }

  static SlashCommandToken? findToken(String text, {int? cursor}) {
    final offset = cursor ?? text.length;
    return activeTokenFor(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: offset),
      ),
    );
  }

  static bool _isSlashTokenBoundary(int codeUnit) =>
      codeUnit == 0x20 ||
      codeUnit == 0x09 ||
      codeUnit == 0x0A ||
      codeUnit == 0x0D;
}
