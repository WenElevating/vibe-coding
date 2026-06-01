import 'package:flutter/material.dart';

import '../../../../models/protocol.dart';
import '../../../core/theme/theme.dart' as theme;

class WorkbenchHeader extends StatelessWidget {
  const WorkbenchHeader({
    super.key,
    required this.title,
    required this.workspace,
    required this.adapter,
    required this.running,
    required this.onBack,
  });

  final String title;
  final WorkspaceSummary workspace;
  final String? adapter;
  final bool running;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Row(children: [
        InkWell(
            onTap: onBack,
            borderRadius: BorderRadius.circular(11),
            child: Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: const Color(0xFF141518),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: theme.stroke)),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: theme.muted, size: 16))),
        const SizedBox(width: 12),
        Expanded(
            child: Text(title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: theme.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0))),
        const SizedBox(width: 46),
      ]);
}
