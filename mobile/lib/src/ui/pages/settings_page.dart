import 'package:flutter/material.dart';

import '../../features/settings/settings.dart' as settings_feature;
import '../../shell/app_route.dart';
import '../../shell/app_snapshot.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.open,
    required this.data,
    required this.streamOutput,
    required this.expandThinking,
    required this.permissionMode,
    required this.onPermissionModeChanged,
    required this.onStreamOutputChanged,
    required this.onExpandThinkingChanged,
  });

  final ValueChanged<RoutePage> open;
  final AppSnapshot data;
  final bool streamOutput;
  final bool expandThinking;
  final String permissionMode;
  final ValueChanged<String> onPermissionModeChanged;
  final ValueChanged<bool> onStreamOutputChanged;
  final ValueChanged<bool> onExpandThinkingChanged;

  @override
  Widget build(BuildContext context) {
    return settings_feature.SettingsPage(
      open: open,
      data: data,
      streamOutput: streamOutput,
      expandThinking: expandThinking,
      permissionMode: permissionMode,
      onPermissionModeChanged: onPermissionModeChanged,
      onStreamOutputChanged: onStreamOutputChanged,
      onExpandThinkingChanged: onExpandThinkingChanged,
    );
  }
}
