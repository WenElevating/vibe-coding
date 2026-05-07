import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/daemon_client.dart';
import '../services/daemon_connection_config.dart';
import '../services/daemon_connection_config_store.dart';
import '../shell/app_snapshot.dart';

enum DaemonConnectionStatus {
  loadingConfig,
  idle,
  validating,
  checkingHealth,
  loadingSnapshot,
  connected,
  failed,
}

typedef DaemonSnapshotLoader = Future<AppSnapshot> Function(
    DaemonClient client);
typedef DaemonHealthProbe = Future<void> Function(DaemonClient client);

class DaemonConnectionController extends ChangeNotifier {
  DaemonConnectionController({
    required this.store,
    required this.tokenStore,
    DaemonSnapshotLoader? snapshotLoader,
    DaemonHealthProbe? healthProbe,
    Duration connectionTimeout = const Duration(seconds: 30),
  })  : _snapshotLoader =
            snapshotLoader ?? ((client) => AppSnapshot.loadBootstrap(client)),
        _healthProbe = healthProbe ?? ((client) async => client.health()),
        _connectionTimeout = connectionTimeout;

  final DaemonConnectionConfigStore store;
  final SecureTokenStore tokenStore;
  final DaemonSnapshotLoader _snapshotLoader;
  final DaemonHealthProbe _healthProbe;
  final Duration _connectionTimeout;

  DaemonConnectionStatus _status = DaemonConnectionStatus.loadingConfig;
  String _addressInput = DaemonConnectionConfig.fallback.addressInput;
  DaemonProxyMode _proxyMode = DaemonConnectionConfig.fallback.proxyMode;
  String _manualProxyInput = DaemonConnectionConfig.fallback.manualProxyInput;
  String? _inputError;
  String? _errorSummary;
  String? _errorDetail;
  AppSnapshot? _snapshot;
  DaemonClient? _client;
  DaemonConnectionConfig? _connectedConfig;
  int _connectionAttempt = 0;

  DaemonConnectionStatus get status => _status;
  String get addressInput => _addressInput;
  DaemonProxyMode get proxyMode => _proxyMode;
  String get manualProxyInput => _manualProxyInput;
  String? get inputError => _inputError;
  String? get errorSummary => _errorSummary;
  String? get errorDetail => _errorDetail;
  AppSnapshot? get snapshot => _snapshot;
  DaemonClient? get client => _client;
  DaemonConnectionConfig? get connectedConfig => _connectedConfig;
  Duration get connectionTimeout => _connectionTimeout;

  bool get isBusy =>
      _status == DaemonConnectionStatus.validating ||
      _status == DaemonConnectionStatus.checkingHealth ||
      _status == DaemonConnectionStatus.loadingSnapshot;

  String get statusLabel => switch (_status) {
        DaemonConnectionStatus.loadingConfig => 'Loading connection settings',
        DaemonConnectionStatus.idle => 'Not connected',
        DaemonConnectionStatus.validating => 'Resolving connection address',
        DaemonConnectionStatus.checkingHealth => 'Checking daemon health',
        DaemonConnectionStatus.loadingSnapshot => 'Syncing workspace state',
        DaemonConnectionStatus.connected => 'Connected',
        DaemonConnectionStatus.failed => 'Connection failed',
      };

  Future<void> load() async {
    final config = await store.load();
    _addressInput = config.addressInput;
    _proxyMode = config.proxyMode;
    _manualProxyInput = config.manualProxyInput;
    _status = DaemonConnectionStatus.idle;
    notifyListeners();
  }

  void setAddressInput(String value) {
    _addressInput = value;
    _clearTransientErrors();
    notifyListeners();
  }

  void setProxyMode(DaemonProxyMode value) {
    _proxyMode = value;
    _clearTransientErrors();
    notifyListeners();
  }

  void setManualProxyInput(String value) {
    _manualProxyInput = value;
    _clearTransientErrors();
    notifyListeners();
  }

  Future<void> connect() async {
    if (isBusy) {
      return;
    }

    final attempt = ++_connectionAttempt;
    _status = DaemonConnectionStatus.validating;
    _inputError = null;
    _errorSummary = null;
    _errorDetail = null;
    notifyListeners();

    NormalizedDaemonAddress address;
    Uri? manualProxy;
    try {
      address = normalizeDaemonAddress(_addressInput);
      if (_proxyMode == DaemonProxyMode.manual) {
        manualProxy = normalizeManualProxy(_manualProxyInput);
      }
    } on DaemonConnectionConfigException catch (error) {
      _inputError = error.message;
      _status = DaemonConnectionStatus.failed;
      notifyListeners();
      return;
    }

    final client = DaemonClient(
      baseUri: address.uri,
      tokenStore: tokenStore,
      proxyMode: _proxyMode,
      manualProxy: manualProxy,
    );

    try {
      await _runConnectionAttempt(client, attempt).timeout(
        _connectionTimeout,
        onTimeout: () {
          if (attempt == _connectionAttempt && isBusy) {
            _connectionAttempt++;
            _client = null;
            _snapshot = null;
            _connectedConfig = null;
            _errorSummary = 'The daemon did not respond in time.';
            _errorDetail =
                'Connection attempt exceeded ${_connectionTimeout.inSeconds}s.';
            _status = DaemonConnectionStatus.failed;
            notifyListeners();
          }
          throw TimeoutException('Connection attempt timed out.');
        },
      );
    } catch (error) {
      if (attempt != _connectionAttempt) {
        return;
      }
      _client = null;
      _snapshot = null;
      _connectedConfig = null;
      _errorSummary = daemonConnectionErrorSummary(error);
      _errorDetail = error.toString();
      _status = DaemonConnectionStatus.failed;
      notifyListeners();
    }
  }

  Future<void> _runConnectionAttempt(
      DaemonClient client, int attempt) async {
    if (attempt != _connectionAttempt) {
      return;
    }
    _status = DaemonConnectionStatus.checkingHealth;
    notifyListeners();
    await _healthProbe(client);
    if (attempt != _connectionAttempt) {
      return;
    }
    _status = DaemonConnectionStatus.loadingSnapshot;
    notifyListeners();
    final loaded = await _snapshotLoader(client);
    if (attempt != _connectionAttempt) {
      return;
    }
    final connectedConfig = DaemonConnectionConfig(
      addressInput: _addressInput.trim(),
      proxyMode: _proxyMode,
      manualProxyInput: _manualProxyInput.trim(),
    );
    await store.save(connectedConfig);
    if (attempt != _connectionAttempt) {
      return;
    }
    _client = client;
    _snapshot = loaded;
    _connectedConfig = connectedConfig;
    _status = DaemonConnectionStatus.connected;
    notifyListeners();
  }

  void _clearTransientErrors() {
    _inputError = null;
    _errorSummary = null;
    _errorDetail = null;
  }
}

String daemonConnectionErrorSummary(Object error) {
  if (error is TimeoutException) {
    return 'The daemon did not respond in time.';
  }
  if (error is DaemonClientException) {
    final message = '${error.body['message'] ?? ''}';
    if (error.statusCode == 502 && message.contains('empty response')) {
      return 'A proxy or gateway may have intercepted the daemon request.';
    }
    if (message.contains('empty response') ||
        message.contains('invalid JSON')) {
      return 'The daemon returned an invalid response.';
    }
  }
  final text = error.toString();
  if (text.contains('Connection refused') || text.contains('ECONNREFUSED')) {
    return 'No daemon is listening at this address.';
  }
  if (text.toLowerCase().contains('timed out')) {
    return 'The daemon did not respond in time.';
  }
  return 'Unable to connect to the daemon.';
}
