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
    unawaited(_runPresenterOperation(_presenter.initialize));
  }

  final MobileAppEventBus _eventBus;
  final ApprovalNotificationPresenter _presenter;
  final Map<String, Map<String, MobileApprovalRequested>>
      _pendingByConversation = <String, Map<String, MobileApprovalRequested>>{};
  final Set<_ApprovalNotificationKey> _notifiedApprovalIds =
      <_ApprovalNotificationKey>{};
  final StreamController<ApprovalNotificationTap> _taps =
      StreamController<ApprovalNotificationTap>.broadcast();
  late final StreamSubscription<MobileAppEvent> _eventSubscription;
  late final StreamSubscription<ApprovalNotificationTap> _tapSubscription;
  AppLifecycleState _lifecycleState;
  bool _disposed = false;

  Stream<ApprovalNotificationTap> get taps => _taps.stream;

  void updateLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    if (state != AppLifecycleState.resumed) {
      unawaited(_showPendingNotifications());
    }
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
    if (_lifecycleState == AppLifecycleState.resumed) {
      return;
    }
    if (!_hasUnnotifiedApproval(event.conversationId)) {
      return;
    }
    await _showConversationNotification(event.conversationId);
  }

  Future<void> _handleApprovalResolved(MobileApprovalResolved event) async {
    final approvals = _pendingByConversation[event.conversationId];
    if (approvals == null) return;
    final approvalId = event.approvalId;
    if (approvalId == null || approvalId.isEmpty) {
      _notifiedApprovalIds.removeAll(approvals.keys.map(
        (approvalId) => _approvalNotificationKey(
          event.conversationId,
          approvalId,
        ),
      ));
      approvals.clear();
    } else {
      approvals.remove(approvalId);
      _notifiedApprovalIds.remove(
        _approvalNotificationKey(event.conversationId, approvalId),
      );
    }
    if (approvals.isEmpty) {
      _pendingByConversation.remove(event.conversationId);
      await _runPresenterOperation(
        () => _presenter.cancelApproval(
          id: approvalNotificationIdForConversation(event.conversationId),
          conversationId: event.conversationId,
        ),
      );
      return;
    }
    if (_lifecycleState != AppLifecycleState.resumed) {
      await _showConversationNotification(event.conversationId);
    }
  }

  Future<void> _showPendingNotifications() async {
    for (final conversationId in _pendingByConversation.keys.toList()) {
      if (!_hasUnnotifiedApproval(conversationId)) continue;
      await _showConversationNotification(conversationId);
    }
  }

  bool _hasUnnotifiedApproval(String conversationId) {
    final approvals = _pendingByConversation[conversationId];
    if (approvals == null || approvals.isEmpty) return false;
    return approvals.keys.any((approvalId) => !_notifiedApprovalIds.contains(
          _approvalNotificationKey(conversationId, approvalId),
        ));
  }

  Future<void> _showConversationNotification(String conversationId) async {
    final notification = _displayForConversation(conversationId);
    if (notification == null) return;
    final approvals = _pendingByConversation[conversationId];
    if (approvals != null) {
      _notifiedApprovalIds.addAll(approvals.keys.map(
        (approvalId) => _approvalNotificationKey(conversationId, approvalId),
      ));
    }
    await _runPresenterOperation(
      () => _presenter.showOrUpdateApproval(notification),
    );
  }

  Future<void> _runPresenterOperation(Future<void> Function() operation) async {
    if (_disposed) return;
    try {
      await operation();
    } catch (_) {
      // System notifications are best-effort; approval handling must keep
      // flowing even when the platform plugin rejects initialization/show/cancel.
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
        : '${latest.body}\n${_additionalApprovalsBody(latest, extraCount)}';
    return ApprovalNotificationDisplay(
      id: approvalNotificationIdForConversation(conversationId),
      title: latest.title,
      body: body,
      workspaceId: latest.workspaceId,
      conversationId: latest.conversationId,
      approvalId: latest.approvalId,
    );
  }

  String _additionalApprovalsBody(
    MobileApprovalRequested latest,
    int extraCount,
  ) {
    final localized = latest.additionalApprovalsBody?.call(extraCount).trim();
    if (localized != null && localized.isNotEmpty) return localized;
    return '+$extraCount more approvals waiting';
  }
}

class _ApprovalNotificationKey {
  const _ApprovalNotificationKey(this.conversationId, this.approvalId);

  final String conversationId;
  final String approvalId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _ApprovalNotificationKey &&
          other.conversationId == conversationId &&
          other.approvalId == approvalId;

  @override
  int get hashCode => Object.hash(conversationId, approvalId);
}

_ApprovalNotificationKey _approvalNotificationKey(
  String conversationId,
  String approvalId,
) =>
    _ApprovalNotificationKey(conversationId, approvalId);

int approvalNotificationIdForConversation(String conversationId) {
  var hash = 0x811c9dc5;
  for (final codeUnit in conversationId.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return 0x10000000 | (hash & 0x0fffffff);
}
