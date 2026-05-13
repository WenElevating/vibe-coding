import 'package:flutter/foundation.dart';

import '../../../../models/protocol.dart';
import '../session_item.dart';
import '../session_list_view_model.dart';

class SessionListViewModel extends ChangeNotifier {
  SessionListViewModel({
    required List<ConversationSummary> conversations,
    required List<RunSummary> runs,
  })  : _conversations = conversations,
        _runs = runs;

  List<ConversationSummary> _conversations;
  List<RunSummary> _runs;
  final List<SessionItem> _localSessions = <SessionItem>[];

  List<SessionItem> get items =>
      mergeSessionItems(_localSessions, _conversations, _runs);

  void rememberSession(SessionItem item) {
    _localSessions.removeWhere((s) => s.id == item.id);
    _localSessions.insert(0, item);
    notifyListeners();
  }

  void updateFromSnapshot({
    required List<ConversationSummary> conversations,
    required List<RunSummary> runs,
  }) {
    _conversations = conversations;
    _runs = runs;
    notifyListeners();
  }
}
