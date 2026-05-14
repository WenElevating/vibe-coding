import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../data/services/auth_service.dart';
import '../data/services/conversation_service.dart';
import '../data/services/run_service.dart';
import '../data/services/workspace_service.dart';
import '../models/protocol.dart';
import 'asr_model_client.dart';
import '../domain/models/daemon_connection_config.dart';
import 'device_identity_store.dart';

abstract class SecureTokenStore {
  Future<void> writeAccessTokenSession(String deviceId, TokenSession session);
  Future<TokenSession?> readAccessTokenSession(String deviceId);
  Future<void> writeRefreshTokenSession(String deviceId, TokenSession session);
  Future<TokenSession?> readRefreshTokenSession(String deviceId);

  Future<void> writeAccessToken(String deviceId, String token);
  Future<String?> readAccessToken(String deviceId);
  Future<void> deleteAccessToken(String deviceId);
  Future<void> writeRefreshToken(String deviceId, String token);
  Future<String?> readRefreshToken(String deviceId);
  Future<void> deleteRefreshToken(String deviceId);

  Future<void> writeDeviceToken(String deviceId, String token) =>
      writeAccessToken(deviceId, token);

  Future<String?> readDeviceToken(String deviceId) => readAccessToken(deviceId);

  Future<void> deleteDeviceToken(String deviceId) =>
      deleteAccessToken(deviceId);
}

class TokenSession {
  const TokenSession({required this.token, required this.expiresAt});

  final String token;
  final DateTime expiresAt;
}

class MemoryTokenStore implements SecureTokenStore {
  final Map<String, TokenSession> _accessTokens = <String, TokenSession>{};
  final Map<String, TokenSession> _refreshTokens = <String, TokenSession>{};

  @override
  Future<void> writeAccessTokenSession(
      String deviceId, TokenSession session) async {
    _accessTokens[deviceId] = session;
  }

  @override
  Future<TokenSession?> readAccessTokenSession(String deviceId) async =>
      _accessTokens[deviceId];

  @override
  Future<void> writeRefreshTokenSession(
      String deviceId, TokenSession session) async {
    _refreshTokens[deviceId] = session;
  }

  @override
  Future<TokenSession?> readRefreshTokenSession(String deviceId) async =>
      _refreshTokens[deviceId];

  @override
  Future<String?> readAccessToken(String deviceId) async =>
      _accessTokens[deviceId]?.token;

  @override
  Future<void> writeAccessToken(String deviceId, String token) async {
    _accessTokens[deviceId] = TokenSession(
        token: token, expiresAt: DateTime.fromMillisecondsSinceEpoch(0));
  }

  @override
  Future<void> deleteAccessToken(String deviceId) async {
    _accessTokens.remove(deviceId);
  }

  @override
  Future<void> writeRefreshToken(String deviceId, String token) async {
    _refreshTokens[deviceId] = TokenSession(
        token: token, expiresAt: DateTime.fromMillisecondsSinceEpoch(0));
  }

  @override
  Future<String?> readRefreshToken(String deviceId) async =>
      _refreshTokens[deviceId]?.token;

  @override
  Future<void> deleteRefreshToken(String deviceId) async {
    _refreshTokens.remove(deviceId);
  }

  @override
  Future<void> writeDeviceToken(String deviceId, String token) =>
      writeAccessToken(deviceId, token);

  @override
  Future<String?> readDeviceToken(String deviceId) => readAccessToken(deviceId);

  @override
  Future<void> deleteDeviceToken(String deviceId) =>
      deleteAccessToken(deviceId);
}

class DaemonClient
    implements AuthService, RunService, WorkspaceService, ConversationService {
  DaemonClient(
      {required this.baseUri,
      required this.tokenStore,
      http.Client? httpClient,
      DaemonProxyMode proxyMode = DaemonProxyMode.direct,
      Uri? manualProxy,
      DateTime Function()? now,
      this.refreshSkew = const Duration(minutes: 10)})
      : _httpClient = httpClient ??
            createDaemonHttpClient(
                proxyMode: proxyMode, manualProxy: manualProxy),
        _now = now ?? DateTime.now;

  final Uri baseUri;
  final SecureTokenStore tokenStore;
  final http.Client _httpClient;
  final DateTime Function() _now;
  final Duration refreshSkew;

  String? _deviceId;
  String? _token;
  Completer<void>? _refreshCompleter;

  String? get currentToken => _token;

  AsrModelClient createAsrModelClient() => AsrModelClient(
      baseUri: baseUri, tokenProvider: () => _token, httpClient: _httpClient);

  @override
  Future<DaemonHealth> health() async {
    final response = await _get('/api/health', authorize: false);
    return DaemonHealth.fromJson(response);
  }

  @override
  Future<DaemonVersionInfo> version() async {
    final response = await _get('/api/version', authorize: false);
    return DaemonVersionInfo.fromJson(response);
  }

  Future<DiagnosticBundleSummary> exportDiagnostics() async {
    final response =
        await _post('/api/diagnostics/export', const <String, Object?>{});
    return DiagnosticBundleSummary.fromJson(response);
  }

  Future<SmokeTestResult> runSmokeTest() async {
    final response = await _post('/api/e2e/smoke', const <String, Object?>{},
        authorize: false);
    return SmokeTestResult.fromJson(response);
  }

  @override
  Future<void> pair(
      {required String code,
      String label = 'Android device',
      String? deviceId}) async {
    final response = await _post(
        '/api/pair',
        <String, Object?>{
          'code': code,
          'label': label,
          if (deviceId != null) 'deviceId': deviceId,
        },
        authorize: false);
    _deviceId = response['deviceId'] as String;
    _token = response['token'] as String;
    await tokenStore.writeAccessTokenSession(
        _deviceId!,
        _sessionFromResponse(response,
            tokenKey: 'token', expiresAtKey: 'accessTokenExpiresAt'));
    final refreshToken = response['refreshToken'] as String?;
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await tokenStore.writeRefreshTokenSession(
          _deviceId!,
          _sessionFromResponse(response,
              tokenKey: 'refreshToken', expiresAtKey: 'refreshTokenExpiresAt'));
    }
  }

  @override
  Future<void> refreshToken() async {
    if (_refreshCompleter != null) return _refreshCompleter!.future;
    _refreshCompleter = Completer<void>();
    try {
      final deviceId = _deviceId;
      if (deviceId == null) {
        throw const DaemonClientException(401, <String, Object?>{
          'error': 'missing_device',
          'message': 'No paired device is available for token refresh.',
        });
      }
      final refreshSession = await tokenStore.readRefreshTokenSession(deviceId);
      final refreshToken = refreshSession?.token;
      if (refreshToken == null || refreshToken.isEmpty) {
        throw const DaemonClientException(401, <String, Object?>{
          'error': 'missing_refresh_token',
          'message': 'No refresh token is available for this device.',
        });
      }
      final response = await _post(
        '/api/token/refresh',
        <String, Object?>{'deviceId': deviceId, 'refreshToken': refreshToken},
        authorize: false,
      );
      _deviceId = response['deviceId'] as String;
      _token = response['token'] as String;
      await tokenStore.writeAccessTokenSession(
          _deviceId!,
          _sessionFromResponse(response,
              tokenKey: 'token', expiresAtKey: 'accessTokenExpiresAt'));
      final nextRefreshToken = response['refreshToken'] as String?;
      if (nextRefreshToken != null && nextRefreshToken.isNotEmpty) {
        await tokenStore.writeRefreshTokenSession(
            _deviceId!,
            _sessionFromResponse(response,
                tokenKey: 'refreshToken',
                expiresAtKey: 'refreshTokenExpiresAt'));
      }
      _refreshCompleter!.complete();
    } catch (e, st) {
      _refreshCompleter!.completeError(e, st);
      rethrow;
    } finally {
      _refreshCompleter = null;
    }
  }

  @override
  Future<void> ensurePaired(
      {required DeviceIdentityStore deviceIdentityStore,
      String label = 'Android device'}) async {
    final deviceId = await deviceIdentityStore.readOrCreateDeviceId();
    final session = await tokenStore.readAccessTokenSession(deviceId);
    if (session != null && session.token.isNotEmpty) {
      _deviceId = deviceId;
      _token = session.token;
      if (_needsRefresh(session)) {
        await _refreshStoredTokenOrClear();
      }
      return;
    }
    final pairingCode = await createPairingCode();
    await pair(code: pairingCode, label: label, deviceId: deviceId);
  }

  @override
  Future<String> createPairingCode() async {
    final response = await _post('/api/pairing-code', const <String, Object?>{},
        authorize: false);
    return response['code'] as String;
  }

  Future<List<AdapterStatus>> listAdapters() async {
    final response = await _get('/api/adapters');
    final items = response['adapters'] as List<Object?>;
    return items
        .cast<Map<String, Object?>>()
        .map(AdapterStatus.fromJson)
        .toList();
  }

  Future<List<ShortcutCommand>> listShortcuts() async {
    final response = await _get('/api/shortcuts');
    final items = response['shortcuts'] as List<Object?>;
    return items
        .cast<Map<String, Object?>>()
        .map(ShortcutCommand.fromJson)
        .toList();
  }

  Future<List<CommandTemplate>> listCommandTemplates() async {
    final response = await _get('/api/command-templates');
    final items = response['templates'] as List<Object?>;
    return items
        .cast<Map<String, Object?>>()
        .map(CommandTemplate.fromJson)
        .toList();
  }

  Future<List<QueueItem>> listQueue() async {
    final response = await _get('/api/queue');
    final items = response['queue'] as List<Object?>;
    return items.cast<Map<String, Object?>>().map(QueueItem.fromJson).toList();
  }

  @override
  Future<GitStatusSummary> gitStatus(String workspaceId) async {
    final response = await _get('/api/workspaces/$workspaceId/git/status');
    return GitStatusSummary.fromJson(response);
  }

  @override
  Future<List<DiffSummary>> gitDiff(String workspaceId) async {
    final response = await _get('/api/workspaces/$workspaceId/git/diff');
    final items = response['summaries'] as List<Object?>;
    return items
        .cast<Map<String, Object?>>()
        .map(DiffSummary.fromJson)
        .toList();
  }

  @override
  Future<ProjectOverview> projectOverview(String workspaceId) async {
    final response = await _get('/api/workspaces/$workspaceId/overview');
    return ProjectOverview.fromJson(response);
  }

  @override
  Future<FileTreeResponse> fileTree(String workspaceId,
      {String path = '', int maxDepth = 8}) async {
    final requestPath = Uri(
        path: '/api/workspaces/$workspaceId/files/tree',
        queryParameters: <String, String>{
          'path': path,
          'maxDepth': '$maxDepth'
        }).toString();
    final response = await _get(requestPath);
    return FileTreeResponse.fromJson(response);
  }

  @override
  Future<FileContent> fileContent(String workspaceId, String path) async {
    final requestPath = Uri(
        path: '/api/workspaces/$workspaceId/files/content',
        queryParameters: <String, String>{'path': path}).toString();
    final response = await _get(requestPath);
    return FileContent.fromJson(response);
  }

  @override
  Future<List<GitCommitSummary>> gitCommits(String workspaceId,
      {int limit = 20}) async {
    final requestPath = Uri(
        path: '/api/workspaces/$workspaceId/git/commits',
        queryParameters: <String, String>{'limit': '$limit'}).toString();
    final response = await _get(requestPath);
    final items = response['commits'] as List<Object?>;
    return items
        .cast<Map<String, Object?>>()
        .map(GitCommitSummary.fromJson)
        .toList();
  }

  @override
  Future<CodeDiagnosticsSummary> codeDiagnostics(String workspaceId) async {
    final response =
        await _get('/api/workspaces/$workspaceId/diagnostics/code');
    return CodeDiagnosticsSummary.fromJson(response);
  }

  Future<List<ExtensionSummary>> listExtensions() async {
    final response = await _get('/api/extensions');
    final items = response['extensions'] as List<Object?>;
    return items
        .cast<Map<String, Object?>>()
        .map(ExtensionSummary.fromJson)
        .toList();
  }

  Future<RunSummary> invokeCommandTemplate(
      {required String templateId,
      required String workspaceId,
      String tool = 'claude'}) async {
    final response = await _post('/api/command-templates/$templateId/invoke',
        <String, Object?>{'workspaceId': workspaceId, 'tool': tool});
    return RunSummary.fromJson(response['run'] as Map<String, Object?>);
  }

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() async {
    final response = await _get('/api/workspaces');
    final items = response['workspaces'] as List<Object?>;
    return items
        .cast<Map<String, Object?>>()
        .map(WorkspaceSummary.fromJson)
        .toList();
  }

  @override
  Future<WorkspaceSummary> createWorkspace(
      {required String path, String? name}) async {
    final response = await _post('/api/workspaces', <String, Object?>{
      'workspacePath': path,
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
    });
    return WorkspaceSummary.fromJson(response);
  }

  @override
  Future<List<DirectoryEntrySummary>> listFileSystemRoots() async {
    final response = await _get('/api/fs/roots');
    final items = response['roots'] as List<Object?>;
    return items
        .cast<Map<String, Object?>>()
        .map(DirectoryEntrySummary.fromJson)
        .toList();
  }

  @override
  Future<DirectoryListing> listDirectory(String path) async {
    final uri = Uri(
        path: '/api/fs/children',
        queryParameters: <String, String>{'path': path});
    final response = await _get(uri.toString());
    return DirectoryListing.fromJson(response);
  }

  @override
  Future<List<RunSummary>> listRuns(
      {String? tool, String? workspaceId, String? status}) async {
    final query = <String, String>{
      if (tool != null) 'tool': tool,
      if (workspaceId != null) 'workspaceId': workspaceId,
      if (status != null) 'status': status,
    };
    final path =
        Uri(path: '/api/runs', queryParameters: query.isEmpty ? null : query)
            .toString();
    final response = await _get(path);
    final items = response['runs'] as List<Object?>;
    return items.cast<Map<String, Object?>>().map(RunSummary.fromJson).toList();
  }

  @override
  Future<RunSummary> createRun(
      {required String tool,
      required String workspaceId,
      String? prompt,
      String? shortcutId,
      String permissionMode = 'default'}) async {
    final response = await _post('/api/runs', <String, Object?>{
      'tool': tool,
      'workspaceId': workspaceId,
      if (prompt != null) 'prompt': prompt,
      if (shortcutId != null) 'shortcutId': shortcutId,
      'permissionMode': permissionMode,
    });
    return RunSummary.fromJson(response);
  }

  @override
  Future<List<AgentEvent>> fetchEvents(String runId, {int afterSeq = 0}) async {
    final response = await _get('/api/runs/$runId/events?afterSeq=$afterSeq');
    final items = response['events'] as List<Object?>;
    return items.cast<Map<String, Object?>>().map(AgentEvent.fromJson).toList();
  }

  @override
  Future<RunSummary> sendRunInput(String runId, String prompt,
      {String permissionMode = 'default'}) async {
    final response = await _post('/api/runs/$runId/input', <String, Object?>{
      'prompt': prompt,
      'permissionMode': permissionMode,
    });
    return RunSummary.fromJson(response);
  }

  @override
  Future<RunSummary> cancelRun(String runId) async {
    final response =
        await _post('/api/runs/$runId/cancel', const <String, Object?>{});
    return RunSummary.fromJson(response);
  }

  @override
  Future<void> respondApproval(String approvalId, String decision) async {
    await _post('/api/approvals/$approvalId/respond',
        <String, Object?>{'decision': decision});
  }

  Future<ExceptionTrace> recordException({
    required String message,
    String? stack,
    String? path,
    String? method,
    String? conversationId,
    String? runId,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    final response = await _post('/api/exceptions', <String, Object?>{
      'source': 'mobile',
      'severity': 'error',
      'message': message,
      if (stack != null) 'stack': stack,
      if (path != null) 'path': path,
      if (method != null) 'method': method,
      if (conversationId != null) 'conversationId': conversationId,
      if (runId != null) 'runId': runId,
      if (metadata.isNotEmpty) 'metadata': metadata,
    });
    return ExceptionTrace.fromJson(response);
  }

  @override
  Future<List<ConversationSummary>> listConversations() async {
    final response = await _get('/api/conversations');
    final items = response['conversations'] as List<Object?>;
    return items
        .cast<Map<String, Object?>>()
        .map(ConversationSummary.fromJson)
        .toList();
  }

  @override
  Future<ConversationSummary> createConversation(
      {required String workspaceId,
      String adapter = 'claude',
      String permissionMode = 'default'}) async {
    final response = await _post('/api/conversations', <String, Object?>{
      'workspaceId': workspaceId,
      'adapter': adapter,
      'permissionMode': permissionMode,
    });
    return ConversationSummary.fromJson(
        response['conversation'] as Map<String, Object?>);
  }

  @override
  Future<ConversationSummary> sendConversationMessage(
      String conversationId, String text) async {
    final response = await _post(
        '/api/conversations/$conversationId/messages', <String, Object?>{
      'text': text,
    });
    return ConversationSummary.fromJson(
        response['conversation'] as Map<String, Object?>);
  }

  @override
  Future<List<ConversationEvent>> fetchConversationEvents(String conversationId,
      {int afterSeq = 0}) async {
    final path = '/api/conversations/$conversationId/events?afterSeq=$afterSeq';
    final response = await _get(path);
    final items = response['events'] as List<Object?>;
    return items
        .cast<Map<String, Object?>>()
        .map(ConversationEvent.fromJson)
        .toList();
  }

  @override
  Future<ConversationSummary> answerConversationQuestion(
      String conversationId, String questionId, String text) async {
    final response = await _post(
        '/api/conversations/$conversationId/questions/respond',
        <String, Object?>{
          'questionId': questionId,
          'text': text,
        });
    return ConversationSummary.fromJson(
        response['conversation'] as Map<String, Object?>);
  }

  @override
  Future<ConversationSummary> respondConversationApproval(
      String conversationId, String approvalId, String decision) async {
    final response = await _post(
        '/api/conversations/$conversationId/approvals/$approvalId/respond',
        <String, Object?>{'decision': decision});
    return ConversationSummary.fromJson(
        response['conversation'] as Map<String, Object?>);
  }

  @override
  Future<ConversationSummary> cancelConversation(String conversationId) async {
    final response = await _post(
        '/api/conversations/$conversationId/cancel', const <String, Object?>{});
    return ConversationSummary.fromJson(
        response['conversation'] as Map<String, Object?>);
  }

  @override
  Future<void> revokeCurrentDevice() async {
    final deviceId = _deviceId;
    if (deviceId == null) return;
    await _post('/api/devices/$deviceId/revoke', const <String, Object?>{});
    await tokenStore.deleteAccessToken(deviceId);
    await tokenStore.deleteRefreshToken(deviceId);
    _deviceId = null;
    _token = null;
  }

  Future<Map<String, Object?>> _get(String path,
      {bool authorize = true}) async {
    final response = await _getWithRetry(path, authorize: authorize);
    if (authorize && _isAuthRequired(response)) {
      await _refreshAfterAuthRequired();
      final retry = await _getWithRetry(path, authorize: authorize);
      return _decode(retry);
    }
    return _decode(response);
  }

  Future<http.Response> _getWithRetry(String path,
      {required bool authorize}) async {
    try {
      return await _httpClient.get(baseUri.resolve(path),
          headers: _headers(authorize: authorize));
    } on SocketException {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return _httpClient.get(baseUri.resolve(path),
          headers: _headers(authorize: authorize));
    } on http.ClientException {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return _httpClient.get(baseUri.resolve(path),
          headers: _headers(authorize: authorize));
    }
  }

  Future<Map<String, Object?>> _post(String path, Map<String, Object?> body,
      {bool authorize = true}) async {
    final response = await _httpClient.post(
      baseUri.resolve(path),
      headers: _headers(authorize: authorize),
      body: jsonEncode(body),
    );
    if (authorize && _isAuthRequired(response)) {
      await _refreshAfterAuthRequired();
      final retry = await _httpClient.post(
        baseUri.resolve(path),
        headers: _headers(authorize: authorize),
        body: jsonEncode(body),
      );
      return _decode(retry);
    }
    return _decode(response);
  }

  bool _needsRefresh(TokenSession session) =>
      !_now().isBefore(session.expiresAt.subtract(refreshSkew));

  TokenSession _sessionFromResponse(Map<String, Object?> response,
      {required String tokenKey, required String expiresAtKey}) {
    final expiresAt = response[expiresAtKey] as String?;
    return TokenSession(
      token: response[tokenKey] as String,
      expiresAt: expiresAt == null
          ? DateTime.utc(9999, 12, 31)
          : DateTime.parse(expiresAt),
    );
  }

  bool _isAuthRequired(http.Response response) {
    if (response.statusCode != 401) return false;
    try {
      final decoded = _decodeResponseBody(response);
      final error = decoded['error'];
      if (error == 'AUTH_REQUIRED') return true;
      return error is Map<String, Object?> && error['code'] == 'AUTH_REQUIRED';
    } on DaemonClientException {
      return false;
    }
  }

  Future<void> _refreshAfterAuthRequired() async {
    await _refreshStoredTokenOrClear();
  }

  Future<void> _refreshStoredTokenOrClear() async {
    try {
      await refreshToken();
    } on DaemonClientException catch (error) {
      final deviceId = _deviceId;
      if (deviceId != null && error.statusCode == 401) {
        await tokenStore.deleteAccessToken(deviceId);
        await tokenStore.deleteRefreshToken(deviceId);
        _deviceId = null;
        _token = null;
      }
      rethrow;
    }
  }

  Map<String, String> _headers({required bool authorize}) {
    return <String, String>{
      'content-type': 'application/json; charset=utf-8',
      if (authorize && _token != null) 'authorization': 'Bearer $_token',
    };
  }

  Map<String, Object?> _decode(http.Response response) {
    final decoded = _decodeResponseBody(response);
    if (response.statusCode >= 400) {
      throw DaemonClientException(response.statusCode, decoded);
    }
    return decoded;
  }

  Map<String, Object?> _decodeResponseBody(http.Response response) {
    if (response.body.trim().isEmpty) {
      throw DaemonClientException(response.statusCode, <String, Object?>{
        'error': 'invalid_response',
        'message': 'daemon returned an empty response body',
      });
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, Object?>) return decoded;
      throw const FormatException('response body is not a JSON object');
    } on FormatException catch (error) {
      throw DaemonClientException(response.statusCode, <String, Object?>{
        'error': 'invalid_response',
        'message': 'daemon returned an invalid JSON response: ${error.message}',
      });
    }
  }
}

class ExceptionTrace {
  const ExceptionTrace({required this.traceId, required this.createdAt});

  final String traceId;
  final String createdAt;

  factory ExceptionTrace.fromJson(Map<String, Object?> json) => ExceptionTrace(
        traceId: json['traceId'] as String,
        createdAt: json['createdAt'] as String? ?? '',
      );
}

class TracedClientException implements Exception {
  const TracedClientException(this.message, this.traceId);

  final String message;
  final String traceId;

  @override
  String toString() => '$message (traceId: $traceId)';
}

http.Client createDaemonHttpClient(
    {DaemonProxyMode proxyMode = DaemonProxyMode.direct, Uri? manualProxy}) {
  final client = HttpClient()
    ..findProxy = (uri) => daemonClientProxyForUri(uri,
        proxyMode: proxyMode, manualProxy: manualProxy);
  return IOClient(client);
}

String daemonClientProxyForUri(Uri uri,
    {DaemonProxyMode proxyMode = DaemonProxyMode.direct, Uri? manualProxy}) {
  if (isLocalOrPrivateDaemonHost(uri.host)) return 'DIRECT';
  return switch (proxyMode) {
    DaemonProxyMode.direct => 'DIRECT',
    DaemonProxyMode.system => HttpClient.findProxyFromEnvironment(uri),
    DaemonProxyMode.manual => manualProxy == null
        ? 'DIRECT'
        : 'PROXY ${manualProxy.host}:${manualProxy.port}',
  };
}

class DaemonClientException implements Exception {
  const DaemonClientException(this.statusCode, this.body);
  final int statusCode;
  final Map<String, Object?> body;
  @override
  String toString() => 'DaemonClientException($statusCode, $body)';
}
