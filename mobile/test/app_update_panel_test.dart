import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/ui/features/settings/view_models/app_update_view_model.dart';
import 'package:lan_ai_cli_control/src/ui/features/settings/widgets/app_update_panel.dart';

void main() {
  testWidgets('panel shows available update and download action', (
    tester,
  ) async {
    const state = AppUpdateState(
      status: AppUpdateStatus.available,
      installedVersionName: '1.3.0',
      installedVersionCode: 1,
      mandatory: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppUpdatePanel(
            state: state,
            onCheck: () {},
            onDownload: () {},
            onInstall: () {},
            onOpenPermissionSettings: () {},
            onDiscard: () {},
          ),
        ),
      ),
    );

    expect(find.textContaining('Update'), findsWidgets);
    expect(find.textContaining('Download'), findsOneWidget);
  });

  testWidgets('panel shows install action for ready update', (tester) async {
    const state = AppUpdateState(
      status: AppUpdateStatus.readyToInstall,
      installedVersionName: '1.3.0',
      installedVersionCode: 1,
      mandatory: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppUpdatePanel(
            state: state,
            onCheck: () {},
            onDownload: () {},
            onInstall: () {},
            onOpenPermissionSettings: () {},
            onDiscard: () {},
          ),
        ),
      ),
    );

    expect(find.textContaining('Install'), findsOneWidget);
    expect(find.textContaining('Required'), findsNothing);
  });
}
