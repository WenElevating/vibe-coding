import '../../models/protocol.dart';

abstract class AuthRepository {
  Future<DaemonHealth> health();
  Future<DaemonVersionInfo> version();

  Future<String> createPairingCode();

  Future<void> pair({
    required String code,
    String label,
    String? deviceId,
  });

  Future<void> refreshToken();

  Future<void> revokeCurrentDevice();
}
