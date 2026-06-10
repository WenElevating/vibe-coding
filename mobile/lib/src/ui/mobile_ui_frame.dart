import 'package:flutter/material.dart';

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
      child: SafeArea(bottom: false, child: child),
    );
  }
}
