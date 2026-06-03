import 'package:shared_preferences/shared_preferences.dart';

class CodingPreferencesStore {
  static const permissionModeStorageKey = 'coding.permissionMode';
  static const expandToolDetailsStorageKey = 'coding.expandToolDetails';

  Future<String> loadPermissionMode() async {
    final prefs = await SharedPreferences.getInstance();
    return normalizePermissionMode(prefs.getString(permissionModeStorageKey));
  }

  Future<void> savePermissionMode(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        permissionModeStorageKey, normalizePermissionMode(value));
  }

  Future<bool> loadExpandToolDetails() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(expandToolDetailsStorageKey) ?? false;
  }

  Future<void> saveExpandToolDetails(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(expandToolDetailsStorageKey, value);
  }

  static String normalizePermissionMode(String? value) {
    return value == 'auto' ? 'auto' : 'default';
  }
}
