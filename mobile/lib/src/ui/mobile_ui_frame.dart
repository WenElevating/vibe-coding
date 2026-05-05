import 'package:flutter/material.dart';

import '../theme/theme.dart' as theme;
import '../widgets/widgets.dart';

class MobileUiFrame extends StatelessWidget {
  const MobileUiFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF101113), Color(0xFF08090B)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -160,
            right: -130,
            child: Glow(
              size: 260,
              color: theme.green.withValues(alpha: .10),
            ),
          ),
          Positioned(
            bottom: -170,
            left: -150,
            child: Glow(
              size: 260,
              color: theme.purple.withValues(alpha: .08),
            ),
          ),
          SafeArea(bottom: false, child: child),
        ],
      ),
    );
  }
}
