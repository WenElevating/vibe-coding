import 'package:flutter/foundation.dart';

import '../../../../domain/repositories/diagnostics_repository.dart';
import '../../../../models/protocol.dart';

class DiagnosticsViewModel extends ChangeNotifier {
  DiagnosticsViewModel({required DiagnosticsRepository repository})
      : _repository = repository;

  final DiagnosticsRepository _repository;

  DiagnosticBundleSummary? _bundle;
  bool _isLoading = false;
  bool _isDisposed = false;
  String? _error;

  DiagnosticBundleSummary? get bundle => _bundle;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> createBundle() async {
    if (_isLoading || _isDisposed) return;

    _isLoading = true;
    _error = null;
    _bundle = null;
    notifyListeners();

    try {
      final bundle = await _repository.exportDiagnostics();
      if (_isDisposed) return;
      _bundle = bundle;
    } catch (error) {
      if (_isDisposed) return;
      _error = error.toString();
    } finally {
      if (!_isDisposed) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
