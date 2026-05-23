import '../../models/protocol.dart' hide AttachmentHandling, AttachmentKind;
import '../models/attachment_types.dart';

class ConversationMessageAttachment {
  const ConversationMessageAttachment({
    required this.localPath,
    required this.name,
    required this.mimeType,
    required this.kind,
    required this.sizeBytes,
  });

  final String localPath;
  final String name;
  final String mimeType;
  final AttachmentKind kind;
  final int sizeBytes;
}

class ConversationMessageSendRequest {
  const ConversationMessageSendRequest({
    required this.text,
    this.clientMessageId,
    this.capabilityVersion,
    this.attachments = const <ConversationMessageAttachment>[],
  });

  final String text;
  final String? clientMessageId;
  final String? capabilityVersion;
  final List<ConversationMessageAttachment> attachments;
}

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
    ConversationMessageSendRequest request,
  );

  Future<ConversationSummary> updateConversationModel(
    String conversationId,
    String? model,
  );

  Future<List<ConversationEvent>> fetchConversationEvents(
    String conversationId, {
    int afterSeq,
  });

  Stream<ConversationEvent> watchConversationEvents(
    String conversationId, {
    required int afterSeq,
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
