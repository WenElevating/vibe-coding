import '../models/codex_app_server_models.dart';

abstract class CodexAppServerRepository {
  Future<CodexAppServerCapabilities> loadCapabilities();

  Future<CodexAppServerThreadPage> listThreads(
    String workspaceId, {
    int limit = 50,
  });

  Future<CodexAppServerThreadDetail> readThread(
    String workspaceId,
    String threadId,
  );

  Future<CodexAppServerDiscoverySnapshot> loadDiscovery();
}
