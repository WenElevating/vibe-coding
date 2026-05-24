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

    expect(find.widgetWithText(TextButton, 'Install'), findsOneWidget);
    expect(find.textContaining('Required'), findsOneWidget);
  });

  testWidgets(
      'panel offers discard but no install while waiting for confirmation', (
    tester,
  ) async {
    const state = AppUpdateState(
      status: AppUpdateStatus.awaitingUserConfirmation,
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

    expect(find.textContaining('Confirm'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Install'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Discard'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Check'), findsNothing);
  });

  testWidgets('panel keeps retry actions after install cancellation', (
    tester,
  ) async {
    const state = AppUpdateState(
      status: AppUpdateStatus.installCancelled,
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

    expect(find.textContaining('Required'), findsOneWidget);
    expect(find.textContaining('Install cancelled'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Install'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Discard'), findsOneWidget);
  });

  testWidgets('panel can retry install after permission settings', (
    tester,
  ) async {
    const state = AppUpdateState(
      status: AppUpdateStatus.installPermissionNeeded,
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

    expect(find.widgetWithText(TextButton, 'Open settings'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Install'), findsOneWidget);
  });

  testWidgets('panel can restart after discarded update state', (
    tester,
  ) async {
    const state = AppUpdateState(
      status: AppUpdateStatus.cancelled,
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

    expect(find.textContaining('discarded'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Download'), findsOneWidget);
  });
}
