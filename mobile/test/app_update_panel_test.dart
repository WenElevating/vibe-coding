import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/app/app_localization.dart';
import 'package:lan_ai_cli_control/src/data/models/app_update_models.dart';
import 'package:lan_ai_cli_control/src/ui/features/settings/view_models/app_update_view_model.dart';
import 'package:lan_ai_cli_control/src/ui/features/settings/widgets/app_update_panel.dart';

void main() {
  const availableManifest = AppUpdateManifest(
    schemaVersion: 1,
    platform: 'android',
    available: true,
    versionName: '1.4.0',
    versionCode: 2,
  );

  Future<void> pumpPanel(
    WidgetTester tester, {
    required AppUpdateState state,
    Locale locale = const Locale('en'),
    VoidCallback? onDownload,
    VoidCallback? onInstall,
    VoidCallback? onPostpone,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
          body: AppUpdatePanel(
            state: state,
            onCheck: () {},
            onDownload: onDownload ?? () {},
            onInstall: onInstall ?? () {},
            onDiscard: () {},
            onPostpone: onPostpone ?? () {},
          ),
        ),
      ),
    );
  }

  testWidgets('panel shows available update and download action', (
    tester,
  ) async {
    const state = AppUpdateState(
      status: AppUpdateStatus.available,
      installedVersionName: '1.3.0',
      installedVersionCode: 1,
      mandatory: false,
      manifest: availableManifest,
    );

    await pumpPanel(
      tester,
      state: state,
    );

    expect(find.textContaining('Update'), findsWidgets);
    expect(find.widgetWithText(TextButton, 'Download'), findsOneWidget);

    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Later'));
    await tester.pumpAndSettle();
  });

  testWidgets('panel shows install action for ready update', (tester) async {
    const state = AppUpdateState(
      status: AppUpdateStatus.readyToInstall,
      installedVersionName: '1.3.0',
      installedVersionCode: 1,
      mandatory: true,
      manifest: availableManifest,
    );

    await pumpPanel(
      tester,
      state: state,
    );

    expect(find.widgetWithText(TextButton, 'Install'), findsOneWidget);
    expect(find.textContaining('Required'), findsOneWidget);
  });

  testWidgets('panel blocks actions while waiting for confirmation', (
    tester,
  ) async {
    const state = AppUpdateState(
      status: AppUpdateStatus.awaitingUserConfirmation,
      installedVersionName: '1.3.0',
      installedVersionCode: 1,
      mandatory: true,
      manifest: availableManifest,
    );

    await pumpPanel(
      tester,
      state: state,
    );
    await tester.pump();

    expect(find.textContaining('Confirm'), findsWidgets);
    expect(find.widgetWithText(TextButton, 'Install'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Clear update'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Check for updates'), findsNothing);
    expect(
      find.byKey(const ValueKey('app-update-progress-dialog')),
      findsOneWidget,
    );
  });

  testWidgets('panel keeps retry actions after install cancellation', (
    tester,
  ) async {
    const state = AppUpdateState(
      status: AppUpdateStatus.installCancelled,
      installedVersionName: '1.3.0',
      installedVersionCode: 1,
      mandatory: true,
      manifest: availableManifest,
    );

    await pumpPanel(
      tester,
      state: state,
    );

    expect(find.textContaining('Required'), findsOneWidget);
    expect(find.textContaining('Install cancelled'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Install'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Clear update'), findsOneWidget);
  });

  testWidgets('panel can retry install after automatic permission settings', (
    tester,
  ) async {
    const state = AppUpdateState(
      status: AppUpdateStatus.installPermissionNeeded,
      installedVersionName: '1.3.0',
      installedVersionCode: 1,
      mandatory: true,
      manifest: availableManifest,
    );

    await pumpPanel(
      tester,
      state: state,
    );

    expect(find.widgetWithText(TextButton, 'Open settings'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Install'), findsOneWidget);
  });

  testWidgets('active update state shows blocking progress dialog', (
    tester,
  ) async {
    var underlyingTaps = 0;
    const state = AppUpdateState(
      status: AppUpdateStatus.downloading,
      installedVersionName: '1.3.0',
      installedVersionCode: 1,
      mandatory: true,
      manifest: availableManifest,
    );

    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: 0,
                bottom: 0,
                child: TextButton(
                  onPressed: () => underlyingTaps++,
                  child: const Text('Underlying action'),
                ),
              ),
              Align(
                alignment: Alignment.topLeft,
                child: AppUpdatePanel(
                  state: state,
                  onCheck: () {},
                  onDownload: () {},
                  onInstall: () {},
                  onDiscard: () {},
                  onPostpone: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('app-update-progress-dialog')),
      findsOneWidget,
    );
    expect(find.text('Downloading update'), findsWidgets);
    expect(find.byType(ModalBarrier), findsWidgets);

    await tester.tap(
      find.widgetWithText(TextButton, 'Underlying action'),
      warnIfMissed: false,
    );
    expect(underlyingTaps, 0);
  });

  testWidgets('panel can restart after cleared update state', (
    tester,
  ) async {
    const state = AppUpdateState(
      status: AppUpdateStatus.cancelled,
      installedVersionName: '1.3.0',
      installedVersionCode: 1,
      mandatory: false,
      manifest: availableManifest,
    );

    await pumpPanel(
      tester,
      state: state,
    );

    expect(find.textContaining('cleared'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Download'), findsOneWidget);
  });

  testWidgets('panel localizes update controls', (tester) async {
    const state = AppUpdateState(
      status: AppUpdateStatus.idle,
      installedVersionName: '1.3.0',
      installedVersionCode: 1,
    );

    await pumpPanel(
      tester,
      locale: const Locale('zh'),
      state: state,
    );

    expect(find.text('应用更新'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '检查更新'), findsOneWidget);
    expect(find.textContaining('Installed'), findsNothing);
  });

  testWidgets('failed check without update manifest only offers check', (
    tester,
  ) async {
    const state = AppUpdateState(
      status: AppUpdateStatus.failed,
      installedVersionName: '1.3.0',
      installedVersionCode: 1,
      errorMessage: 'HttpException(404)',
    );

    await pumpPanel(tester, state: state);

    expect(
        find.widgetWithText(TextButton, 'Check for updates'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Download'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Clear update'), findsNothing);
  });

  testWidgets('checking state keeps following content stationary', (
    tester,
  ) async {
    Future<double> pumpAndMeasureAboutTop(AppUpdateStatus status) async {
      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: appSupportedLocales,
          localizationsDelegates: appLocalizationsDelegates,
          home: Scaffold(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppUpdatePanel(
                  state: AppUpdateState(
                    status: status,
                    installedVersionName: '1.3.0',
                    installedVersionCode: 1,
                  ),
                  onCheck: () {},
                  onDownload: () {},
                  onInstall: () {},
                  onDiscard: () {},
                  onPostpone: () {},
                ),
                const Text('About marker'),
              ],
            ),
          ),
        ),
      );
      return tester.getTopLeft(find.text('About marker')).dy;
    }

    final idleTop = await pumpAndMeasureAboutTop(AppUpdateStatus.idle);
    final checkingTop = await pumpAndMeasureAboutTop(AppUpdateStatus.checking);

    expect(checkingTop, idleTop);
    expect(
      tester
          .widget<TextButton>(
              find.widgetWithText(TextButton, 'Check for updates'))
          .enabled,
      isFalse,
    );
  });

  testWidgets('available update prompts before downloading', (tester) async {
    var downloads = 0;
    const state = AppUpdateState(
      status: AppUpdateStatus.available,
      installedVersionName: '1.3.0',
      installedVersionCode: 1,
      manifest: availableManifest,
    );

    await pumpPanel(
      tester,
      state: state,
      onDownload: () => downloads++,
    );
    await tester.pump();

    expect(find.text('Update available'), findsWidgets);
    expect(find.widgetWithText(TextButton, 'Download update'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Download update'));
    await tester.pumpAndSettle();

    expect(downloads, 1);
  });

  testWidgets('available update can suppress automatic prompt', (
    tester,
  ) async {
    var downloads = 0;
    const state = AppUpdateState(
      status: AppUpdateStatus.available,
      installedVersionName: '1.3.0',
      installedVersionCode: 1,
      manifest: availableManifest,
      promptSuppressed: true,
    );

    await pumpPanel(
      tester,
      state: state,
      onDownload: () => downloads++,
    );
    await tester.pump();

    expect(find.widgetWithText(TextButton, 'Download update'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Download'), findsOneWidget);
    expect(downloads, 0);
  });

  testWidgets('later action records postponed update', (tester) async {
    var postponed = 0;
    const state = AppUpdateState(
      status: AppUpdateStatus.available,
      installedVersionName: '1.3.0',
      installedVersionCode: 1,
      manifest: availableManifest,
    );

    await pumpPanel(
      tester,
      state: state,
      onPostpone: () => postponed++,
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(TextButton, 'Later'));
    await tester.pumpAndSettle();

    expect(postponed, 1);
  });

  testWidgets('mandatory available prompt cannot be dismissed later', (
    tester,
  ) async {
    var downloads = 0;
    var postponed = 0;
    const state = AppUpdateState(
      status: AppUpdateStatus.available,
      installedVersionName: '1.3.0',
      installedVersionCode: 1,
      mandatory: true,
      manifest: availableManifest,
    );

    await pumpPanel(
      tester,
      state: state,
      onDownload: () => downloads++,
      onPostpone: () => postponed++,
    );
    await tester.pump();

    expect(find.widgetWithText(TextButton, 'Later'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Download update'), findsOneWidget);

    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextButton, 'Download update'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextButton, 'Download update'), findsOneWidget);
    expect(postponed, 0);

    await tester.tap(find.widgetWithText(TextButton, 'Download update'));
    await tester.pumpAndSettle();

    expect(downloads, 1);
  });
}
