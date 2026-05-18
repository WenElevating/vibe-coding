import '../../models/protocol.dart';

abstract class ConversationService {
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
