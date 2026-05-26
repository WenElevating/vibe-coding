import 'package:shared_preferences/shared_preferences.dart';

class RecentDaemonAddressStore {
  static const storageKey = 'daemonConnection.recentAddresses';
  static const maxRecentAddresses = 8;

  Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return List<String>.unmodifiable(
      _sanitize(prefs.getStringList(storageKey) ?? const <String>[]),
    );
  }

  Future<void> record(String addressInput) async {
    final trimmed = addressInput.trim();
    if (trimmed.isEmpty) return;

    final current = await load();
    final dedupeKey = _dedupeKey(trimmed);
    final next = <String>[
      trimmed,
      for (final address in current)
        if (_dedupeKey(address) != dedupeKey) address,
    ].take(maxRecentAddresses).toList(growable: false);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(storageKey, next);
  }

  List<String> _sanitize(List<String> values) {
    final sanitized = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) continue;

      if (seen.add(_dedupeKey(trimmed))) {
        sanitized.add(trimmed);
      }
      if (sanitized.length == maxRecentAddresses) break;
    }
    return sanitized;
  }

  String _dedupeKey(String value) => value.trim().toLowerCase();
}
