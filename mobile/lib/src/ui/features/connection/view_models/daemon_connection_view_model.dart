import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../domain/models/daemon_initial_data.dart';
import '../../../../domain/repositories/daemon_connection_config_repository.dart';
import '../../../../domain/repositories/recent_daemon_address_repository.dart';
import '../../../../domain/use_cases/connect_to_daemon_use_case.dart';
import '../../../../services/daemon_client.dart';
import '../../../../services/exception_redactor.dart';
import '../../../../domain/models/daemon_connection_config.dart';
import '../../../../workflows/connection/daemon_connection_workflow.dart'
    show DaemonConnectionCancelled;

enum DaemonConnectionStatus {
  loadingConfig,
  idle,
  validating,
  checkingHealth,
  loadingSnapshot,
  connected,
  failed,
}

typedef DiagnosticRecorder = void Function(
  String event,
  Map<String, Object?> metadata,
);

void noopDiagnosticRecorder(String event, Map<String, Object?> metadata) {}

class DaemonConnectionViewModel extends ChangeNotifier {
  DaemonConnectionViewModel({
    required DaemonConnectionConfigRepository configRepository,
    required RecentDaemonAddressRepository recentAddressRepository,
    required ConnectToDaemonUseCase<DaemonClient> connectToDaemon,
    Duration connectionTimeout = const Duration(seconds: 30),
    DiagnosticRecorder recordDiagnostic = noopDiagnosticRecorder,
  })  : _configRepository = configRepository,
        _recentAddressRepository = recentAddressRepository,
        _connectToDaemon = connectToDaemon,
        _connectionTimeout = connectionTimeout,
        _recordDiagnostic = recordDiagnostic;

  final DaemonConnectionConfigRepository _configRepository;
  final RecentDaemonAddressRepository _recentAddressRepository;
  final ConnectToDaemonUseCase<DaemonClient> _connectToDaemon;
  final Duration _connectionTimeout;
  final DiagnosticRecorder _recordDiagnostic;

  DaemonConnectionStatus _status = DaemonConnectionStatus.loadingConfig;
  String _addressInput = DaemonConnectionConfig.fallback.addressInput;
  DaemonProxyMode _proxyMode = DaemonConnectionConfig.fallback.proxyMode;
  String _manualProxyInput = DaemonConnectionConfig.fallback.manualProxyInput;
  String? _inputError;
  String? _errorSummary;
  String? _errorDetail;
  DaemonInitialData? _initialData;
  DaemonClient? _client;
  DaemonConnectionConfig? _connectedConfig;
  int _connectionAttempt = 0;
  List<String> _recentAddresses = const <String>[];

  DaemonConnectionStatus get status => _status;
  String get addressInput => _addressInput;
  DaemonProxyMode get proxyMode => _proxyMode;
  String get manualProxyInput => _manualProxyInput;
  String? get inputError => _inputError;
  String? get errorSummary => _errorSummary;
  String? get errorDetail => _errorDetail;
  DaemonInitialData? get initialData => _initialData;
  DaemonClient? get client => _client;
  DaemonConnectionConfig? get connectedConfig => _connectedConfig;
  Duration get connectionTimeout => _connectionTimeout;
  List<String> get recentAddresses => _recentAddresses;

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
    final config = await _configRepository.load();
    List<String> recentAddresses;
    try {
      recentAddresses = await _recentAddressRepository.loadRecentAddresses();
    } catch (error) {
      recentAddresses = const <String>[];
      _recordDiagnostic('connection.recent_addresses.load_failed', {
        'errorSummary': '$error',
      });
    }
    _addressInput = config.addressInput;
    _proxyMode = config.proxyMode;
    _manualProxyInput = config.manualProxyInput;
    _recentAddresses = List<String>.unmodifiable(recentAddresses);
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

  void selectRecentAddress(String address) {
    _addressInput = address;
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

    try {
      final connection = _connectToDaemon.connect(
        addressInput: _addressInput,
        proxyMode: _proxyMode,
        manualProxyInput: _manualProxyInput,
        shouldContinue: () => attempt == _connectionAttempt,
        onCheckingHealth: () {
          if (attempt != _connectionAttempt) {
            return;
          }
          _status = DaemonConnectionStatus.checkingHealth;
          notifyListeners();
        },
        onLoadingInitialData: () {
          if (attempt != _connectionAttempt) {
            return;
          }
          _status = DaemonConnectionStatus.loadingSnapshot;
          notifyListeners();
        },
      );
      connection.then((session) {
        if (attempt != _connectionAttempt) {
          session.client.close();
        }
      }, onError: (_) {});
      final session = await connection.timeout(
        _connectionTimeout,
        onTimeout: () {
          if (attempt == _connectionAttempt && isBusy) {
            _connectionAttempt++;
            _client = null;
            _initialData = null;
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
      if (attempt != _connectionAttempt) {
        session.client.close();
        return;
      }
      _client = session.client;
      _initialData = session.initialData;
      _connectedConfig = session.connectedConfig;
      _status = DaemonConnectionStatus.connected;
      notifyListeners();
      await _recordSuccessfulRecentAddress(session.connectedConfig.addressInput);
    } on DaemonConnectionConfigException catch (error) {
      if (attempt != _connectionAttempt) {
        return;
      }
      _inputError = error.message;
      _status = DaemonConnectionStatus.failed;
      notifyListeners();
    } on DaemonConnectionCancelled {
      return;
    } catch (error) {
      if (attempt != _connectionAttempt) {
        return;
      }
      _client = null;
      _initialData = null;
      _connectedConfig = null;
      _errorSummary = daemonConnectionErrorSummary(error);
      _errorDetail = ExceptionRedactor.redactText(error.toString());
      _status = DaemonConnectionStatus.failed;
      notifyListeners();
    }
  }

  void _clearTransientErrors() {
    _inputError = null;
    _errorSummary = null;
    _errorDetail = null;
  }

  Future<void> _recordSuccessfulRecentAddress(String addressInput) async {
    try {
      await _recentAddressRepository.recordSuccessfulAddress(addressInput);
      _recentAddresses = List<String>.unmodifiable(
        await _recentAddressRepository.loadRecentAddresses(),
      );
      notifyListeners();
    } catch (error) {
      _recordDiagnostic('connection.recent_addresses.record_failed', {
        'errorSummary': '$error',
      });
    }
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
