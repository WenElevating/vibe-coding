import 'package:flutter/foundation.dart';

import '../../domain/repositories/adapter_repository.dart';
import '../../models/protocol.dart';

class CachedAdapterRepository extends ChangeNotifier
    implements AdapterRepository {
  CachedAdapterRepository({required AdapterRepository delegate})
      : _delegate = delegate;

  final AdapterRepository _delegate;

  List<AdapterStatus> _adapters = const <AdapterStatus>[];
  List<ShortcutCommand> _shortcuts = const <ShortcutCommand>[];
  List<CommandTemplate> _templates = const <CommandTemplate>[];
  List<ExtensionSummary> _extensions = const <ExtensionSummary>[];
  Object? _error;
  bool _adaptersLoaded = false;
  bool _shortcutsLoaded = false;
  bool _templatesLoaded = false;
  bool _extensionsLoaded = false;
  int _adaptersGeneration = 0;
  int _shortcutsGeneration = 0;
  int _templatesGeneration = 0;
  int _extensionsGeneration = 0;
  int _pendingLoads = 0;
  Future<void>? _adaptersFuture;
  Future<void>? _shortcutsFuture;
  Future<void>? _templatesFuture;
  Future<void>? _extensionsFuture;
  bool _disposed = false;

  List<AdapterStatus> get adapters => List.unmodifiable(_adapters);
  List<ShortcutCommand> get shortcuts => List.unmodifiable(_shortcuts);
  List<CommandTemplate> get templates => List.unmodifiable(_templates);
  List<ExtensionSummary> get extensions => List.unmodifiable(_extensions);
  bool get loading => _pendingLoads > 0;
  Object? get error => _error;

  Future<void> load() => Future.wait<void>([
        _loadAdapters(force: true),
        _loadShortcuts(force: true),
        _loadTemplates(force: true),
        _loadExtensions(force: true),
      ]);

  @override
  Future<List<AdapterStatus>> listAdapters() async {
    await _ensureAdaptersLoaded();
    return adapters;
  }

  @override
  Future<List<ShortcutCommand>> listShortcuts() async {
    await _ensureShortcutsLoaded();
    return shortcuts;
  }

  @override
  Future<List<CommandTemplate>> listCommandTemplates() async {
    await _ensureTemplatesLoaded();
    return templates;
  }

  @override
  Future<List<ExtensionSummary>> listExtensions() async {
    await _ensureExtensionsLoaded();
    return extensions;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _adaptersGeneration++;
    _shortcutsGeneration++;
    _templatesGeneration++;
    _extensionsGeneration++;
    super.dispose();
  }

  Future<void> _ensureAdaptersLoaded() async {
    final future = _adaptersFuture;
    if (future != null) {
      await future;
      return;
    }
    if (!_adaptersLoaded) {
      await _loadAdapters();
    }
  }

  Future<void> _ensureShortcutsLoaded() async {
    final future = _shortcutsFuture;
    if (future != null) {
      await future;
      return;
    }
    if (!_shortcutsLoaded) {
      await _loadShortcuts();
    }
  }

  Future<void> _ensureTemplatesLoaded() async {
    final future = _templatesFuture;
    if (future != null) {
      await future;
      return;
    }
    if (!_templatesLoaded) {
      await _loadTemplates();
    }
  }

  Future<void> _ensureExtensionsLoaded() async {
    final future = _extensionsFuture;
    if (future != null) {
      await future;
      return;
    }
    if (!_extensionsLoaded) {
      await _loadExtensions();
    }
  }

  Future<void> _loadAdapters({bool force = false}) {
    if (!force && _adaptersFuture != null) return _adaptersFuture!;
    final generation = ++_adaptersGeneration;
    final future = _loadResource<List<AdapterStatus>>(
      isCurrent: () => generation == _adaptersGeneration,
      load: _delegate.listAdapters,
      apply: (value) {
        _adapters = List<AdapterStatus>.unmodifiable(value);
        _adaptersLoaded = true;
      },
      clearFuture: () => _adaptersFuture = null,
    );
    _adaptersFuture = future;
    return future;
  }

  Future<void> _loadShortcuts({bool force = false}) {
    if (!force && _shortcutsFuture != null) return _shortcutsFuture!;
    final generation = ++_shortcutsGeneration;
    final future = _loadResource<List<ShortcutCommand>>(
      isCurrent: () => generation == _shortcutsGeneration,
      load: _delegate.listShortcuts,
      apply: (value) {
        _shortcuts = List<ShortcutCommand>.unmodifiable(value);
        _shortcutsLoaded = true;
      },
      clearFuture: () => _shortcutsFuture = null,
    );
    _shortcutsFuture = future;
    return future;
  }

  Future<void> _loadTemplates({bool force = false}) {
    if (!force && _templatesFuture != null) return _templatesFuture!;
    final generation = ++_templatesGeneration;
    final future = _loadResource<List<CommandTemplate>>(
      isCurrent: () => generation == _templatesGeneration,
      load: _delegate.listCommandTemplates,
      apply: (value) {
        _templates = List<CommandTemplate>.unmodifiable(value);
        _templatesLoaded = true;
      },
      clearFuture: () => _templatesFuture = null,
    );
    _templatesFuture = future;
    return future;
  }

  Future<void> _loadExtensions({bool force = false}) {
    if (!force && _extensionsFuture != null) return _extensionsFuture!;
    final generation = ++_extensionsGeneration;
    final future = _loadResource<List<ExtensionSummary>>(
      isCurrent: () => generation == _extensionsGeneration,
      load: _delegate.listExtensions,
      apply: (value) {
        _extensions = List<ExtensionSummary>.unmodifiable(value);
        _extensionsLoaded = true;
      },
      clearFuture: () => _extensionsFuture = null,
    );
    _extensionsFuture = future;
    return future;
  }

  Future<void> _loadResource<T>({
    required bool Function() isCurrent,
    required Future<T> Function() load,
    required void Function(T value) apply,
    required void Function() clearFuture,
  }) async {
    _beginLoad();
    try {
      final value = await load();
      if (!_disposed && isCurrent()) {
        apply(value);
      }
    } catch (error) {
      if (!_disposed && isCurrent()) _error = error;
      rethrow;
    } finally {
      if (!_disposed) {
        if (isCurrent()) clearFuture();
        _finishLoad();
      }
    }
  }

  void _beginLoad() {
    if (_disposed) return;
    _pendingLoads++;
    _error = null;
    _notifyIfActive();
  }

  void _finishLoad() {
    if (_disposed) return;
    if (_pendingLoads > 0) _pendingLoads--;
    _notifyIfActive();
  }

  void _notifyIfActive() {
    if (!_disposed) notifyListeners();
  }
}
