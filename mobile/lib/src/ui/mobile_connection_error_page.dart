import 'package:flutter/material.dart';

import '../theme/theme.dart' as theme;
import '../widgets/widgets.dart';
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
    return Scaffold(
      body: MobileUiFrame(
        child: PageScroll(
          children: [
            const TopBar(title: 'Connection failed'),
            const SizedBox(height: 32),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.wifi_off_rounded,
                      color: theme.red, size: 34),
                  const SizedBox(height: 14),
                  const Text('Unable to connect to the local daemon',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text(error,
                      style: const TextStyle(color: theme.muted, fontSize: 12)),
                  const SizedBox(height: 16),
                  PrimaryButton('Retry connection', onTap: onRetry),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Run start-daemon.bat from D:\\AiProject\\vibe-coding. The preview uses http://127.0.0.1:4317.',
              style: TextStyle(color: theme.muted, fontSize: 12, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
