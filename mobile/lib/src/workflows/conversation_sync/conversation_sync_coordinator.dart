import 'dart:async';
import 'dart:collection';

import '../../data/repositories/cached_conversation_repository.dart';
import '../../models/protocol.dart';
import '../../services/background_conversation_sync_bridge.dart';
import '../../services/mobile_app_event_bus.dart';
import 'conversation_sync_policy.dart';

abstract class ConversationSyncLease {
  String get conversationId;
  Stream<ConversationEvent> get events;
  Future<void> dispose();
}

class ConversationSyncConsumerLagged implements Exception {
  const ConversationSyncConsumerLagged({
    required this.conversationId,
    required this.lastDeliveredSeq,
    required this.droppedAfterSeq,
  });

  final String conversationId;
  final int lastDeliveredSeq;
  final int droppedAfterSeq;

  @override
  String toString() => 'ConversationSyncConsumerLagged($conversationId, '
      'lastDeliveredSeq: $lastDeliveredSeq, '
      'droppedAfterSeq: $droppedAfterSeq)';
}

class ConversationSyncCoordinator {
  ConversationSyncCoordinator({
    required CachedConversationRepository conversationRepository,
    MobileAppEventBus? eventBus,
    BackgroundConversationSyncBridge? backgroundSyncBridge,
    ConversationSyncPolicy policy = const ConversationSyncPolicy(),
  })  : _conversationRepository = conversationRepository,
        _eventBus = eventBus,
        _backgroundSyncBridge = backgroundSyncBridge,
        _policy = policy;

  final CachedConversationRepository _conversationRepository;
  MobileAppEventBus? _eventBus;
  final BackgroundConversationSyncBridge? _backgroundSyncBridge;
  final ConversationSyncPolicy _policy;
  String _approvalTitle = 'Approval required';
  String _approvalFallbackBody = 'Approval requested';
  String _backgroundNotificationTitle = 'Vibe Coding';
  MobileApprovalExtraBodyBuilder? _additionalApprovalsBody;

  final Map<String, _TrackedConversation> _tracked =
      <String, _TrackedConversation>{};
  Timer? _backgroundDisconnectTimer;
  StreamSubscription<BackgroundConversationSyncSnapshot>?
      _backgroundSyncSubscription;
  bool _appForeground = true;
  bool _keepAliveInBackground = false;
  bool _backgroundAnchorActive = false;
  bool _disposed = false;

  void updateEventBus(MobileAppEventBus? eventBus) {
    _eventBus = eventBus;
  }

  void updateApprovalText({
    required String title,
    required String fallbackBody,
    MobileApprovalExtraBodyBuilder? additionalApprovalsBody,
  }) {
    _approvalTitle = title;
    _approvalFallbackBody = fallbackBody;
    _additionalApprovalsBody = additionalApprovalsBody;
  }

  void updateBackgroundNotificationText({required String title}) {
    _backgroundNotificationTitle = title;
  }

  void trackConversation({
    required String conversationId,
    required String runId,
    required int afterSeq,
    required String status,
  }) {
    if (_disposed) return;
    final target = _tracked.putIfAbsent(
      conversationId,
      () => _TrackedConversation(
        conversationId: conversationId,
        runId: runId,
        lastSeq: afterSeq,
        status: status,
      ),
    );
    target
      ..runId = runId
      ..lastSeq = afterSeq > target.lastSeq ? afterSeq : target.lastSeq
      ..status = status;
    _cancelTerminalTimer(target);
    if (_isTrackedStatus(status)) {
      _ensureWatcher(target);
      return;
    }
    _scheduleTerminalStop(target);
  }

  ConversationSyncLease attachForegroundConsumer({
    required String conversationId,
    required String runId,
    required int afterSeq,
  }) {
    if (_disposed) {
      return _DisposedConversationSyncLease(conversationId);
    }
    trackConversation(
      conversationId: conversationId,
      runId: runId,
      afterSeq: afterSeq,
      status: _currentConversationStatus(conversationId) ?? 'running',
    );
    final target = _tracked[conversationId]!;
    late final _ConversationSyncLease lease;
    lease = _ConversationSyncLease(
      conversationId: conversationId,
      queueLimit: _policy.consumerLagQueueLimit,
      onDispose: () async {
        if (!target.leases.remove(lease)) return;
        _maybeStopConversation(target);
      },
    );
    target.leases.add(lease);
    _ensureWatcher(target);
    return lease;
  }

  void setAppForeground(
    bool isForeground, {
    required bool keepAliveInBackground,
  }) {
    if (_disposed) return;
    _appForeground = isForeground;
    _keepAliveInBackground = keepAliveInBackground;
    _backgroundDisconnectTimer?.cancel();
    _backgroundDisconnectTimer = null;
    if (_appForeground) {
      _stopBackgroundAnchor();
      for (final target in _tracked.values) {
        _ensureWatcher(target);
      }
      return;
    }
    if (_keepAliveInBackground) {
      _startBackgroundAnchorIfNeeded();
      for (final target in _tracked.values) {
        _ensureWatcher(target);
      }
      return;
    }
    _backgroundDisconnectTimer = Timer(_policy.backgroundDisconnectGrace, () {
      _backgroundDisconnectTimer = null;
      if (_disposed || _appForeground || _keepAliveInBackground) return;
      _stopBackgroundAnchor();
      for (final target in _tracked.values) {
        unawaited(_stopWatcher(target));
      }
    });
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _backgroundDisconnectTimer?.cancel();
    _backgroundDisconnectTimer = null;
    await _backgroundSyncSubscription?.cancel();
    _backgroundSyncSubscription = null;
    await _backgroundSyncBridge?.stop();
    final tracked = _tracked.values.toList(growable: false);
    _tracked.clear();
    await Future.wait<void>(
      tracked.map((target) async {
        _cancelTerminalTimer(target);
        for (final lease in target.leases.toList(growable: false)) {
          await lease.dispose();
        }
        await _stopWatcher(target);
      }),
    );
  }

  void _ensureWatcher(_TrackedConversation target) {
    if (_disposed || target.subscription != null) return;
    if (!_appForeground && !_keepAliveInBackground) return;
    target.stopping = false;
    target.subscription = _conversationRepository
        .watchConversationEvents(
      target.conversationId,
      afterSeq: target.lastSeq,
    )
        .listen(
      (event) => _handleEvent(target, event),
      onError: (_, __) {
        if (_disposed) return;
        final subscription = target.subscription;
        target.subscription = null;
        unawaited(_cancelThenRestart(target, subscription));
      },
      onDone: () {
        target.subscription = null;
        _scheduleWatcherRestart(target);
      },
      cancelOnError: false,
    );
  }

  Future<void> _cancelThenRestart(
    _TrackedConversation target,
    StreamSubscription<ConversationEvent>? subscription,
  ) async {
    try {
      await subscription?.cancel();
    } finally {
      _scheduleWatcherRestart(target);
    }
  }

  void _scheduleWatcherRestart(_TrackedConversation target) {
    scheduleMicrotask(() {
      if (_disposed ||
          target.stopping ||
          target.subscription != null ||
          !_shouldKeepWatcher(target)) {
        return;
      }
      _ensureWatcher(target);
    });
  }

  Future<void> _stopWatcher(_TrackedConversation target) async {
    final subscription = target.subscription;
    target.stopping = true;
    target.subscription = null;
    try {
      await subscription?.cancel();
    } catch (_) {
      // Cleanup is best-effort for lifecycle transitions.
    }
  }

  void _handleEvent(_TrackedConversation target, ConversationEvent event) {
    if (_disposed || event.conversationId != target.conversationId) return;
    if (event.seq > target.lastSeq) {
      target.lastSeq = event.seq;
    }
    final nextStatus = _nextStatusForEvent(event, target.status);
    if (nextStatus != null) {
      target.status = nextStatus;
      if (_isTrackedStatus(nextStatus)) {
        _cancelTerminalTimer(target);
      } else {
        _scheduleTerminalStop(target);
      }
      _refreshBackgroundAnchor();
    }
    _publishApprovalEvent(event);
    for (final lease in target.leases.toList(growable: false)) {
      lease.add(event);
    }
  }

  void _publishApprovalEvent(ConversationEvent event) {
    final eventBus = _eventBus;
    if (eventBus == null) return;
    final conversation = _currentConversation(event.conversationId);
    final workspaceId = conversation?.workspaceId ?? '';
    final conversationId = event.conversationId;
    if (conversationId.isEmpty) return;
    switch (event.type) {
      case 'approval.requested':
        final approvalId = event.approvalId;
        if (approvalId == null || approvalId.isEmpty || workspaceId.isEmpty) {
          return;
        }
        final body = _approvalBodyForEvent(event);
        eventBus.publish(
          MobileApprovalRequested(
            workspaceId: workspaceId,
            conversationId: conversationId,
            approvalId: approvalId,
            title: _approvalTitle,
            body: body,
            createdAt: event.createdAt,
            additionalApprovalsBody: _additionalApprovalsBody,
            conversationTitle: conversation?.title,
            toolName: event.toolName,
            summary: event.summary,
          ),
        );
        break;
      case 'approval.resolved':
      case 'blocking.request_cancelled':
      case 'conversation.completed':
      case 'conversation.cancelled':
      case 'run.error':
        eventBus.publish(
          MobileApprovalResolved(
            conversationId: conversationId,
            approvalId: event.approvalId,
          ),
        );
        break;
    }
  }

  String _approvalBodyForEvent(ConversationEvent event) {
    final summary = event.summary?.trim();
    if (summary != null && summary.isNotEmpty) return summary;
    final toolName = event.toolName?.trim();
    if (toolName != null && toolName.isNotEmpty) return toolName;
    return _approvalFallbackBody;
  }

  ConversationSummary? _currentConversation(String conversationId) {
    for (final conversation in _conversationRepository.conversations) {
      if (conversation.id == conversationId) return conversation;
    }
    return null;
  }

  String? _currentConversationStatus(String conversationId) =>
      _currentConversation(conversationId)?.status;

  bool _shouldKeepWatcher(_TrackedConversation target) {
    if (_disposed) return false;
    if (_appForeground) return true;
    if (_keepAliveInBackground) return true;
    return false;
  }

  bool _isTrackedStatus(String? status) {
    final normalized = normalizeConversationStatus(status);
    return normalized == 'running' ||
        normalized == 'sending' ||
        normalized == 'waiting_input' ||
        normalized == 'waiting_approval';
  }

  void _scheduleTerminalStop(_TrackedConversation target) {
    _cancelTerminalTimer(target);
    target.terminalTimer = Timer(_policy.terminalGrace, () {
      target.terminalTimer = null;
      _maybeStopConversation(target);
    });
  }

  void _cancelTerminalTimer(_TrackedConversation target) {
    target.terminalTimer?.cancel();
    target.terminalTimer = null;
  }

  void _maybeStopConversation(_TrackedConversation target) {
    if (_disposed) return;
    if (_isTrackedStatus(target.status)) return;
    if (target.terminalTimer != null) return;
    if (target.leases.isNotEmpty) return;
    unawaited(_stopWatcher(target));
    _tracked.remove(target.conversationId);
    _refreshBackgroundAnchor();
  }

  Future<void> _startBackgroundAnchorIfNeeded() async {
    final bridge = _backgroundSyncBridge;
    if (bridge == null || _backgroundAnchorActive || _disposed) return;
    final counts = _trackedCounts();
    if (counts.runningCount == 0 &&
        counts.waitingApprovalCount == 0 &&
        !_hasTerminalGraceTargets()) {
      return;
    }
    _backgroundAnchorActive = true;
    _backgroundSyncSubscription ??= bridge.events.listen(
      (snapshot) {
        if (snapshot.status == BackgroundConversationSyncStatus.stopped) {
          _disableBackgroundKeepAlive();
          return;
        }
        if (snapshot.status == BackgroundConversationSyncStatus.denied ||
            snapshot.status == BackgroundConversationSyncStatus.failed) {
          _disableBackgroundKeepAlive();
        }
      },
      onError: (_) {
        _disableBackgroundKeepAlive();
      },
    );
    try {
      final supported = await bridge.isSupported;
      if (!supported ||
          _disposed ||
          _appForeground ||
          !_keepAliveInBackground) {
        _backgroundAnchorActive = false;
        if (!supported && !_appForeground && _keepAliveInBackground) {
          _disableBackgroundKeepAlive();
        }
        return;
      }
      final snapshot = await bridge.start(
        BackgroundConversationSyncRequest(
          runningCount: counts.runningCount,
          waitingApprovalCount: counts.waitingApprovalCount,
          notificationTitle: _backgroundNotificationTitle,
          notificationBody: _backgroundNotificationBody(counts),
        ),
      );
      if (snapshot.status == BackgroundConversationSyncStatus.denied ||
          snapshot.status == BackgroundConversationSyncStatus.failed) {
        _disableBackgroundKeepAlive();
      }
    } catch (_) {
      _disableBackgroundKeepAlive();
    }
  }

  void _disableBackgroundKeepAlive() {
    _backgroundAnchorActive = false;
    if (!_appForeground && _keepAliveInBackground) {
      setAppForeground(false, keepAliveInBackground: false);
    }
  }

  void _refreshBackgroundAnchor() {
    if (_disposed || _appForeground || !_keepAliveInBackground) return;
    final counts = _trackedCounts();
    if (counts.runningCount == 0 && counts.waitingApprovalCount == 0) {
      if (_hasTerminalGraceTargets()) {
        if (!_backgroundAnchorActive) {
          unawaited(_startBackgroundAnchorIfNeeded());
        }
        return;
      }
      _stopBackgroundAnchor();
      return;
    }
    _backgroundAnchorActive = false;
    unawaited(_startBackgroundAnchorIfNeeded());
  }

  void _stopBackgroundAnchor() {
    if (!_backgroundAnchorActive && _backgroundSyncSubscription == null) return;
    _backgroundAnchorActive = false;
    unawaited(_backgroundSyncSubscription?.cancel());
    _backgroundSyncSubscription = null;
    unawaited(_backgroundSyncBridge?.stop());
  }

  ({int runningCount, int waitingApprovalCount}) _trackedCounts() {
    var runningCount = 0;
    var waitingApprovalCount = 0;
    for (final target in _tracked.values) {
      final status = normalizeConversationStatus(target.status);
      if (status == 'waiting_approval') {
        waitingApprovalCount += 1;
      } else if (_isTrackedStatus(status)) {
        runningCount += 1;
      }
    }
    return (
      runningCount: runningCount,
      waitingApprovalCount: waitingApprovalCount,
    );
  }

  bool _hasTerminalGraceTargets() =>
      _tracked.values.any((target) => target.terminalTimer != null);

  String _backgroundNotificationBody(
    ({int runningCount, int waitingApprovalCount}) counts,
  ) {
    final parts = <String>[];
    if (counts.runningCount > 0) {
      parts.add(
        counts.runningCount == 1
            ? '1 task running'
            : '${counts.runningCount} tasks running',
      );
    }
    if (counts.waitingApprovalCount > 0) {
      parts.add(
        counts.waitingApprovalCount == 1
            ? '1 waiting for approval'
            : '${counts.waitingApprovalCount} waiting for approval',
      );
    }
    return parts.isEmpty ? 'Background sync active' : parts.join(', ');
  }

  String? _nextStatusForEvent(ConversationEvent event, String? currentStatus) {
    if (event.type == 'conversation.status_changed') {
      return normalizeConversationStatus(event.raw['status'] as String?);
    }
    if (conversationEventCompletesTurn(event)) return 'idle';
    if (event.type == 'conversation.cancelled') {
      return event.raw['status'] as String? ?? 'cancelled';
    }
    if (event.type == 'run.error') return 'failed';
    if (event.type == 'assistant.question') return 'waiting_input';
    if (event.type == 'approval.requested') return 'waiting_approval';
    if (event.type == 'approval.resolved') {
      if (!conversationStatusCanResumeAfterApprovalResolution(currentStatus)) {
        return null;
      }
      if (normalizeConversationStatus(currentStatus) == 'waiting_approval') {
        return 'running';
      }
      return 'running';
    }
    if (event.type == 'blocking.request_cancelled') return 'running';
    return null;
  }
}

class _TrackedConversation {
  _TrackedConversation({
    required this.conversationId,
    required this.runId,
    required this.lastSeq,
    required this.status,
  });

  final String conversationId;
  String runId;
  int lastSeq;
  String status;
  final Set<_ConversationSyncLease> leases = <_ConversationSyncLease>{};
  StreamSubscription<ConversationEvent>? subscription;
  Timer? terminalTimer;
  bool stopping = false;
}

class _ConversationSyncLease implements ConversationSyncLease {
  _ConversationSyncLease({
    required this.conversationId,
    required int queueLimit,
    required Future<void> Function() onDispose,
  })  : _queueLimit = queueLimit < 1 ? 1 : queueLimit,
        _onDispose = onDispose {
    _controller = StreamController<ConversationEvent>(
      onListen: _drainQueuedEvents,
      onResume: _drainQueuedEvents,
      onCancel: _release,
    );
    _events = _controller.stream;
  }

  @override
  final String conversationId;
  final int _queueLimit;
  final Future<void> Function() _onDispose;
  late final StreamController<ConversationEvent> _controller;
  late final Stream<ConversationEvent> _events;
  final Queue<ConversationEvent> _pendingEvents = Queue<ConversationEvent>();
  bool _disposed = false;
  bool _released = false;
  bool _lagged = false;
  int _lastDeliveredSeq = 0;

  @override
  Stream<ConversationEvent> get events => _events;

  void add(ConversationEvent event) {
    if (_disposed || _controller.isClosed) return;
    if (_lagged) return;
    if (!_controller.hasListener || _controller.isPaused) {
      _enqueue(event);
      return;
    }
    _controller.add(event);
    _lastDeliveredSeq = event.seq;
  }

  void _enqueue(ConversationEvent event) {
    _pendingEvents.addLast(event);
    if (_pendingEvents.length <= _queueLimit) return;
    _pendingEvents.clear();
    _lagged = true;
    _controller.addError(
      ConversationSyncConsumerLagged(
        conversationId: conversationId,
        lastDeliveredSeq: _lastDeliveredSeq,
        droppedAfterSeq: event.seq,
      ),
    );
  }

  void _drainQueuedEvents() {
    if (_disposed || _controller.isClosed || _lagged) return;
    while (_pendingEvents.isNotEmpty && !_controller.isPaused) {
      final event = _pendingEvents.removeFirst();
      _controller.add(event);
      _lastDeliveredSeq = event.seq;
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _pendingEvents.clear();
    await _release();
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }

  Future<void> _release() async {
    if (_released) return;
    _released = true;
    await _onDispose();
  }
}

class _DisposedConversationSyncLease implements ConversationSyncLease {
  const _DisposedConversationSyncLease(this.conversationId);

  @override
  final String conversationId;

  @override
  Stream<ConversationEvent> get events =>
      const Stream<ConversationEvent>.empty();

  @override
  Future<void> dispose() async {}
}
