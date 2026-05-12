import '../../domain/repositories/auth_repository.dart';
import '../../models/protocol.dart';
import '../../services/daemon_client.dart';

class DaemonAuthRepository implements AuthRepository {
  DaemonAuthRepository({required DaemonClient client}) : _client = client;

  final DaemonClient _client;

  @override
  Future<DaemonHealth> health() => _client.health();

  @override
  Future<DaemonVersionInfo> version() => _client.version();

  @override
  Future<String> createPairingCode() => _client.createPairingCode();

  @override
  Future<void> pair({
    required String code,
    String label = 'mobile',
    String? deviceId,
  }) =>
      _client.pair(code: code, label: label, deviceId: deviceId);

  @override
  Future<void> refreshToken() => _client.refreshToken();

  @override
  Future<void> revokeCurrentDevice() => _client.revokeCurrentDevice();
}
