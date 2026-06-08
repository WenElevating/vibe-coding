import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../core/theme/theme.dart' as theme;
import '../view_models/daemon_connection_view_model.dart';
import 'connection_labels.dart';

class ConnectionStatusPanel extends StatelessWidget {
  const ConnectionStatusPanel({
    super.key,
    required this.controller,
    required this.l10n,
  });

  final DaemonConnectionViewModel controller;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final failed = controller.status == DaemonConnectionStatus.failed;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0F12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: .07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: failed ? theme.red : theme.green,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  connectionStatusLabel(l10n, controller.status),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ),
              _ConnectionStatusTrailing(controller: controller, l10n: l10n),
            ],
          ),
          const SizedBox(height: 12),
          _ConnectionMetaRow(
            label: l10n.connectionTargetLabel,
            value: controller.addressInput,
          ),
          const SizedBox(height: 6),
          _ConnectionMetaRow(
            label: l10n.connectionProxyLabel,
            value: connectionProxyModeLabel(l10n, controller.proxyMode),
          ),
          if (controller.inputError != null ||
              controller.errorSummary != null) ...[
            const SizedBox(height: 12),
            Text(
              connectionErrorLabel(l10n, controller),
              style:
                  const TextStyle(color: theme.red, fontSize: 12, height: 1.4),
            ),
          ],
          if (controller.errorDetail != null) ...[
            const SizedBox(height: 6),
            Text(
              controller.errorDetail!,
              style: const TextStyle(
                color: theme.faint,
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConnectionStatusTrailing extends StatelessWidget {
  const _ConnectionStatusTrailing({
    required this.controller,
    required this.l10n,
  });

  final DaemonConnectionViewModel controller;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    if (controller.isBusy) {
      return const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: theme.green,
          backgroundColor: Color(0x2232D583),
        ),
      );
    }
    if (controller.status == DaemonConnectionStatus.failed) {
      return Text(
        l10n.connectionStatusError,
        style: const TextStyle(
          color: theme.red,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _ConnectionMetaRow extends StatelessWidget {
  const _ConnectionMetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              label,
              style: const TextStyle(
                color: theme.faint,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: theme.muted,
                fontSize: 12,
                fontFamily: 'Consolas',
                height: 1.35,
              ),
            ),
          ),
        ],
      );
}
