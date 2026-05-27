import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/ui/features/sessions/session_item.dart';
import 'package:lan_ai_cli_control/src/ui/features/sessions/view_models/session_list_view_model.dart';

void main() {
  group('SessionListViewModel', () {
    test('notifies once when remembering a local session', () {
      final viewModel = SessionListViewModel(
        conversations: const <ConversationSummary>[],
        runs: const <RunSummary>[],
      );
      var notifications = 0;
      viewModel.addListener(() => notifications++);

      viewModel.rememberSession(SessionItem(run: _run('run_1')));

      expect(notifications, 1);
      expect(viewModel.items.single.id, 'run_1');
    });

    test('replaces duplicate local session at the top', () {
      final viewModel = SessionListViewModel(
        conversations: const <ConversationSummary>[],
        runs: const <RunSummary>[],
      );

      viewModel.rememberSession(SessionItem(run: _run('run_1')));
      viewModel.rememberSession(SessionItem(run: _run('run_2')));
      viewModel.rememberSession(
          SessionItem(run: _run('run_1', status: 'completed')));

      expect(
          viewModel.items.map((item) => item.id), <String>['run_1', 'run_2']);
      expect(viewModel.items.first.run.status, 'completed');
    });

    test('notifies once when snapshot sessions update', () {
      final viewModel = SessionListViewModel(
        conversations: const <ConversationSummary>[],
        runs: const <RunSummary>[],
      );
      var notifications = 0;
      viewModel.addListener(() => notifications++);

      viewModel.updateFromSnapshot(
        conversations: <ConversationSummary>[_conversation('conversation_1')],
        runs: <RunSummary>[_run('run_1')],
      );

      expect(notifications, 1);
      expect(
        viewModel.items.map((item) => item.id),
        <String>['conversation_1', 'run_1'],
      );
    });

    test('snapshot conversation replaces optimistic session when persisted',
        () {
      final viewModel = SessionListViewModel(
        conversations: const <ConversationSummary>[],
        runs: const <RunSummary>[],
      );
      viewModel.rememberSession(SessionItem(
        run: _run('conversation_1', status: 'running'),
        conversation: _conversation(
          'conversation_1',
          status: 'idle',
          userMessageCount: 0,
        ),
      ));

      viewModel.updateFromSnapshot(
        conversations: <ConversationSummary>[
          _conversation(
            'conversation_1',
            status: 'running',
            userMessageCount: 1,
            title: 'Persisted title',
          ),
        ],
        runs: const <RunSummary>[],
      );

      expect(viewModel.items, hasLength(1));
      expect(viewModel.items.single.conversation?.title, 'Persisted title');
      expect(viewModel.items.single.run.status, 'running');
    });

    test('filters idle conversations without user activity', () {
      final viewModel = SessionListViewModel(
        conversations: <ConversationSummary>[
          _conversation('idle_empty', status: 'idle'),
          _conversation('idle_active', status: 'idle', userMessageCount: 1),
        ],
        runs: const <RunSummary>[],
      );

      expect(viewModel.items.map((item) => item.id), <String>['idle_active']);
    });
  });
}

RunSummary _run(String id, {String status = 'running'}) => RunSummary(
      id: id,
      tool: 'codex',
      workspaceId: 'workspace_1',
      status: status,
    );

ConversationSummary _conversation(
  String id, {
  String status = 'running',
  int userMessageCount = 0,
  String? title,
}) =>
    ConversationSummary(
      id: id,
      workspaceId: 'workspace_1',
      adapter: 'codex',
      status: status,
      capabilities: const ConversationCapabilities(
        longLivedProcess: false,
        waitingInput: false,
        waitingApproval: false,
        resume: false,
        partialOutput: false,
      ),
      createdAt: '2026-05-16T00:00:00.000Z',
      updatedAt: '2026-05-16T00:00:00.000Z',
      userMessageCount: userMessageCount,
      title: title,
    );
