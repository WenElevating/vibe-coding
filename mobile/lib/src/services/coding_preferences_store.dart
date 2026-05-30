import 'package:shared_preferences/shared_preferences.dart';

class CodingPreferencesStore {
  static const permissionModeStorageKey = 'coding.permissionMode';

  Future<String> loadPermissionMode() async {
    final prefs = await SharedPreferences.getInstance();
    return normalizePermissionMode(prefs.getString(permissionModeStorageKey));
  }

  Future<void> savePermissionMode(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        permissionModeStorageKey, normalizePermissionMode(value));
  }

  static String normalizePermissionMode(String? value) {
    return value == 'auto' ? 'auto' : 'default';
  }
}
