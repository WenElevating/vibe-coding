import 'package:flutter/material.dart';

import '../../../theme/theme.dart' as theme;

class NavSpec {
  const NavSpec(this.icon, this.label);
  final IconData icon;
  final String label;
}

class BottomNav extends StatelessWidget {
  const BottomNav(
      {super.key,
      required this.selected,
      required this.items,
      required this.onTap});
  final int selected;
  final List<NavSpec> items;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xE6080D15),
        border: Border(top: BorderSide(color: theme.stroke)),
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
                          color: i == selected ? theme.active : theme.muted,
                          size: 22),
                      const SizedBox(height: 4),
                      Text(items[i].label,
                          style: TextStyle(
                              color: i == selected ? theme.active : theme.muted,
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

class Tabs extends StatelessWidget {
  const Tabs({super.key, required this.labels});
  final List<String> labels;

  @override
  Widget build(BuildContext context) => Row(children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
              child: Container(
                  padding: const EdgeInsets.only(bottom: 9),
                  decoration: BoxDecoration(
                      border: Border(
                          bottom: BorderSide(
                              color: i == 0 ? theme.purple : theme.stroke,
                              width: i == 0 ? 2 : 1))),
                  child: Text(labels[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: i == 0 ? theme.purple : theme.muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w800))))
      ]);
}
