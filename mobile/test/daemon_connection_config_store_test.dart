import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/domain/models/daemon_connection_config.dart';
import 'package:lan_ai_cli_control/src/services/daemon_connection_config_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('loads fallback config when no values are stored', () async {
    final store = DaemonConnectionConfigStore();

    final config = await store.load();

    expect(config.addressInput, '127.0.0.1:4317');
    expect(config.proxyMode, DaemonProxyMode.direct);
    expect(config.manualProxyInput, '');
  });

  test('saves and loads last successful config', () async {
    final store = DaemonConnectionConfigStore();
    const config = DaemonConnectionConfig(
      addressInput: '192.168.1.23:4317',
      proxyMode: DaemonProxyMode.manual,
      manualProxyInput: 'http://proxy.local:8080',
    );

    await store.save(config);
    final loaded = await store.load();

    expect(loaded.addressInput, config.addressInput);
    expect(loaded.proxyMode, config.proxyMode);
    expect(loaded.manualProxyInput, config.manualProxyInput);
  });
}
