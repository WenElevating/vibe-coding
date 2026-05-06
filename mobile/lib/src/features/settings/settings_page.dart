import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../app/language_mode.dart';
import '../../app/language_scope.dart';
import '../../models/protocol.dart';
import '../../services/daemon_connection_config.dart';
import '../../shell/shell.dart';
import '../../theme/theme.dart' as theme;
import '../../widgets/widgets.dart';
import '../workspace_picker/workspace_display.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage(
      {super.key,
      required this.open,
      required this.data,
      required this.connectionConfig,
      required this.streamOutput,
      required this.expandThinking,
      required this.permissionMode,
      required this.onPermissionModeChanged,
      required this.onStreamOutputChanged,
      required this.onExpandThinkingChanged});
  final ValueChanged<RoutePage> open;
  final AppSnapshot data;
  final DaemonConnectionConfig connectionConfig;
  final bool streamOutput;
  final bool expandThinking;
  final String permissionMode;
  final ValueChanged<String> onPermissionModeChanged;
  final ValueChanged<bool> onStreamOutputChanged;
  final ValueChanged<bool> onExpandThinkingChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final language = LanguageScope.watch(context);
    return PageScroll(
      children: [
        TopBar(title: l10n.settingsTitle),
        const SizedBox(height: 14),
        _SettingsConnectionCard(
            workspace: data.workspace,
            connectionConfig: connectionConfig,
            mode: data.health.mode,
            lanMode: data.health.lanMode,
            l10n: l10n),
        const SizedBox(height: 20),
        Subhead(l10n.settingsPreferencesSection),
        _SettingsCard(children: [
          _SettingsTapRow(
              title: l10n.settingsLanguageTitle,
              value: _languageModeLabel(l10n, language.mode),
              onTap: () => _showLanguagePicker(context)),
        ]),
        const SizedBox(height: 20),
        Subhead(l10n.settingsCodingControlSection),
        _SettingsCard(children: [
          _PermissionModeRow(
              value: permissionMode,
              onChanged: onPermissionModeChanged,
              l10n: l10n),
          _SettingsSwitchRow(
              title: l10n.settingsStreamOutputTitle,
              subtitle: l10n.settingsStreamOutputSubtitle,
              value: streamOutput,
              onChanged: onStreamOutputChanged),
          _SettingsSwitchRow(
              title: l10n.settingsExpandThinkingTitle,
              subtitle: l10n.settingsExpandThinkingSubtitle,
              value: expandThinking,
              onChanged: onExpandThinkingChanged),
        ]),
        const SizedBox(height: 20),
        Subhead(l10n.settingsDataStatusSection),
        _SettingsCard(children: [
          _SettingsRow(
              title: l10n.settingsDiagnosticsTitle,
              value: l10n.settingsDiagnosticsCount(
                  data.diagnostics.diagnostics.length)),
          _SettingsRow(
              title: l10n.settingsGitStatusTitle,
              value: data.gitStatus?.clean == true
                  ? l10n.settingsGitClean
                  : l10n.settingsGitFiles(data.gitStatus?.files.length ?? 0)),
        ]),
        const SizedBox(height: 20),
        Subhead(l10n.settingsAboutSection),
        _SettingsCard(children: [
          _SettingsRow(title: 'daemon', value: data.health.daemonVersion),
          _SettingsRow(
              title: l10n.settingsExtensionsTitle,
              value: l10n.settingsExtensionsCount(data.extensions.length)),
        ]),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
              child: _SettingsActionButton(l10n.settingsAdaptersAction,
                  icon: Icons.extension_rounded,
                  onTap: () => open(RoutePage.adapters))),
          const SizedBox(width: 10),
          Expanded(
              child: _SettingsActionButton(l10n.settingsNotificationsAction,
                  icon: Icons.notifications_rounded,
                  onTap: () => open(RoutePage.notifications))),
        ]),
        const SizedBox(height: 10),
        _SettingsActionButton(l10n.settingsGenerateDiagnosticsAction,
            icon: Icons.health_and_safety_rounded,
            fullWidth: true,
            onTap: () => open(RoutePage.diagnostics)),
      ],
    );
  }
}

String _languageModeLabel(
        AppLocalizations l10n, LanguageModePreference mode) =>
    switch (mode) {
      LanguageModePreference.system => l10n.settingsLanguageSystem,
      LanguageModePreference.zhHansCn => '简体中文',
      LanguageModePreference.enUs => 'English',
    };

void _showLanguagePicker(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  final controller = LanguageScope.read(context);
  showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _LanguagePickerSheet(
          title: l10n.settingsLanguagePickerTitle,
          selected: controller.mode,
          onSelected: (mode) async {
            Navigator.of(context).pop();
            await controller.setMode(mode);
          }));
}

class _SettingsTapRow extends StatelessWidget {
  const _SettingsTapRow(
      {required this.title, required this.value, required this.onTap});
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(children: [
            Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w800))),
            Text(value,
                style: const TextStyle(
                    color: theme.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded,
                color: theme.faint, size: 18),
          ])));
}

class _LanguagePickerSheet extends StatelessWidget {
  const _LanguagePickerSheet(
      {required this.title, required this.selected, required this.onSelected});
  final String title;
  final LanguageModePreference selected;
  final ValueChanged<LanguageModePreference> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final options = <(LanguageModePreference, String)>[
      (LanguageModePreference.system, l10n.settingsLanguageSystem),
      (LanguageModePreference.zhHansCn, '简体中文'),
      (LanguageModePreference.enUs, 'English'),
    ];
    return SafeArea(
        child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            decoration: BoxDecoration(
                color: const Color(0xFF101113),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: .08))),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            color: theme.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w900))),
                IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded,
                        color: theme.muted, size: 18)),
              ]),
              for (final option in options)
                ListTile(
                    dense: true,
                    title: Text(option.$2),
                    trailing: selected == option.$1
                        ? const Icon(Icons.check_rounded,
                            color: theme.green, size: 18)
                        : null,
                    onTap: () => onSelected(option.$1)),
            ])));
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: const Color(0xFF101113),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: .07))),
      child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Column(children: [
            for (var i = 0; i < children.length; i++) ...[
              children[i],
              if (i != children.length - 1) const Hairline()
            ],
          ])),
    );
  }
}

class _SettingsConnectionCard extends StatelessWidget {
  const _SettingsConnectionCard(
      {required this.workspace,
      required this.connectionConfig,
      required this.mode,
      required this.lanMode,
      required this.l10n});
  final WorkspaceSummary workspace;
  final DaemonConnectionConfig connectionConfig;
  final String mode;
  final bool lanMode;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => Container(
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
                  border:
                      Border.all(color: Colors.white.withValues(alpha: .055))),
              child:
                  const Icon(Icons.lan_rounded, color: theme.active, size: 18)),
          const SizedBox(width: 11),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(l10n.settingsCurrentConnectionTitle,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 15)),
                const SizedBox(height: 4),
                Text(workspace.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color(0xFF858A94),
                        fontSize: 11.5,
                        fontFamily: 'Consolas')),
              ])),
          _SettingsPill(l10n.settingsConnected)
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
              child: _SettingsMetric(
                  label: l10n.settingsWorkspaceLabel,
                  value: workspaceDisplayName(workspace))),
          const SizedBox(width: 10),
          Expanded(
              child: _SettingsMetric(
                  label: l10n.settingsSecurityModeLabel,
                  value: lanMode ? 'LAN' : mode)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
              child: _SettingsMetric(
                  label: l10n.settingsDaemonAddressLabel,
                  value: connectionConfig.addressInput)),
          const SizedBox(width: 10),
          Expanded(
              child: _SettingsMetric(
                  label: l10n.settingsProxyModeLabel,
                  value: _proxyModeLabel(l10n, connectionConfig.proxyMode))),
        ]),
      ]));
}

String _proxyModeLabel(AppLocalizations l10n, DaemonProxyMode mode) =>
    switch (mode) {
      DaemonProxyMode.direct => l10n.settingsProxyDirect,
      DaemonProxyMode.system => l10n.settingsProxySystem,
      DaemonProxyMode.manual => l10n.settingsProxyManual,
    };

class _SettingsMetric extends StatelessWidget {
  const _SettingsMetric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
          color: const Color(0xFF0B0C0E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: .055))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style:
                const TextStyle(color: theme.faint, fontSize: 10.5, height: 1)),
        const SizedBox(height: 7),
        Text(value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900)),
      ]));
}

class _SettingsPill extends StatelessWidget {
  const _SettingsPill(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
          color: theme.active.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: theme.active.withValues(alpha: .16))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Dot(color: theme.green, size: 5),
        const SizedBox(width: 6),
        Text(text,
            style: const TextStyle(
                color: theme.active,
                fontSize: 11,
                fontWeight: FontWeight.w900)),
      ]));
}

class _SettingsActionButton extends StatelessWidget {
  const _SettingsActionButton(this.text,
      {required this.icon, required this.onTap, this.fullWidth = false});
  final String text;
  final IconData icon;
  final VoidCallback onTap;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
          height: 46,
          width: fullWidth ? double.infinity : null,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
              color: const Color(0xFF101113),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.white.withValues(alpha: .075))),
          child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: theme.active, size: 16),
                const SizedBox(width: 8),
                Text(text,
                    style: const TextStyle(
                        color: theme.active,
                        fontSize: 13,
                        fontWeight: FontWeight.w900)),
              ])));
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.title, required this.value});
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(children: [
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
        ])),
        Text(value,
            style: const TextStyle(
                color: theme.muted, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _PermissionModeRow extends StatelessWidget {
  const _PermissionModeRow(
      {required this.value, required this.onChanged, required this.l10n});
  final String value;
  final ValueChanged<String> onChanged;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(l10n.settingsPermissionModeTitle,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 14))),
          _PermissionChip(
              label: l10n.settingsPermissionDefault,
              selected: value == 'default',
              onTap: () => onChanged('default')),
          const SizedBox(width: 8),
          _PermissionChip(
              label: l10n.settingsPermissionAuto,
              selected: value == 'auto',
              onTap: () => onChanged('auto')),
        ]),
        const SizedBox(height: 8),
        Text(l10n.settingsPermissionSubtitle,
            style: const TextStyle(
                color: Color(0xFF858A94), fontSize: 11.5, height: 1.35)),
      ]));
}

class _PermissionChip extends StatelessWidget {
  const _PermissionChip(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: selected
                  ? theme.activePanel
                  : Colors.white.withValues(alpha: .04),
              border: Border.all(
                  color: selected
                      ? theme.activeStroke.withValues(alpha: .9)
                      : theme.stroke)),
          child: Text(label,
              style: TextStyle(
                  color: selected ? theme.active : theme.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w900))));
}

class _SettingsSwitchRow extends StatelessWidget {
  const _SettingsSwitchRow(
      {required this.title,
      required this.subtitle,
      required this.value,
      required this.onChanged});
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(children: [
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(subtitle,
              style: const TextStyle(
                  color: Color(0xFF858A94), fontSize: 11.5, height: 1.35))
        ])),
        Switch(
            value: value,
            activeThumbColor: theme.active,
            activeTrackColor: theme.activeStroke.withValues(alpha: .55),
            inactiveThumbColor: theme.faint,
            inactiveTrackColor: theme.panelHi,
            onChanged: onChanged),
      ]),
    );
  }
}
