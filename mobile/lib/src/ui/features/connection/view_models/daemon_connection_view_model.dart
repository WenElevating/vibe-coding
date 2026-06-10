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

enum DaemonConnectionFailureCode {
  timeout,
  proxyGatewayInterception,
  invalidDaemonResponse,
  noDaemonListening,
  unableToConnect,
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
  DaemonConnectionConfigErrorCode? _inputErrorCode;
  DaemonConnectionFailureCode? _errorCode;
  String? _errorSummary;
  String? _errorDetail;
  DaemonInitialData? _initialData;
  DaemonClient? _client;
  DaemonConnectionConfig? _connectedConfig;
  int _connectionAttempt = 0;
  int _latestSuccessfulAttempt = 0;
  String? _latestSuccessfulAddressInput;
  List<String> _recentAddresses = const <String>[];
  bool _disposed = false;

  DaemonConnectionStatus get status => _status;
  String get addressInput => _addressInput;
  DaemonProxyMode get proxyMode => _proxyMode;
  String get manualProxyInput => _manualProxyInput;
  String? get inputError => _inputError;
  DaemonConnectionConfigErrorCode? get inputErrorCode => _inputErrorCode;
  DaemonConnectionFailureCode? get errorCode => _errorCode;
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

  Future<void> load() async {
    if (_disposed) {
      return;
    }
    final config = await _configRepository.load();
    if (_disposed) {
      return;
    }
    List<String> recentAddresses;
    try {
      recentAddresses = await _recentAddressRepository.loadRecentAddresses();
    } catch (error) {
      if (_disposed) {
        return;
      }
      recentAddresses = const <String>[];
      _recordDiagnostic('connection.recent_addresses.load_failed', {
        'errorSummary': '$error',
      });
    }
    if (_disposed) {
      return;
    }
    _addressInput = config.addressInput;
    _proxyMode = config.proxyMode;
    _manualProxyInput = config.manualProxyInput;
    _recentAddresses = List<String>.unmodifiable(recentAddresses);
    _status = DaemonConnectionStatus.idle;
    notifyListeners();
  }

  void setAddressInput(String value) {
    if (_disposed) return;
    _addressInput = value;
    _clearTransientErrors();
    notifyListeners();
  }

  void setProxyMode(DaemonProxyMode value) {
    if (_disposed) return;
    _proxyMode = value;
    _clearTransientErrors();
    notifyListeners();
  }

  void setManualProxyInput(String value) {
    if (_disposed) return;
    _manualProxyInput = value;
    _clearTransientErrors();
    notifyListeners();
  }

  void selectRecentAddress(String address) {
    if (_disposed) return;
    _addressInput = address;
    _clearTransientErrors();
    notifyListeners();
  }

  Future<void> connect() async {
    if (_disposed || isBusy) {
      return;
    }

    final attempt = ++_connectionAttempt;
    final hadConnectedSession =
        _client != null && _initialData != null && _connectedConfig != null;
    _status = DaemonConnectionStatus.validating;
    _inputError = null;
    _inputErrorCode = null;
    _errorCode = null;
    _errorSummary = null;
    _errorDetail = null;
    notifyListeners();

    try {
      final connection = _connectToDaemon.connect(
        addressInput: _addressInput,
        proxyMode: _proxyMode,
        manualProxyInput: _manualProxyInput,
        shouldContinue: () => _isCurrentAttempt(attempt),
        onCheckingHealth: () {
          if (!_isCurrentAttempt(attempt)) {
            return;
          }
          _status = DaemonConnectionStatus.checkingHealth;
          notifyListeners();
        },
        onLoadingInitialData: () {
          if (!_isCurrentAttempt(attempt)) {
            return;
          }
          _status = DaemonConnectionStatus.loadingSnapshot;
          notifyListeners();
        },
      );
      connection.then((session) {
        if (!_isCurrentAttempt(attempt)) {
          session.client.close();
        }
      }, onError: (_) {});
      final session = await connection.timeout(
        _connectionTimeout,
        onTimeout: () {
          if (_isCurrentAttempt(attempt) && isBusy) {
            _connectionAttempt++;
            if (!hadConnectedSession) {
              _clearConnectedSession();
            }
            _errorCode = DaemonConnectionFailureCode.timeout;
            _errorSummary = daemonConnectionErrorSummaryForCode(_errorCode!);
            _errorDetail = null;
            _status = DaemonConnectionStatus.failed;
            notifyListeners();
          }
          throw TimeoutException('Connection attempt timed out.');
        },
      );
      if (!_isCurrentAttempt(attempt)) {
        session.client.close();
        return;
      }
      final previousClient = _client;
      _client = session.client;
      _initialData = session.initialData;
      _connectedConfig = session.connectedConfig;
      _latestSuccessfulAttempt = attempt;
      _latestSuccessfulAddressInput = session.connectedConfig.addressInput;
      _status = DaemonConnectionStatus.connected;
      notifyListeners();
      if (!identical(previousClient, session.client)) {
        previousClient?.close();
      }
      await _recordSuccessfulRecentAddress(
        session.connectedConfig.addressInput,
        attempt,
      );
    } on DaemonConnectionConfigException catch (error) {
      if (!_isCurrentAttempt(attempt)) {
        return;
      }
      _inputError = error.message;
      _inputErrorCode = error.code;
      _status = DaemonConnectionStatus.failed;
      notifyListeners();
    } on DaemonConnectionCancelled {
      return;
    } catch (error) {
      if (!_isCurrentAttempt(attempt)) {
        return;
      }
      if (!hadConnectedSession) {
        _clearConnectedSession();
      }
      _errorCode = daemonConnectionFailureCode(error);
      _errorSummary = daemonConnectionErrorSummaryForCode(_errorCode!);
      _errorDetail = ExceptionRedactor.redactText(error.toString());
      _status = DaemonConnectionStatus.failed;
      notifyListeners();
    }
  }

  void _clearTransientErrors() {
    _inputError = null;
    _inputErrorCode = null;
    _errorCode = null;
    _errorSummary = null;
    _errorDetail = null;
  }

  Future<void> _recordSuccessfulRecentAddress(
    String addressInput,
    int attempt,
  ) async {
    if (!_isCurrentAttempt(attempt)) {
      return;
    }
    try {
      await _recentAddressRepository.recordSuccessfulAddress(addressInput);
      if (!_isCurrentAttempt(attempt)) {
        await _restoreLatestRecentAddressAfterStaleWrite(
          staleAttempt: attempt,
          staleAddressInput: addressInput,
        );
        return;
      }
      final recentAddresses =
          await _recentAddressRepository.loadRecentAddresses();
      if (!_isCurrentAttempt(attempt)) {
        return;
      }
      _recentAddresses = List<String>.unmodifiable(recentAddresses);
      notifyListeners();
    } catch (error) {
      if (!_isCurrentAttempt(attempt)) {
        return;
      }
      _recordDiagnostic('connection.recent_addresses.record_failed', {
        'errorSummary': '$error',
      });
    }
  }

  Future<void> _restoreLatestRecentAddressAfterStaleWrite({
    required int staleAttempt,
    required String staleAddressInput,
  }) async {
    if (_disposed || _latestSuccessfulAttempt <= staleAttempt) {
      return;
    }
    final latestAddressInput = _latestSuccessfulAddressInput;
    if (latestAddressInput == null || latestAddressInput == staleAddressInput) {
      return;
    }
    final latestAttempt = _latestSuccessfulAttempt;
    try {
      await _recentAddressRepository
          .recordSuccessfulAddress(latestAddressInput);
      if (!_isCurrentAttempt(latestAttempt)) {
        await _restoreLatestRecentAddressAfterStaleWrite(
          staleAttempt: latestAttempt,
          staleAddressInput: latestAddressInput,
        );
        return;
      }
      final recentAddresses =
          await _recentAddressRepository.loadRecentAddresses();
      if (!_isCurrentAttempt(latestAttempt)) {
        return;
      }
      _recentAddresses = List<String>.unmodifiable(recentAddresses);
      notifyListeners();
    } catch (error) {
      if (!_isCurrentAttempt(latestAttempt)) {
        return;
      }
      _recordDiagnostic('connection.recent_addresses.record_failed', {
        'errorSummary': '$error',
      });
    }
  }

  bool _isCurrentAttempt(int attempt) {
    return !_disposed && attempt == _connectionAttempt;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _connectionAttempt++;
    _closeConnectedClient();
    super.dispose();
  }

  void _closeConnectedClient() {
    final client = _client;
    _clearConnectedSession();
    client?.close();
  }

  void _clearConnectedSession() {
    _client = null;
    _initialData = null;
    _connectedConfig = null;
  }
}

String daemonConnectionErrorSummary(Object error) {
  return daemonConnectionErrorSummaryForCode(
      daemonConnectionFailureCode(error));
}

DaemonConnectionFailureCode daemonConnectionFailureCode(Object error) {
  if (error is TimeoutException) {
    return DaemonConnectionFailureCode.timeout;
  }
  if (error is DaemonClientException) {
    final message = '${error.body['message'] ?? ''}';
    if (error.statusCode == 502 && message.contains('empty response')) {
      return DaemonConnectionFailureCode.proxyGatewayInterception;
    }
    if (message.contains('empty response') ||
        message.contains('invalid JSON')) {
      return DaemonConnectionFailureCode.invalidDaemonResponse;
    }
  }
  final text = error.toString();
  if (text.contains('Connection refused') || text.contains('ECONNREFUSED')) {
    return DaemonConnectionFailureCode.noDaemonListening;
  }
  if (text.toLowerCase().contains('timed out')) {
    return DaemonConnectionFailureCode.timeout;
  }
  return DaemonConnectionFailureCode.unableToConnect;
}

String daemonConnectionErrorSummaryForCode(DaemonConnectionFailureCode code) {
  return switch (code) {
    DaemonConnectionFailureCode.timeout =>
      'The daemon did not respond in time.',
    DaemonConnectionFailureCode.proxyGatewayInterception =>
      'A proxy or gateway may have intercepted the daemon request.',
    DaemonConnectionFailureCode.invalidDaemonResponse =>
      'The daemon returned an invalid response.',
    DaemonConnectionFailureCode.noDaemonListening =>
      'No daemon is listening at this address.',
    DaemonConnectionFailureCode.unableToConnect =>
      'Unable to connect to the daemon.',
  };
}
