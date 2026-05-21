import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/services/conversation_service.dart';
import '../models/protocol.dart';
import 'daemon_client.dart';

class ConversationClient {
  ConversationClient({
    required this.baseUri,
    required this.tokenStore,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  final Uri baseUri;
  final SecureTokenStore tokenStore;
  final http.Client _httpClient;
  String? _deviceId;
  String? _token;

  Future<void> attachDevice(String deviceId) async {
    _deviceId = deviceId;
    _token = await tokenStore.readDeviceToken(deviceId);
  }

  Future<List<ConversationSummary>> listConversations() async {
    final response = await _get('/api/conversations');
    final items = response['conversations'] as List<Object?>;
    return items
        .cast<Map<String, Object?>>()
        .map(ConversationSummary.fromJson)
        .toList();
  }

  Future<ConversationSummary> createConversation({
    required String workspaceId,
    String adapter = 'claude',
    String permissionMode = 'default',
    String? model,
  }) async {
    final trimmedModel = model?.trim();
    final response = await _post('/api/conversations', <String, Object?>{
      'workspaceId': workspaceId,
      'adapter': adapter,
      'permissionMode': permissionMode,
      if (trimmedModel != null && trimmedModel.isNotEmpty)
        'model': trimmedModel,
    });
    return ConversationSummary.fromJson(
      response['conversation'] as Map<String, Object?>,
    );
  }

  Future<ConversationSummary> sendMessage(
      String conversationId, String text) async {
    return sendMessageRequest(
      conversationId,
      ConversationServiceMessageSendRequest(text: text),
    );
  }

  Future<ConversationSummary> sendMessageRequest(
    String conversationId,
    ConversationServiceMessageSendRequest request,
  ) async {
    if (request.attachments.isNotEmpty) {
      return _sendMultipartMessage(conversationId, request);
    }
    final response = await _post(
      '/api/conversations/$conversationId/messages',
      <String, Object?>{
        'text': request.text,
      },
    );
    return ConversationSummary.fromJson(
      response['conversation'] as Map<String, Object?>,
    );
  }

  Future<ConversationSummary> _sendMultipartMessage(
    String conversationId,
    ConversationServiceMessageSendRequest request,
  ) async {
    final multipart = http.MultipartRequest(
      'POST',
      baseUri.resolve('/api/conversations/$conversationId/messages'),
    )
      ..headers.addAll(_authHeaders())
      ..fields['payload'] =
          jsonEncode(conversationServiceMessagePayload(request));

    for (var index = 0; index < request.attachments.length; index++) {
      final attachment = request.attachments[index];
      multipart.files.add(await http.MultipartFile.fromPath(
        'files[]',
        attachment.localPath,
        filename: attachment.name,
      ));
    }

    final streamed = await _httpClient.send(multipart);
    final response = await http.Response.fromStream(streamed);
    final decoded = _decode(response);
    return ConversationSummary.fromJson(
      decoded['conversation'] as Map<String, Object?>,
    );
  }

  Future<List<ConversationEvent>> fetchEvents(
    String conversationId, {
    int afterSeq = 0,
  }) async {
    final response = await _get(
      '/api/conversations/$conversationId/events?afterSeq=$afterSeq',
    );
    final items = response['events'] as List<Object?>;
    return items
        .cast<Map<String, Object?>>()
        .map(ConversationEvent.fromJson)
        .toList();
  }

  Future<ConversationSummary> answerQuestion(
    String conversationId,
    String questionId,
    String text,
  ) async {
    final response = await _post(
      '/api/conversations/$conversationId/questions/respond',
      <String, Object?>{
        'questionId': questionId,
        'text': text,
      },
    );
    return ConversationSummary.fromJson(
      response['conversation'] as Map<String, Object?>,
    );
  }

  Future<ConversationSummary> respondApproval(
    String conversationId,
    String approvalId,
    String decision,
  ) async {
    final response = await _post(
      '/api/conversations/$conversationId/approvals/$approvalId/respond',
      <String, Object?>{
        'decision': decision,
      },
    );
    return ConversationSummary.fromJson(
      response['conversation'] as Map<String, Object?>,
    );
  }

  Future<ConversationSummary> cancelConversation(String conversationId) async {
    final response = await _post(
      '/api/conversations/$conversationId/cancel',
      const <String, Object?>{},
    );
    return ConversationSummary.fromJson(
      response['conversation'] as Map<String, Object?>,
    );
  }

  Future<Map<String, Object?>> _get(String path) async {
    final response = await _httpClient.get(
      baseUri.resolve(path),
      headers: _headers(),
    );
    return _decode(response);
  }

  Future<Map<String, Object?>> _post(
      String path, Map<String, Object?> body) async {
    final response = await _httpClient.post(
      baseUri.resolve(path),
      headers: _headers(),
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  Map<String, String> _headers() => <String, String>{
        'content-type': 'application/json; charset=utf-8',
        if (_token != null) 'authorization': 'Bearer $_token',
      };

  Map<String, String> _authHeaders() => <String, String>{
        if (_token != null) 'authorization': 'Bearer $_token',
      };

  Map<String, Object?> _decode(http.Response response) {
    if (response.body.trim().isEmpty) {
      throw DaemonClientException(
        response.statusCode,
        const <String, Object?>{'error': 'empty_response'},
      );
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, Object?>) {
        throw DaemonClientException(
          response.statusCode,
          const <String, Object?>{'error': 'invalid_response_format'},
        );
      }
      if (response.statusCode >= 400) {
        throw DaemonClientException(response.statusCode, decoded);
      }
      return decoded;
    } on FormatException catch (e) {
      throw DaemonClientException(
        response.statusCode,
        <String, Object?>{'error': 'malformed_json', 'message': e.message},
      );
    }
  }

  String? get deviceId => _deviceId;
}
