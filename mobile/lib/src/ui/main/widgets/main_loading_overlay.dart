import 'package:flutter/material.dart';

import '../../core/theme/theme.dart' as theme;

class MainLoadingOverlay extends StatelessWidget {
  const MainLoadingOverlay({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: .24),
        alignment: Alignment.center,
        padding: EdgeInsets.fromLTRB(16, 16, 16, 90 + bottomInset),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF111820),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: .1)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: theme.text, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
