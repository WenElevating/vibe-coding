import 'package:shared_preferences/shared_preferences.dart';

import 'daemon_connection_config.dart';

class DaemonConnectionConfigStore {
  static const _addressKey = 'daemonConnection.addressInput';
  static const _proxyModeKey = 'daemonConnection.proxyMode';
  static const _manualProxyKey = 'daemonConnection.manualProxyInput';

  Future<DaemonConnectionConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return DaemonConnectionConfig(
      addressInput: prefs.getString(_addressKey) ??
          DaemonConnectionConfig.fallback.addressInput,
      proxyMode:
          DaemonProxyMode.fromStorageValue(prefs.getString(_proxyModeKey)),
      manualProxyInput: prefs.getString(_manualProxyKey) ??
          DaemonConnectionConfig.fallback.manualProxyInput,
    );
  }

  Future<void> save(DaemonConnectionConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_addressKey, config.addressInput);
    await prefs.setString(_proxyModeKey, config.proxyMode.storageValue);
    await prefs.setString(_manualProxyKey, config.manualProxyInput);
  }
}
