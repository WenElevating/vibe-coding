import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../models/protocol.dart';

import '../../core/theme/theme.dart' as theme;
import '../../core/widgets/widgets.dart';
import '../workspace_picker/workspace_picker.dart';
import 'session_item.dart';

class CodingSessionListPage extends StatelessWidget {
  const CodingSessionListPage(
      {super.key,
      required this.items,
      required this.currentWorkspace,
      required this.onNewSession,
      required this.onSelectItem,
      required this.onBackToWorkspaces,
      this.headerBanner});
  final List<SessionItem> items;
  final WorkspaceSummary currentWorkspace;
  final VoidCallback onNewSession;
  final ValueChanged<SessionItem> onSelectItem;
  final VoidCallback onBackToWorkspaces;
  final Widget? headerBanner;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currentItems = items
        .where((item) => item.run.workspaceId == currentWorkspace.id)
        .toList(growable: false);
    return Column(key: const ValueKey('coding-session-list'), children: [
      Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
              color: const Color(0xEE0A0B0D),
              border: Border(
                  bottom:
                      BorderSide(color: Colors.white.withValues(alpha: .07)))),
          child: Row(children: [
            InkWell(
                onTap: onBackToWorkspaces,
                borderRadius: BorderRadius.circular(12),
                child: const SizedBox(
                    width: 36,
                    height: 36,
                    child: Icon(Icons.chevron_left_rounded,
                        color: theme.muted, size: 24))),
            Expanded(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  Text(l10n.sessionsTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: theme.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0)),
                  const SizedBox(height: 3),
                  Text(
                      '${workspaceDisplayName(currentWorkspace)} · ${compactWorkspacePath(currentWorkspace.path)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: theme.faint,
                          fontSize: 10.5,
                          fontFamily: 'Consolas')),
                ])),
            _SessionNewButton(onTap: onNewSession),
          ])),
      Expanded(
          child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
              children: [
            if (headerBanner != null) ...[
              headerBanner!,
              const SizedBox(height: 12),
            ],
            const _SessionSearchBox(),
            const SizedBox(height: 14),
            _SessionGroupHeader(
                title: l10n.sessionsCurrentProject,
                meta: workspaceDisplayName(currentWorkspace)),
            const SizedBox(height: 6),
            if (currentItems.isEmpty)
              _EmptySessionStack(onNewSession: onNewSession)
            else
              _SessionStack(
                  children: currentItems
                      .map((item) => _SessionRunRow(
                          item: item, onTap: () => onSelectItem(item)))
                      .toList(growable: false)),
            const SizedBox(height: 16),
            Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                child: Text(l10n.sessionsFootnote,
                    style: const TextStyle(
                        color: Color(0xFF666D77),
                        fontSize: 11.5,
                        height: 1.5))),
          ])),
    ]);
  }
}

class _SessionNewButton extends StatelessWidget {
  const _SessionNewButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
      key: const ValueKey('session-new-button'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: const Color(0xFFF0F0F0),
              borderRadius: BorderRadius.circular(13)),
          child: const Icon(Icons.add_rounded,
              color: Color(0xFF08090B), size: 22)));
}

class _SessionSearchBox extends StatelessWidget {
  const _SessionSearchBox();

  @override
  Widget build(BuildContext context) => Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
          color: const Color(0xFF101113),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: .075))),
      child: Text(AppLocalizations.of(context).sessionsSearchPlaceholder,
          style: const TextStyle(color: Color(0xFF737983), fontSize: 13)));
}

class _SessionGroupHeader extends StatelessWidget {
  const _SessionGroupHeader({required this.title, required this.meta});
  final String title;
  final String meta;

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(children: [
        Text(title,
            style: const TextStyle(
                color: Color(0xFFD8D8D8),
                fontSize: 12.5,
                fontWeight: FontWeight.w800)),
        const Spacer(),
        Text(meta,
            style: const TextStyle(
                color: Color(0xFF6F757E),
                fontSize: 10.5,
                fontFamily: 'Consolas')),
      ]));
}

class _SessionStack extends StatelessWidget {
  const _SessionStack({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
      decoration: BoxDecoration(
          color: const Color(0xFF101113),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: .075))),
      child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(children: children)));
}

class _EmptySessionStack extends StatelessWidget {
  const _EmptySessionStack({required this.onNewSession});
  final VoidCallback onNewSession;

  @override
  Widget build(BuildContext context) => _SessionStack(children: [
        Padding(
            padding: const EdgeInsets.all(14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(AppLocalizations.of(context).sessionsEmptyTitle,
                  style: const TextStyle(
                      color: theme.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              TinyActionButton(AppLocalizations.of(context).sessionsNewSession,
                  onTap: onNewSession, primary: true),
            ]))
      ]);
}

class _SessionRunRow extends StatelessWidget {
  const _SessionRunRow({required this.item, required this.onTap});
  final SessionItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final run = item.run;
    final state = _sessionRunState(run.status, l10n);
    return InkWell(
        onTap: onTap,
        child: Container(
            constraints: const BoxConstraints(minHeight: 66),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(
                        color: Colors.white.withValues(alpha: .045)))),
            child: Row(children: [
              Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: const Color(0xFF18191C),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(state.icon,
                      style: TextStyle(
                          color: state.color,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'Consolas'))),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    Text(_sessionRunTitle(item, l10n),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Color(0xFFE9E9E9),
                            fontSize: 12.7,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                        '${_toolDisplayName(run.tool)} · ${run.cliSessionId ?? run.id} · ${state.label}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Color(0xFF858A94),
                            fontSize: 10.5,
                            fontFamily: 'Consolas')),
                  ])),
              const SizedBox(width: 10),
              Text(state.badge,
                  style: TextStyle(
                      color: state.color,
                      fontSize: 10.5,
                      fontFamily: 'Consolas')),
            ])));
  }
}

class _SessionRunVisualState {
  const _SessionRunVisualState(
      {required this.icon,
      required this.label,
      required this.badge,
      required this.color});
  final String icon;
  final String label;
  final String badge;
  final Color color;
}

_SessionRunVisualState _sessionRunState(String status, AppLocalizations l10n) {
  final lower = status.toLowerCase();
  if (lower.contains('approval') || lower.contains('pending')) {
    return _SessionRunVisualState(
        icon: '!',
        label: l10n.sessionsWaitingApproval,
        badge: l10n.sessionsPendingBadge,
        color: theme.amber);
  }
  if (lower.contains('running') || lower.contains('start')) {
    return _SessionRunVisualState(
        icon: '?',
        label: l10n.sessionsRunning,
        badge: 'live',
        color: theme.green);
  }
  if (lower.contains('fail') || lower.contains('error')) {
    return _SessionRunVisualState(
        icon: '?',
        label: l10n.sessionsFailed,
        badge: l10n.sessionsFailed,
        color: theme.red);
  }
  return _SessionRunVisualState(
      icon: '?',
      label: l10n.sessionsDone,
      badge: l10n.sessionsDone,
      color: const Color(0xFFA0A0A0));
}

String _sessionRunTitle(SessionItem item, AppLocalizations l10n) {
  final title = item.conversation?.title?.trim();
  if (title != null && title.isNotEmpty) return title;
  final run = item.run;
  if (run.cliSessionId != null && run.cliSessionId!.isNotEmpty) {
    return '${_toolDisplayName(run.tool)} ${l10n.sessionsSessionNoun} ${run.cliSessionId!.split('-').first}';
  }
  return '${_toolDisplayName(run.tool)} ${l10n.sessionsTaskNoun} ${run.id.split('_').last}';
}

String _toolDisplayName(String tool) {
  if (tool.isEmpty) return 'CLI';
  return tool[0].toUpperCase() + tool.substring(1);
}
