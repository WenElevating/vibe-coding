import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/services/coding_preferences_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('loadPermissionMode defaults missing preference to default', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = CodingPreferencesStore();

    final permissionMode = await store.loadPermissionMode();

    expect(permissionMode, 'default');
  });

  test('savePermissionMode normalizes unknown values to default', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = CodingPreferencesStore();

    await store.savePermissionMode('invalid');

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(CodingPreferencesStore.permissionModeStorageKey),
      'default',
    );
  });
}
