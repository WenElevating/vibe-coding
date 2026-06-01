import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../../domain/models/daemon_connection_config.dart';
import '../../../../models/protocol.dart';
import '../../../core/theme/theme.dart' as theme;
import '../../workspace_picker/workspace_display.dart';
import 'settings_metric.dart';

class SettingsConnectionCard extends StatelessWidget {
  const SettingsConnectionCard({
    super.key,
    required this.workspace,
    required this.connectionConfig,
    required this.mode,
    required this.lanMode,
    required this.l10n,
  });

  final WorkspaceSummary? workspace;
  final DaemonConnectionConfig connectionConfig;
  final String mode;
  final bool lanMode;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final workspace = this.workspace;
    return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: const Color(0xFF101113),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: .075))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: const Color(0xFF18191C),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: .055))),
                child: const Icon(Icons.lan_rounded,
                    color: theme.active, size: 18)),
            const SizedBox(width: 11),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(l10n.settingsCurrentConnectionTitle,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(workspace?.path ?? l10n.workspaceAvailableSection,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Color(0xFF858A94),
                          fontSize: 11.5,
                          fontFamily: 'Consolas')),
                ])),
            SettingsPill(l10n.settingsConnected)
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
                child: SettingsMetric(
                    label: l10n.settingsWorkspaceLabel,
                    value: workspace == null
                        ? l10n.workspaceListTitle
                        : workspaceDisplayName(workspace))),
            const SizedBox(width: 10),
            Expanded(
                child: SettingsMetric(
                    label: l10n.settingsSecurityModeLabel,
                    value: lanMode ? 'LAN' : mode)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
                child: SettingsMetric(
                    label: l10n.settingsDaemonAddressLabel,
                    value: connectionConfig.addressInput)),
            const SizedBox(width: 10),
            Expanded(
                child: SettingsMetric(
                    label: l10n.settingsProxyModeLabel,
                    value: proxyModeLabel(l10n, connectionConfig.proxyMode))),
          ]),
        ]));
  }
}

String proxyModeLabel(AppLocalizations l10n, DaemonProxyMode mode) =>
    switch (mode) {
      DaemonProxyMode.direct => l10n.settingsProxyDirect,
      DaemonProxyMode.system => l10n.settingsProxySystem,
      DaemonProxyMode.manual => l10n.settingsProxyManual,
    };
