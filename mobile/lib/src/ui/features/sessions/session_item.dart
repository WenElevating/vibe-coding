import '../../../models/protocol.dart';

class SessionItem {
  const SessionItem({required this.run, this.conversation});

  final RunSummary run;
  final ConversationSummary? conversation;

  String get id => conversation?.id ?? run.id;
}
