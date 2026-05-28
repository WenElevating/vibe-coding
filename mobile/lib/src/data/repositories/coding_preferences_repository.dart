import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CodingPreferencesRepository extends ChangeNotifier {
  static const permissionModeStorageKey = 'coding.permissionMode';

  String _permissionMode = 'auto';
  bool _loading = false;
  Object? _error;
  bool _disposed = false;

  String get permissionMode => _permissionMode;
  bool get loading => _loading;
  Object? get error => _error;

  Future<void> load() async {
    if (_disposed) return;
    _loading = true;
    _error = null;
    _notifyListenersIfActive();
    try {
      final prefs = await SharedPreferences.getInstance();
      final permissionMode =
          normalizePermissionMode(prefs.getString(permissionModeStorageKey));
      if (_disposed) return;
      _permissionMode = permissionMode;
    } catch (error) {
      if (_disposed) return;
      _error = error;
      rethrow;
    } finally {
      if (!_disposed) {
        _loading = false;
        _notifyListenersIfActive();
      }
    }
  }

  Future<void> setPermissionMode(String value) async {
    if (_disposed) return;
    final normalized = normalizePermissionMode(value);
    _permissionMode = normalized;
    _error = null;
    _notifyListenersIfActive();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(permissionModeStorageKey, normalized);
    } catch (error) {
      if (_disposed) return;
      _error = error;
      _notifyListenersIfActive();
      rethrow;
    }
  }

  static String normalizePermissionMode(String? value) =>
      value == 'default' ? 'default' : 'auto';

  void _notifyListenersIfActive() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
