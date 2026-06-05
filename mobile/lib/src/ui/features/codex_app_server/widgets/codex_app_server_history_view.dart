import 'package:flutter/material.dart';

import '../../../../domain/models/codex_app_server_models.dart';
import '../../../../models/protocol.dart';
import '../../../core/theme/theme.dart' as theme;
import '../../../core/widgets/widgets.dart';

class CodexAppServerHistoryView extends StatelessWidget {
  const CodexAppServerHistoryView({
    super.key,
    required this.threads,
    required this.workspace,
  });

  final List<CodexAppServerThreadSummary> threads;
  final WorkspaceSummary? workspace;

  @override
  Widget build(BuildContext context) {
    if (workspace == null) {
      return const _EmptyState(
        title: 'Select a workspace',
        detail: 'History is scoped to the active authorized workspace.',
      );
    }
    if (threads.isEmpty) {
      return const _EmptyState(
        title: 'No app-server threads',
        detail:
            'Thread history will appear here after app-server sessions run.',
      );
    }
    return PageScroll(
      children: [
        const SizedBox(height: 14),
        for (final thread in threads) ...[
          _ThreadTile(thread: thread),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({required this.thread});

  final CodexAppServerThreadSummary thread;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101113),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: .07)),
      ),
      child: Row(
        children: [
          Icon(
            thread.archived ? Icons.inventory_2_rounded : Icons.forum_rounded,
            color: thread.archived ? theme.muted : const Color(0xFF63D297),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  thread.title.isEmpty ? thread.id : thread.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  thread.workspacePath ?? thread.id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: theme.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _ThreadStatusChip(label: thread.archived ? 'Archived' : 'Open'),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded, color: theme.faint),
        ],
      ),
    );
  }
}

class _ThreadStatusChip extends StatelessWidget {
  const _ThreadStatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: theme.muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
