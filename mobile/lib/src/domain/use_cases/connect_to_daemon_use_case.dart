import '../models/connected_app_session.dart';
import '../models/daemon_connection_config.dart';

abstract class ConnectToDaemonUseCase<TClient extends Object> {
  Future<ConnectedAppSession<TClient>> connect({
    required String addressInput,
    required DaemonProxyMode proxyMode,
    required String manualProxyInput,
    bool Function()? shouldContinue,
    void Function()? onCheckingHealth,
    void Function()? onLoadingInitialData,
  });
}
