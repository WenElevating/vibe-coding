import 'package:flutter/material.dart';

import '../../../core/widgets/widgets.dart';

class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: const Color(0xFF101113),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: .07))),
      child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Column(children: [
            for (var i = 0; i < children.length; i++) ...[
              children[i],
              if (i != children.length - 1) const Hairline()
            ],
          ])),
    );
  }
}
