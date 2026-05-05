import 'package:flutter/material.dart';

import '../../theme/theme.dart' as theme;

Color runStatusColor(String status) {
  final lower = status.toLowerCase();
  if (lower.contains('fail') || lower.contains('error')) return theme.red;
  if (lower.contains('queue') || lower.contains('pending')) return theme.amber;
  if (lower.contains('running') || lower.contains('start')) return theme.green;
  return theme.purple;
}

Color runToolColor(String tool) {
  final lower = tool.toLowerCase();
  if (lower.contains('claude')) return theme.orange;
  if (lower.contains('codex')) return theme.purple;
  if (lower.contains('open')) return theme.green;
  return const Color(0xFF8BC7FF);
}
