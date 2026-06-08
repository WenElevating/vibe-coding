import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../l10n/app_localizations.dart';
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
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_runErrorText(l10n, error),
            style:
                const TextStyle(color: theme.red, fontSize: 12, height: 1.45)),
        if (traceId != null) ...[
          const SizedBox(height: 8),
          Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SelectableText(l10n.workbenchRunErrorTraceId(traceId!),
                    style: const TextStyle(
                        color: theme.muted, fontSize: 12, height: 1.35)),
                TinyActionButton(l10n.workbenchRunErrorCopyTraceId,
                    onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await Clipboard.setData(ClipboardData(text: traceId!));
                  messenger.showSnackBar(SnackBar(
                      content: Text(l10n.workbenchRunErrorTraceIdCopied)));
                })
              ]),
        ],
      ]),
    );
  }
}

String _runErrorText(AppLocalizations l10n, String error) {
  final prefix = l10n.workbenchRunErrorPrefix;
  final separator = prefix.endsWith('：') ? '' : ' ';
  return '$prefix$separator$error';
}
