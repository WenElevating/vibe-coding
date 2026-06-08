import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart' as theme;

class ConnectionHeader extends StatelessWidget {
  const ConnectionHeader({
    super.key,
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              color: theme.faint,
              fontSize: 12.5,
              height: 1.35,
              letterSpacing: 0,
            ),
          ),
        ],
      );
}
