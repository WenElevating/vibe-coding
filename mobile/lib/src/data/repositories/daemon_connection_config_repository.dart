import '../../domain/models/daemon_connection_config.dart';
import '../../domain/repositories/daemon_connection_config_repository.dart';
import '../../services/daemon_connection_config_store.dart';

class StoreDaemonConnectionConfigRepository
    implements DaemonConnectionConfigRepository {
  StoreDaemonConnectionConfigRepository(
      {required DaemonConnectionConfigStore store})
      : _store = store;

  final DaemonConnectionConfigStore _store;

  @override
  Future<DaemonConnectionConfig> load() => _store.load();

  @override
  Future<void> save(DaemonConnectionConfig config) => _store.save(config);
}
