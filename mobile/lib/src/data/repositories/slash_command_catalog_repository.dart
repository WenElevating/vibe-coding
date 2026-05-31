import 'package:flutter/foundation.dart';

import '../models/adapter_models.dart';

typedef SlashCommandLoader = Future<List<SlashCommand>> Function(
  String adapterId, {
  String? workspaceId,
});

class SlashCommandCatalogRepository extends ChangeNotifier {
  SlashCommandCatalogRepository({required SlashCommandLoader client})
      : _client = client;

  final SlashCommandLoader _client;

  final Map<String, List<SlashCommand>> _commandsByAdapter =
      <String, List<SlashCommand>>{};
  final Map<String, Object?> _errorsByAdapter = <String, Object?>{};
  final Map<String, Future<List<SlashCommand>>> _loadsByAdapter =
      <String, Future<List<SlashCommand>>>{};
  final Map<String, int> _generationsByAdapter = <String, int>{};
  final Set<String> _loadedAdapters = <String>{};
  bool _disposed = false;

  bool get loading => _loadsByAdapter.isNotEmpty;

  List<SlashCommand> commandsForAdapter(
    String adapterId, {
    String? workspaceId,
  }) {
    final key = _cacheKey(adapterId, workspaceId);
    return List<SlashCommand>.unmodifiable(
      _commandsByAdapter[key] ?? const <SlashCommand>[],
    );
  }

  Object? errorForAdapter(String adapterId, {String? workspaceId}) =>
      _errorsByAdapter[_cacheKey(adapterId, workspaceId)];

  bool hasLoadedAdapter(String adapterId, {String? workspaceId}) =>
      _loadedAdapters.contains(_cacheKey(adapterId, workspaceId));

  Future<List<SlashCommand>> loadForAdapter(
    String adapterId, {
    String? workspaceId,
    bool force = false,
  }) {
    final adapterKey = _adapterKey(adapterId);
    final key = _cacheKey(adapterId, workspaceId);
    if (adapterKey.isEmpty) {
      return Future<List<SlashCommand>>.value(const <SlashCommand>[]);
    }
    if (!force && _loadedAdapters.contains(key)) {
      return Future<List<SlashCommand>>.value(
        commandsForAdapter(adapterKey, workspaceId: workspaceId),
      );
    }
    final existing = _loadsByAdapter[key];
    if (!force && existing != null) return existing;

    final generation = (_generationsByAdapter[key] ?? 0) + 1;
    _generationsByAdapter[key] = generation;
    _errorsByAdapter.remove(key);

    final future =
        _client(adapterKey, workspaceId: workspaceId).then((commands) {
      if (_disposed || _generationsByAdapter[key] != generation) {
        return commandsForAdapter(adapterKey, workspaceId: workspaceId);
      }
      final normalized = _normalizeCommands(commands);
      _commandsByAdapter[key] = List<SlashCommand>.unmodifiable(normalized);
      _loadedAdapters.add(key);
      return commandsForAdapter(adapterKey, workspaceId: workspaceId);
    }).catchError((Object error) {
      if (!_disposed && _generationsByAdapter[key] == generation) {
        _errorsByAdapter[key] = error;
      }
      throw error;
    }).whenComplete(() {
      if (_disposed) return;
      if (_generationsByAdapter[key] == generation) {
        _loadsByAdapter.remove(key);
      }
      _notifyIfActive();
    });
    _loadsByAdapter[key] = future;
    _notifyIfActive();
    return future;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final key in _generationsByAdapter.keys.toList(growable: false)) {
      _generationsByAdapter[key] = (_generationsByAdapter[key] ?? 0) + 1;
    }
    super.dispose();
  }

  List<SlashCommand> _normalizeCommands(List<SlashCommand> commands) {
    final byKey = <String, SlashCommand>{};
    for (final command in commands) {
      final normalized = SlashCommand(
        command: normalizeSlashCommand(command.command),
        description: command.description,
      );
      final key = normalized.matchingKey;
      if (key.isEmpty || byKey.containsKey(key)) continue;
      byKey[key] = normalized;
    }
    final result = byKey.values.toList(growable: false);
    result.sort((a, b) => a.matchingKey.compareTo(b.matchingKey));
    return result;
  }

  String _adapterKey(String value) => value.trim().toLowerCase();

  String _cacheKey(String adapterId, String? workspaceId) {
    final adapter = _adapterKey(adapterId);
    final workspace = (workspaceId ?? '').trim();
    return workspace.isEmpty ? adapter : '$adapter\u0000$workspace';
  }

  void _notifyIfActive() {
    if (!_disposed) notifyListeners();
  }
}
