import '../../services/daemon_connection_config.dart';
import 'daemon_initial_data.dart';

class ConnectedAppSession<TClient extends Object> {
  const ConnectedAppSession({
    required this.client,
    required this.initialData,
    required this.connectedConfig,
  });

  final TClient client;
  final DaemonInitialData initialData;
  final DaemonConnectionConfig connectedConfig;
}
