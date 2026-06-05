import '../../domain/repositories/codex_app_server_repository.dart';
import '../../services/conversation_client.dart';

class DaemonCodexAppServerRepository implements CodexAppServerRepository {
  DaemonCodexAppServerRepository({required ConversationClient client})
      : _client = client;

  final ConversationClient _client;

  @override
  Future<CodexAppServerCapabilities> loadCapabilities() async {
    final response = await _client.getCodexAppServerCapabilities();
    return CodexAppServerCapabilities.fromJson(response);
  }

  @override
  Future<CodexAppServerThreadPage> listThreads(
    String workspaceId, {
    int limit = 50,
  }) async {
    final response = await _client.listCodexAppServerThreads(
      workspaceId,
      limit: limit,
    );
    return CodexAppServerThreadPage.fromJson(response);
  }

  @override
  Future<CodexAppServerThreadDetail> readThread(String threadId) async {
    final response = await _client.readCodexAppServerThread(threadId);
    return CodexAppServerThreadDetail.fromJson(response);
  }

  @override
  Future<CodexAppServerDiscoverySnapshot> loadDiscovery() async {
    final response = await _client.getCodexAppServerDiscovery();
    return CodexAppServerDiscoverySnapshot.fromJson(response);
  }
}
