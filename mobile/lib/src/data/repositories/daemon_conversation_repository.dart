import '../../domain/repositories/conversation_repository.dart';
import '../../models/protocol.dart';
import '../../services/daemon_client.dart';
import '../services/conversation_service.dart';
import '../services/notification_service.dart';

class DaemonConversationRepository implements ConversationRepository {
  DaemonConversationRepository({
    required DaemonClient client,
    NotificationService? notificationService,
  })  : _client = client,
        _notificationService = notificationService;

  final DaemonClient _client;
  final NotificationService? _notificationService;

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
    ConversationMessageSendRequest request,
  ) async {
    try {
      return await _client.sendConversationMessage(
        conversationId,
        _toServiceMessageRequest(request),
      );
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
  Stream<ConversationEvent> watchConversationEvents(
    String conversationId, {
    required int afterSeq,
  }) {
    final service = _notificationService;
    if (service == null) {
      return Stream<List<ConversationEvent>>.periodic(
        const Duration(seconds: 5),
      )
          .asyncMap(
              (_) => fetchConversationEvents(conversationId, afterSeq: afterSeq))
          .expand((events) => events);
    }
    return service.watchConversationEvents(conversationId, afterSeq: afterSeq);
  }

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

ConversationServiceMessageSendRequest _toServiceMessageRequest(
  ConversationMessageSendRequest request,
) =>
    ConversationServiceMessageSendRequest(
      text: request.text,
      clientMessageId: request.clientMessageId,
      capabilityVersion: request.capabilityVersion,
      attachments: <ConversationServiceMessageAttachment>[
        for (final attachment in request.attachments)
          ConversationServiceMessageAttachment(
            localPath: attachment.localPath,
            name: attachment.name,
            mimeType: attachment.mimeType,
            kind: attachment.kind.name,
            sizeBytes: attachment.sizeBytes,
          ),
      ],
    );

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
