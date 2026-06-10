import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/services/device_identity_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('persistent device identity store reuses the same uuid v4', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = SharedPreferencesDeviceIdentityStore();

    final first = await store.readOrCreateDeviceId();
    final second = await store.readOrCreateDeviceId();

    expect(first, second);
    expect(
      first,
      matches(RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
    );
  });

  test('persistent device identity store shares concurrent first read',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = SharedPreferencesDeviceIdentityStore();

    final ids = await Future.wait<String>(List<Future<String>>.generate(
      20,
      (_) => store.readOrCreateDeviceId(),
    ));

    expect(ids.toSet(), hasLength(1));
    expect(ids.first, await store.readOrCreateDeviceId());
  });

  test('memory device identity store reuses injected device id', () async {
    final store = MemoryDeviceIdentityStore(
        deviceId: '11111111-1111-4111-8111-111111111111');

    final first = await store.readOrCreateDeviceId();
    final second = await store.readOrCreateDeviceId();

    expect(first, '11111111-1111-4111-8111-111111111111');
    expect(second, first);
  });
}
