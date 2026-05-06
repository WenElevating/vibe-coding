import 'package:flutter/material.dart';

import '../theme/theme.dart' as theme;
import 'status.dart';
import 'top_bar.dart';

class MetricCard extends StatelessWidget {
  const MetricCard(
      {super.key,
      required this.label,
      required this.value,
      required this.note,
      required this.colors});
  final String label;
  final String value;
  final String note;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 110,
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 11),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.stroke),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: theme.text, fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(value,
            style: const TextStyle(
                fontSize: 28, fontWeight: FontWeight.w300, height: 1)),
        const SizedBox(height: 4),
        Text(note,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                const TextStyle(color: theme.muted, fontSize: 11, height: 1)),
      ]),
    );
  }
}

class GlassCard extends StatelessWidget {
  const GlassCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(14)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: theme.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.stroke),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: .28),
              blurRadius: 22,
              offset: const Offset(0, 12))
        ],
      ),
      child: child,
    );
  }
}

class CompactRun extends StatelessWidget {
  const CompactRun(
      {super.key,
      required this.title,
      required this.tool,
      required this.time,
      required this.status,
      required this.color,
      required this.iconColor,
      this.onTap});
  final String title;
  final String tool;
  final String time;
  final String status;
  final Color color;
  final Color iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          AgentIcon(color: iconColor),
          const SizedBox(width: 9),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Row(children: [
                  Text(tool,
                      style: const TextStyle(color: theme.muted, fontSize: 12)),
                  const SizedBox(width: 6),
                  Text('· $status',
                      style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(width: 4),
                  Dot(color: color, size: 4)
                ]),
              ])),
          Text(time, style: const TextStyle(color: theme.muted, fontSize: 12)),
        ]),
      ),
    );
  }
}

class RunCard extends StatelessWidget {
  const RunCard(
      {super.key,
      required this.title,
      required this.tool,
      required this.time,
      required this.status,
      required this.progress,
      required this.statusColor,
      this.onTap});
  final String title;
  final String tool;
  final String time;
  final String status;
  final double progress;
  final Color statusColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800))),
            StatusBadge(status, color: statusColor),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            AgentIcon(color: theme.purple),
            const SizedBox(width: 6),
            Text(tool, style: const TextStyle(color: theme.muted, fontSize: 12))
          ]),
          const SizedBox(height: 8),
          Text(time, style: const TextStyle(color: theme.muted, fontSize: 12)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                backgroundColor: Colors.white.withValues(alpha: .06),
                color: statusColor == theme.red ? theme.red : theme.purple),
          ),
        ]),
      ),
    );
  }
}

class QuickAction extends StatelessWidget {
  const QuickAction(
      {super.key,
      required this.icon,
      required this.title,
      required this.subtitle,
      required this.color,
      this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 92,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color.withValues(alpha: .32), theme.panelHi]),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: .22)),
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 25),
          const Spacer(),
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 3),
          Text(subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: theme.muted, fontSize: 10)),
        ]),
      ),
    );
  }
}

class CodeDiff extends StatelessWidget {
  const CodeDiff({super.key});
  @override
  Widget build(BuildContext context) => GlassCard(
      child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: const Color(0xFF081018),
              borderRadius: BorderRadius.circular(6)),
          child: const Text(
              '@@ -48,7 +48,13 @@ Future<User?> login(String email)\n\n-  throw Exception(\'Login failed\');\n+  // Handle edge cases\n+  if (response.body == null ||\n+      response.body.isEmpty) {\n+    throw Exception(\'Empty response\');\n+  }\n+\n   final data = jsonDecode(response.body);',
              style: TextStyle(
                  fontFamily: 'monospace',
                  color: Color(0xFF66E69A),
                  fontSize: 11,
                  height: 1.55))));
}

class ApprovalPreview extends StatelessWidget {
  const ApprovalPreview(
      {super.key,
      required this.title,
      required this.action,
      required this.onTap});
  final String title;
  final String action;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      child: GlassCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.warning_amber_rounded, color: theme.amber, size: 18),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const Spacer(),
          const Text('10:35', style: TextStyle(color: theme.muted, fontSize: 12))
        ]),
        const SizedBox(height: 8),
        Text(action, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('lib/services/auth_service.dart   +32 -8',
            style: TextStyle(color: theme.muted, fontSize: 12))
      ])));
}
