import 'package:flutter/material.dart';

import '../../shell/app_route.dart';
import '../features/settings/settings.dart' as settings_feature;

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.open,
    required this.viewModel,
    required this.streamOutput,
    required this.expandThinking,
    this.appUpdateViewModel,
    required this.onStreamOutputChanged,
    required this.onExpandThinkingChanged,
  });

  final ValueChanged<RoutePage> open;
  final settings_feature.SettingsViewModel viewModel;
  final bool streamOutput;
  final bool expandThinking;
  final settings_feature.AppUpdateViewModel? appUpdateViewModel;
  final ValueChanged<bool> onStreamOutputChanged;
  final ValueChanged<bool> onExpandThinkingChanged;

  @override
  Widget build(BuildContext context) {
    return settings_feature.SettingsPage(
      open: open,
      viewModel: viewModel,
      streamOutput: streamOutput,
      expandThinking: expandThinking,
      appUpdateViewModel: appUpdateViewModel,
      onStreamOutputChanged: onStreamOutputChanged,
      onExpandThinkingChanged: onExpandThinkingChanged,
    );
  }
}
