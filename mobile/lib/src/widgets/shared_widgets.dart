part of '../app/app.dart';

class _PageScroll extends PageScroll {
  const _PageScroll({required super.children, super.floating});
}

class _TopBar extends TopBar {
  const _TopBar({
    required super.title,
    super.subtitle,
    super.showScan = false,
    super.leading = false,
    super.action,
  });
}

class _SectionTitle extends SectionTitle {
  const _SectionTitle(super.title, {super.action, super.onAction});
}

class _Subhead extends Subhead {
  const _Subhead(super.text);
}

typedef _NavSpec = NavSpec;

class _BottomNav extends BottomNav {
  const _BottomNav({
    required super.selected,
    required super.items,
    required super.onTap,
  });
}

class _Tabs extends Tabs {
  const _Tabs({required super.labels});
}

class _MetricCard extends MetricCard {
  const _MetricCard({
    required super.label,
    required super.value,
    required super.note,
    required super.colors,
  });
}

class _GlassCard extends GlassCard {
  const _GlassCard({required super.child, super.padding});
}

class _CompactRun extends CompactRun {
  const _CompactRun({
    required super.title,
    required super.tool,
    required super.time,
    required super.status,
    required super.color,
    required super.iconColor,
    super.onTap,
  });
}

class _RunCard extends RunCard {
  const _RunCard({
    required super.title,
    required super.tool,
    required super.time,
    required super.status,
    required super.progress,
    required super.statusColor,
    super.onTap,
  });
}

class _QuickAction extends QuickAction {
  const _QuickAction({
    required super.icon,
    required super.title,
    required super.subtitle,
    required super.color,
    super.onTap,
  });
}

class _CodeDiff extends CodeDiff {
  const _CodeDiff();
}

class _ApprovalPreview extends ApprovalPreview {
  const _ApprovalPreview({required super.onTap});
}

class _Pill extends Pill {
  const _Pill(
    super.text, {
    super.selected = false,
    super.green = false,
    super.amber = false,
  });
}

class _SearchBar extends AppSearchBar {
  const _SearchBar();
}

class _QueueRow extends QueueRow {
  const _QueueRow({
    required super.title,
    required super.tool,
    required super.iconColor,
  });
}

class _WaitingRow extends WaitingRow {
  const _WaitingRow({
    required super.index,
    required super.title,
    required super.tool,
  });
}

class _AgentIcon extends AgentIcon {
  const _AgentIcon({required super.color});
}

class _FloatingPlus extends FloatingPlus {
  const _FloatingPlus({super.onTap});
}

class _Hairline extends Hairline {
  const _Hairline();
}

class _Glow extends Glow {
  const _Glow({required super.size, required super.color});
}

class _PrimaryButton extends PrimaryButton {
  const _PrimaryButton(super.text, {required super.onTap});
}

class _GhostButton extends GhostButton {
  const _GhostButton(super.text, {required super.color, required super.onTap});
}
