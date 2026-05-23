import '../../models/protocol.dart';

abstract class NotificationService {
  Stream<ConversationEvent> watchConversationEvents(
    String conversationId, {
    required int afterSeq,
  });
}
