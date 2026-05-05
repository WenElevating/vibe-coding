import 'package:flutter/material.dart';

class PageScroll extends StatelessWidget {
  const PageScroll({super.key, required this.children, this.floating});
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

class Glow extends StatelessWidget {
  const Glow({super.key, required this.size, required this.color});
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
