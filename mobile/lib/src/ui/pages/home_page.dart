import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../models/protocol.dart';
import '../../shell/app_route.dart';
import '../core/theme/theme.dart' as theme;
import '../core/widgets/widgets.dart';
import '../features/workspace_picker/workspace_display.dart';
import 'home_command_deck_model.dart';
import 'home_view_model.dart';

class HomePage extends StatelessWidget {
  const HomePage(
      {super.key,
      required this.open,
      required this.selectTab,
      required this.viewModel,
      required this.health});
  final ValueChanged<RoutePage> open;
  final ValueChanged<int> selectTab;
  final HomeViewModel viewModel;
  final DaemonHealth health;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final l10n = AppLocalizations.of(context);
        final deck = viewModel.deck;
        if (deck == null) {
          return PageScroll(children: [
            _AgentConsolePanel.empty(
              daemon: health,
              l10n: l10n,
              onWorkspaceTap: () => selectTab(1),
              onPrimaryTap: () => selectTab(1),
              onTemplatesTap: () => selectTab(1),
            ),
          ]);
        }
        final global = _buildGlobalConsoleSummary(deck);
        return PageScroll(
          children: [
            _AgentConsolePanel(
              workspace: viewModel.currentWorkspace!,
              summary: global,
              daemon: health,
              l10n: l10n,
              onWorkspaceTap: () => selectTab(1),
              onPrimaryTap: global.needsAttention
                  ? () => open(RoutePage.approval)
                  : () => selectTab(1),
              onTemplatesTap: () => selectTab(1),
            ),
            if (global.attentionItems.isNotEmpty) ...[
              const SizedBox(height: 16),
              _HomeInterruptLane(items: global.attentionItems, l10n: l10n),
            ],
            const SizedBox(height: 18),
            _HomeExecutionStream(
                items: global.activityItems,
                l10n: l10n,
                onTap: () => open(RoutePage.detail)),
            const SizedBox(height: 18),
            _HomeWorkspaceSignals(data: deck.signals, l10n: l10n),
            const SizedBox(height: 18),
            _HomeQuickActions(selectTab: selectTab, l10n: l10n),
          ],
        );
      },
    );
  }
}

class _GlobalConsoleSummary {
  const _GlobalConsoleSummary({
    required this.attentionCount,
    required this.runningCount,
    required this.queueCount,
    required this.attentionItems,
    required this.activityItems,
  });

  final int attentionCount;
  final int runningCount;
  final int queueCount;
  final List<HomeSignalItem> attentionItems;
  final List<HomeSignalItem> activityItems;

  bool get needsAttention => attentionCount > 0;
}

_GlobalConsoleSummary _buildGlobalConsoleSummary(HomeCommandDeckData data) {
  final allAttentionItems = data.allSignals
      .where((item) =>
          item.kind == HomeSignalKind.approval ||
          item.kind == HomeSignalKind.failure ||
          item.kind == HomeSignalKind.queue)
      .toList();
  final attentionItems = allAttentionItems.take(3).toList();
  final activityItems = data.allSignals
      .where((item) => item.kind != HomeSignalKind.idle)
      .take(4)
      .toList();
  return _GlobalConsoleSummary(
    attentionCount: allAttentionItems.length,
    runningCount: data.allSignals
        .where((item) => item.kind == HomeSignalKind.running)
        .length,
    queueCount: data.allSignals
        .where((item) => item.kind == HomeSignalKind.queue)
        .length,
    attentionItems: attentionItems,
    activityItems: activityItems,
  );
}

class _AgentConsolePanel extends StatelessWidget {
  const _AgentConsolePanel({
    required this.workspace,
    required this.summary,
    required this.daemon,
    required this.l10n,
    required this.onWorkspaceTap,
    required this.onPrimaryTap,
    required this.onTemplatesTap,
  });

  const _AgentConsolePanel.empty({
    required this.daemon,
    required this.l10n,
    required this.onWorkspaceTap,
    required this.onPrimaryTap,
    required this.onTemplatesTap,
  })  : workspace = null,
        summary = const _GlobalConsoleSummary(
          attentionCount: 0,
          runningCount: 0,
          queueCount: 0,
          attentionItems: <HomeSignalItem>[],
          activityItems: <HomeSignalItem>[],
        );

  final WorkspaceSummary? workspace;
  final _GlobalConsoleSummary summary;
  final DaemonHealth daemon;
  final AppLocalizations l10n;
  final VoidCallback onWorkspaceTap;
  final VoidCallback onPrimaryTap;
  final VoidCallback onTemplatesTap;

  @override
  Widget build(BuildContext context) {
    final workspace = this.workspace;
    final accent = summary.needsAttention ? theme.amber : theme.green;
    final primaryLabel = summary.needsAttention
        ? l10n.homeInterruptsTitle
        : l10n.homeNewTaskTitle;
    final healthLabel = daemon.status.toLowerCase() == 'ok'
        ? l10n.homeDaemonOnline
        : daemon.status;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 15),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF111820), Color(0xFF080B10)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: .055)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('vibe-coding',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            height: 1.0)),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        _LiveMark(color: accent),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(healthLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: theme.muted, fontSize: 12.5)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _RoundIconButton(
                  icon: Icons.keyboard_arrow_down_rounded,
                  onTap: onWorkspaceTap),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _ConsoleMetric(
                  label: l10n.homeInterruptsTitle,
                  value: '${summary.attentionCount}',
                  color: summary.needsAttention ? theme.amber : theme.muted,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ConsoleMetric(
                  label: l10n.homeRunningMetricLabel,
                  value: '${summary.runningCount}',
                  color: theme.green,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ConsoleMetric(
                  label: l10n.homeQueueLabel,
                  value: '${summary.queueCount}',
                  color: theme.purple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (workspace != null)
            InkWell(
              onTap: onWorkspaceTap,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 11, 11, 11),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .035),
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: .055)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.folder_open_rounded,
                        color: theme.faint, size: 17),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(workspaceDisplayName(workspace),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  height: 1.1)),
                          const SizedBox(height: 4),
                          Text(compactWorkspacePath(workspace.path),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: theme.muted, fontSize: 11.5)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        color: theme.faint, size: 20),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _HomeCommandButton(
                  icon: summary.needsAttention
                      ? Icons.priority_high_rounded
                      : Icons.add_rounded,
                  label: primaryLabel,
                  color: accent,
                  primary: true,
                  onTap: onPrimaryTap,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HomeCommandButton(
                  icon: Icons.terminal_rounded,
                  label: l10n.homeCommandTemplatesTitle,
                  color: theme.purple,
                  onTap: onTemplatesTap,
                ),
              ),
            ],
          ),
        ],
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
          SectionTitle(l10n.homeInterruptsTitle),
          const SizedBox(height: 10),
          for (final item in items) ...[
            _SignalRow(item: item, prominent: true),
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
            _Surface(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.inbox_rounded,
                        color: theme.faint, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(l10n.homeNoRecentActivity,
                          style: const TextStyle(
                              color: theme.muted, fontSize: 13)),
                    ),
                  ],
                ),
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
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 2.55,
            children: [
              _SignalMetricTile(
                icon: Icons.commit_rounded,
                label: l10n.homeGitChangedLabel,
                value: _signalValue(data.changedFiles),
                color: theme.purple,
              ),
              _SignalMetricTile(
                icon: Icons.health_and_safety_rounded,
                label: l10n.homeDiagnosticsLabel,
                value: _signalValue(data.diagnostics),
                color: theme.amber,
              ),
              _SignalMetricTile(
                icon: Icons.queue_rounded,
                label: l10n.homeQueueLabel,
                value: '${data.queue}',
                color: theme.green,
              ),
              _SignalMetricTile(
                icon: Icons.history_rounded,
                label: l10n.homeRecentFilesLabel,
                value: _signalValue(data.recentFiles),
                color: const Color(0xFF8BC7FF),
              ),
            ],
          ),
        ],
      );
}

class _HomeQuickActions extends StatelessWidget {
  const _HomeQuickActions({required this.selectTab, required this.l10n});

  final ValueChanged<int> selectTab;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(l10n.homeQuickActionsTitle),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _QuickActionTile(
                  icon: Icons.add_rounded,
                  title: l10n.homeNewTaskTitle,
                  subtitle: l10n.homeNewTaskSubtitle,
                  color: theme.purple,
                  onTap: () => selectTab(1),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _QuickActionTile(
                  icon: Icons.terminal_rounded,
                  title: l10n.homeCommandTemplatesTitle,
                  subtitle: l10n.homeCommandTemplatesSubtitle,
                  color: theme.green,
                  onTap: () => selectTab(1),
                ),
              ),
            ],
          ),
        ],
      );
}

class _Surface extends StatelessWidget {
  const _Surface({required this.child, this.prominent = false});

  final Widget child;
  final bool prominent;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: prominent ? const Color(0xFF10161D) : const Color(0xFF0B0F14),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: .075)),
        ),
        child: child,
      );
}

class _ConsoleMetric extends StatelessWidget {
  const _ConsoleMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 9),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .18),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white.withValues(alpha: .045)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: color, fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: theme.muted, fontSize: 10.5)),
          ],
        ),
      );
}

class _LiveMark extends StatelessWidget {
  const _LiveMark({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: .38), blurRadius: 10),
          ],
        ),
      );
}

class _SignalRow extends StatelessWidget {
  const _SignalRow({required this.item, this.prominent = false});
  final HomeSignalItem item;
  final bool prominent;

  @override
  Widget build(BuildContext context) => _Surface(
        prominent: prominent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              _StatusGlyph(kind: item.kind, small: true),
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
                    Text('${item.workspaceName} / ${item.detail}',
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

class _SignalMetricTile extends StatelessWidget {
  const _SignalMetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => _Surface(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(11, 9, 10, 9),
          child: Row(
            children: [
              Icon(icon, color: color, size: 17),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: theme.muted, fontSize: 11.5)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: _Surface(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(height: 10),
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 13)),
                const SizedBox(height: 4),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: theme.muted, fontSize: 11.5)),
              ],
            ),
          ),
        ),
      );
}

class _HomeCommandButton extends StatelessWidget {
  const _HomeCommandButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: primary
                ? color.withValues(alpha: .2)
                : Colors.white.withValues(alpha: .045),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: primary
                    ? color.withValues(alpha: .38)
                    : Colors.white.withValues(alpha: .08)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 7),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w900)),
              ),
            ],
          ),
        ),
      );
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .045),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: .08)),
          ),
          child: Icon(icon, color: theme.muted, size: 21),
        ),
      );
}

class _StatusGlyph extends StatelessWidget {
  const _StatusGlyph({required this.kind, this.small = false});

  final HomeSignalKind kind;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final color = _signalColor(kind);
    final size = small ? 28.0 : 36.0;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(small ? 10 : 13),
        border: Border.all(color: color.withValues(alpha: .24)),
      ),
      child: Icon(_signalIcon(kind), color: color, size: small ? 15 : 19),
    );
  }
}

IconData _signalIcon(HomeSignalKind kind) => switch (kind) {
      HomeSignalKind.approval => Icons.rule_rounded,
      HomeSignalKind.failure => Icons.error_outline_rounded,
      HomeSignalKind.running => Icons.play_arrow_rounded,
      HomeSignalKind.queue => Icons.queue_rounded,
      HomeSignalKind.idle => Icons.check_rounded,
    };

Color _signalColor(HomeSignalKind kind) => switch (kind) {
      HomeSignalKind.approval => theme.amber,
      HomeSignalKind.failure => theme.red,
      HomeSignalKind.running => theme.green,
      HomeSignalKind.queue => theme.purple,
      HomeSignalKind.idle => theme.muted,
    };

String _signalValue(int? value) => value == null ? '-' : '$value';
