import '../../models/protocol.dart';
import '../../services/device_identity_store.dart';

abstract class AuthService {
  Future<DaemonHealth> health();
  Future<DaemonVersionInfo> version();

  Future<String> createPairingCode();

  Future<void> pair({
    required String code,
    String label,
    String? deviceId,
  });

  Future<void> refreshToken();

  Future<void> ensurePaired({
    required DeviceIdentityStore deviceIdentityStore,
    String label,
  });

  Future<void> revokeCurrentDevice();
}
