import '../../../../../l10n/app_localizations.dart';
import '../../../../domain/models/daemon_connection_config.dart';
import '../view_models/daemon_connection_view_model.dart';

String connectionStatusLabel(
  AppLocalizations l10n,
  DaemonConnectionStatus status,
) =>
    switch (status) {
      DaemonConnectionStatus.loadingConfig =>
        l10n.connectionStatusLoadingConfig,
      DaemonConnectionStatus.idle => l10n.connectionStatusIdle,
      DaemonConnectionStatus.validating => l10n.connectionStatusValidating,
      DaemonConnectionStatus.checkingHealth =>
        l10n.connectionStatusCheckingHealth,
      DaemonConnectionStatus.loadingSnapshot =>
        l10n.connectionStatusLoadingSnapshot,
      DaemonConnectionStatus.connected => l10n.connectionStatusConnected,
      DaemonConnectionStatus.failed => l10n.connectionStatusFailed,
    };

String connectionProxyModeLabel(
  AppLocalizations l10n,
  DaemonProxyMode mode,
) =>
    switch (mode) {
      DaemonProxyMode.direct => l10n.settingsProxyDirect,
      DaemonProxyMode.system => l10n.settingsProxySystem,
      DaemonProxyMode.manual => l10n.settingsProxyManual,
    };

String connectionErrorLabel(
  AppLocalizations l10n,
  DaemonConnectionViewModel controller,
) {
  final inputError = controller.inputError;
  if (inputError == null) {
    return switch (controller.errorCode) {
      DaemonConnectionFailureCode.timeout => l10n.connectionErrorDaemonTimeout,
      DaemonConnectionFailureCode.proxyGatewayInterception =>
        l10n.connectionErrorProxyGateway,
      DaemonConnectionFailureCode.invalidDaemonResponse =>
        l10n.connectionErrorInvalidDaemonResponse,
      DaemonConnectionFailureCode.noDaemonListening =>
        l10n.connectionErrorNoDaemonListening,
      DaemonConnectionFailureCode.unableToConnect =>
        l10n.connectionErrorUnableToConnect,
      null => controller.errorSummary!,
    };
  }
  return switch (controller.inputErrorCode) {
    DaemonConnectionConfigErrorCode.emptyDaemonAddress =>
      l10n.connectionErrorEnterDaemonAddress,
    DaemonConnectionConfigErrorCode.invalidDaemonAddress =>
      l10n.connectionErrorEnterValidDaemonAddress,
    DaemonConnectionConfigErrorCode.unsupportedDaemonAddressScheme =>
      l10n.connectionErrorDaemonAddressHttp,
    DaemonConnectionConfigErrorCode.emptyProxyAddress =>
      l10n.connectionErrorEnterProxyAddress,
    DaemonConnectionConfigErrorCode.invalidProxyAddress =>
      l10n.connectionErrorEnterValidProxy,
    DaemonConnectionConfigErrorCode.unsupportedManualProxyScheme =>
      l10n.connectionErrorManualProxyHttp,
    null => inputError,
  };
}
