import '../data/repositories/daemon_connection_config_repository.dart';
import '../services/daemon_client.dart';
import '../services/daemon_connection_config_store.dart';
import '../shell/app_snapshot.dart';
import '../ui/features/connection/view_models/daemon_connection_view_model.dart';
import '../workflows/connection/daemon_connection_workflow.dart';

export '../ui/features/connection/view_models/daemon_connection_view_model.dart'
    show DaemonConnectionStatus, daemonConnectionErrorSummary;

typedef DaemonSnapshotLoader = Future<AppSnapshot> Function(
    DaemonClient client);

class DaemonConnectionController extends DaemonConnectionViewModel {
  DaemonConnectionController({
    required DaemonConnectionConfigStore store,
    required SecureTokenStore tokenStore,
    DaemonSnapshotLoader? snapshotLoader,
    DaemonHealthProbe? healthProbe,
    Duration? connectionTimeout,
  }) : this._fromRepo(
          configRepository: DaemonConnectionConfigRepository(store: store),
          tokenStore: tokenStore,
          snapshotLoader: snapshotLoader,
          healthProbe: healthProbe,
          connectionTimeout: connectionTimeout,
        );

  DaemonConnectionController._fromRepo({
    required DaemonConnectionConfigRepository configRepository,
    required SecureTokenStore tokenStore,
    DaemonSnapshotLoader? snapshotLoader,
    DaemonHealthProbe? healthProbe,
    Duration? connectionTimeout,
  }) : super(
          configRepository: configRepository,
          workflow: DaemonConnectionWorkflow(
            configRepository: configRepository,
            tokenStore: tokenStore,
            initialDataLoader: snapshotLoader,
            healthProbe: healthProbe,
          ),
          connectionTimeout: connectionTimeout,
        );
}
