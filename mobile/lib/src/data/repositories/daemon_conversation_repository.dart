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
  }) =>
      _client.createConversation(
        workspaceId: workspaceId,
        adapter: adapter,
        permissionMode: permissionMode,
      );

  @override
  Future<ConversationSummary> sendConversationMessage(
    String conversationId,
    String text,
  ) =>
      _client.sendConversationMessage(conversationId, text);

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
