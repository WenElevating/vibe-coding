import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/data/repositories/cached_conversation_repository.dart';
import 'package:lan_ai_cli_control/src/domain/models/approval_response.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/conversation_repository.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/services/background_conversation_sync_bridge.dart';
import 'package:lan_ai_cli_control/src/services/mobile_app_event_bus.dart';
import 'package:lan_ai_cli_control/src/workflows/conversation_sync/conversation_sync_coordinator.dart';
import 'package:lan_ai_cli_control/src/workflows/conversation_sync/conversation_sync_policy.dart';

void main() {
  test(
    'detaching foreground lease keeps watcher alive while app is foreground',
    () async {
      final delegate = _FakeConversationRepository();
      final repository = CachedConversationRepository(delegate: delegate)
        ..replaceFromBootstrap(
          workspaceId: 'workspace_1',
          conversations: <ConversationSummary>[
            _conversation(id: 'conv_1', status: 'running'),
          ],
        );
      final coordinator = ConversationSyncCoordinator(
        conversationRepository: repository,
        policy: const ConversationSyncPolicy(
          backgroundDisconnectGrace: Duration(milliseconds: 30),
        ),
      );

      coordinator.trackConversation(
        conversationId: 'conv_1',
        runId: 'run_1',
        afterSeq: 0,
        status: 'running',
      );
      final lease = coordinator.attachForegroundConsumer(
        conversationId: 'conv_1',
        runId: 'run_1',
        afterSeq: 0,
      );
      final received = <ConversationEvent>[];
      final sub = lease.events.listen(received.add);
      await pumpEventQueue();

      expect(delegate.watchCalls, 1);
      expect(delegate.cancelCalls, 0);

      await lease.dispose();
      await sub.cancel();
      await pumpEventQueue();

      expect(delegate.cancelCalls, 0);

      delegate.emit(
        _event(
          seq: 1,
          conversationId: 'conv_1',
          type: 'conversation.status_changed',
          raw: const <String, Object?>{'status': 'waiting_input'},
        ),
      );
      await pumpEventQueue();

      expect(delegate.cancelCalls, 0);
      expect(repository.conversations.single.status, 'waiting_input');
      await coordinator.dispose();
    },
  );

  test(
    'background grace cancels watcher when keep-live setting is disabled',
    () async {
      final delegate = _FakeConversationRepository();
      final repository = CachedConversationRepository(delegate: delegate)
        ..replaceFromBootstrap(
          workspaceId: 'workspace_1',
          conversations: <ConversationSummary>[
            _conversation(id: 'conv_1', status: 'running'),
          ],
        );
      final coordinator = ConversationSyncCoordinator(
        conversationRepository: repository,
        policy: const ConversationSyncPolicy(
          backgroundDisconnectGrace: Duration(milliseconds: 10),
        ),
      );

      coordinator.trackConversation(
        conversationId: 'conv_1',
        runId: 'run_1',
        afterSeq: 0,
        status: 'running',
      );
      await pumpEventQueue();
      expect(delegate.watchCalls, 1);

      coordinator.setAppForeground(false, keepAliveInBackground: false);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(delegate.cancelCalls, 1);
      await coordinator.dispose();
    },
  );

  test(
    'background keep-live starts platform anchor for tracked conversations',
    () async {
      final delegate = _FakeConversationRepository();
      final backgroundBridge = _FakeBackgroundConversationSyncBridge();
      final repository = CachedConversationRepository(delegate: delegate)
        ..replaceFromBootstrap(
          workspaceId: 'workspace_1',
          conversations: <ConversationSummary>[
            _conversation(id: 'conv_1', status: 'running'),
          ],
        );
      final coordinator = ConversationSyncCoordinator(
        conversationRepository: repository,
        backgroundSyncBridge: backgroundBridge,
      )..updateBackgroundNotificationText(title: 'Vibe Coding');

      coordinator.trackConversation(
        conversationId: 'conv_1',
        runId: 'run_1',
        afterSeq: 0,
        status: 'running',
      );
      coordinator.setAppForeground(false, keepAliveInBackground: true);
      await pumpEventQueue();

      expect(delegate.cancelCalls, 0);
      expect(backgroundBridge.startRequests, hasLength(1));
      expect(backgroundBridge.startRequests.single.runningCount, 1);
      expect(backgroundBridge.startRequests.single.waitingApprovalCount, 0);
      expect(
        backgroundBridge.startRequests.single.notificationTitle,
        'Vibe Coding',
      );

      await coordinator.dispose();
    },
  );

  test(
    'background anchor denial falls back to normal disconnect grace',
    () async {
      final delegate = _FakeConversationRepository();
      final backgroundBridge = _FakeBackgroundConversationSyncBridge(
        startStatus: BackgroundConversationSyncStatus.denied,
      );
      final repository = CachedConversationRepository(delegate: delegate)
        ..replaceFromBootstrap(
          workspaceId: 'workspace_1',
          conversations: <ConversationSummary>[
            _conversation(id: 'conv_1', status: 'running'),
          ],
        );
      final coordinator = ConversationSyncCoordinator(
        conversationRepository: repository,
        backgroundSyncBridge: backgroundBridge,
        policy: const ConversationSyncPolicy(
          backgroundDisconnectGrace: Duration(milliseconds: 10),
        ),
      );

      coordinator.trackConversation(
        conversationId: 'conv_1',
        runId: 'run_1',
        afterSeq: 0,
        status: 'running',
      );
      coordinator.setAppForeground(false, keepAliveInBackground: true);
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(backgroundBridge.startRequests, hasLength(1));
      expect(delegate.cancelCalls, 1);

      await coordinator.dispose();
    },
  );

  test(
    'background anchor stop event falls back to normal disconnect grace',
    () async {
      final delegate = _FakeConversationRepository();
      final backgroundBridge = _FakeBackgroundConversationSyncBridge();
      final repository = CachedConversationRepository(delegate: delegate)
        ..replaceFromBootstrap(
          workspaceId: 'workspace_1',
          conversations: <ConversationSummary>[
            _conversation(id: 'conv_1', status: 'running'),
          ],
        );
      final coordinator = ConversationSyncCoordinator(
        conversationRepository: repository,
        backgroundSyncBridge: backgroundBridge,
        policy: const ConversationSyncPolicy(
          backgroundDisconnectGrace: Duration(milliseconds: 10),
        ),
      );

      coordinator.trackConversation(
        conversationId: 'conv_1',
        runId: 'run_1',
        afterSeq: 0,
        status: 'running',
      );
      coordinator.setAppForeground(false, keepAliveInBackground: true);
      await pumpEventQueue();

      backgroundBridge.emit(
        BackgroundConversationSyncSnapshot(
          status: BackgroundConversationSyncStatus.stopped,
          runningCount: 1,
          waitingApprovalCount: 0,
          message: 'Background sync stopped',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(backgroundBridge.startRequests, hasLength(1));
      expect(delegate.cancelCalls, 1);

      await coordinator.dispose();
    },
  );

  test(
    'background anchor stop event is ignored after foreground return',
    () async {
      final delegate = _FakeConversationRepository();
      final backgroundBridge = _FakeBackgroundConversationSyncBridge();
      final repository = CachedConversationRepository(delegate: delegate)
        ..replaceFromBootstrap(
          workspaceId: 'workspace_1',
          conversations: <ConversationSummary>[
            _conversation(id: 'conv_1', status: 'running'),
          ],
        );
      final coordinator = ConversationSyncCoordinator(
        conversationRepository: repository,
        backgroundSyncBridge: backgroundBridge,
        policy: const ConversationSyncPolicy(
          backgroundDisconnectGrace: Duration(milliseconds: 10),
        ),
      );

      coordinator.trackConversation(
        conversationId: 'conv_1',
        runId: 'run_1',
        afterSeq: 0,
        status: 'running',
      );
      coordinator.setAppForeground(false, keepAliveInBackground: true);
      await pumpEventQueue();
      coordinator.setAppForeground(true, keepAliveInBackground: true);
      backgroundBridge.emit(
        BackgroundConversationSyncSnapshot(
          status: BackgroundConversationSyncStatus.stopped,
          runningCount: 1,
          waitingApprovalCount: 0,
          message: 'Background sync stopped',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(delegate.cancelCalls, 0);

      await coordinator.dispose();
    },
  );

  test('background anchor stays active until terminal grace expires', () async {
    final delegate = _FakeConversationRepository();
    final backgroundBridge = _FakeBackgroundConversationSyncBridge();
    final repository = CachedConversationRepository(delegate: delegate)
      ..replaceFromBootstrap(
        workspaceId: 'workspace_1',
        conversations: <ConversationSummary>[
          _conversation(id: 'conv_1', status: 'running'),
        ],
      );
    final coordinator = ConversationSyncCoordinator(
      conversationRepository: repository,
      backgroundSyncBridge: backgroundBridge,
      policy: const ConversationSyncPolicy(
        terminalGrace: Duration(milliseconds: 30),
      ),
    );

    coordinator.trackConversation(
      conversationId: 'conv_1',
      runId: 'run_1',
      afterSeq: 0,
      status: 'running',
    );
    coordinator.setAppForeground(false, keepAliveInBackground: true);
    await pumpEventQueue();

    delegate.emit(
      _event(seq: 1, conversationId: 'conv_1', type: 'conversation.completed'),
    );
    await pumpEventQueue();

    expect(backgroundBridge.stopCalls, 0);

    await Future<void>.delayed(const Duration(milliseconds: 45));

    expect(backgroundBridge.stopCalls, 1);

    await coordinator.dispose();
  });

  test('terminal grace keeps watcher briefly for late final events', () async {
    final delegate = _FakeConversationRepository();
    final repository = CachedConversationRepository(delegate: delegate)
      ..replaceFromBootstrap(
        workspaceId: 'workspace_1',
        conversations: <ConversationSummary>[
          _conversation(id: 'conv_1', status: 'running'),
        ],
      );
    final coordinator = ConversationSyncCoordinator(
      conversationRepository: repository,
      policy: const ConversationSyncPolicy(
        terminalGrace: Duration(milliseconds: 20),
      ),
    );

    coordinator.trackConversation(
      conversationId: 'conv_1',
      runId: 'run_1',
      afterSeq: 0,
      status: 'running',
    );
    final lease = coordinator.attachForegroundConsumer(
      conversationId: 'conv_1',
      runId: 'run_1',
      afterSeq: 0,
    );
    await pumpEventQueue();

    delegate.emit(
      _event(seq: 1, conversationId: 'conv_1', type: 'conversation.completed'),
    );
    await pumpEventQueue();
    await lease.dispose();
    await pumpEventQueue();

    expect(repository.conversations.single.status, 'idle');
    expect(delegate.cancelCalls, 0);

    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(delegate.cancelCalls, 1);
    await coordinator.dispose();
  });

  test('default policy documents route-independent sync timing', () {
    const policy = ConversationSyncPolicy();

    expect(policy.terminalGrace, const Duration(seconds: 45));
    expect(policy.backgroundDisconnectGrace, const Duration(seconds: 30));
    expect(policy.consumerLagQueueLimit, 256);
  });

  test('watcher failure reconnects from the latest event cursor', () async {
    final delegate = _FakeConversationRepository();
    final repository = CachedConversationRepository(delegate: delegate)
      ..replaceFromBootstrap(
        workspaceId: 'workspace_1',
        conversations: <ConversationSummary>[
          _conversation(id: 'conv_1', status: 'running'),
        ],
      );
    final coordinator = ConversationSyncCoordinator(
      conversationRepository: repository,
    );

    coordinator.trackConversation(
      conversationId: 'conv_1',
      runId: 'run_1',
      afterSeq: 0,
      status: 'running',
    );
    await pumpEventQueue();
    delegate.emit(
      _event(seq: 4, conversationId: 'conv_1', type: 'assistant.delta'),
    );
    await pumpEventQueue();

    delegate.failActiveWatcher(StateError('socket closed'));
    await pumpEventQueue();

    expect(delegate.watchCalls, 2);
    expect(delegate.afterSeqs, const <int>[0, 4]);
    await coordinator.dispose();
  });

  test('approval events are published without a foreground lease', () async {
    final delegate = _FakeConversationRepository();
    final repository = CachedConversationRepository(delegate: delegate)
      ..replaceFromBootstrap(
        workspaceId: 'workspace_1',
        conversations: <ConversationSummary>[
          _conversation(
            id: 'conv_1',
            status: 'running',
            title: 'Approval task',
          ),
        ],
      );
    final eventBus = MobileAppEventBus();
    final approvals = <MobileApprovalRequested>[];
    final sub = eventBus.on<MobileApprovalRequested>().listen(approvals.add);
    final coordinator = ConversationSyncCoordinator(
      conversationRepository: repository,
      eventBus: eventBus,
    );

    coordinator.trackConversation(
      conversationId: 'conv_1',
      runId: 'run_1',
      afterSeq: 0,
      status: 'running',
    );
    delegate.emit(
      _event(
        seq: 1,
        conversationId: 'conv_1',
        type: 'approval.requested',
        approvalId: 'approval_1',
        toolName: 'Bash',
        summary: 'npm test',
      ),
    );
    await pumpEventQueue();

    expect(approvals, hasLength(1));
    expect(approvals.single.workspaceId, 'workspace_1');
    expect(approvals.single.conversationId, 'conv_1');
    expect(approvals.single.approvalId, 'approval_1');
    expect(approvals.single.conversationTitle, 'Approval task');
    expect(approvals.single.body, 'npm test');

    await coordinator.dispose();
    await sub.cancel();
    await eventBus.dispose();
  });

  test(
    'slow foreground consumer gets lagged signal without stopping watcher',
    () async {
      final delegate = _FakeConversationRepository();
      final repository = CachedConversationRepository(delegate: delegate)
        ..replaceFromBootstrap(
          workspaceId: 'workspace_1',
          conversations: <ConversationSummary>[
            _conversation(id: 'conv_1', status: 'running'),
          ],
        );
      final coordinator = ConversationSyncCoordinator(
        conversationRepository: repository,
        policy: const ConversationSyncPolicy(consumerLagQueueLimit: 2),
      );

      final lease = coordinator.attachForegroundConsumer(
        conversationId: 'conv_1',
        runId: 'run_1',
        afterSeq: 0,
      );
      final received = <ConversationEvent>[];
      final errors = <Object>[];
      final sub = lease.events.listen(received.add, onError: errors.add);
      sub.pause();
      await pumpEventQueue();

      delegate
        ..emit(
          _event(seq: 1, conversationId: 'conv_1', type: 'assistant.delta'),
        )
        ..emit(
          _event(seq: 2, conversationId: 'conv_1', type: 'assistant.delta'),
        )
        ..emit(
          _event(seq: 3, conversationId: 'conv_1', type: 'assistant.delta'),
        );
      await pumpEventQueue();

      expect(delegate.cancelCalls, 0);
      expect(repository.conversations.single.status, 'running');
      expect(errors, isEmpty);

      sub.resume();
      await pumpEventQueue();

      expect(received, isEmpty);
      expect(errors, hasLength(1));
      expect(errors.single, isA<ConversationSyncConsumerLagged>());
      final lagged = errors.single as ConversationSyncConsumerLagged;
      expect(lagged.conversationId, 'conv_1');
      expect(lagged.droppedAfterSeq, 3);
      expect(delegate.cancelCalls, 0);
      await lease.dispose();
      await sub.cancel();
      await coordinator.dispose();
    },
  );
}

class _FakeConversationRepository implements ConversationRepository {
  final List<StreamController<ConversationEvent>> _watchers =
      <StreamController<ConversationEvent>>[];
  final List<int> afterSeqs = <int>[];
  int watchCalls = 0;
  int cancelCalls = 0;

  void emit(ConversationEvent event) {
    for (final watcher in _watchers.toList(growable: false)) {
      if (!watcher.isClosed) watcher.add(event);
    }
  }

  void failActiveWatcher(Object error) {
    for (final watcher in _watchers.toList(growable: false)) {
      if (watcher.isClosed) continue;
      watcher.addError(error);
      unawaited(watcher.close());
    }
  }

  @override
  Stream<ConversationEvent> watchConversationEvents(
    String conversationId, {
    required int afterSeq,
  }) {
    watchCalls += 1;
    afterSeqs.add(afterSeq);
    late final StreamController<ConversationEvent> controller;
    controller = StreamController<ConversationEvent>(
      onListen: () => _watchers.add(controller),
      onCancel: () {
        cancelCalls += 1;
        _watchers.remove(controller);
      },
    );
    return controller.stream.where(
      (event) => event.conversationId == conversationId,
    );
  }

  @override
  Future<List<ConversationSummary>> listConversations() async =>
      const <ConversationSummary>[];

  @override
  Future<ConversationSummary> createConversation({
    required String workspaceId,
    String adapter = 'claude',
    String permissionMode = 'default',
    String? model,
  }) async =>
      _conversation(id: 'created', workspaceId: workspaceId);

  @override
  Future<ConversationSummary> sendConversationMessage(
    String conversationId,
    ConversationMessageSendRequest request,
  ) async =>
      _conversation(id: conversationId);

  @override
  Future<ConversationSummary> updateConversationModel(
    String conversationId,
    String? model,
  ) async =>
      _conversation(id: conversationId);

  @override
  Future<ConversationSummary> updateConversationPermissionMode(
    String conversationId,
    String permissionMode,
  ) async =>
      _conversation(id: conversationId);

  @override
  Future<List<ConversationEvent>> fetchConversationEvents(
    String conversationId, {
    int afterSeq = 0,
  }) async =>
      const <ConversationEvent>[];

  @override
  Future<ConversationEventPage> fetchConversationEventPage(
    String conversationId, {
    int? beforeSeq,
    required int limit,
  }) async =>
      const ConversationEventPage(
        events: <ConversationEvent>[],
        oldestSeq: null,
        newestSeq: null,
        hasMoreBefore: false,
      );

  @override
  Future<ConversationSummary> answerConversationQuestion(
    String conversationId,
    String questionId,
    String text,
  ) async =>
      _conversation(id: conversationId);

  @override
  Future<ConversationSummary> respondConversationApproval(
    String conversationId,
    String approvalId,
    ApprovalResponse response,
  ) async =>
      _conversation(id: conversationId);

  @override
  Future<ConversationSummary> cancelConversation(String conversationId) async =>
      _conversation(id: conversationId, status: 'cancelled');
}

class _FakeBackgroundConversationSyncBridge
    implements BackgroundConversationSyncBridge {
  _FakeBackgroundConversationSyncBridge({
    this.supported = true,
    this.startStatus = BackgroundConversationSyncStatus.active,
  });

  final bool supported;
  final BackgroundConversationSyncStatus startStatus;
  final List<BackgroundConversationSyncRequest> startRequests =
      <BackgroundConversationSyncRequest>[];
  final StreamController<BackgroundConversationSyncSnapshot> _controller =
      StreamController<BackgroundConversationSyncSnapshot>.broadcast();
  int stopCalls = 0;

  @override
  Future<bool> get isSupported async => supported;

  @override
  Stream<BackgroundConversationSyncSnapshot> get events => _controller.stream;

  @override
  Future<BackgroundConversationSyncSnapshot> start(
    BackgroundConversationSyncRequest request,
  ) async {
    startRequests.add(request);
    final snapshot = BackgroundConversationSyncSnapshot(
      status: startStatus,
      runningCount: request.runningCount,
      waitingApprovalCount: request.waitingApprovalCount,
      message: request.notificationBody,
    );
    _controller.add(snapshot);
    return snapshot;
  }

  @override
  Future<BackgroundConversationSyncSnapshot?> snapshot() async => null;

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }

  void emit(BackgroundConversationSyncSnapshot snapshot) {
    _controller.add(snapshot);
  }
}

ConversationSummary _conversation({
  required String id,
  String workspaceId = 'workspace_1',
  String status = 'running',
  String? title,
}) =>
    ConversationSummary(
      id: id,
      workspaceId: workspaceId,
      adapter: 'codex',
      status: status,
      title: title,
      capabilities:
          ConversationCapabilities.fromJson(const <String, Object?>{}),
      createdAt: '2026-06-12T00:00:00.000Z',
      updatedAt: '2026-06-12T00:00:01.000Z',
    );

ConversationEvent _event({
  required int seq,
  required String conversationId,
  required String type,
  String? approvalId,
  String? toolName,
  String? summary,
  Map<String, Object?> raw = const <String, Object?>{},
}) =>
    ConversationEvent(
      seq: seq,
      conversationId: conversationId,
      type: type,
      approvalId: approvalId,
      toolName: toolName,
      summary: summary,
      raw: raw,
      createdAt: DateTime.parse('2026-06-12T00:00:01.000Z'),
    );
