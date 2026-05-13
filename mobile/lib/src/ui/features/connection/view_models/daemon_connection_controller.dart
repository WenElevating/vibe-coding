import '../../../../data/repositories/daemon_connection_config_repository.dart';
import '../../../../domain/use_cases/connect_to_daemon_use_case.dart';
import '../../../../services/daemon_client.dart';
import '../../../../services/daemon_connection_config_store.dart';
import '../../../../shell/app_snapshot.dart';
import '../../../../workflows/connection/daemon_connection_workflow.dart';
import 'daemon_connection_view_model.dart';

export 'daemon_connection_view_model.dart'
    show DaemonConnectionStatus, daemonConnectionErrorSummary;

typedef DaemonSnapshotLoader = Future<AppSnapshot> Function(
    DaemonClient client);

class DaemonConnectionController extends DaemonConnectionViewModel {
  DaemonConnectionController({
    required DaemonConnectionConfigStore store,
    required SecureTokenStore tokenStore,
    ConnectToDaemonUseCase<DaemonClient>? connectToDaemon,
    DaemonSnapshotLoader? snapshotLoader,
    DaemonHealthProbe? healthProbe,
    Duration? connectionTimeout,
  }) : this._fromRepo(
          configRepository: DaemonConnectionConfigRepository(store: store),
          tokenStore: tokenStore,
          connectToDaemon: connectToDaemon,
          snapshotLoader: snapshotLoader,
          healthProbe: healthProbe,
          connectionTimeout: connectionTimeout,
        );

  DaemonConnectionController._fromRepo({
    required super.configRepository,
    required SecureTokenStore tokenStore,
    ConnectToDaemonUseCase<DaemonClient>? connectToDaemon,
    DaemonSnapshotLoader? snapshotLoader,
    DaemonHealthProbe? healthProbe,
    Duration? connectionTimeout,
  }) : super(
          connectToDaemon: connectToDaemon ??
              DaemonConnectionWorkflow(
                configRepository: configRepository,
                tokenStore: tokenStore,
                initialDataLoader: snapshotLoader,
                healthProbe: healthProbe,
              ),
          connectionTimeout: connectionTimeout ?? const Duration(seconds: 30),
        );
}
