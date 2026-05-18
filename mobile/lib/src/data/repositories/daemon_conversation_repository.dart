import '../../domain/repositories/conversation_repository.dart';
import '../../models/protocol.dart';
import '../../services/daemon_client.dart';

class DaemonConversationRepository implements ConversationRepository {
  DaemonConversationRepository({required DaemonClient client})
      : _client = client;

  final DaemonClient _client;

  @override
  Future<List<ConversationSummary>> listConversations() =>
      _client.listConversations();

  @override
  Future<ConversationSummary> createConversation({
    required String workspaceId,
    String adapter = 'claude',
    String permissionMode = 'default',
    String? model,
  }) =>
      _client.createConversation(
        workspaceId: workspaceId,
        adapter: adapter,
        permissionMode: permissionMode,
        model: model,
      );

  @override
  Future<ConversationSummary> sendConversationMessage(
    String conversationId,
    String text,
  ) =>
      _client.sendConversationMessage(conversationId, text);

  @override
  Future<ConversationSummary> updateConversationModel(
    String conversationId,
    String? model,
  ) async {
    try {
      return await _client.updateConversationModel(conversationId, model);
    } on DaemonClientException catch (error) {
      throw ConversationRepositoryException(
        statusCode: error.statusCode,
        code: _daemonErrorCode(error.body),
        message: _daemonErrorMessage(error.body),
        cause: error,
      );
    }
  }

  @override
  Future<List<ConversationEvent>> fetchConversationEvents(
    String conversationId, {
    int afterSeq = 0,
  }) =>
      _client.fetchConversationEvents(conversationId, afterSeq: afterSeq);

  @override
  Future<ConversationSummary> answerConversationQuestion(
    String conversationId,
    String questionId,
    String text,
  ) =>
      _client.answerConversationQuestion(conversationId, questionId, text);

  @override
  Future<ConversationSummary> respondConversationApproval(
    String conversationId,
    String approvalId,
    String decision,
  ) =>
      _client.respondConversationApproval(conversationId, approvalId, decision);

  @override
  Future<ConversationSummary> cancelConversation(String conversationId) =>
      _client.cancelConversation(conversationId);
}

String? _daemonErrorCode(Map<String, Object?> body) {
  final bodyError = body['error'];
  if (bodyError is Map<String, Object?>) {
    final code = bodyError['code'];
    return code is String ? code : null;
  }
  return bodyError is String ? bodyError : null;
}

String? _daemonErrorMessage(Map<String, Object?> body) {
  final bodyError = body['error'];
  if (bodyError is Map<String, Object?>) {
    final message = bodyError['message'];
    return message is String && message.trim().isNotEmpty
        ? message.trim()
        : null;
  }
  final message = body['message'];
  if (message is String && message.trim().isNotEmpty) return message.trim();
  return null;
}
