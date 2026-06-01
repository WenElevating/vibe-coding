import 'package:flutter/material.dart';

import '../../core/theme/theme.dart' as theme;

class MainErrorBanner extends StatelessWidget {
  const MainErrorBanner({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Positioned(
      left: 16,
      right: 16,
      bottom: 92 + bottomInset,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.red.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.red.withValues(alpha: .24)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: theme.red, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$error',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: theme.red, fontSize: 11.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
