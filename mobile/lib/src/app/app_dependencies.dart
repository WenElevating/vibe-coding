import 'dart:async';

import 'package:path_provider/path_provider.dart';

import '../data/repositories/daemon_connection_config_repository.dart';
import '../data/repositories/daemon_adapter_repository.dart';
import '../data/repositories/daemon_app_update_repository.dart';
import '../data/repositories/daemon_auth_repository.dart';
import '../data/repositories/daemon_conversation_repository.dart';
import '../data/repositories/daemon_diagnostics_repository.dart';
import '../data/repositories/daemon_run_repository.dart';
import '../data/repositories/daemon_workspace_repository.dart';
import '../data/repositories/recent_daemon_address_repository.dart';
import '../data/repositories/workspace_repository.dart';
import '../domain/repositories/adapter_repository.dart';
import '../domain/repositories/app_update_repository.dart';
import '../domain/repositories/auth_repository.dart';
import '../domain/repositories/conversation_repository.dart';
import '../domain/repositories/daemon_connection_config_repository.dart';
import '../domain/repositories/diagnostics_repository.dart';
import '../domain/repositories/recent_daemon_address_repository.dart';
import '../domain/repositories/run_repository.dart';
import '../models/protocol.dart';
import '../services/android_package_installer.dart';
import '../services/app_update_client.dart';
import '../services/app_update_download_manager.dart';
import '../services/asr_model_manager.dart';
import '../services/daemon_client.dart';
import '../services/daemon_connection_config_store.dart';
import '../services/daemon_notification_client.dart';
import '../services/device_identity_store.dart';
import '../services/recent_daemon_address_store.dart';
import '../services/speech_input_service.dart';
import '../shell/app_snapshot.dart';
import '../ui/features/connection/view_models/daemon_connection_view_model.dart';
import '../ui/features/diagnostics/diagnostics.dart';
import '../ui/features/run_detail/run_detail.dart';
import '../ui/features/settings/settings.dart';
import '../ui/features/workbench/attachments/attachment_preview_cache.dart';
import '../ui/features/workbench/workbench_dependencies.dart';
import '../workflows/app_update_workflow.dart';
import '../workflows/connection/daemon_connection_workflow.dart';

typedef NotificationClientFactory = DaemonNotificationClient Function(
  DaemonClient client,
);

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

  MainTabsDependencies createMainTabsDependencies(DaemonClient client) {
    final connectedData = data.forDaemonClient(client);
    return MainTabsDependencies(
      connectedData: connectedData,
      workbenchDependencies: features.createWorkbenchDependencies(
        client,
        connectedData,
      ),
      featureDependencies: features,
      createAppUpdateViewModel: ({
        required installedVersionCode,
        required installedVersionName,
      }) =>
          features.createAppUpdateViewModel(
        client: client,
        connectedData: connectedData,
        installedVersionCode: installedVersionCode,
        installedVersionName: installedVersionName,
      ),
      loadWorkspaceBootstrap: ({
        required health,
        required workspaces,
        required workspace,
      }) =>
          loadWorkspaceBootstrap(
        client,
        health: health,
        workspaces: workspaces,
        workspace: workspace,
      ),
    );
  }
}

class MainTabsDependencies {
  MainTabsDependencies({
    required this.connectedData,
    required this.workbenchDependencies,
    required this.featureDependencies,
    required this.createAppUpdateViewModel,
    required this.loadWorkspaceBootstrap,
  });

  final ConnectedDataDependencies connectedData;
  final WorkbenchDependencies workbenchDependencies;
  final FeatureDependencies featureDependencies;
  final Future<AppUpdateViewModel> Function({
    required int installedVersionCode,
    required String installedVersionName,
  }) createAppUpdateViewModel;
  final Future<AppSnapshot> Function({
    required DaemonHealth health,
    required List<WorkspaceSummary> workspaces,
    required WorkspaceSummary workspace,
  }) loadWorkspaceBootstrap;
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
  DataDependencies({
    required this.connectionConfigRepository,
    RecentDaemonAddressRepository? recentAddressRepository,
    NotificationClientFactory? createNotificationClient,
  })  : recentAddressRepository = recentAddressRepository ??
            StoreRecentDaemonAddressRepository(
              store: RecentDaemonAddressStore(),
            ),
        createNotificationClient =
            createNotificationClient ?? _createDefaultNotificationClient;

  factory DataDependencies.createDefault() {
    final connectionConfigStore = DaemonConnectionConfigStore();
    final recentAddressStore = RecentDaemonAddressStore();
    return DataDependencies(
      connectionConfigRepository:
          StoreDaemonConnectionConfigRepository(store: connectionConfigStore),
      recentAddressRepository:
          StoreRecentDaemonAddressRepository(store: recentAddressStore),
    );
  }

  final DaemonConnectionConfigRepository connectionConfigRepository;
  final RecentDaemonAddressRepository recentAddressRepository;
  final NotificationClientFactory createNotificationClient;

  ConnectedDataDependencies forDaemonClient(DaemonClient client) {
    final notificationClient = createNotificationClient(client);
    final appUpdateClient = AppUpdateClient.authorized(
      baseUri: client.baseUri,
      authorizedGet: (path, {required headers}) =>
          client.getAuthorizedRaw(path, headers: headers),
      authorizedStreamSend: client.sendAuthorizedStream,
    );
    return ConnectedDataDependencies(
      authRepository: DaemonAuthRepository(client: client),
      adapterRepository: DaemonAdapterRepository(client: client),
      appUpdateRepository: DaemonAppUpdateRepository(client: appUpdateClient),
      conversationRepository: DaemonConversationRepository(
        client: client,
        notificationService: notificationClient,
      ),
      diagnosticsRepository: DaemonDiagnosticsRepository(client: client),
      runRepository: DaemonRunRepository(client: client),
      workspaceRepository: DaemonWorkspaceRepository(client: client),
      dispose: notificationClient.close,
    );
  }
}

class ConnectedDataDependencies {
  ConnectedDataDependencies({
    required this.authRepository,
    required this.adapterRepository,
    required this.appUpdateRepository,
    required this.conversationRepository,
    required this.diagnosticsRepository,
    required this.runRepository,
    required this.workspaceRepository,
    Future<void> Function()? dispose,
  }) : _dispose = dispose;

  final AuthRepository authRepository;
  final AdapterRepository adapterRepository;
  final AppUpdateRepository appUpdateRepository;
  final ConversationRepository conversationRepository;
  final DiagnosticsRepository diagnosticsRepository;
  final RunRepository runRepository;
  final WorkspaceRepository workspaceRepository;
  final Future<void> Function()? _dispose;
  bool _disposed = false;

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _dispose?.call();
    } catch (_) {
      // Cleanup failures must not surface as unhandled async errors.
    }
  }

  void recordDiagnosticEvent(
    String event,
    Map<String, Object?> metadata, {
    String severity = 'info',
    String? path,
  }) {
    unawaited(_recordDiagnosticEvent(
      event,
      metadata,
      severity: severity,
      path: path,
    ));
  }

  Future<void> _recordDiagnosticEvent(
    String event,
    Map<String, Object?> metadata, {
    required String severity,
    String? path,
  }) async {
    if (_disposed) return;
    try {
      await diagnosticsRepository.recordException(
        message: event,
        severity: severity,
        path: path,
        method: event,
        metadata: metadata,
      );
    } catch (_) {
      // Diagnostics must never interfere with the foreground UI path.
    }
  }
}

DaemonNotificationClient _createDefaultNotificationClient(
        DaemonClient client) =>
    DaemonNotificationClient(
      baseUri: client.baseUri,
      tokenProvider: () => client.currentToken,
      fetchBackfill: (conversationId, {required afterSeq}) =>
          client.fetchConversationEvents(
        conversationId,
        afterSeq: afterSeq,
      ),
      refreshAuth: client.refreshToken,
    );

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
    required this.createAppUpdateViewModel,
    required this.createWorkbenchDependencies,
  });

  factory FeatureDependencies.createDefault({
    required DataDependencies data,
    required DomainDependencies domain,
  }) =>
      FeatureDependencies(
        createDaemonConnectionViewModel: () => DaemonConnectionViewModel(
          configRepository: data.connectionConfigRepository,
          recentAddressRepository: data.recentAddressRepository,
          connectToDaemon: domain.connectionWorkflow,
        ),
        createDiagnosticsViewModel: (connectedData) => DiagnosticsViewModel(
          repository: connectedData.diagnosticsRepository,
        ),
        createRunDetailViewModel: (connectedData, run) => RunDetailViewModel(
          run: run,
          runRepository: connectedData.runRepository,
        ),
        createAppUpdateViewModel: ({
          required DaemonClient client,
          required ConnectedDataDependencies connectedData,
          required int installedVersionCode,
          required String installedVersionName,
        }) async {
          final installer = AndroidPackageInstaller();
          final cacheDirectory = await getTemporaryDirectory();
          final appUpdateClient = AppUpdateClient.authorized(
            baseUri: client.baseUri,
            authorizedGet: (path, {required headers}) =>
                client.getAuthorizedRaw(path, headers: headers),
            authorizedStreamSend: client.sendAuthorizedStream,
          );
          return AppUpdateViewModel(
            installedVersionCode: installedVersionCode,
            installedVersionName: installedVersionName,
            workflow: AppUpdateWorkflow(
              repository: connectedData.appUpdateRepository,
              installerService: installer,
              downloaderService: AppUpdateDownloadManager(
                cacheDirectory: cacheDirectory,
                openStream: appUpdateClient.openApkStream,
                availableBytes: installer.availableBytes,
              ),
            ),
            daemonBaseUri: client.baseUri,
            recordDiagnostic: (event, metadata) {
              connectedData.recordDiagnosticEvent(
                event,
                metadata,
                path: 'app_update',
              );
            },
          );
        },
        createWorkbenchDependencies: (client, connectedData) {
          return WorkbenchDependencies(
            adapterRepository: connectedData.adapterRepository,
            asrModelManager:
                AsrModelManager(client: client.createAsrModelClient()),
            conversationRepository: connectedData.conversationRepository,
            diagnosticsRepository: connectedData.diagnosticsRepository,
            runRepository: connectedData.runRepository,
            speechInputServiceBuilder: (modelDirectory) =>
                SherpaSpeechInputService(modelDirectory: modelDirectory),
            workspaceRepository: connectedData.workspaceRepository,
            attachmentPreviewCache: LocalAttachmentPreviewCache(),
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
  final Future<AppUpdateViewModel> Function({
    required DaemonClient client,
    required ConnectedDataDependencies connectedData,
    required int installedVersionCode,
    required String installedVersionName,
  }) createAppUpdateViewModel;
  final WorkbenchDependencies Function(
    DaemonClient client,
    ConnectedDataDependencies connectedData,
  ) createWorkbenchDependencies;
}
