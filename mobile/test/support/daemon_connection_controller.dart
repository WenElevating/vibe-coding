import 'package:lan_ai_cli_control/src/data/repositories/daemon_connection_config_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/recent_daemon_address_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/recent_daemon_address_repository.dart';
import 'package:lan_ai_cli_control/src/domain/use_cases/connect_to_daemon_use_case.dart';
import 'package:lan_ai_cli_control/src/services/daemon_client.dart';
import 'package:lan_ai_cli_control/src/services/daemon_connection_config_store.dart';
import 'package:lan_ai_cli_control/src/services/recent_daemon_address_store.dart';
import 'package:lan_ai_cli_control/src/shell/app_snapshot.dart';
import 'package:lan_ai_cli_control/src/ui/features/connection/view_models/daemon_connection_view_model.dart';
import 'package:lan_ai_cli_control/src/workflows/connection/daemon_connection_workflow.dart';

export 'package:lan_ai_cli_control/src/ui/features/connection/view_models/daemon_connection_view_model.dart'
    show
        DaemonConnectionFailureCode,
        DaemonConnectionStatus,
        DiagnosticRecorder,
        daemonConnectionErrorSummary,
        noopDiagnosticRecorder;

typedef DaemonSnapshotLoader = Future<AppSnapshot> Function(
  DaemonClient client,
);

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
    super.recordDiagnostic = noopDiagnosticRecorder,
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
        );
}
