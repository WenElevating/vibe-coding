part of '../app/app.dart';

class _PageScroll extends StatelessWidget {
  const _PageScroll({required this.children, this.floating});
  final List<Widget> children;
  final Widget? floating;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 104),
          children: children,
        ),
        if (floating != null)
          Positioned(right: 18, bottom: 92, child: floating!),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar(
      {required this.title,
      this.subtitle,
      this.showScan = false,
      this.leading = false,
      this.action});
  final String title;
  final String? subtitle;
  final bool showScan;
  final bool leading;
  final String? action;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (leading) ...[
              const Icon(Icons.chevron_left_rounded, color: _text, size: 26),
              const SizedBox(width: 8)
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Row(children: [
                      Text(subtitle!.replaceAll('在线', ''),
                          style: const TextStyle(
                              color: _muted, fontSize: 12, letterSpacing: .5)),
                      const Text('在线',
                          style: TextStyle(
                              color: _green,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(width: 4),
                      const _Dot(color: _green, size: 5),
                    ]),
                  ],
                ],
              ),
            ),
            if (action != null)
              Text(action!,
                  style: const TextStyle(
                      color: _purple, fontWeight: FontWeight.w700)),
            if (showScan)
              const Icon(Icons.center_focus_weak_rounded,
                  color: _muted, size: 24),
            if (!showScan && action == null)
              const Icon(Icons.more_horiz_rounded, color: _muted, size: 26),
          ],
        ),
      ],
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav(
      {required this.selected, required this.items, required this.onTap});
  final int selected;
  final List<_NavSpec> items;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xE6080D15),
        border: Border(top: BorderSide(color: _stroke)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 18),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (var i = 0; i < items.length; i++)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onTap(i),
                child: SizedBox(
                  width: 58,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(items[i].icon,
                          color: i == selected ? _active : _muted, size: 22),
                      const SizedBox(height: 4),
                      Text(items[i].label,
                          style: TextStyle(
                              color: i == selected ? _active : _muted,
                              fontSize: 11,
                              fontWeight: i == selected
                                  ? FontWeight.w800
                                  : FontWeight.w500)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(
      {required this.label,
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
        border: Border.all(color: _stroke),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: _text, fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(value,
            style: const TextStyle(
                fontSize: 28, fontWeight: FontWeight.w300, height: 1)),
        const SizedBox(height: 4),
        Text(note,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _muted, fontSize: 11, height: 1)),
      ]),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard(
      {required this.child, this.padding = const EdgeInsets.all(14)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _stroke),
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

class _CompactRun extends StatelessWidget {
  const _CompactRun(
      {required this.title,
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
          _AgentIcon(color: iconColor),
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
                      style: const TextStyle(color: _muted, fontSize: 12)),
                  const SizedBox(width: 6),
                  Text('· $status',
                      style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(width: 4),
                  _Dot(color: color, size: 4)
                ]),
              ])),
          Text(time, style: const TextStyle(color: _muted, fontSize: 12)),
        ]),
      ),
    );
  }
}

class _RunCard extends StatelessWidget {
  const _RunCard(
      {required this.title,
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
      child: _GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800))),
            _StatusBadge(status, color: statusColor),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _AgentIcon(color: _purple),
            const SizedBox(width: 6),
            Text(tool, style: const TextStyle(color: _muted, fontSize: 12))
          ]),
          const SizedBox(height: 8),
          Text(time, style: const TextStyle(color: _muted, fontSize: 12)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                backgroundColor: Colors.white.withValues(alpha: .06),
                color: statusColor == _red ? _red : _purple),
          ),
        ]),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction(
      {required this.icon,
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
              colors: [color.withValues(alpha: .32), _panelHi]),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: .22)),
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 25),
          const Spacer(),
          Text(title,
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 3),
          Text(subtitle, style: const TextStyle(color: _muted, fontSize: 10)),
        ]),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text,
      {this.selected = false, this.green = false, this.amber = false});
  final String text;
  final bool selected;
  final bool green;
  final bool amber;

  @override
  Widget build(BuildContext context) {
    final color = green
        ? _green
        : amber
            ? _amber
            : _purple;
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: selected || green || amber
            ? color.withValues(alpha: .28)
            : _panelHi,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
            color: (selected || green || amber)
                ? color.withValues(alpha: .22)
                : _stroke),
      ),
      child: Text(text,
          style: TextStyle(
              color: selected ? Colors.white : _muted,
              fontSize: 12,
              fontWeight: FontWeight.w800)),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar();

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
              color: _panelHi,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _stroke)),
          child: const Row(children: [
            Icon(Icons.search_rounded, color: _muted, size: 18),
            SizedBox(width: 8),
            Text('搜索任务、描述、工具...', style: TextStyle(color: _faint, fontSize: 13))
          ]),
        ),
      ),
      const SizedBox(width: 9),
      Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
              color: _panelHi,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _stroke)),
          child: const Icon(Icons.filter_alt_rounded, color: _text, size: 18)),
    ]);
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow(
      {required this.title, required this.tool, required this.iconColor});
  final String title;
  final String tool;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        _AgentIcon(color: iconColor),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          Text(tool, style: const TextStyle(color: _muted, fontSize: 12))
        ])),
        const SizedBox(
            width: 17,
            height: 17,
            child: CircularProgressIndicator(strokeWidth: 2, color: _green))
      ]),
    );
  }
}

class _WaitingRow extends StatelessWidget {
  const _WaitingRow(
      {required this.index, required this.title, required this.tool});
  final String index;
  final String title;
  final String tool;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Text(index, style: const TextStyle(color: _muted, fontSize: 18)),
        const SizedBox(width: 15),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          Text(tool, style: const TextStyle(color: _muted, fontSize: 12))
        ])),
        _StatusBadge('等待中', color: _amber)
      ]),
    );
  }
}


class _StatusBadge extends StatelessWidget {
  const _StatusBadge(this.text, {required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .13),
          borderRadius: BorderRadius.circular(7)),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w900)),
    );
  }
}

class _AgentIcon extends StatelessWidget {
  const _AgentIcon({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient:
                LinearGradient(colors: [color, color.withValues(alpha: .45)])),
        child: const Icon(Icons.auto_awesome_rounded,
            size: 10, color: Colors.white));
  }
}

class _FloatingPlus extends StatelessWidget {
  const _FloatingPlus({this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(colors: [_purple, _purple2]),
              boxShadow: [
                BoxShadow(color: _purple.withValues(alpha: .42), blurRadius: 24)
              ]),
          child: const Icon(Icons.add_rounded, size: 34, color: Colors.white),
        ));
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline();
  @override
  Widget build(BuildContext context) => Container(height: 1, color: _stroke);
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, this.size = 6});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: .45), blurRadius: 8)
          ]));
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => IgnorePointer(
      child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                color.withValues(alpha: .18),
                color.withValues(alpha: .04),
                Colors.transparent
              ]))));
}

class _NavSpec {
  const _NavSpec(this.icon, this.label);
  final IconData icon;
  final String label;
}


class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton(this.text, {required this.onTap});
  final String text;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_purple, _purple2]),
              borderRadius: BorderRadius.circular(8)),
          child:
              Text(text, style: const TextStyle(fontWeight: FontWeight.w900))));
}

class _GhostButton extends StatelessWidget {
  const _GhostButton(this.text, {required this.color, required this.onTap});
  final String text;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: .35))),
          child: Text(text,
              style: TextStyle(color: color, fontWeight: FontWeight.w900))));
}
