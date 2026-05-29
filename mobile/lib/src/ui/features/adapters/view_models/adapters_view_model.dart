import 'package:flutter/foundation.dart';

import '../../../../data/repositories/cli_adapter_repository.dart';
import '../../../../data/repositories/command_catalog_repository.dart';
import '../../../../models/protocol.dart';

class AdaptersViewModel extends ChangeNotifier {
  AdaptersViewModel({
    required CliAdapterRepository adapterRepository,
    required CommandCatalogRepository commandCatalogRepository,
  })  : _adapterRepository = adapterRepository,
        _commandCatalogRepository = commandCatalogRepository,
        _loading =
            adapterRepository.loading || commandCatalogRepository.loading,
        _error = adapterRepository.error ?? commandCatalogRepository.error {
    _adapterRepository.addListener(_onRepositoryChanged);
    _commandCatalogRepository.addListener(_onRepositoryChanged);
  }

  final CliAdapterRepository _adapterRepository;
  final CommandCatalogRepository _commandCatalogRepository;
  bool _loading;
  Object? _error;
  bool _disposed = false;

  List<AdapterStatus> get adapters => _adapterRepository.adapters;
  List<ExtensionSummary> get extensions => _commandCatalogRepository.extensions;
  bool get loading => _loading;
  Object? get error => _error;

  Future<void> loadCatalog() async {
    if (_disposed) return;
    try {
      await _commandCatalogRepository.load();
    } catch (_) {
      // Repository state exposes the failure; background catalog loading should
      // not require every caller to catch errors.
    }
  }

  void _onRepositoryChanged() {
    if (_disposed) return;
    final loading =
        _adapterRepository.loading || _commandCatalogRepository.loading;
    final error = _adapterRepository.error ?? _commandCatalogRepository.error;
    _loading = loading;
    _error = error;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _adapterRepository.removeListener(_onRepositoryChanged);
    _commandCatalogRepository.removeListener(_onRepositoryChanged);
    super.dispose();
  }
}
