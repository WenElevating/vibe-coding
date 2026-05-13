import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../features/workspace_picker/workspace_display.dart';
import '../../models/protocol.dart';
import '../../shell/app_route.dart';
import '../../shell/app_snapshot.dart';
import '../../theme/theme.dart' as theme;
import '../core/widgets/widgets.dart';
import 'home_command_deck_model.dart';

class HomePage extends StatelessWidget {
  const HomePage(
      {super.key,
      required this.open,
      required this.selectTab,
      required this.data});
  final ValueChanged<RoutePage> open;
  final ValueChanged<int> selectTab;
  final AppSnapshot data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final deck = buildHomeCommandDeckData(
      currentWorkspace: data.workspace,
      workspaces: data.workspaces,
      runs: data.runs,
      conversations: data.conversations,
      queue: data.queue,
      changedFiles: data.gitStatus?.files.length,
      diagnostics: data.diagnostics.available
          ? data.diagnostics.diagnostics.length
          : null,
      recentFiles:
          data.diagnostics.available ? data.overview.recentFiles.length : null,
    );

    return PageScroll(
      children: [
        _HomeCommandBar(workspace: data.workspace, onTap: () => selectTab(2)),
        const SizedBox(height: 14),
        _HomeNowPanel(
            data: deck, l10n: l10n, onTap: () => open(RoutePage.approval)),
        if (deck.interrupts.isNotEmpty) ...[
          const SizedBox(height: 14),
          _HomeInterruptLane(items: deck.interrupts, l10n: l10n),
        ],
        const SizedBox(height: 18),
        _HomeExecutionStream(
            items: deck.executionStream,
            l10n: l10n,
            onTap: () => open(RoutePage.detail)),
        const SizedBox(height: 18),
        _HomeWorkspaceSignals(data: deck.signals, l10n: l10n),
        const SizedBox(height: 18),
        _HomeActionRow(selectTab: selectTab, l10n: l10n),
      ],
    );
  }
}

class _HomeCommandBar extends StatelessWidget {
  const _HomeCommandBar({required this.workspace, required this.onTap});

  final WorkspaceSummary workspace;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1117),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: .08)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(workspaceDisplayName(workspace),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -.5)),
                    const SizedBox(height: 5),
                    Text(compactWorkspacePath(workspace.path),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: theme.muted, fontSize: 12.5)),
                  ],
                ),
              ),
              const Icon(Icons.keyboard_arrow_down_rounded, color: theme.muted),
            ],
          ),
        ),
      );
}

class _HomeNowPanel extends StatelessWidget {
  const _HomeNowPanel(
      {required this.data, required this.l10n, required this.onTap});

  final HomeCommandDeckData data;
  final AppLocalizations l10n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final item = data.now;
    return _InstrumentPanel(
      child: InkWell(
        onTap: item.isIdle ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PanelLabel(text: l10n.homeNowTitle),
              const SizedBox(height: 10),
              Row(
                children: [
                  _SignalDot(kind: item.kind),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.isIdle ? l10n.homeIdleNow : item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -.2)),
                        const SizedBox(height: 4),
                        Text(
                            item.isIdle
                                ? item.workspaceName
                                : '${item.workspaceName} · ${item.detail}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: theme.muted, fontSize: 12.5)),
                      ],
                    ),
                  ),
                  if (data.nowOverflowCount > 0)
                    Text(l10n.homeMoreSignalsLabel(data.nowOverflowCount),
                        style: const TextStyle(
                            color: theme.purple, fontWeight: FontWeight.w800)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeInterruptLane extends StatelessWidget {
  const _HomeInterruptLane({required this.items, required this.l10n});

  final List<HomeSignalItem> items;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelLabel(text: l10n.homeInterruptsTitle),
          const SizedBox(height: 8),
          for (final item in items) ...[
            _SignalRow(item: item),
            if (item != items.last) const SizedBox(height: 8),
          ],
        ],
      );
}

class _HomeExecutionStream extends StatelessWidget {
  const _HomeExecutionStream(
      {required this.items, required this.l10n, required this.onTap});

  final List<HomeSignalItem> items;
  final AppLocalizations l10n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(l10n.homeExecutionStreamTitle,
              action: l10n.homeViewAllAction, onAction: onTap),
          const SizedBox(height: 10),
          if (items.isEmpty)
            _InstrumentPanel(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(l10n.homeNoRecentActivity,
                    style: const TextStyle(color: theme.muted, fontSize: 13)),
              ),
            )
          else
            for (final item in items) ...[
              InkWell(onTap: onTap, child: _SignalRow(item: item)),
              if (item != items.last) const SizedBox(height: 8),
            ],
        ],
      );
}

class _HomeWorkspaceSignals extends StatelessWidget {
  const _HomeWorkspaceSignals({required this.data, required this.l10n});

  final HomeWorkspaceSignalsData data;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(l10n.homeWorkspaceSignalsTitle),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SignalChip(
                  label: l10n.homeGitChangedLabel,
                  value: _signalValue(data.changedFiles)),
              _SignalChip(
                  label: l10n.homeDiagnosticsLabel,
                  value: _signalValue(data.diagnostics)),
              _SignalChip(label: l10n.homeQueueLabel, value: '${data.queue}'),
              _SignalChip(
                  label: l10n.homeRecentFilesLabel,
                  value: _signalValue(data.recentFiles)),
            ],
          ),
        ],
      );
}

class _HomeActionRow extends StatelessWidget {
  const _HomeActionRow({required this.selectTab, required this.l10n});

  final ValueChanged<int> selectTab;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
              child: _ActionPill(
                  icon: Icons.add_rounded,
                  label: l10n.homeNewTaskTitle,
                  onTap: () => selectTab(1))),
          const SizedBox(width: 8),
          Expanded(
              child: _ActionPill(
                  icon: Icons.terminal_rounded,
                  label: l10n.homeCommandTemplatesTitle,
                  onTap: () => selectTab(2))),
          const SizedBox(width: 8),
          Expanded(
              child: _ActionPill(
                  icon: Icons.format_list_bulleted_rounded,
                  label: l10n.homeViewQueueTitle,
                  onTap: () => selectTab(3))),
        ],
      );
}

class _InstrumentPanel extends StatelessWidget {
  const _InstrumentPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0B0F14),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: .075)),
        ),
        child: child,
      );
}

class _PanelLabel extends StatelessWidget {
  const _PanelLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
      style: const TextStyle(
          color: theme.muted,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1));
}

class _SignalDot extends StatelessWidget {
  const _SignalDot({required this.kind});
  final HomeSignalKind kind;

  @override
  Widget build(BuildContext context) => Container(
        width: 8,
        height: 8,
        decoration:
            BoxDecoration(color: _signalColor(kind), shape: BoxShape.circle),
      );
}

class _SignalRow extends StatelessWidget {
  const _SignalRow({required this.item});
  final HomeSignalItem item;

  @override
  Widget build(BuildContext context) => _InstrumentPanel(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              _SignalDot(kind: item.kind),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 13.5)),
                    const SizedBox(height: 3),
                    Text('${item.workspaceName} · ${item.detail}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(color: theme.muted, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _SignalChip extends StatelessWidget {
  const _SignalChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1218),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: .07)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value,
                style:
                    const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(color: theme.muted, fontSize: 12)),
          ],
        ),
      );
}

class _ActionPill extends StatelessWidget {
  const _ActionPill(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          decoration: BoxDecoration(
            color: const Color(0xFF10151B),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: .075)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: theme.purple),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      );
}

Color _signalColor(HomeSignalKind kind) => switch (kind) {
      HomeSignalKind.approval => theme.amber,
      HomeSignalKind.failure => theme.red,
      HomeSignalKind.running => theme.green,
      HomeSignalKind.queue => theme.purple,
      HomeSignalKind.idle => theme.muted,
    };

String _signalValue(int? value) => value == null ? '—' : '$value';
