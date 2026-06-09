import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/services/approval_notification_handler.dart';
import 'package:lan_ai_cli_control/src/services/local_approval_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dexterous.com/flutter/local_notifications');

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('show retries plugin initialization after a transient failure',
      () async {
    var failInitialize = true;
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'initialize':
          if (failInitialize) {
            throw PlatformException(code: 'init_failed');
          }
          return true;
        case 'getNotificationAppLaunchDetails':
          return <String, Object?>{'notificationLaunchedApp': false};
        case 'requestNotificationsPermission':
          return true;
        case 'show':
          return null;
      }
      return null;
    });
    final presenter = SystemApprovalNotificationPresenter(
      isAndroid: () => true,
    );

    await expectLater(
      presenter.showOrUpdateApproval(_approvalNotification()),
      throwsA(isA<PlatformException>()),
    );
    failInitialize = false;

    await presenter.showOrUpdateApproval(_approvalNotification());

    expect(
      calls.where((method) => method == 'initialize'),
      hasLength(2),
    );
    expect(calls, contains('show'));

    await presenter.dispose();
  });

  test('show reports false when notification permission is denied', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'initialize':
          return true;
        case 'getNotificationAppLaunchDetails':
          return <String, Object?>{'notificationLaunchedApp': false};
        case 'requestNotificationsPermission':
          return false;
        case 'show':
          fail('show should not be called when permission is denied');
      }
      return null;
    });
    final presenter = SystemApprovalNotificationPresenter(
      isAndroid: () => true,
    );

    final shown = await presenter.showOrUpdateApproval(_approvalNotification());

    expect(shown, isFalse);
    expect(calls, isNot(contains('show')));

    await presenter.dispose();
  });
}

ApprovalNotificationDisplay _approvalNotification() =>
    const ApprovalNotificationDisplay(
      id: 1,
      title: 'Approval required',
      body: 'Bash: git status',
      workspaceId: 'ws_1',
      conversationId: 'conv_1',
      approvalId: 'ap_1',
    );
