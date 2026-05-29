import 'package:flutter/foundation.dart';

import '../../domain/repositories/adapter_repository.dart';
import '../../models/protocol.dart';

class CliAdapterRepository extends ChangeNotifier {
  CliAdapterRepository({required AdapterRepository delegate})
      : _delegate = delegate;

  final AdapterRepository _delegate;
  List<AdapterStatus> _adapters = const <AdapterStatus>[];
  bool _loading = false;
  Object? _error;
  Future<void>? _probeFuture;
  int _generation = 0;
  bool _disposed = false;

  List<AdapterStatus> get adapters => List.unmodifiable(_adapters);
  bool get loading => _loading;
  Object? get error => _error;

  Future<List<AdapterStatus>> listAdapters() async {
    await probe();
    return adapters;
  }

  Future<void> probe() {
    final current = _probeFuture;
    if (current != null) return current;
    final generation = ++_generation;
    _loading = true;
    _error = null;
    _notifyIfActive();
    final future = _delegate.listAdapters().then((value) {
      if (_disposed || generation != _generation) return;
      _adapters = List<AdapterStatus>.unmodifiable(value);
    }).catchError((Object error) {
      if (!_disposed && generation == _generation) _error = error;
      throw error;
    }).whenComplete(() {
      if (_disposed || generation != _generation) return;
      _loading = false;
      _probeFuture = null;
      _notifyIfActive();
    });
    _probeFuture = future;
    return future;
  }

  void replaceFromBootstrap(List<AdapterStatus> adapters) {
    if (_disposed) return;
    _generation++;
    _probeFuture = null;
    _loading = false;
    _error = null;
    _adapters = List<AdapterStatus>.unmodifiable(adapters);
    _notifyIfActive();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    super.dispose();
  }

  void _notifyIfActive() {
    if (!_disposed) notifyListeners();
  }
}
