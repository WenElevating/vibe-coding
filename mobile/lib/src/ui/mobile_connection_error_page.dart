import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'core/theme/theme.dart' as theme;
import 'core/widgets/widgets.dart';
import 'mobile_ui_frame.dart';

class MobileConnectionErrorPage extends StatelessWidget {
  const MobileConnectionErrorPage({
    super.key,
    required this.error,
    required this.onRetry,
  });

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: MobileUiFrame(
        child: PageScroll(
          children: [
            TopBar(title: l10n.connectionStatusFailed),
            const SizedBox(height: 32),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.wifi_off_rounded,
                      color: theme.red, size: 34),
                  const SizedBox(height: 14),
                  Text(l10n.connectionFailureHeadline,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text(error,
                      style: const TextStyle(color: theme.muted, fontSize: 12)),
                  const SizedBox(height: 16),
                  PrimaryButton(l10n.connectionRetryAction, onTap: onRetry),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              l10n.connectionFailureHelp,
              style: const TextStyle(
                  color: theme.muted, fontSize: 12, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
