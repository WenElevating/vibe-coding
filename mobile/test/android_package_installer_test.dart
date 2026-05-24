import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/services/android_package_installer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('install event parser maps native statuses', () {
    expect(
      AndroidInstallEvent.fromJson(const <Object?, Object?>{
        'status': 'pendingUserAction',
        'sessionId': 12,
        'message': 'confirm',
      }).status,
      AndroidInstallStatus.pendingUserAction,
    );
    expect(
      AndroidInstallEvent.fromJson(const <Object?, Object?>{
        'status': 'committed',
      }).status,
      AndroidInstallStatus.committed,
    );
    expect(
      AndroidInstallEvent.fromJson(const <Object?, Object?>{
        'status': 'success',
      }).status,
      AndroidInstallStatus.success,
    );
    expect(
      AndroidInstallEvent.fromJson(const <Object?, Object?>{
        'status': 'cancelled',
      }).status,
      AndroidInstallStatus.cancelled,
    );
    expect(
      AndroidInstallEvent.fromJson(const <Object?, Object?>{
        'status': 'unexpected',
      }).status,
      AndroidInstallStatus.failed,
    );
  });

  test('installer wrapper calls native methods', () async {
    const methodChannel = MethodChannel('test/app_update_installer');
    const eventChannel = EventChannel('test/app_update_installer/events');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'canRequestPackageInstalls' => true,
        'openInstallPermissionSettings' => null,
        'installApk' => 42,
        'availableBytes' => 123456,
        'recoverInstallSession' => const <String, Object?>{
            'status': 'pendingUserAction',
            'sessionId': 42,
            'message': 'pending',
          },
        _ => throw PlatformException(code: 'not_implemented'),
      };
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(methodChannel, null);
    });

    final installer = AndroidPackageInstaller(
      methodChannel: methodChannel,
      eventChannel: eventChannel,
    );

    expect(await installer.canRequestPackageInstalls(), true);
    await installer.openInstallPermissionSettings();
    expect(await installer.installApk('/cache/app_updates/app.apk'), 42);
    expect(await installer.availableBytes(), 123456);
    final recovered = await installer.recoverInstallSession(42);

    expect(recovered?.status, AndroidInstallStatus.pendingUserAction);
    expect(calls.map((call) => call.method), <String>[
      'canRequestPackageInstalls',
      'openInstallPermissionSettings',
      'installApk',
      'availableBytes',
      'recoverInstallSession',
    ]);
    expect(calls[2].arguments, <String, Object?>{
      'filePath': '/cache/app_updates/app.apk',
    });
    expect(calls[4].arguments, <String, Object?>{'sessionId': 42});
  });

  test('installer wrapper reuses one native event stream', () {
    const methodChannel = MethodChannel('test/app_update_installer_cache');
    const eventChannel = EventChannel('test/app_update_installer_cache/events');
    final installer = AndroidPackageInstaller(
      methodChannel: methodChannel,
      eventChannel: eventChannel,
    );

    expect(identical(installer.events, installer.events), true);
  });
}
