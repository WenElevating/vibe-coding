import '../../domain/models/connected_app_session.dart';
import '../../domain/models/daemon_initial_data.dart';
import '../../domain/repositories/daemon_connection_config_repository.dart';
import '../../domain/use_cases/connect_to_daemon_use_case.dart';
import '../../services/daemon_client.dart';
import '../../domain/models/daemon_connection_config.dart';
import '../../services/device_identity_store.dart';
import '../../shell/app_snapshot.dart';

typedef DaemonClientFactory = DaemonClient Function({
  required Uri baseUri,
  required SecureTokenStore tokenStore,
  required DaemonProxyMode proxyMode,
  Uri? manualProxy,
});

typedef DaemonInitialDataLoader = Future<DaemonInitialData> Function(
    DaemonClient client);
typedef DaemonHealthProbe = Future<void> Function(DaemonClient client);

class DaemonConnectionWorkflow implements ConnectToDaemonUseCase<DaemonClient> {
  DaemonConnectionWorkflow({
    required DaemonConnectionConfigRepository configRepository,
    required SecureTokenStore tokenStore,
    DeviceIdentityStore? deviceIdentityStore,
    DaemonClientFactory? clientFactory,
    DaemonInitialDataLoader? initialDataLoader,
    DaemonHealthProbe? healthProbe,
  })  : _configRepository = configRepository,
        _tokenStore = tokenStore,
        _deviceIdentityStore =
            deviceIdentityStore ?? SharedPreferencesDeviceIdentityStore(),
        _clientFactory = clientFactory ?? _defaultClientFactory,
        _initialDataLoader = initialDataLoader,
        _healthProbe = healthProbe ?? ((client) async => client.health());

  final DaemonConnectionConfigRepository _configRepository;
  final SecureTokenStore _tokenStore;
  final DeviceIdentityStore _deviceIdentityStore;
  final DaemonClientFactory _clientFactory;
  final DaemonInitialDataLoader? _initialDataLoader;
  final DaemonHealthProbe _healthProbe;

  @override
  Future<ConnectedAppSession<DaemonClient>> connect({
    required String addressInput,
    required DaemonProxyMode proxyMode,
    required String manualProxyInput,
    bool Function()? shouldContinue,
    void Function()? onCheckingHealth,
    void Function()? onLoadingInitialData,
  }) async {
    final address = normalizeDaemonAddress(addressInput);
    final manualProxy = proxyMode == DaemonProxyMode.manual
        ? normalizeManualProxy(manualProxyInput)
        : null;
    final client = _clientFactory(
      baseUri: address.uri,
      tokenStore: _tokenStore,
      proxyMode: proxyMode,
      manualProxy: manualProxy,
    );

    onCheckingHealth?.call();
    await _healthProbe(client);
    if (shouldContinue != null && !shouldContinue()) {
      throw const DaemonConnectionCancelled();
    }
    onLoadingInitialData?.call();
    final initialData = _initialDataLoader == null
        ? await loadDaemonInitialDataBootstrap(client,
            deviceIdentityStore: _deviceIdentityStore)
        : await _initialDataLoader(client);
    if (shouldContinue != null && !shouldContinue()) {
      throw const DaemonConnectionCancelled();
    }
    final connectedConfig = DaemonConnectionConfig(
      addressInput: addressInput.trim(),
      proxyMode: proxyMode,
      manualProxyInput: manualProxyInput.trim(),
    );
    await _configRepository.save(connectedConfig);
    return ConnectedAppSession(
      client: client,
      initialData: initialData,
      connectedConfig: connectedConfig,
    );
  }

  static DaemonClient _defaultClientFactory({
    required Uri baseUri,
    required SecureTokenStore tokenStore,
    required DaemonProxyMode proxyMode,
    Uri? manualProxy,
  }) =>
      DaemonClient(
        baseUri: baseUri,
        tokenStore: tokenStore,
        proxyMode: proxyMode,
        manualProxy: manualProxy,
      );
}

class DaemonConnectionCancelled implements Exception {
  const DaemonConnectionCancelled();

  @override
  String toString() => 'Connection attempt was cancelled.';
}
