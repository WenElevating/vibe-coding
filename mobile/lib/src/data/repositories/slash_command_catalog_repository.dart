import 'package:flutter/foundation.dart';

import '../models/adapter_models.dart';

typedef SlashCommandLoader = Future<List<SlashCommand>> Function(
  String adapterId,
);

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

  List<SlashCommand> commandsForAdapter(String adapterId) {
    final key = _adapterKey(adapterId);
    return List<SlashCommand>.unmodifiable(
      _commandsByAdapter[key] ?? const <SlashCommand>[],
    );
  }

  Object? errorForAdapter(String adapterId) =>
      _errorsByAdapter[_adapterKey(adapterId)];

  bool hasLoadedAdapter(String adapterId) =>
      _loadedAdapters.contains(_adapterKey(adapterId));

  Future<List<SlashCommand>> loadForAdapter(
    String adapterId, {
    bool force = false,
  }) {
    final key = _adapterKey(adapterId);
    if (key.isEmpty) {
      return Future<List<SlashCommand>>.value(const <SlashCommand>[]);
    }
    if (!force && _loadedAdapters.contains(key)) {
      return Future<List<SlashCommand>>.value(commandsForAdapter(key));
    }
    final existing = _loadsByAdapter[key];
    if (!force && existing != null) return existing;

    final generation = (_generationsByAdapter[key] ?? 0) + 1;
    _generationsByAdapter[key] = generation;
    _errorsByAdapter.remove(key);

    final future = _client(key).then((commands) {
      if (_disposed || _generationsByAdapter[key] != generation) {
        return commandsForAdapter(key);
      }
      final normalized = _normalizeCommands(commands);
      _commandsByAdapter[key] = List<SlashCommand>.unmodifiable(normalized);
      _loadedAdapters.add(key);
      return commandsForAdapter(key);
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

  void _notifyIfActive() {
    if (!_disposed) notifyListeners();
  }
}
