import '../../domain/models/codex_app_server_models.dart';
import '../../domain/repositories/codex_app_server_repository.dart';
import '../models/codex_app_server_models.dart';

typedef CodexAppServerJsonGet = Future<Map<String, Object?>> Function(
  String path,
);

class DaemonCodexAppServerRepository implements CodexAppServerRepository {
  DaemonCodexAppServerRepository({required CodexAppServerJsonGet getJson})
      : _getJson = getJson;

  final CodexAppServerJsonGet _getJson;

  @override
  Future<CodexAppServerCapabilities> loadCapabilities() async {
    final response = await _getJson('/api/codex-app-server/capabilities');
    return parseCodexAppServerCapabilities(response);
  }

  @override
  Future<CodexAppServerThreadPage> listThreads(
    String workspaceId, {
    int limit = 50,
  }) async {
    final query = Uri(queryParameters: <String, String>{
      'limit': limit.toString(),
    }).query;
    final response = await _getJson(
      '/api/codex-app-server/workspaces/'
      '${Uri.encodeComponent(workspaceId)}/threads?$query',
    );
    return parseCodexAppServerThreadPage(response);
  }

  @override
  Future<CodexAppServerThreadDetail> readThread(
    String workspaceId,
    String threadId,
  ) async {
    final response = await _getJson(
      '/api/codex-app-server/workspaces/'
      '${Uri.encodeComponent(workspaceId)}/threads/'
      '${Uri.encodeComponent(threadId)}',
    );
    return parseCodexAppServerThreadDetail(response);
  }

  @override
  Future<CodexAppServerDiscoverySnapshot> loadDiscovery() async {
    final models =
        await _getJson('/api/codex-app-server/model-provider-capabilities');
    final mcpServers = await _getJson('/api/codex-app-server/mcp/servers');
    final skills = await _getJson('/api/codex-app-server/skills');
    final plugins = await _getJson('/api/codex-app-server/plugins');
    final apps = await _getJson('/api/codex-app-server/apps');
    final config = await _getJson('/api/codex-app-server/config');
    final response = <String, Object?>{
      'models': models,
      'mcpServers': mcpServers,
      'skills': skills,
      'plugins': plugins,
      'apps': apps,
      'config': config,
    };
    return parseCodexAppServerDiscoverySnapshot(response);
  }
}
