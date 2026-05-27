import 'package:flutter/material.dart';

import '../theme/theme.dart' as theme;

String displayVersion(String? version) =>
    version == null || version.isEmpty ? 'unknown' : version;

Color toolColor(String tool) {
  final lower = tool.toLowerCase();
  if (lower.contains('claude')) return theme.orange;
  if (lower.contains('codex')) return theme.purple;
  if (lower.contains('open')) return theme.green;
  return const Color(0xFF8BC7FF);
}

class Pill extends StatelessWidget {
  const Pill(this.text,
      {super.key,
      this.selected = false,
      this.green = false,
      this.amber = false});
  final String text;
  final bool selected;
  final bool green;
  final bool amber;

  @override
  Widget build(BuildContext context) {
    final color = green
        ? theme.green
        : amber
            ? theme.amber
            : theme.purple;
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: selected || green || amber
            ? color.withValues(alpha: .28)
            : theme.panelHi,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
            color: (selected || green || amber)
                ? color.withValues(alpha: .22)
                : theme.stroke),
      ),
      child: Text(text,
          style: TextStyle(
              color: selected ? Colors.white : theme.muted,
              fontSize: 12,
              fontWeight: FontWeight.w800)),
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.text, {super.key, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .13),
          borderRadius: BorderRadius.circular(7)),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w900)),
    );
  }
}

class AgentIcon extends StatelessWidget {
  const AgentIcon({super.key, required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient:
                LinearGradient(colors: [color, color.withValues(alpha: .45)])),
        child: const Icon(Icons.auto_awesome_rounded,
            size: 10, color: Colors.white));
  }
}

class QueueRow extends StatelessWidget {
  const QueueRow(
      {super.key,
      required this.title,
      required this.tool,
      required this.iconColor});
  final String title;
  final String tool;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        AgentIcon(color: iconColor),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          Text(tool, style: const TextStyle(color: theme.muted, fontSize: 12))
        ])),
        const SizedBox(
            width: 17,
            height: 17,
            child:
                CircularProgressIndicator(strokeWidth: 2, color: theme.green))
      ]),
    );
  }
}

class WaitingRow extends StatelessWidget {
  const WaitingRow(
      {super.key,
      required this.index,
      required this.title,
      required this.tool,
      required this.statusLabel});
  final String index;
  final String title;
  final String tool;
  final String statusLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Text(index, style: const TextStyle(color: theme.muted, fontSize: 18)),
        const SizedBox(width: 15),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          Text(tool, style: const TextStyle(color: theme.muted, fontSize: 12))
        ])),
        StatusBadge(statusLabel, color: theme.amber)
      ]),
    );
  }
}
