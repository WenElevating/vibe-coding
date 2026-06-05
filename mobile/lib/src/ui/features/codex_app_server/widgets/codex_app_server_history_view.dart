import 'package:flutter/material.dart';

import '../../../../domain/models/codex_app_server_models.dart';
import '../../../../models/protocol.dart';
import '../../../core/theme/theme.dart' as theme;
import '../../../core/widgets/widgets.dart';
import 'codex_app_server_ui.dart';

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
      return const CodexEmptyState(
        icon: Icons.folder_open_rounded,
        title: 'Select a workspace',
        detail: 'History is scoped to the active authorized workspace.',
      );
    }
    if (threads.isEmpty) {
      return const CodexEmptyState(
        icon: Icons.forum_outlined,
        title: 'No app-server threads',
        detail:
            'Thread history will appear here after app-server sessions run.',
      );
    }
    return PageScroll(
      children: [
        const CodexSectionHeader(
          label: 'Recent threads',
          trailing: 'Workspace scoped',
        ),
        CodexSurface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var index = 0; index < threads.length; index++) ...[
                _ThreadRow(thread: threads[index]),
                if (index != threads.length - 1)
                  const Divider(height: 1, color: codexLine),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ThreadRow extends StatelessWidget {
  const _ThreadRow({required this.thread});

  final CodexAppServerThreadSummary thread;

  @override
  Widget build(BuildContext context) {
    final title = _threadTitle(thread);
    final contextLine = _threadContext(thread);
    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 0, 12),
          child: _ThreadGlyph(archived: thread.archived),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                contextLine,
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
        const SizedBox(width: 12),
        CodexStatusPill(
          label: thread.archived ? 'Archived' : 'Open',
          color: thread.archived ? theme.faint : codexSuccess,
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(8, 0, 12, 0),
          child: Icon(Icons.chevron_right_rounded, color: theme.faint),
        ),
      ],
    );
  }
}

class _ThreadGlyph extends StatelessWidget {
  const _ThreadGlyph({required this.archived});

  final bool archived;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: archived
            ? Colors.white.withValues(alpha: .05)
            : codexSuccess.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        archived ? Icons.inventory_2_outlined : Icons.chat_bubble_outline,
        color: archived ? theme.faint : codexSuccess,
        size: 17,
      ),
    );
  }
}

String _threadTitle(CodexAppServerThreadSummary thread) {
  final title = thread.title.trim();
  if (title.isNotEmpty) return title;
  return _shortId(thread.id);
}

String _threadContext(CodexAppServerThreadSummary thread) {
  final path = thread.workspacePath?.trim();
  if (path != null && path.isNotEmpty) return path;
  return thread.id;
}

String _shortId(String value) {
  if (value.length <= 24) return value;
  return '${value.substring(0, 12)}...${value.substring(value.length - 8)}';
}
