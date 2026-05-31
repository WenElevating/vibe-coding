import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/data/repositories/coding_preferences_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('load normalizes persisted permission mode and notifies', () async {
    SharedPreferences.setMockInitialValues(
      <String, Object>{
        CodingPreferencesRepository.permissionModeStorageKey: 'default',
      },
    );
    final repository = CodingPreferencesRepository();
    var notifications = 0;
    repository.addListener(() => notifications++);

    await repository.load();

    expect(repository.permissionMode, 'default');
    expect(repository.loading, isFalse);
    expect(repository.error, isNull);
    expect(notifications, greaterThanOrEqualTo(1));
  });

  test('load uses default permission mode when no preference is persisted',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final repository = CodingPreferencesRepository();

    await repository.load();

    expect(repository.permissionMode, 'default');
    expect(repository.keepConversationEventsInBackground, isFalse);
  });

  test(
      'load preserves permission mode when background events preference is old',
      () async {
    SharedPreferences.setMockInitialValues(
      <String, Object>{
        CodingPreferencesRepository.permissionModeStorageKey: 'auto',
      },
    );
    final repository = CodingPreferencesRepository();

    await repository.load();

    expect(repository.permissionMode, 'auto');
    expect(repository.keepConversationEventsInBackground, isFalse);
  });

  test('load treats unknown persisted permission mode as default', () async {
    SharedPreferences.setMockInitialValues(
      <String, Object>{
        CodingPreferencesRepository.permissionModeStorageKey: 'invalid',
      },
    );
    final repository = CodingPreferencesRepository();

    await repository.load();

    expect(repository.permissionMode, 'default');
  });

  test('setPermissionMode persists normalized value and notifies', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final repository = CodingPreferencesRepository();
    var notifications = 0;
    repository.addListener(() => notifications++);

    await repository.setPermissionMode('invalid');

    final prefs = await SharedPreferences.getInstance();
    expect(repository.permissionMode, 'default');
    expect(
      prefs.getString(CodingPreferencesRepository.permissionModeStorageKey),
      'default',
    );
    expect(repository.error, isNull);
    expect(notifications, greaterThanOrEqualTo(1));
  });

  test('setPermissionMode preserves default value', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final repository = CodingPreferencesRepository();

    await repository.setPermissionMode('default');

    final prefs = await SharedPreferences.getInstance();
    expect(repository.permissionMode, 'default');
    expect(
      prefs.getString(CodingPreferencesRepository.permissionModeStorageKey),
      'default',
    );
  });

  test('setKeepConversationEventsInBackground persists value and notifies',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final repository = CodingPreferencesRepository();
    var notifications = 0;
    repository.addListener(() => notifications++);

    await repository.setKeepConversationEventsInBackground(true);

    final prefs = await SharedPreferences.getInstance();
    expect(repository.keepConversationEventsInBackground, isTrue);
    expect(
      prefs.getBool(
        CodingPreferencesRepository
            .keepConversationEventsInBackgroundStorageKey,
      ),
      isTrue,
    );
    expect(notifications, greaterThanOrEqualTo(1));

    await repository.setKeepConversationEventsInBackground(false);

    expect(repository.keepConversationEventsInBackground, isFalse);
    expect(
      prefs.getBool(
        CodingPreferencesRepository
            .keepConversationEventsInBackgroundStorageKey,
      ),
      isFalse,
    );
  });

  test('load completion after dispose is ignored', () async {
    SharedPreferences.setMockInitialValues(
      <String, Object>{
        CodingPreferencesRepository.permissionModeStorageKey: 'default',
      },
    );
    final repository = CodingPreferencesRepository();

    final load = repository.load();
    repository.dispose();

    await load;
  });
}
