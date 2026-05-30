import 'package:flutter/foundation.dart';

import '../../domain/repositories/conversation_repository.dart';
import '../../models/protocol.dart';
import 'bootstrap_hydration.dart';

class CachedConversationRepository extends ChangeNotifier
    implements ConversationRepository, ConversationBootstrapTarget {
  CachedConversationRepository({required ConversationRepository delegate})
      : _delegate = delegate;

  final ConversationRepository _delegate;

  List<ConversationSummary> _conversations = const <ConversationSummary>[];
  bool _loading = false;
  Object? _error;
  bool _loaded = false;
  String? _loadedWorkspaceId;
  int _refreshGeneration = 0;
  int _mutationEpoch = 0;
  final _locallyMutatedConversationIds = <String>{};
  Future<void>? _refreshFuture;
  bool _disposed = false;

  List<ConversationSummary> get conversations =>
      List.unmodifiable(_conversations);
  bool get loading => _loading;
  Object? get error => _error;
  @override
  String? get loadedWorkspaceId => _loadedWorkspaceId;

  @override
  void replaceFromBootstrap({
    required String workspaceId,
    required List<ConversationSummary> conversations,
  }) {
    if (_disposed) return;
    _refreshGeneration++;
    _refreshFuture = null;
    _loading = false;
    _error = null;
    _loadedWorkspaceId = workspaceId;
    final sorted = conversations.toList(growable: false)
      ..sort(_compareByUpdatedAtDescending);
    _conversations = List<ConversationSummary>.unmodifiable(sorted);
    _loaded = true;
    _locallyMutatedConversationIds.clear();
    _notifyIfActive();
  }

  Future<void> refresh() {
    final generation = _startRefresh();
    final mutationEpoch = _mutationEpoch;
    final mutatedIdsAtStart = Set<String>.from(_locallyMutatedConversationIds);
    final future = _refreshForGeneration(
      generation: generation,
      mutationEpoch: mutationEpoch,
      mutatedIdsAtStart: mutatedIdsAtStart,
    );
    _refreshFuture = future;
    return future;
  }

  Future<void> _refreshForGeneration({
    required int generation,
    required int mutationEpoch,
    required Set<String> mutatedIdsAtStart,
  }) async {
    try {
      final conversations = await _delegate.listConversations();
      if (_canApplyRefreshResult(generation)) {
        _conversations = _mutationEpoch == mutationEpoch
            ? List<ConversationSummary>.unmodifiable(conversations)
            : _mergeConversationRefresh(
                conversations,
                mutatedIdsAtStart: mutatedIdsAtStart,
              );
        _locallyMutatedConversationIds.clear();
        _loaded = true;
      }
    } catch (error) {
      if (_isCurrentRefresh(generation)) _error = error;
      rethrow;
    } finally {
      if (!_disposed && _isCurrentRefresh(generation)) {
        _loading = false;
        _refreshFuture = null;
        _notifyIfActive();
      }
    }
  }

  @override
  Future<List<ConversationSummary>> listConversations() async {
    await _ensureLoaded();
    return conversations;
  }

  @override
  Future<ConversationSummary> createConversation({
    required String workspaceId,
    String adapter = 'claude',
    String permissionMode = 'default',
    String? model,
  }) async {
    _startMutation();
    try {
      final conversation = await _delegate.createConversation(
        workspaceId: workspaceId,
        adapter: adapter,
        permissionMode: permissionMode,
        model: model,
      );
      _upsert(conversation);
      return conversation;
    } catch (error) {
      _applyMutationError(error);
      rethrow;
    }
  }

  @override
  Future<ConversationSummary> sendConversationMessage(
    String conversationId,
    ConversationMessageSendRequest request,
  ) async {
    _startMutation();
    try {
      final conversation = await _delegate.sendConversationMessage(
        conversationId,
        request,
      );
      _upsert(conversation);
      return conversation;
    } catch (error) {
      _applyMutationError(error);
      rethrow;
    }
  }

  @override
  Future<ConversationSummary> updateConversationModel(
    String conversationId,
    String? model,
  ) async {
    _startMutation();
    try {
      final conversation = await _delegate.updateConversationModel(
        conversationId,
        model,
      );
      _upsert(conversation);
      return conversation;
    } catch (error) {
      _applyMutationError(error);
      rethrow;
    }
  }

  @override
  Future<List<ConversationEvent>> fetchConversationEvents(
    String conversationId, {
    int afterSeq = 0,
  }) =>
      _delegate.fetchConversationEvents(conversationId, afterSeq: afterSeq);

  @override
  Future<ConversationEventPage> fetchConversationEventPage(
    String conversationId, {
    int? beforeSeq,
    required int limit,
  }) =>
      _delegate.fetchConversationEventPage(
        conversationId,
        beforeSeq: beforeSeq,
        limit: limit,
      );

  @override
  Stream<ConversationEvent> watchConversationEvents(
    String conversationId, {
    required int afterSeq,
  }) =>
      _delegate.watchConversationEvents(
        conversationId,
        afterSeq: afterSeq,
      );

  @override
  Future<ConversationSummary> answerConversationQuestion(
    String conversationId,
    String questionId,
    String text,
  ) async {
    _startMutation();
    try {
      final conversation = await _delegate.answerConversationQuestion(
        conversationId,
        questionId,
        text,
      );
      _upsert(conversation);
      return conversation;
    } catch (error) {
      _applyMutationError(error);
      rethrow;
    }
  }

  @override
  Future<ConversationSummary> respondConversationApproval(
    String conversationId,
    String approvalId,
    String decision,
  ) async {
    _startMutation();
    try {
      final conversation = await _delegate.respondConversationApproval(
        conversationId,
        approvalId,
        decision,
      );
      _upsert(conversation);
      return conversation;
    } catch (error) {
      _applyMutationError(error);
      rethrow;
    }
  }

  @override
  Future<ConversationSummary> cancelConversation(String conversationId) async {
    _startMutation();
    try {
      final conversation = await _delegate.cancelConversation(conversationId);
      _upsert(conversation);
      return conversation;
    } catch (error) {
      _applyMutationError(error);
      rethrow;
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _refreshGeneration++;
    _mutationEpoch++;
    super.dispose();
  }

  int _startRefresh() {
    final generation = ++_refreshGeneration;
    if (_disposed) return generation;
    _loading = true;
    _error = null;
    _notifyIfActive();
    return generation;
  }

  void _startMutation() {
    _mutationEpoch++;
  }

  bool _isCurrentRefresh(int generation) => generation == _refreshGeneration;

  bool _canApplyRefreshResult(int generation) =>
      !_disposed && _isCurrentRefresh(generation);

  void _upsert(ConversationSummary conversation) {
    if (_disposed) return;
    final loadedWorkspaceId = _loadedWorkspaceId;
    if (loadedWorkspaceId != null &&
        conversation.workspaceId != loadedWorkspaceId) {
      return;
    }
    _mutationEpoch++;
    _locallyMutatedConversationIds.add(conversation.id);
    final index = _conversations.indexWhere(
      (item) => item.id == conversation.id,
    );
    final updated = <ConversationSummary>[..._conversations];
    if (index == -1) {
      updated.insert(0, conversation);
    } else {
      updated[index] = conversation;
    }
    updated.sort(_compareByUpdatedAtDescending);
    _conversations = List<ConversationSummary>.unmodifiable(updated);
    _notifyIfActive();
  }

  void _applyMutationError(Object error) {
    if (_disposed) return;
    _error = error;
    _notifyIfActive();
  }

  Future<void> _ensureLoaded() async {
    final refreshFuture = _refreshFuture;
    if (refreshFuture != null) {
      await refreshFuture;
      return;
    }
    if (!_loaded) {
      await refresh();
    }
  }

  void _notifyIfActive() {
    if (!_disposed) notifyListeners();
  }

  List<ConversationSummary> _mergeConversationRefresh(
    List<ConversationSummary> refreshed, {
    required Set<String> mutatedIdsAtStart,
  }) {
    final mutatedDuringRefresh =
        _locallyMutatedConversationIds.difference(mutatedIdsAtStart);
    final byId = <String, ConversationSummary>{
      for (final conversation in refreshed) conversation.id: conversation,
      for (final conversation in _conversations)
        if (mutatedDuringRefresh.contains(conversation.id))
          conversation.id: conversation,
    };
    final merged = byId.values.toList(growable: false)
      ..sort(_compareByUpdatedAtDescending);
    return List<ConversationSummary>.unmodifiable(merged);
  }
}

int _compareByUpdatedAtDescending(
  ConversationSummary left,
  ConversationSummary right,
) {
  final leftTime = DateTime.tryParse(left.updatedAt);
  final rightTime = DateTime.tryParse(right.updatedAt);
  if (leftTime != null && rightTime != null) {
    return rightTime.compareTo(leftTime);
  }
  if (leftTime != null) return -1;
  if (rightTime != null) return 1;
  return 0;
}
