import '../../services/daemon_connection_config.dart';
import '../models/connected_app_session.dart';

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
