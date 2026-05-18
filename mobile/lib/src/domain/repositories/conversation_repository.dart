import '../../models/protocol.dart';

class ConversationRepositoryException implements Exception {
  const ConversationRepositoryException({
    required this.statusCode,
    this.code,
    this.message,
    this.cause,
  });

  final int statusCode;
  final String? code;
  final String? message;
  final Object? cause;

  @override
  String toString() {
    final detail = message?.trim();
    if (detail != null && detail.isNotEmpty) {
      return 'ConversationRepositoryException($statusCode, $detail)';
    }
    return 'ConversationRepositoryException($statusCode)';
  }
}

abstract class ConversationRepository {
  Future<List<ConversationSummary>> listConversations();

  Future<ConversationSummary> createConversation({
    required String workspaceId,
    String adapter,
    String permissionMode,
    String? model,
  });

  Future<ConversationSummary> sendConversationMessage(
    String conversationId,
    String text,
  );

  Future<ConversationSummary> updateConversationModel(
    String conversationId,
    String? model,
  );

  Future<List<ConversationEvent>> fetchConversationEvents(
    String conversationId, {
    int afterSeq,
  });

  Future<ConversationSummary> answerConversationQuestion(
    String conversationId,
    String questionId,
    String text,
  );

  Future<ConversationSummary> respondConversationApproval(
    String conversationId,
    String approvalId,
    String decision,
  );

  Future<ConversationSummary> cancelConversation(String conversationId);
}
