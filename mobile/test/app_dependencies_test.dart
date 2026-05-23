import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/app/app_dependencies.dart';
import 'package:lan_ai_cli_control/src/domain/models/daemon_connection_config.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/daemon_connection_config_repository.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/services/daemon_client.dart';
import 'package:lan_ai_cli_control/src/services/daemon_notification_client.dart';

void main() {
  test('connected data disposal closes notification client', () async {
    final notificationClient = _CloseRecordingNotificationClient();
    final data = DataDependencies(
      connectionConfigRepository: _FakeConnectionConfigRepository(),
      createNotificationClient: (_) => notificationClient,
    );
    final client = DaemonClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenStore: MemoryTokenStore(),
    );
    final connectedData = data.forDaemonClient(client);

    await connectedData.dispose();
    await connectedData.dispose();
    client.close();

    expect(notificationClient.closeCalls, 1);
  });
}

class _FakeConnectionConfigRepository
    implements DaemonConnectionConfigRepository {
  @override
  Future<DaemonConnectionConfig> load() async => DaemonConnectionConfig.fallback;

  @override
  Future<void> save(DaemonConnectionConfig config) async {}
}

class _CloseRecordingNotificationClient extends DaemonNotificationClient {
  _CloseRecordingNotificationClient()
      : super(
          baseUri: Uri.parse('http://127.0.0.1:4317'),
          tokenProvider: () => null,
          fetchBackfill: (_, {required afterSeq}) async =>
              const <ConversationEvent>[],
        );

  int closeCalls = 0;

  @override
  Future<void> close() async {
    closeCalls += 1;
  }
}
