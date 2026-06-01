import 'package:flutter/material.dart';

import '../core/theme/theme.dart' as theme;

class EmptyStateCard extends StatelessWidget {
  const EmptyStateCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: theme.stroke),
        ),
        child: Column(children: children),
      );
}

class EmptyStateRow extends StatelessWidget {
  const EmptyStateRow({
    super.key,
    required this.title,
    required this.value,
  });

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Text(title, style: const TextStyle(color: theme.muted, fontSize: 12)),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: theme.text,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ]),
      );
}

class EmptyStateTapRow extends StatelessWidget {
  const EmptyStateTapRow({
    super.key,
    required this.title,
    this.value,
    required this.onTap,
  });

  final String title;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(color: theme.muted, fontSize: 12),
            ),
          ),
          _EmptyStateTapRowTrailing(value: value),
        ]),
      ),
    );
  }
}

class _EmptyStateTapRowTrailing extends StatelessWidget {
  const _EmptyStateTapRowTrailing({required this.value});

  final String? value;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null && value!.isNotEmpty) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                value!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: theme.text,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          const Icon(Icons.chevron_right_rounded, color: theme.faint, size: 18),
        ],
      );
}
