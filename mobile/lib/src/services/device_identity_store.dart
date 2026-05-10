import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

abstract class DeviceIdentityStore {
  Future<String> readOrCreateDeviceId();
}

class SharedPreferencesDeviceIdentityStore implements DeviceIdentityStore {
  static const String _deviceIdKey = 'daemon.deviceId';

  @override
  Future<String> readOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final deviceId = _generateUuidV4();
    await prefs.setString(_deviceIdKey, deviceId);
    return deviceId;
  }
}

class MemoryDeviceIdentityStore implements DeviceIdentityStore {
  MemoryDeviceIdentityStore({String? deviceId}) : _deviceId = deviceId;

  String? _deviceId;

  @override
  Future<String> readOrCreateDeviceId() async =>
      _deviceId ??= _generateUuidV4();
}

String _generateUuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex =
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
