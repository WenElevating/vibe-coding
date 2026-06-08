import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/services/approval_notification_handler.dart';
import 'package:lan_ai_cli_control/src/services/mobile_app_event_bus.dart';

void main() {
  test('foreground approval event does not show a system notification',
      () async {
    final bus = MobileAppEventBus();
    final presenter = _FakeApprovalNotificationPresenter();
    final handler = ApprovalNotificationHandler(
      eventBus: bus,
      presenter: presenter,
    );

    bus.publish(_approvalRequested());
    await _flushAsync();

    expect(presenter.shown, isEmpty);

    await handler.dispose();
    await bus.dispose();
  });

  test('background approval event shows one notification per approval id',
      () async {
    final bus = MobileAppEventBus();
    final presenter = _FakeApprovalNotificationPresenter();
    final handler = ApprovalNotificationHandler(
      eventBus: bus,
      presenter: presenter,
      initialLifecycleState: AppLifecycleState.paused,
    );

    bus
      ..publish(_approvalRequested())
      ..publish(_approvalRequested());
    await _flushAsync();

    expect(presenter.shown, hasLength(1));
    expect(presenter.shown.single.conversationId, 'conv_1');
    expect(presenter.shown.single.approvalId, 'ap_1');

    await handler.dispose();
    await bus.dispose();
  });

  test(
      'approval already seen in foreground is not replay-alerted in background',
      () async {
    final bus = MobileAppEventBus();
    final presenter = _FakeApprovalNotificationPresenter();
    final handler = ApprovalNotificationHandler(
      eventBus: bus,
      presenter: presenter,
    );

    bus.publish(_approvalRequested());
    await _flushAsync();
    handler.updateLifecycleState(AppLifecycleState.paused);
    bus.publish(_approvalRequested());
    await _flushAsync();

    expect(presenter.shown, isEmpty);

    await handler.dispose();
    await bus.dispose();
  });

  test('resolved approval cancels the conversation notification', () async {
    final bus = MobileAppEventBus();
    final presenter = _FakeApprovalNotificationPresenter();
    final handler = ApprovalNotificationHandler(
      eventBus: bus,
      presenter: presenter,
      initialLifecycleState: AppLifecycleState.paused,
    );

    bus
      ..publish(_approvalRequested())
      ..publish(const MobileApprovalResolved(
        conversationId: 'conv_1',
        approvalId: 'ap_1',
      ));
    await _flushAsync();

    expect(presenter.cancelledConversationIds, <String>['conv_1']);

    await handler.dispose();
    await bus.dispose();
  });

  test('notification taps are exposed by the handler', () async {
    final bus = MobileAppEventBus();
    final presenter = _FakeApprovalNotificationPresenter();
    final handler = ApprovalNotificationHandler(
      eventBus: bus,
      presenter: presenter,
    );
    final taps = <ApprovalNotificationTap>[];
    final sub = handler.taps.listen(taps.add);

    presenter.tap(const ApprovalNotificationTap(
      workspaceId: 'ws_1',
      conversationId: 'conv_1',
      approvalId: 'ap_1',
    ));
    await _flushAsync();

    expect(taps.single.conversationId, 'conv_1');

    await sub.cancel();
    await handler.dispose();
    await bus.dispose();
  });

  test('presenter failures are isolated from handler event flow', () async {
    final uncaughtErrors = <Object>[];
    final guarded = runZonedGuarded<Future<void>>(() async {
      final bus = MobileAppEventBus();
      final presenter = _FakeApprovalNotificationPresenter()
        ..initializeError = StateError('notification init failed')
        ..showError = StateError('notification show failed')
        ..cancelError = StateError('notification cancel failed');
      final handler = ApprovalNotificationHandler(
        eventBus: bus,
        presenter: presenter,
        initialLifecycleState: AppLifecycleState.paused,
      );

      bus
        ..publish(_approvalRequested())
        ..publish(const MobileApprovalResolved(
          conversationId: 'conv_1',
          approvalId: 'ap_1',
        ));
      await _flushAsync();

      expect(presenter.showAttempts, 1);
      expect(presenter.cancelAttempts, 1);

      await handler.dispose();
      await bus.dispose();
    }, (error, _) {
      uncaughtErrors.add(error);
    });

    await guarded;
    expect(uncaughtErrors, isEmpty);
  });
}

MobileApprovalRequested _approvalRequested({
  String approvalId = 'ap_1',
  DateTime? createdAt,
}) =>
    MobileApprovalRequested(
      workspaceId: 'ws_1',
      conversationId: 'conv_1',
      approvalId: approvalId,
      title: 'Approval required',
      body: 'Bash: git status',
      createdAt: createdAt ?? DateTime.utc(2026, 5, 31, 12),
    );

Future<void> _flushAsync() => Future<void>.delayed(Duration.zero);

class _FakeApprovalNotificationPresenter
    implements ApprovalNotificationPresenter {
  final shown = <ApprovalNotificationDisplay>[];
  final cancelledConversationIds = <String>[];
  final _taps = StreamController<ApprovalNotificationTap>.broadcast();
  Object? initializeError;
  Object? showError;
  Object? cancelError;
  var showAttempts = 0;
  var cancelAttempts = 0;

  @override
  Stream<ApprovalNotificationTap> get taps => _taps.stream;

  @override
  Future<void> initialize() async {
    final error = initializeError;
    if (error != null) throw error;
  }

  @override
  Future<void> showOrUpdateApproval(
      ApprovalNotificationDisplay notification) async {
    showAttempts += 1;
    final error = showError;
    if (error != null) throw error;
    shown.add(notification);
  }

  @override
  Future<void> cancelApproval({
    required int id,
    required String conversationId,
  }) async {
    cancelAttempts += 1;
    final error = cancelError;
    if (error != null) throw error;
    cancelledConversationIds.add(conversationId);
  }

  void tap(ApprovalNotificationTap tap) => _taps.add(tap);

  @override
  Future<void> dispose() => _taps.close();
}
