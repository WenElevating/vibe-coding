import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/run_repository.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/ui/features/run_detail/run_detail.dart';

void main() {
  group('RunDetailViewModel', () {
    test('loadEvents fetches from start, merges events, and clears loading',
        () async {
      final repository = _FakeRunRepository(
        events: [_event(seq: 1), _event(seq: 2)],
      );
      final viewModel = RunDetailViewModel(
        run: _run,
        runRepository: repository,
      );

      await viewModel.loadEvents();

      expect(repository.fetchCalls, [
        const _FetchCall(runId: 'run_1', afterSeq: 0),
      ]);
      expect(viewModel.events.map((event) => event.seq), [1, 2]);
      expect(viewModel.state.lastSeq, 2);
      expect(viewModel.error, isNull);
      expect(viewModel.isLoading, isFalse);
    });

    test('loadEvents uses lastSeq and merges new events in sequence', () async {
      final repository = _FakeRunRepository(
        events: [_event(seq: 3), _event(seq: 2)],
      );
      final viewModel = RunDetailViewModel(
        run: _run,
        runRepository: repository,
      );
      viewModel.applyEvents([_event(seq: 1)]);

      await viewModel.loadEvents();

      expect(repository.fetchCalls, [
        const _FetchCall(runId: 'run_1', afterSeq: 1),
      ]);
      expect(viewModel.events.map((event) => event.seq), [1, 2, 3]);
      expect(viewModel.state.lastSeq, 3);
      expect(viewModel.error, isNull);
      expect(viewModel.isLoading, isFalse);
    });

    test('loadEvents captures failure and clears loading', () async {
      final repository = _FakeRunRepository(
        fetchError: StateError('fetch failed'),
      );
      final viewModel = RunDetailViewModel(
        run: _run,
        runRepository: repository,
      );

      await viewModel.loadEvents();

      expect(repository.fetchCalls, [
        const _FetchCall(runId: 'run_1', afterSeq: 0),
      ]);
      expect(viewModel.events, isEmpty);
      expect(viewModel.state.lastSeq, 0);
      expect(viewModel.error, contains('fetch failed'));
      expect(viewModel.isLoading, isFalse);
    });

    test('duplicate loadEvents calls share the in-flight fetch', () async {
      final completer = Completer<List<AgentEvent>>();
      final repository = _FakeRunRepository(fetchCompleter: completer);
      final viewModel = RunDetailViewModel(
        run: _run,
        runRepository: repository,
      );

      final firstLoad = viewModel.loadEvents();
      final secondLoad = viewModel.loadEvents();
      var firstCompleted = false;
      var secondCompleted = false;
      unawaited(firstLoad.then((_) => firstCompleted = true));
      unawaited(secondLoad.then((_) => secondCompleted = true));
      await Future<void>.delayed(Duration.zero);

      expect(repository.fetchCalls, [
        const _FetchCall(runId: 'run_1', afterSeq: 0),
      ]);
      expect(viewModel.isLoading, isTrue);
      expect(firstCompleted, isFalse);
      expect(secondCompleted, isFalse);

      completer.complete([_event(seq: 1)]);
      await Future.wait([firstLoad, secondLoad]);

      expect(viewModel.events.map((event) => event.seq), [1]);
      expect(viewModel.isLoading, isFalse);
    });

    test('re-entrant loadEvents during loading notification shares fetch',
        () async {
      final completer = Completer<List<AgentEvent>>();
      final repository = _FakeRunRepository(fetchCompleter: completer);
      final viewModel = RunDetailViewModel(
        run: _run,
        runRepository: repository,
      );
      Future<void>? reentrantLoad;

      viewModel.addListener(() {
        if (!viewModel.isLoading || reentrantLoad != null) return;
        reentrantLoad = viewModel.loadEvents();
      });

      final firstLoad = viewModel.loadEvents();
      await Future<void>.delayed(Duration.zero);

      expect(repository.fetchCalls, [
        const _FetchCall(runId: 'run_1', afterSeq: 0),
      ]);
      expect(reentrantLoad, isNotNull);
      expect(viewModel.isLoading, isTrue);

      completer.complete([_event(seq: 1)]);
      await Future.wait([firstLoad, reentrantLoad!]);

      expect(viewModel.events.map((event) => event.seq), [1]);
      expect(viewModel.isLoading, isFalse);
    });

    test('re-entrant loadEvents during final loading false shares fetch',
        () async {
      final completer = Completer<List<AgentEvent>>();
      final repository = _FakeRunRepository(fetchCompleter: completer);
      final viewModel = RunDetailViewModel(
        run: _run,
        runRepository: repository,
      );
      Future<void>? reentrantLoad;
      var reentrantSharedOriginalLoad = false;
      late Future<void> firstLoad;

      viewModel.addListener(() {
        if (viewModel.isLoading || reentrantLoad != null) return;
        reentrantLoad = viewModel.loadEvents();
        reentrantSharedOriginalLoad = identical(reentrantLoad, firstLoad);
      });

      firstLoad = viewModel.loadEvents();
      await Future<void>.delayed(Duration.zero);

      expect(repository.fetchCalls, [
        const _FetchCall(runId: 'run_1', afterSeq: 0),
      ]);
      expect(viewModel.isLoading, isTrue);
      expect(reentrantLoad, isNull);

      completer.complete([_event(seq: 1)]);
      await firstLoad;
      expect(reentrantLoad, isNotNull);
      await reentrantLoad;

      expect(repository.fetchCalls, [
        const _FetchCall(runId: 'run_1', afterSeq: 0),
      ]);
      expect(reentrantSharedOriginalLoad, isTrue);
      expect(viewModel.events.map((event) => event.seq), [1]);
      expect(viewModel.isLoading, isFalse);
    });

    test('dispose during in-flight fetch ignores completion', () async {
      final completer = Completer<List<AgentEvent>>();
      final repository = _FakeRunRepository(fetchCompleter: completer);
      final viewModel = RunDetailViewModel(
        run: _run,
        runRepository: repository,
      );

      final load = viewModel.loadEvents();
      viewModel.dispose();

      completer.complete([_event(seq: 1)]);
      await load;

      expect(repository.fetchCalls, [
        const _FetchCall(runId: 'run_1', afterSeq: 0),
      ]);
    });

    test('empty run id skips fetch and leaves loading false', () async {
      final repository = _FakeRunRepository(
        events: [_event(seq: 1)],
      );
      final viewModel = RunDetailViewModel(
        run: const RunSummary(
          id: '',
          tool: 'codex',
          workspaceId: 'workspace_1',
          status: 'unknown',
        ),
        runRepository: repository,
      );

      await viewModel.loadEvents();

      expect(repository.fetchCalls, isEmpty);
      expect(viewModel.events, isEmpty);
      expect(viewModel.isLoading, isFalse);
      expect(viewModel.error, isNull);
    });

    test('applyEvents ignores empty and unchanged incoming events', () {
      final repository = _FakeRunRepository();
      final viewModel = RunDetailViewModel(
        run: _run,
        runRepository: repository,
      );
      var notifyCount = 0;
      viewModel.addListener(() => notifyCount += 1);
      final event = _event(seq: 1);

      viewModel.applyEvents(const <AgentEvent>[]);
      viewModel.applyEvents([event]);
      viewModel.applyEvents([event]);

      expect(notifyCount, 1);
      expect(viewModel.events, [event]);
    });
  });
}

const _run = RunSummary(
  id: 'run_1',
  tool: 'codex',
  workspaceId: 'workspace_1',
  status: 'running',
);

AgentEvent _event({required int seq}) {
  return AgentEvent(
    type: 'agent.message',
    seq: seq,
    runId: _run.id,
    createdAt: DateTime.utc(2026, 5, 14, 10, 30 + seq),
    name: 'Event $seq',
    text: 'Message $seq',
  );
}

class _FetchCall {
  const _FetchCall({required this.runId, required this.afterSeq});

  final String runId;
  final int afterSeq;

  @override
  bool operator ==(Object other) =>
      other is _FetchCall && other.runId == runId && other.afterSeq == afterSeq;

  @override
  int get hashCode => Object.hash(runId, afterSeq);

  @override
  String toString() => '_FetchCall(runId: $runId, afterSeq: $afterSeq)';
}

class _FakeRunRepository implements RunRepository {
  _FakeRunRepository({
    this.events = const <AgentEvent>[],
    this.fetchError,
    this.fetchCompleter,
  });

  List<AgentEvent> events;
  Object? fetchError;
  Completer<List<AgentEvent>>? fetchCompleter;
  final fetchCalls = <_FetchCall>[];

  @override
  Future<RunSummary> cancelRun(String runId) {
    throw UnimplementedError();
  }

  @override
  Future<RunSummary> createRun({
    required String tool,
    required String workspaceId,
    String? prompt,
    String? shortcutId,
    String permissionMode = 'default',
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<AgentEvent>> fetchEvents(String runId, {int afterSeq = 0}) async {
    fetchCalls.add(_FetchCall(runId: runId, afterSeq: afterSeq));
    final completer = fetchCompleter;
    if (completer != null) {
      return completer.future;
    }
    final error = fetchError;
    if (error != null) {
      throw error;
    }
    return events;
  }

  @override
  Future<RunSummary> invokeCommandTemplate({
    required String templateId,
    required String workspaceId,
    String tool = 'claude',
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<QueueItem>> listQueue() {
    throw UnimplementedError();
  }

  @override
  Future<List<RunSummary>> listRuns({
    String? tool,
    String? workspaceId,
    String? status,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> respondApproval(String approvalId, String decision) {
    throw UnimplementedError();
  }

  @override
  Future<RunSummary> sendRunInput(
    String runId,
    String prompt, {
    String permissionMode = 'default',
  }) {
    throw UnimplementedError();
  }
}
