import 'package:flutter/foundation.dart';

import '../../../../models/protocol.dart';
import '../../../../state/run_detail_state.dart';

class RunDetailViewModel extends ChangeNotifier {
  RunDetailViewModel() : _state = const RunDetailState();

  RunDetailState _state;
  bool _isLoading = false;
  String? _error;

  RunDetailState get state => _state;
  bool get isLoading => _isLoading;
  String? get error => _error;

  List<AgentEvent> get events => _state.events;
  RunConnectionState get connectionState => _state.connectionState;

  void applyEvents(Iterable<AgentEvent> incoming) {
    _state = _state.mergeEvents(incoming);
    notifyListeners();
  }

  void setLoading({required bool loading}) {
    if (_isLoading == loading) return;
    _isLoading = loading;
    notifyListeners();
  }

  void setError(String? message) {
    if (_error == message) return;
    _error = message;
    notifyListeners();
  }
}
