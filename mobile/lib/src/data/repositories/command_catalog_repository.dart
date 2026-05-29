import 'package:flutter/foundation.dart';

import '../../domain/repositories/adapter_repository.dart';
import '../../models/protocol.dart';

class CommandCatalogRepository extends ChangeNotifier {
  CommandCatalogRepository({required AdapterRepository delegate})
      : _delegate = delegate;

  final AdapterRepository _delegate;
  List<ShortcutCommand> _shortcuts = const <ShortcutCommand>[];
  List<CommandTemplate> _templates = const <CommandTemplate>[];
  List<ExtensionSummary> _extensions = const <ExtensionSummary>[];
  bool _loading = false;
  bool _loaded = false;
  Object? _error;
  Future<void>? _loadFuture;
  int _generation = 0;
  bool _disposed = false;

  List<ShortcutCommand> get shortcuts => List.unmodifiable(_shortcuts);
  List<CommandTemplate> get templates => List.unmodifiable(_templates);
  List<ExtensionSummary> get extensions => List.unmodifiable(_extensions);
  bool get loading => _loading;
  bool get loaded => _loaded;
  Object? get error => _error;

  Future<void> load({bool force = false}) {
    if (_loaded && !force) return Future<void>.value();
    final current = _loadFuture;
    if (current != null) return current;
    final generation = ++_generation;
    _loading = true;
    _error = null;
    _notifyIfActive();
    final future = Future.wait<void>([
      _loadShortcuts(generation),
      _loadTemplates(generation),
      _loadExtensions(generation),
    ]).then<void>((_) {
      if (_disposed || generation != _generation) return;
      _loaded = true;
    }).catchError((Object error) {
      if (!_disposed && generation == _generation) _error = error;
      throw error;
    }).whenComplete(() {
      if (_disposed || generation != _generation) return;
      _loading = false;
      _loadFuture = null;
      _notifyIfActive();
    });
    _loadFuture = future;
    return future;
  }

  Future<List<ShortcutCommand>> listShortcuts() async {
    await load();
    return shortcuts;
  }

  Future<List<CommandTemplate>> listCommandTemplates() async {
    await load();
    return templates;
  }

  Future<List<ExtensionSummary>> listExtensions() async {
    await load();
    return extensions;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    super.dispose();
  }

  Future<void> _loadShortcuts(int generation) async {
    final shortcuts = await _delegate.listShortcuts();
    if (_disposed || generation != _generation) return;
    _shortcuts = List<ShortcutCommand>.unmodifiable(shortcuts);
  }

  Future<void> _loadTemplates(int generation) async {
    final templates = await _delegate.listCommandTemplates();
    if (_disposed || generation != _generation) return;
    _templates = List<CommandTemplate>.unmodifiable(templates);
  }

  Future<void> _loadExtensions(int generation) async {
    final extensions = await _delegate.listExtensions();
    if (_disposed || generation != _generation) return;
    _extensions = List<ExtensionSummary>.unmodifiable(extensions);
  }

  void _notifyIfActive() {
    if (!_disposed) notifyListeners();
  }
}
