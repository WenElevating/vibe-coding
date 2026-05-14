import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../domain/repositories/run_repository.dart';
import '../../../../models/protocol.dart';
import '../run_detail_state.dart';

class RunDetailViewModel extends ChangeNotifier {
  RunDetailViewModel({
    required RunSummary run,
    required RunRepository runRepository,
  })  : _run = run,
        _runRepository = runRepository,
        _state = const RunDetailState();

  final RunSummary _run;
  final RunRepository _runRepository;

  RunDetailState _state;
  bool _isLoading = false;
  bool _isDisposed = false;
  String? _error;
  Future<void>? _loadEventsOperation;

  RunSummary get run => _run;
  RunDetailState get state => _state;
  bool get isLoading => _isLoading;
  String? get error => _error;

  List<AgentEvent> get events => _state.events;
  RunConnectionState get connectionState => _state.connectionState;

  Future<void> loadEvents() {
    if (_isDisposed || _run.id.isEmpty) return Future<void>.value();
    final inFlight = _loadEventsOperation;
    if (inFlight != null) return inFlight;

    final completer = Completer<void>();
    _loadEventsOperation = completer.future;
    unawaited(_completeLoadEvents(completer));
    return completer.future;
  }

  Future<void> _completeLoadEvents(Completer<void> completer) async {
    try {
      await _loadEvents();
      if (!completer.isCompleted) completer.complete();
    } catch (error, stackTrace) {
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
    }
  }

  Future<void> _loadEvents() async {
    setLoading(loading: true);
    setError(null);
    try {
      final events =
          await _runRepository.fetchEvents(_run.id, afterSeq: _state.lastSeq);
      if (_isDisposed) return;
      applyEvents(events);
    } catch (error) {
      if (_isDisposed) return;
      setError('$error');
    } finally {
      try {
        if (!_isDisposed) {
          setLoading(loading: false);
        }
      } finally {
        _loadEventsOperation = null;
      }
    }
  }

  void applyEvents(Iterable<AgentEvent> incoming) {
    if (_isDisposed) return;
    final events = incoming.toList(growable: false);
    if (events.isEmpty) return;
    final nextState = _state.mergeEvents(events);
    if (_sameState(_state, nextState)) return;
    _state = nextState;
    notifyListeners();
  }

  void setLoading({required bool loading}) {
    if (_isDisposed) return;
    if (_isLoading == loading) return;
    _isLoading = loading;
    notifyListeners();
  }

  void setError(String? message) {
    if (_isDisposed) return;
    if (_error == message) return;
    _error = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}

bool _sameState(RunDetailState current, RunDetailState next) {
  if (current.connectionState != next.connectionState ||
      current.lastSeq != next.lastSeq ||
      current.pendingApprovalCount != next.pendingApprovalCount ||
      current.events.length != next.events.length) {
    return false;
  }
  for (var i = 0; i < current.events.length; i += 1) {
    if (!identical(current.events[i], next.events[i])) return false;
  }
  return true;
}
