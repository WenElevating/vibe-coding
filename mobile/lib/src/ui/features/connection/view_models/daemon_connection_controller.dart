import '../../../../data/repositories/daemon_connection_config_repository.dart';
import '../../../../data/repositories/recent_daemon_address_repository.dart';
import '../../../../domain/repositories/recent_daemon_address_repository.dart';
import '../../../../domain/use_cases/connect_to_daemon_use_case.dart';
import '../../../../services/daemon_client.dart';
import '../../../../services/daemon_connection_config_store.dart';
import '../../../../services/recent_daemon_address_store.dart';
import '../../../../shell/app_snapshot.dart';
import '../../../../workflows/connection/daemon_connection_workflow.dart';
import 'daemon_connection_view_model.dart';

export 'daemon_connection_view_model.dart'
    show
        DaemonConnectionStatus,
        DiagnosticRecorder,
        daemonConnectionErrorSummary,
        noopDiagnosticRecorder;

typedef DaemonSnapshotLoader = Future<AppSnapshot> Function(
    DaemonClient client);

class DaemonConnectionController extends DaemonConnectionViewModel {
  DaemonConnectionController({
    required DaemonConnectionConfigStore store,
    required SecureTokenStore tokenStore,
    ConnectToDaemonUseCase<DaemonClient>? connectToDaemon,
    RecentDaemonAddressRepository? recentAddressRepository,
    DiagnosticRecorder recordDiagnostic = noopDiagnosticRecorder,
    DaemonSnapshotLoader? snapshotLoader,
    DaemonHealthProbe? healthProbe,
    Duration? connectionTimeout,
  }) : this._fromRepo(
          configRepository: StoreDaemonConnectionConfigRepository(store: store),
          recentAddressRepository: recentAddressRepository ??
              StoreRecentDaemonAddressRepository(
                store: RecentDaemonAddressStore(),
              ),
          tokenStore: tokenStore,
          connectToDaemon: connectToDaemon,
          recordDiagnostic: recordDiagnostic,
          snapshotLoader: snapshotLoader,
          healthProbe: healthProbe,
          connectionTimeout: connectionTimeout,
        );

  DaemonConnectionController._fromRepo({
    required super.configRepository,
    required super.recentAddressRepository,
    required SecureTokenStore tokenStore,
    ConnectToDaemonUseCase<DaemonClient>? connectToDaemon,
    DiagnosticRecorder recordDiagnostic = noopDiagnosticRecorder,
    DaemonSnapshotLoader? snapshotLoader,
    DaemonHealthProbe? healthProbe,
    Duration? connectionTimeout,
  }) : super(
          connectToDaemon: connectToDaemon ??
              DaemonConnectionWorkflow(
                configRepository: configRepository,
                tokenStore: tokenStore,
                initialDataLoader: snapshotLoader == null
                    ? null
                    : (client) async =>
                        (await snapshotLoader(client)).toDaemonInitialData(),
                healthProbe: healthProbe,
              ),
          connectionTimeout: connectionTimeout ?? const Duration(seconds: 30),
          recordDiagnostic: recordDiagnostic,
        );
}
