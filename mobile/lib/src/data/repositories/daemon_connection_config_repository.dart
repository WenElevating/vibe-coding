import '../../services/daemon_connection_config.dart';
import '../../services/daemon_connection_config_store.dart';

class DaemonConnectionConfigRepository {
  DaemonConnectionConfigRepository({required DaemonConnectionConfigStore store})
      : _store = store;

  final DaemonConnectionConfigStore _store;

  Future<DaemonConnectionConfig> load() => _store.load();

  Future<void> save(DaemonConnectionConfig config) => _store.save(config);
}
