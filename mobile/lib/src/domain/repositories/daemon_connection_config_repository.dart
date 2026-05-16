import '../models/daemon_connection_config.dart';

abstract interface class DaemonConnectionConfigRepository {
  Future<DaemonConnectionConfig> load();

  Future<void> save(DaemonConnectionConfig config);
}
