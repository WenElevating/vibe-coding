import 'dart:async';

import 'package:flutter/widgets.dart';

import 'mobile_app_event_bus.dart';

class ApprovalNotificationTap {
  const ApprovalNotificationTap({
    required this.workspaceId,
    required this.conversationId,
    this.approvalId,
  });

  final String workspaceId;
  final String conversationId;
  final String? approvalId;
}

class ApprovalNotificationDisplay {
  const ApprovalNotificationDisplay({
    required this.id,
    required this.title,
    required this.body,
    required this.workspaceId,
    required this.conversationId,
    required this.approvalId,
  });

  final int id;
  final String title;
  final String body;
  final String workspaceId;
  final String conversationId;
  final String approvalId;
}

abstract class ApprovalNotificationPresenter {
  Stream<ApprovalNotificationTap> get taps;

  Future<void> initialize();

  Future<void> showOrUpdateApproval(ApprovalNotificationDisplay notification);

  Future<void> cancelApproval({
    required int id,
    required String conversationId,
  });

  Future<void> dispose();
}

class NoopApprovalNotificationPresenter
    implements ApprovalNotificationPresenter {
  const NoopApprovalNotificationPresenter();

  @override
  Stream<ApprovalNotificationTap> get taps =>
      const Stream<ApprovalNotificationTap>.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> showOrUpdateApproval(
      ApprovalNotificationDisplay notification) async {}

  @override
  Future<void> cancelApproval({
    required int id,
    required String conversationId,
  }) async {}

  @override
  Future<void> dispose() async {}
}

class ApprovalNotificationHandler {
  ApprovalNotificationHandler({
    required MobileAppEventBus eventBus,
    required ApprovalNotificationPresenter presenter,
    AppLifecycleState initialLifecycleState = AppLifecycleState.resumed,
  })  : _eventBus = eventBus,
        _presenter = presenter,
        _lifecycleState = initialLifecycleState {
    _eventSubscription = _eventBus.events.listen(_handleEvent);
    _tapSubscription = _presenter.taps.listen(_taps.add);
    unawaited(_presenter.initialize());
  }

  final MobileAppEventBus _eventBus;
  final ApprovalNotificationPresenter _presenter;
  final Map<String, Map<String, MobileApprovalRequested>>
      _pendingByConversation = <String, Map<String, MobileApprovalRequested>>{};
  final Set<String> _seenApprovalIds = <String>{};
  final StreamController<ApprovalNotificationTap> _taps =
      StreamController<ApprovalNotificationTap>.broadcast();
  late final StreamSubscription<MobileAppEvent> _eventSubscription;
  late final StreamSubscription<ApprovalNotificationTap> _tapSubscription;
  AppLifecycleState _lifecycleState;
  bool _disposed = false;

  Stream<ApprovalNotificationTap> get taps => _taps.stream;

  void updateLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _eventSubscription.cancel();
    await _tapSubscription.cancel();
    await _taps.close();
    await _presenter.dispose();
  }

  void _handleEvent(MobileAppEvent event) {
    if (_disposed) return;
    switch (event) {
      case MobileApprovalRequested():
        unawaited(_handleApprovalRequested(event));
      case MobileApprovalResolved():
        unawaited(_handleApprovalResolved(event));
      default:
        break;
    }
  }

  Future<void> _handleApprovalRequested(MobileApprovalRequested event) async {
    if (event.approvalId.isEmpty || event.conversationId.isEmpty) return;
    final approvals = _pendingByConversation.putIfAbsent(
      event.conversationId,
      () => <String, MobileApprovalRequested>{},
    );
    approvals[event.approvalId] = event;
    final firstSeen = _seenApprovalIds.add(event.approvalId);
    if (_lifecycleState == AppLifecycleState.resumed) {
      return;
    }
    if (!firstSeen) {
      return;
    }
    final notification = _displayForConversation(event.conversationId);
    if (notification == null) return;
    await _presenter.showOrUpdateApproval(notification);
  }

  Future<void> _handleApprovalResolved(MobileApprovalResolved event) async {
    final approvals = _pendingByConversation[event.conversationId];
    if (approvals == null) return;
    final approvalId = event.approvalId;
    if (approvalId == null || approvalId.isEmpty) {
      approvals.clear();
    } else {
      approvals.remove(approvalId);
    }
    if (approvals.isEmpty) {
      _pendingByConversation.remove(event.conversationId);
      await _presenter.cancelApproval(
        id: approvalNotificationIdForConversation(event.conversationId),
        conversationId: event.conversationId,
      );
      return;
    }
    if (_lifecycleState != AppLifecycleState.resumed) {
      final notification = _displayForConversation(event.conversationId);
      if (notification != null) {
        await _presenter.showOrUpdateApproval(notification);
      }
    }
  }

  ApprovalNotificationDisplay? _displayForConversation(String conversationId) {
    final approvals = _pendingByConversation[conversationId];
    if (approvals == null || approvals.isEmpty) return null;
    final latest = approvals.values.reduce((left, right) =>
        left.createdAt.isAfter(right.createdAt) ? left : right);
    final extraCount = approvals.length - 1;
    final body = extraCount <= 0
        ? latest.body
        : '${latest.body}\n+$extraCount more approvals waiting';
    return ApprovalNotificationDisplay(
      id: approvalNotificationIdForConversation(conversationId),
      title: latest.title,
      body: body,
      workspaceId: latest.workspaceId,
      conversationId: latest.conversationId,
      approvalId: latest.approvalId,
    );
  }
}

int approvalNotificationIdForConversation(String conversationId) {
  var hash = 0x811c9dc5;
  for (final codeUnit in conversationId.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return 0x10000000 | (hash & 0x0fffffff);
}
