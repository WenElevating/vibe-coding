import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/theme.dart' as theme;
import '../../../core/widgets/widgets.dart';

class WorkbenchRunErrorCard extends StatelessWidget {
  const WorkbenchRunErrorCard({
    super.key,
    required this.error,
    required this.traceId,
  });

  final String error;
  final String? traceId;

  @override
  Widget build(BuildContext context) => GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Run error: $error',
              style: const TextStyle(
                  color: theme.red, fontSize: 12, height: 1.45)),
          if (traceId != null) ...[
            const SizedBox(height: 8),
            Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SelectableText('Trace ID: $traceId',
                      style: const TextStyle(
                          color: theme.muted, fontSize: 12, height: 1.35)),
                  TinyActionButton('Copy Trace ID', onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await Clipboard.setData(ClipboardData(text: traceId!));
                    messenger.showSnackBar(
                        const SnackBar(content: Text('Trace ID copied')));
                  })
                ]),
          ],
        ]),
      );
}
