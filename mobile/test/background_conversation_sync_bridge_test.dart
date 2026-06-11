import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/services/background_conversation_sync_bridge.dart';
import 'package:lan_ai_cli_control/src/services/method_channel_background_conversation_sync_bridge.dart';
import 'package:lan_ai_cli_control/src/services/noop_background_conversation_sync_bridge.dart';

void main() {
  test('snapshot parses native status payload', () {
    final snapshot =
        BackgroundConversationSyncSnapshot.fromJson(const <String, Object?>{
      'status': 'active',
      'runningCount': 2,
      'waitingApprovalCount': 1,
      'message': '2 tasks running',
    });

    expect(snapshot.status, BackgroundConversationSyncStatus.active);
    expect(snapshot.runningCount, 2);
    expect(snapshot.waitingApprovalCount, 1);
    expect(snapshot.message, '2 tasks running');
  });

  test('request serializes tracked conversation counts', () {
    const request = BackgroundConversationSyncRequest(
      runningCount: 3,
      waitingApprovalCount: 1,
      notificationTitle: 'Vibe Coding',
      notificationBody: '3 tasks running, 1 waiting for approval',
    );

    expect(request.toJson(), const <String, Object?>{
      'runningCount': 3,
      'waitingApprovalCount': 1,
      'notificationTitle': 'Vibe Coding',
      'notificationBody': '3 tasks running, 1 waiting for approval',
    });
  });

  test('unsupported bridge reports failed start without throwing', () async {
    final bridge = UnsupportedBackgroundConversationSyncBridge();

    expect(await bridge.isSupported, false);
    expect(
      bridge.events,
      emitsInOrder(<Matcher>[
        isA<BackgroundConversationSyncSnapshot>().having(
          (snapshot) => snapshot.status,
          'status',
          BackgroundConversationSyncStatus.failed,
        ),
      ]),
    );

    final result = await bridge.start(
      const BackgroundConversationSyncRequest(
        runningCount: 1,
        waitingApprovalCount: 0,
        notificationTitle: 'Vibe Coding',
        notificationBody: '1 task running',
      ),
    );

    expect(result.status, BackgroundConversationSyncStatus.failed);
  });

  test(
    'method channel bridge starts native anchor and parses result',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final calls = <MethodCall>[];
      const methodChannel = MethodChannel(
        'lan_ai_cli_control/background_conversation_sync',
      );
      const eventChannel = EventChannel(
        'lan_ai_cli_control/background_conversation_sync/events',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
        calls.add(call);
        if (call.method == 'isSupported') return true;
        if (call.method == 'start') {
          return <String, Object?>{
            'status': 'active',
            'runningCount': 2,
            'waitingApprovalCount': 1,
            'message': '2 tasks running',
          };
        }
        return null;
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler(eventChannel.name, (_) async => null);

      final bridge = MethodChannelBackgroundConversationSyncBridge(
        methodChannel: methodChannel,
        eventChannel: eventChannel,
      );
      final supported = await bridge.isSupported;
      final result = await bridge.start(
        const BackgroundConversationSyncRequest(
          runningCount: 2,
          waitingApprovalCount: 1,
          notificationTitle: 'Vibe Coding',
          notificationBody: '2 tasks running',
        ),
      );

      expect(supported, true);
      expect(result.status, BackgroundConversationSyncStatus.active);
      expect(calls.map((call) => call.method), <String>[
        'isSupported',
        'start',
      ]);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler(eventChannel.name, null);
    },
  );

  test(
    'method channel bridge parses stopped acknowledgement for iOS cleanup mode',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const methodChannel = MethodChannel(
        'lan_ai_cli_control/background_conversation_sync',
      );
      const eventChannel = EventChannel(
        'lan_ai_cli_control/background_conversation_sync/events',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
        if (call.method == 'start') {
          return <String, Object?>{
            'status': 'stopped',
            'runningCount': 1,
            'waitingApprovalCount': 0,
            'message':
                'iOS uses resume backfill instead of continuous background sync',
          };
        }
        return true;
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler(eventChannel.name, (_) async => null);

      final bridge = MethodChannelBackgroundConversationSyncBridge(
        methodChannel: methodChannel,
        eventChannel: eventChannel,
      );
      final result = await bridge.start(
        const BackgroundConversationSyncRequest(
          runningCount: 1,
          waitingApprovalCount: 0,
          notificationTitle: 'Vibe Coding',
          notificationBody: '1 task running',
        ),
      );

      expect(result.status, BackgroundConversationSyncStatus.stopped);
      expect(
        result.message,
        'iOS uses resume backfill instead of continuous background sync',
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler(eventChannel.name, null);
    },
  );

  test(
    'method channel bridge keeps stream alive after malformed native event',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final controller = StreamController<Object?>.broadcast();
      addTearDown(controller.close);
      final bridge = MethodChannelBackgroundConversationSyncBridge(
        eventStream: controller.stream,
      );

      final expectation = expectLater(
        bridge.events,
        emitsThrough(
          isA<BackgroundConversationSyncSnapshot>().having(
            (snapshot) => snapshot.status,
            'status',
            BackgroundConversationSyncStatus.active,
          ),
        ),
      );

      await Future<void>.delayed(Duration.zero);
      controller.add(const <String, Object?>{'unexpected': 'shape'});
      controller.add('not a native event map');
      controller.add(const <String, Object?>{
        'status': 'active',
        'runningCount': 1,
        'waitingApprovalCount': 0,
        'message': '1 task running',
      });

      await expectation;
    },
  );
}
