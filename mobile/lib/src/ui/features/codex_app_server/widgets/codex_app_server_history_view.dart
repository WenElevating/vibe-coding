import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
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
    final l10n = AppLocalizations.of(context);
    if (workspace == null) {
      return CodexEmptyState(
        icon: Icons.folder_open_rounded,
        title: l10n.codexAppServerSelectWorkspaceTitle,
        detail: l10n.codexAppServerSelectWorkspaceDetail,
      );
    }
    if (threads.isEmpty) {
      return CodexEmptyState(
        icon: Icons.forum_outlined,
        title: l10n.codexAppServerNoThreadsTitle,
        detail: l10n.codexAppServerNoThreadsDetail,
      );
    }
    return PageScroll(
      children: [
        CodexSectionHeader(
          label: l10n.codexAppServerRecentThreads,
          trailing: l10n.codexAppServerWorkspaceScoped,
        ),
        CodexSurface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var index = 0; index < threads.length; index++) ...[
                _ThreadRow(
                  thread: threads[index],
                  l10n: l10n,
                ),
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
  const _ThreadRow({
    required this.thread,
    required this.l10n,
  });

  final CodexAppServerThreadSummary thread;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final title = _threadTitle(l10n, thread);
    final contextLine = _threadContext(thread);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
      child: Row(
        children: [
          _ThreadGlyph(archived: thread.archived),
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
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                    height: 1.12,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  contextLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: theme.muted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                    height: 1.12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          CodexStatusPill(
            label: thread.archived
                ? l10n.codexAppServerThreadArchived
                : l10n.codexAppServerThreadOpen,
            color: thread.archived ? theme.faint : codexSuccess,
          ),
          const SizedBox(width: 4),
          const Icon(
            Icons.chevron_right_rounded,
            color: theme.faint,
            size: 22,
          ),
        ],
      ),
    );
  }
}

class _ThreadGlyph extends StatelessWidget {
  const _ThreadGlyph({required this.archived});

  final bool archived;

  @override
  Widget build(BuildContext context) {
    final color = archived ? theme.faint : codexSuccess;
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: color.withValues(alpha: archived ? .08 : .13),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: .10)),
      ),
      child: Icon(
        archived ? Icons.inventory_2_outlined : Icons.chat_bubble_outline,
        color: color,
        size: 16,
      ),
    );
  }
}

String _threadTitle(AppLocalizations l10n, CodexAppServerThreadSummary thread) {
  final title = thread.title.trim();
  if (title.isNotEmpty) return title;
  return l10n.codexAppServerThreadUntitled(_threadSuffix(thread.id));
}

String _threadContext(CodexAppServerThreadSummary thread) {
  final path = thread.workspacePath?.trim();
  if (path != null && path.isNotEmpty) return path;
  return _shortId(thread.id);
}

String _threadSuffix(String value) {
  if (value.length <= 8) return value;
  return value.substring(value.length - 8);
}

String _shortId(String value) {
  if (value.length <= 18) return value;
  return '${value.substring(0, 8)}...${value.substring(value.length - 6)}';
}
