import 'package:flutter/material.dart';

import '../core/widgets/widgets.dart';

class CodingAdapterGate extends StatelessWidget {
  const CodingAdapterGate({
    super.key,
    required this.failed,
    required this.error,
    required this.onRetry,
  });

  final bool failed;
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!failed) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Loading CLI...'),
            ] else ...[
              const Icon(Icons.error_outline, size: 42),
              const SizedBox(height: 12),
              const Text('Unable to load CLI adapters'),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text('$error', textAlign: TextAlign.center),
              ],
              const SizedBox(height: 16),
              PrimaryButton('Retry loading CLI', onTap: onRetry),
            ],
          ],
        ),
      ),
    );
  }
}
