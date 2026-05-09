import '../../services/daemon_client.dart';
import '../../services/daemon_connection_config.dart';
import 'daemon_initial_data.dart';

class ConnectedAppSession {
  const ConnectedAppSession({
    required this.client,
    required this.initialData,
    required this.connectedConfig,
  });

  final DaemonClient client;
  final DaemonInitialData initialData;
  final DaemonConnectionConfig connectedConfig;
}
