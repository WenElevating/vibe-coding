import 'package:flutter/material.dart';

class HomeSurface extends StatelessWidget {
  const HomeSurface({super.key, required this.child, this.prominent = false});

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
