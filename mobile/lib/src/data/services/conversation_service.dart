import '../../models/protocol.dart';

class ConversationServiceMessageAttachment {
  const ConversationServiceMessageAttachment({
    required this.localPath,
    required this.name,
    required this.mimeType,
    required this.kind,
    required this.sizeBytes,
  });

  final String localPath;
  final String name;
  final String mimeType;
  final String kind;
  final int sizeBytes;
}

class ConversationServiceMessageSendRequest {
  const ConversationServiceMessageSendRequest({
    required this.text,
    this.clientMessageId,
    this.capabilityVersion,
    this.attachments = const <ConversationServiceMessageAttachment>[],
  });

  final String text;
  final String? clientMessageId;
  final String? capabilityVersion;
  final List<ConversationServiceMessageAttachment> attachments;
}

Map<String, Object?> conversationServiceMessagePayload(
  ConversationServiceMessageSendRequest request, {
  bool includeAttachments = true,
}) =>
    <String, Object?>{
      'text': request.text,
      if (request.clientMessageId != null)
        'clientMessageId': request.clientMessageId,
      if (request.capabilityVersion != null)
        'capabilityVersion': request.capabilityVersion,
      if (includeAttachments)
        'attachments': <Map<String, Object?>>[
          for (var index = 0; index < request.attachments.length; index++)
            <String, Object?>{
              'field': 'files[$index]',
              'name': request.attachments[index].name,
              'mimeType': request.attachments[index].mimeType,
              'kind': request.attachments[index].kind,
              'sizeBytes': request.attachments[index].sizeBytes,
            },
        ],
    };

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
    ConversationServiceMessageSendRequest request,
  );

  Future<ConversationSummary> updateConversationModel(
    String conversationId,
    String? model,
  );

  Future<List<ConversationEvent>> fetchConversationEvents(
    String conversationId, {
    int afterSeq,
  });

  Future<ConversationEventPage> fetchConversationEventPage(
    String conversationId, {
    int? beforeSeq,
    required int limit,
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
