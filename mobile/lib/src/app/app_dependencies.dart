import '../data/repositories/daemon_connection_config_repository.dart';
import '../data/repositories/daemon_adapter_repository.dart';
import '../data/repositories/daemon_auth_repository.dart';
import '../data/repositories/daemon_conversation_repository.dart';
import '../data/repositories/daemon_diagnostics_repository.dart';
import '../data/repositories/daemon_run_repository.dart';
import '../data/repositories/daemon_workspace_repository.dart';
import '../domain/repositories/adapter_repository.dart';
import '../domain/repositories/auth_repository.dart';
import '../domain/repositories/conversation_repository.dart';
import '../domain/repositories/diagnostics_repository.dart';
import '../domain/repositories/run_repository.dart';
import '../domain/repositories/workspace_repository.dart';
import '../models/protocol.dart';
import '../services/asr_model_manager.dart';
import '../services/daemon_client.dart';
import '../services/daemon_connection_config_store.dart';
import '../services/device_identity_store.dart';
import '../services/speech_input_service.dart';
import '../ui/features/connection/view_models/daemon_connection_view_model.dart';
import '../ui/features/diagnostics/diagnostics.dart';
import '../ui/features/run_detail/run_detail.dart';
import '../ui/features/workbench/workbench_dependencies.dart';
import '../workflows/connection/daemon_connection_workflow.dart';

class AppDependencies {
  AppDependencies({
    required this.network,
    required this.data,
    required this.domain,
    required this.features,
  });

  factory AppDependencies.createDefault() {
    final network = NetworkDependencies.createDefault();
    final data = DataDependencies.createDefault();
    final domain = DomainDependencies.createDefault(
      data: data,
      network: network,
    );
    final features = FeatureDependencies.createDefault(
      data: data,
      domain: domain,
    );
    return AppDependencies(
      network: network,
      data: data,
      domain: domain,
      features: features,
    );
  }

  final NetworkDependencies network;
  final DataDependencies data;
  final DomainDependencies domain;
  final FeatureDependencies features;
}

class NetworkDependencies {
  NetworkDependencies({
    required this.tokenStore,
    required this.deviceIdentityStore,
  });

  factory NetworkDependencies.createDefault() => NetworkDependencies(
        tokenStore: MemoryTokenStore(),
        deviceIdentityStore: SharedPreferencesDeviceIdentityStore(),
      );

  final SecureTokenStore tokenStore;
  final DeviceIdentityStore deviceIdentityStore;
}

class DataDependencies {
  DataDependencies({required this.connectionConfigRepository});

  factory DataDependencies.createDefault() {
    final connectionConfigStore = DaemonConnectionConfigStore();
    return DataDependencies(
      connectionConfigRepository:
          DaemonConnectionConfigRepository(store: connectionConfigStore),
    );
  }

  final DaemonConnectionConfigRepository connectionConfigRepository;

  ConnectedDataDependencies forDaemonClient(DaemonClient client) =>
      ConnectedDataDependencies(
        authRepository: DaemonAuthRepository(client: client),
        adapterRepository: DaemonAdapterRepository(client: client),
        conversationRepository: DaemonConversationRepository(client: client),
        diagnosticsRepository: DaemonDiagnosticsRepository(client: client),
        runRepository: DaemonRunRepository(client: client),
        workspaceRepository: DaemonWorkspaceRepository(client: client),
      );
}

class ConnectedDataDependencies {
  ConnectedDataDependencies({
    required this.authRepository,
    required this.adapterRepository,
    required this.conversationRepository,
    required this.diagnosticsRepository,
    required this.runRepository,
    required this.workspaceRepository,
  });

  final AuthRepository authRepository;
  final AdapterRepository adapterRepository;
  final ConversationRepository conversationRepository;
  final DiagnosticsRepository diagnosticsRepository;
  final RunRepository runRepository;
  final WorkspaceRepository workspaceRepository;
}

class DomainDependencies {
  DomainDependencies({required this.connectionWorkflow});

  factory DomainDependencies.createDefault({
    required DataDependencies data,
    required NetworkDependencies network,
  }) =>
      DomainDependencies(
        connectionWorkflow: DaemonConnectionWorkflow(
          configRepository: data.connectionConfigRepository,
          tokenStore: network.tokenStore,
          deviceIdentityStore: network.deviceIdentityStore,
        ),
      );

  final DaemonConnectionWorkflow connectionWorkflow;
}

class FeatureDependencies {
  FeatureDependencies({
    required this.createDaemonConnectionViewModel,
    required this.createDiagnosticsViewModel,
    required this.createRunDetailViewModel,
    required this.createWorkbenchDependencies,
  });

  factory FeatureDependencies.createDefault({
    required DataDependencies data,
    required DomainDependencies domain,
  }) =>
      FeatureDependencies(
        createDaemonConnectionViewModel: () => DaemonConnectionViewModel(
          configRepository: data.connectionConfigRepository,
          connectToDaemon: domain.connectionWorkflow,
        ),
        createDiagnosticsViewModel: (connectedData) => DiagnosticsViewModel(
          repository: connectedData.diagnosticsRepository,
        ),
        createRunDetailViewModel: (connectedData, run) => RunDetailViewModel(
          run: run,
          runRepository: connectedData.runRepository,
        ),
        createWorkbenchDependencies: (client) {
          final connectedData = data.forDaemonClient(client);
          return WorkbenchDependencies(
            asrModelManager:
                AsrModelManager(client: client.createAsrModelClient()),
            conversationRepository: connectedData.conversationRepository,
            diagnosticsRepository: connectedData.diagnosticsRepository,
            runRepository: connectedData.runRepository,
            speechInputServiceBuilder: (modelDirectory) =>
                SherpaSpeechInputService(modelDirectory: modelDirectory),
            workspaceRepository: connectedData.workspaceRepository,
          );
        },
      );

  final DaemonConnectionViewModel Function() createDaemonConnectionViewModel;
  final DiagnosticsViewModel Function(ConnectedDataDependencies connectedData)
      createDiagnosticsViewModel;
  final RunDetailViewModel Function(
    ConnectedDataDependencies connectedData,
    RunSummary run,
  ) createRunDetailViewModel;
  final WorkbenchDependencies Function(DaemonClient client)
      createWorkbenchDependencies;
}
