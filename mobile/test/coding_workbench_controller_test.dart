import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/l10n/app_localizations_zh.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/conversation_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/diagnostics_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/run_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/workspace_repository.dart';
import 'package:lan_ai_cli_control/src/ui/features/sessions/session_item.dart';
import 'package:lan_ai_cli_control/src/ui/features/workbench/attachments/attachment_preview_cache.dart';
import 'package:lan_ai_cli_control/src/ui/features/workbench/attachments/draft_attachment.dart';
import 'package:lan_ai_cli_control/src/ui/features/workbench/workbench.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/shell/app_snapshot.dart';
import 'package:lan_ai_cli_control/src/workflows/workspace/create_workspace_workflow.dart';

void main() {
  test('workspace list route exposes daemon-confirmed workspaces', () {
    const current = WorkspaceSummary(
      id: 'workspace_current',
      name: 'Current Project',
      path: r'D:\current',
    );
    const route = WorkspaceListRouteState(
      workspaces: <WorkspaceSummary>[current],
    );

    expect(route.workspaces, const <WorkspaceSummary>[current]);
  });

  test(
      'creating workspace route keeps previous workspaces only as display state',
      () {
    const current = WorkspaceSummary(
      id: 'workspace_current',
      name: 'Current Project',
      path: r'D:\current',
    );
    const state = CreatingWorkspaceRouteState(
      previousWorkspaces: <WorkspaceSummary>[current],
      requestLabel: 'Created Workspace',
    );

    expect(state.workspaces, const <WorkspaceSummary>[current]);
    expect(state.requestLabel, 'Created Workspace');
  });

  test('sessions route carries workspace context and workspace list', () {
    const current = WorkspaceSummary(
      id: 'workspace_current',
      name: 'Current Project',
      path: r'D:\current',
    );
    const created = WorkspaceSummary(
      id: 'workspace_created',
      name: 'Created Workspace',
      path: r'D:\created',
    );

    const route = WorkspaceSessionsRouteState(
      workspace: created,
      workspaces: <WorkspaceSummary>[current, created],
    );

    expect(route.workspace, created);
    expect(route.workspaces, const <WorkspaceSummary>[current, created]);
  });

  test('conversation route carries workspace context and workspace list', () {
    const current = WorkspaceSummary(
      id: 'workspace_current',
      name: 'Current Project',
      path: r'D:\current',
    );
    const conversationWorkspace = WorkspaceSummary(
      id: 'workspace_conversation',
      name: 'Conversation Workspace',
      path: r'D:\conversation',
    );

    const route = ConversationRouteState(
      workspace: conversationWorkspace,
      workspaces: <WorkspaceSummary>[current, conversationWorkspace],
    );

    expect(route.workspace, conversationWorkspace);
    expect(route.workspaces,
        const <WorkspaceSummary>[current, conversationWorkspace]);
  });

  test('workbench view model owns current route workspace state', () {
    const other = WorkspaceSummary(
      id: 'workspace_2',
      name: 'Other Workspace',
      path: r'D:\other',
    );
    final viewModel = WorkbenchViewModel(
      initialData:
          _snapshot(workspaces: const <WorkspaceSummary>[_workspace, other]),
    );

    expect(viewModel.routeWorkspace, isNull);

    viewModel.showSessions(_workspace);
    expect(viewModel.routeWorkspace, _workspace);

    viewModel.showConversation(other);
    expect(viewModel.routeWorkspace, other);

    viewModel.showWorkspaceList();
    expect(viewModel.routeWorkspace, isNull);
  });

  test('workbench view model owns active conversation identity', () {
    final conversation = _conversation(
      id: 'conv_1',
      workspaceId: _workspace.id,
      status: 'running',
    );
    final updated = _conversation(
      id: 'conv_1',
      workspaceId: _workspace.id,
      status: 'idle',
      userMessageCount: 1,
    );
    final viewModel = WorkbenchViewModel(
      initialData: _snapshot(workspaces: const <WorkspaceSummary>[_workspace]),
    );

    expect(viewModel.activeRunId, isNull);
    expect(viewModel.activeConversationId, isNull);
    expect(viewModel.activeConversation, isNull);

    viewModel.openSession(SessionItem(
      run: WorkbenchViewModel.runSummaryFromConversation(conversation),
      conversation: conversation,
    ));
    expect(viewModel.activeRunId, 'conv_1');
    expect(viewModel.activeConversationId, 'conv_1');
    expect(viewModel.activeConversation, conversation);

    viewModel.updateActiveConversation(updated);
    expect(viewModel.activeRunId, 'conv_1');
    expect(viewModel.activeConversationId, 'conv_1');
    expect(viewModel.activeConversation, updated);

    viewModel.clearActiveConversation();
    expect(viewModel.activeRunId, isNull);
    expect(viewModel.activeConversationId, isNull);
    expect(viewModel.activeConversation, isNull);
  });

  test('workbench view model restores conversation adapter and locks changes',
      () {
    final conversation = _conversation(
      id: 'conv_codex',
      workspaceId: _workspace.id,
      status: 'idle',
      adapter: 'codex',
    );
    final viewModel = WorkbenchViewModel(
      initialData: _snapshot(
        workspaces: const <WorkspaceSummary>[_workspace],
        adapters: const <AdapterStatus>[_claudeAdapter, _codexAdapter],
      ),
    );

    expect(viewModel.selectedAdapter, 'claude');

    viewModel.openSession(SessionItem(
      run: WorkbenchViewModel.runSummaryFromConversation(conversation),
      conversation: conversation,
    ));
    expect(viewModel.selectedAdapter, 'codex');

    viewModel.setSelectedAdapter('claude');
    expect(viewModel.selectedAdapter, 'codex');
  });

  test(
      'workbench view model keeps active conversation adapter on snapshot update',
      () {
    final conversation = _conversation(
      id: 'conv_claude',
      workspaceId: _workspace.id,
      status: 'idle',
      adapter: 'claude',
    );
    final viewModel = WorkbenchViewModel(
      initialData: _snapshot(
        workspaces: const <WorkspaceSummary>[_workspace],
        adapters: const <AdapterStatus>[_codexAdapter, _claudeAdapter],
      ),
    );

    viewModel.updateActiveConversation(conversation);
    expect(viewModel.selectedAdapter, 'claude');

    viewModel.updateFromSnapshot(_snapshot(
      workspaces: const <WorkspaceSummary>[_workspace],
      adapters: const <AdapterStatus>[_codexAdapter],
      conversations: <ConversationSummary>[conversation],
    ));

    expect(viewModel.selectedAdapter, 'claude');
  });

  test('workbench view model owns operation busy and error state', () {
    final viewModel = WorkbenchViewModel(
      initialData: _snapshot(workspaces: const <WorkspaceSummary>[_workspace]),
    );

    expect(viewModel.sending, isFalse);
    expect(viewModel.error, isNull);
    expect(viewModel.errorTraceId, isNull);

    viewModel.beginOperation();
    expect(viewModel.sending, isTrue);
    expect(viewModel.error, isNull);
    expect(viewModel.errorTraceId, isNull);

    viewModel.setOperationError('boom', traceId: 'trace_1');
    expect(viewModel.error, 'boom');
    expect(viewModel.errorTraceId, 'trace_1');

    viewModel.finishOperation();
    expect(viewModel.sending, isFalse);

    viewModel.clearOperationError();
    expect(viewModel.error, isNull);
    expect(viewModel.errorTraceId, isNull);
  });

  test('send acknowledgement timeout is non-fatal after session is active', () {
    final timeout = TimeoutException('Future not completed');

    expect(
      isSendAcknowledgementTimeout(
        timeout,
        activeConversationId: 'conv_1',
        activeRunId: null,
      ),
      isTrue,
    );
    expect(
      isSendAcknowledgementTimeout(
        timeout,
        activeConversationId: null,
        activeRunId: 'run_1',
      ),
      isTrue,
    );
    expect(
      isSendAcknowledgementTimeout(
        timeout,
        activeConversationId: null,
        activeRunId: null,
      ),
      isFalse,
    );
    expect(
      isSendAcknowledgementTimeout(
        Exception('boom'),
        activeConversationId: 'conv_1',
        activeRunId: null,
      ),
      isFalse,
    );
  });

  test('workbench view model owns conversation event projection', () {
    final viewModel = WorkbenchViewModel(
      initialData: _snapshot(workspaces: const <WorkspaceSummary>[_workspace]),
    );
    final conversation = _conversation(
      id: 'conv_1',
      workspaceId: _workspace.id,
      status: 'running',
    );
    viewModel.updateActiveConversation(conversation);

    final approvalEventsApplied = viewModel.applyConversationEvents(
      <ConversationEvent>[
        _event(seq: 1, type: 'user.message', text: 'run tests'),
        _event(seq: 2, type: 'assistant.partial', text: 'Checking'),
        _event(
          seq: 3,
          type: 'approval.requested',
          approvalId: 'approval_1',
          toolUseId: 'tool_1',
          toolName: 'Bash',
          summary: 'Run flutter tests',
          input: const <String, Object?>{'command': 'flutter test'},
        ),
      ],
      streamOutput: true,
    );

    expect(approvalEventsApplied, isTrue);
    expect(viewModel.lastSeq, 3);
    expect(viewModel.conversationEvents, hasLength(3));
    expect(viewModel.conversationState.status, 'waiting_approval');
    expect(viewModel.pendingQuestionId, isNull);
    expect(viewModel.activeConversation?.status, 'waiting_approval');
    expect(
        viewModel.activeConversation?.blockingItem?.approvalId, 'approval_1');
    expect(
      viewModel.messages.map((message) => '${message.role}:${message.body}'),
      const <String>[
        'user:run tests',
        'assistant_stream:Checking',
        'approval:Run flutter tests',
      ],
    );

    final completionEventsApplied = viewModel.applyConversationEvents(
      <ConversationEvent>[
        _event(
          seq: 4,
          type: 'approval.resolved',
          approvalId: 'approval_1',
          toolUseId: 'tool_1',
          toolName: 'Bash',
          input: const <String, Object?>{'command': 'flutter test'},
          raw: const <String, Object?>{'decision': 'allow'},
        ),
        _event(seq: 5, type: 'assistant.message', text: 'Done.'),
      ],
      streamOutput: true,
    );

    expect(completionEventsApplied, isTrue);
    expect(viewModel.lastSeq, 5);
    expect(viewModel.conversationEvents, hasLength(5));
    expect(viewModel.conversationState.status, 'idle');
    expect(viewModel.activeConversation?.status, 'idle');
    expect(viewModel.activeConversation?.blockingItem, isNull);
    expect(
      viewModel.messages.map((message) => '${message.role}:${message.body}'),
      const <String>[
        'user:run tests',
        'command:flutter test',
        'assistant:Done.',
      ],
    );
  });

  test('conversation started event keeps optimistic user message visible', () {
    final viewModel = WorkbenchViewModel(
      initialData: _snapshot(workspaces: const <WorkspaceSummary>[_workspace]),
    );
    viewModel.updateActiveConversation(_conversation(
        id: 'conv_1', workspaceId: _workspace.id, status: 'sending'));
    viewModel.addUserMessage('inspect image');

    final changed = viewModel.applyConversationEvents(
      <ConversationEvent>[_event(seq: 1, type: 'conversation.started')],
      streamOutput: false,
    );

    expect(changed, isTrue);
    expect(viewModel.messages.single.role, 'user');
    expect(viewModel.messages.single.body, 'inspect image');
  });

  test('committed attachment event binds cache identity and resolves local path',
      () async {
    const imageCapableAdapter = AdapterStatus(
      adapter: 'codex',
      available: true,
      status: 'available',
      capabilityVersion: 'cap_v1',
      attachmentCapabilities:
          AttachmentCapabilities(image: AttachmentHandling.native),
    );
    final repository = _FakeConversationRepository();
    final cache = _FakeAttachmentPreviewCache();
    final viewModel = WorkbenchViewModel(
      initialData: _snapshot(
        workspaces: const <WorkspaceSummary>[_workspace],
        adapters: const <AdapterStatus>[imageCapableAdapter],
      ),
      conversationRepository: repository,
      attachmentPreviewCache: cache,
    );
    viewModel.updateActiveConversation(_conversation(
        id: 'conv_1', workspaceId: _workspace.id, status: 'sending'));
    viewModel.addDraftAttachmentForTest(const DraftAttachment(
      localPath: r'C:\tmp\screenshot.png',
      name: 'screenshot.png',
      mimeType: 'image/png',
      kind: AttachmentKind.image,
      sizeBytes: 42,
    ));
    viewModel.addUserMessage('inspect image', includeDraftAttachments: true);
    await viewModel.sendExistingConversationPrompt(
      conversationId: 'conv_1',
      prompt: 'inspect image',
    );
    final clientMessageId = repository.sentRequests.single.clientMessageId;
    expect(clientMessageId, isNotNull);

    await viewModel.applyConversationEventsAsync(
      <ConversationEvent>[
        ConversationEvent(
          seq: 1,
          conversationId: 'conv_1',
          type: 'user.message',
          createdAt: DateTime.parse('2026-05-12T00:00:01.000Z'),
          text: 'inspect image',
          raw: <String, Object?>{'clientMessageId': clientMessageId},
          attachments: const <CommittedAttachment>[
            CommittedAttachment(
              id: 'att_0',
              name: 'screenshot.png',
              kind: AttachmentKind.image,
              mimeType: 'image/png',
              sizeBytes: 42,
              handling: AttachmentHandling.native,
            ),
          ],
        ),
      ],
      streamOutput: false,
    );

    expect(cache.bound, <String>[
      'conv_1|$clientMessageId|att_0|hash_0',
    ]);
    expect(viewModel.messages.single.attachments.single.localPath,
        r'C:\cache\screenshot.png');

    viewModel.resetConversationDisplay(clearActiveConversation: false);
    await viewModel.applyConversationEventsAsync(
      <ConversationEvent>[
        ConversationEvent(
          seq: 1,
          conversationId: 'conv_1',
          type: 'user.message',
          createdAt: DateTime.parse('2026-05-12T00:00:01.000Z'),
          text: 'inspect image',
          raw: <String, Object?>{'clientMessageId': clientMessageId},
          attachments: const <CommittedAttachment>[
            CommittedAttachment(
              id: 'att_0',
              name: 'screenshot.png',
              kind: AttachmentKind.image,
              mimeType: 'image/png',
              sizeBytes: 42,
              handling: AttachmentHandling.native,
            ),
          ],
        ),
      ],
      streamOutput: false,
    );

    expect(viewModel.messages.single.attachments.single.localPath,
        r'C:\cache\screenshot.png');
  });

  test('attachment preview cache failure does not block event projection',
      () async {
    final cache = _FakeAttachmentPreviewCache()
      ..bindError = StateError('preview cache unavailable')
      ..resolveError = StateError('preview cache unavailable');
    final viewModel = WorkbenchViewModel(
      initialData: _snapshot(workspaces: const <WorkspaceSummary>[_workspace]),
      attachmentPreviewCache: cache,
    );
    viewModel.updateActiveConversation(
        _conversation(id: 'conv_1', workspaceId: _workspace.id));

    final changed = await viewModel.applyConversationEventsAsync(
      <ConversationEvent>[
        ConversationEvent(
          seq: 1,
          conversationId: 'conv_1',
          type: 'user.message',
          createdAt: DateTime.parse('2026-05-12T00:00:01.000Z'),
          text: 'inspect image',
          raw: const <String, Object?>{'clientMessageId': 'client_1'},
          attachments: const <CommittedAttachment>[
            CommittedAttachment(
              id: 'att_0',
              name: 'screenshot.png',
              kind: AttachmentKind.image,
              mimeType: 'image/png',
              sizeBytes: 42,
              handling: AttachmentHandling.native,
            ),
          ],
        ),
      ],
      streamOutput: false,
    );

    expect(changed, isTrue);
    expect(viewModel.messages.single.body, 'inspect image');
    expect(viewModel.messages.single.attachments.single.localPath, isNull);
  });

  test('workbench view model exposes pending question id', () {
    final viewModel = WorkbenchViewModel(
      initialData: _snapshot(workspaces: const <WorkspaceSummary>[_workspace]),
    );
    viewModel.applyConversationEvents(
      <ConversationEvent>[
        _event(seq: 1, type: 'assistant.message', text: 'Need detail'),
        _event(
          seq: 2,
          type: 'assistant.question',
          questionId: 'question_hidden',
          text: 'Which direction?',
          raw: const <String, Object?>{'turnFinal': false},
        ),
      ],
      streamOutput: false,
    );

    expect(viewModel.pendingQuestionId, 'question_hidden');

    viewModel.applyConversationEvents(
      <ConversationEvent>[
        _event(
          seq: 3,
          type: 'assistant.question',
          questionId: 'question_visible',
          text: 'Pick one',
        )
      ],
      streamOutput: false,
    );

    expect(viewModel.pendingQuestionId, 'question_visible');
  });

  test('workbench view model resets conversation display state', () {
    final viewModel = WorkbenchViewModel(
      initialData: _snapshot(workspaces: const <WorkspaceSummary>[_workspace]),
    );
    final conversation = _conversation(
      id: 'conv_1',
      workspaceId: _workspace.id,
      status: 'running',
    );
    viewModel.updateActiveConversation(conversation);
    viewModel.addUserMessage('hello');
    viewModel.applyConversationEvents(
      <ConversationEvent>[
        _event(seq: 1, type: 'conversation.started'),
        _event(seq: 2, type: 'assistant.message', text: 'hi'),
      ],
      streamOutput: false,
    );

    expect(viewModel.messages, isNotEmpty);
    expect(viewModel.conversationEvents, isNotEmpty);
    expect(viewModel.lastSeq, 2);
    expect(viewModel.activeConversationId, 'conv_1');

    viewModel.resetConversationDisplay();

    expect(viewModel.messages, isEmpty);
    expect(viewModel.conversationEvents, isEmpty);
    expect(viewModel.conversationState.messages, isEmpty);
    expect(viewModel.conversationState.status, 'idle');
    expect(viewModel.lastSeq, 0);
    expect(viewModel.activeConversationId, isNull);
    expect(viewModel.activeConversation, isNull);
  });

  test('reusable conversation statuses can send another message', () {
    expect(canSendInConversationStatus(null), isTrue);
    expect(canSendInConversationStatus('idle'), isTrue);
    expect(canSendInConversationStatus('cancelled'), isTrue);
    expect(canSendInConversationStatus('failed'), isTrue);
    expect(canSendInConversationStatus('interrupted'), isTrue);
    expect(canSendInConversationStatus('running'), isFalse);
    expect(canSendInConversationStatus('waiting_input'), isFalse);
    expect(canSendInConversationStatus('waiting_approval'), isFalse);
  });

  test('active conversation status helper matches executor states', () {
    expect(isActiveConversationStatus('sending'), isTrue);
    expect(isActiveConversationStatus('running'), isTrue);
    expect(isActiveConversationStatus('waiting_input'), isTrue);
    expect(isActiveConversationStatus('waiting_approval'), isTrue);
    expect(isActiveConversationStatus('cancelled'), isFalse);
    expect(isActiveConversationStatus('interrupted'), isFalse);
  });

  test('terminal poll drain keeps one extra poll after completion events', () {
    expect(
      shouldKeepPollingForTerminalDrain(
        isRunningCli: true,
        changed: false,
        drainPending: false,
      ),
      isTrue,
    );
    expect(
      shouldKeepPollingForTerminalDrain(
        isRunningCli: false,
        changed: true,
        drainPending: false,
      ),
      isTrue,
    );
    expect(
      shouldKeepPollingForTerminalDrain(
        isRunningCli: false,
        changed: false,
        drainPending: true,
      ),
      isFalse,
    );
  });

  test('pending status does not report completed tool activity', () {
    final l10n = AppLocalizationsZh();
    final events = <ConversationEvent>[
      _event(
        seq: 1,
        type: 'conversation.status_changed',
        raw: const <String, Object?>{'status': 'running'},
      ),
      _event(
        seq: 2,
        type: 'tool.started',
        toolUseId: 'cmd_1',
        toolName: 'command_execution',
        input: const <String, Object?>{'command': 'flutter test'},
      ),
      _event(
        seq: 3,
        type: 'tool.completed',
        toolUseId: 'cmd_1',
        toolName: 'command_execution',
        text: 'Done',
      ),
    ];

    expect(
      conversationPendingStatusText(l10n, 'running', events),
      l10n.workbenchPendingWaitingNextEvent,
    );
  });

  test('send acknowledgement does not overwrite terminal event state', () {
    expect(
      shouldApplyConversationSendAcknowledgement(
        sendStartSeq: 10,
        currentSeq: 12,
        acknowledgementStatus: 'running',
        reducerStatus: 'idle',
      ),
      isFalse,
    );
    expect(
      shouldApplyConversationSendAcknowledgement(
        sendStartSeq: 10,
        currentSeq: 10,
        acknowledgementStatus: 'running',
        reducerStatus: 'idle',
      ),
      isTrue,
    );
    expect(
      shouldApplyConversationSendAcknowledgement(
        sendStartSeq: 10,
        currentSeq: 12,
        acknowledgementStatus: 'idle',
        reducerStatus: 'idle',
      ),
      isTrue,
    );
  });

  test('cancelled conversation summary keeps product identity and binding', () {
    const conversation = ConversationSummary(
      id: 'conv_1',
      workspaceId: 'workspace_1',
      adapter: 'claude',
      status: 'cancelled',
      cliSessionId: 'claude-session-1',
      sessionBinding: 'confirmed',
      userMessageCount: 2,
      capabilities: ConversationCapabilities(
        longLivedProcess: true,
        waitingInput: true,
        waitingApproval: true,
        resume: true,
        partialOutput: true,
      ),
      blockingItem: ConversationBlockingItem(type: 'approval_request'),
      createdAt: '2026-05-08T00:00:00.000Z',
      updatedAt: '2026-05-08T00:00:01.000Z',
    );

    final cancelled = applyCancelledConversationSummary(conversation);

    expect(cancelled.id, 'conv_1');
    expect(cancelled.cliSessionId, 'claude-session-1');
    expect(cancelled.sessionBinding, 'confirmed');
    expect(cancelled.userMessageCount, 2);
    expect(cancelled.blockingItem, isNull);
  });

  test('workbench view model coordinates new conversation send flow', () async {
    final repository = _FakeConversationRepository();
    final viewModel = WorkbenchViewModel(
      initialData: _snapshot(workspaces: const <WorkspaceSummary>[_workspace]),
      conversationRepository: repository,
    );

    final result = await viewModel.createAndSend(
      workspace: _workspace,
      prompt: 'hello',
      adapter: 'codex',
      permissionMode: 'default',
    );
    final updated = await result.updatedConversation;

    expect(repository.calls, <String>[
      'create:workspace_1:codex:default',
      'send:conv_1:hello',
    ]);
    expect(result.conversation.id, 'conv_1');
    expect(result.runningConversation.status, 'sending');
    expect(result.run.id, 'conv_1');
    expect(updated.status, 'idle');
  });

  test('workbench view model keeps optimistic session until snapshot is active',
      () async {
    final repository = _FakeConversationRepository();
    final viewModel = WorkbenchViewModel(
      initialData: _snapshot(workspaces: const <WorkspaceSummary>[_workspace]),
      conversationRepository: repository,
    );

    final result = await viewModel.createAndSend(
      workspace: _workspace,
      prompt: 'hello',
      adapter: 'codex',
      permissionMode: 'default',
    );
    final optimisticItems = viewModel.sessionItems(
      const <ConversationSummary>[],
      const <RunSummary>[],
    );

    expect(optimisticItems, hasLength(1));
    expect(optimisticItems.single.id, 'conv_1');
    expect(optimisticItems.single.conversation?.status, 'sending');

    viewModel.reconcile(
      _snapshot(
        workspaces: const <WorkspaceSummary>[_workspace],
        conversations: <ConversationSummary>[
          _conversation(
              id: 'conv_1', workspaceId: _workspace.id, status: 'idle'),
        ],
      ),
    );
    final idleSnapshotItems = viewModel.sessionItems(
      <ConversationSummary>[
        _conversation(id: 'conv_1', workspaceId: _workspace.id, status: 'idle'),
      ],
      const <RunSummary>[],
    );

    expect(idleSnapshotItems, hasLength(1));
    expect(idleSnapshotItems.single.conversation?.status, 'sending');

    viewModel.reconcile(
      _snapshot(
        workspaces: const <WorkspaceSummary>[_workspace],
        conversations: <ConversationSummary>[
          _conversation(
            id: 'conv_1',
            workspaceId: _workspace.id,
            status: 'running',
            userMessageCount: 1,
          ),
        ],
      ),
    );
    final activeSnapshotItems = viewModel.sessionItems(
      <ConversationSummary>[
        _conversation(
          id: 'conv_1',
          workspaceId: _workspace.id,
          status: 'running',
          userMessageCount: 1,
        ),
      ],
      const <RunSummary>[],
    );

    expect(activeSnapshotItems, hasLength(1));
    expect(activeSnapshotItems.single.conversation?.status, 'running');
    expect(await result.updatedConversation, isA<ConversationSummary>());
  });

  test('workbench view model sends existing conversation prompt', () async {
    final repository = _FakeConversationRepository();
    final viewModel = WorkbenchViewModel(
      initialData: _snapshot(workspaces: const <WorkspaceSummary>[_workspace]),
      conversationRepository: repository,
    );

    final updated = await viewModel.sendExistingConversationPrompt(
      conversationId: 'conv_existing',
      prompt: 'continue',
    );

    expect(repository.calls, <String>['send:conv_existing:continue']);
    expect(updated.id, 'conv_existing');
    expect(updated.status, 'idle');
  });

  test('workbench view model fetches conversation events after sequence',
      () async {
    final repository = _FakeConversationRepository();
    final viewModel = WorkbenchViewModel(
      initialData: _snapshot(workspaces: const <WorkspaceSummary>[_workspace]),
      conversationRepository: repository,
    );

    final events = await viewModel.fetchConversationEvents(
      conversationId: 'conv_existing',
      afterSeq: 7,
    );

    expect(repository.calls, <String>['events:conv_existing:7']);
    expect(events.single.seq, 8);
    expect(events.single.type, 'assistant.message');
  });

  test('workbench view model responds to conversation approval', () async {
    final repository = _FakeConversationRepository();
    final viewModel = WorkbenchViewModel(
      initialData: _snapshot(workspaces: const <WorkspaceSummary>[_workspace]),
      conversationRepository: repository,
    );

    final updated = await viewModel.respondConversationApproval(
      conversationId: 'conv_existing',
      approvalId: 'approval_1',
      decision: 'allow',
    );

    expect(repository.calls, <String>[
      'approval:conv_existing:approval_1:allow',
    ]);
    expect(updated.id, 'conv_existing');
    expect(updated.status, 'running');
  });

  test('workbench view model responds to run approval fallback', () async {
    final repository = _FakeRunRepository();
    final viewModel = WorkbenchViewModel(
      initialData: _snapshot(workspaces: const <WorkspaceSummary>[_workspace]),
      runRepository: repository,
    );

    await viewModel.respondRunApproval(
      approvalId: 'approval_1',
      decision: 'allow',
    );

    expect(repository.calls, <String>['approval:approval_1:allow']);
  });

  test('workbench view model cancels active conversation', () async {
    final repository = _FakeConversationRepository();
    final viewModel = WorkbenchViewModel(
      initialData: _snapshot(workspaces: const <WorkspaceSummary>[_workspace]),
      conversationRepository: repository,
    );

    final result = await viewModel.cancelActiveRun(conversationId: 'conv_1');

    expect(repository.calls, <String>['cancelConversation:conv_1']);
    expect(result.conversation?.id, 'conv_1');
    expect(result.conversation?.status, 'cancelled');
    expect(result.run?.id, 'conv_1');
    expect(result.run?.status, 'cancelled');
  });

  test('workbench view model cancels active run', () async {
    final repository = _FakeRunRepository();
    final viewModel = WorkbenchViewModel(
      initialData: _snapshot(workspaces: const <WorkspaceSummary>[_workspace]),
      runRepository: repository,
    );

    final result = await viewModel.cancelActiveRun(runId: 'run_1');

    expect(repository.calls, <String>['cancelRun:run_1']);
    expect(result.conversation, isNull);
    expect(result.run?.id, 'run_1');
    expect(result.run?.status, 'cancelled');
  });

  test('workbench view model records exceptions with operation metadata',
      () async {
    final repository = _FakeDiagnosticsRepository();
    final viewModel = WorkbenchViewModel(
      initialData: _snapshot(workspaces: const <WorkspaceSummary>[_workspace]),
      diagnosticsRepository: repository,
    );

    final traceId = await viewModel.recordException(
      message: 'boom',
      stack: 'stack',
      path: '/api/conversations',
      conversationId: 'conv_1',
      runId: 'run_1',
      operation: 'poll_events',
    );

    expect(traceId, 'trace_1');
    expect(repository.calls, <String>[
      'boom|stack|/api/conversations|GET|conv_1|run_1|error|poll_events|null|null|null|null|null|null|null',
    ]);
  });

  test('workbench view model records poll trace metadata', () async {
    final repository = _FakeDiagnosticsRepository();
    final viewModel = WorkbenchViewModel(
      initialData: _snapshot(workspaces: const <WorkspaceSummary>[_workspace]),
      diagnosticsRepository: repository,
    );

    await viewModel.recordPollTrace(WorkbenchPollTraceEntry(
      conversationId: 'conv_1',
      runId: 'run_1',
      path: '/api/conversations/conv_1/events?afterSeq=7',
      afterSeq: 7,
      returnedCount: 3,
      durationMs: 42,
      cancelled: false,
      changed: true,
      terminalDrainPending: false,
    ));

    expect(viewModel.pollTraceEntries, hasLength(1));
    expect(viewModel.pollTraceEntries.single.afterSeq, 7);
    expect(repository.calls, <String>[
      'pollConversationEvents: success|null|/api/conversations/conv_1/events?afterSeq=7|GET|conv_1|run_1|info|pollConversationEvents|7|3|42|false|true|false|null',
    ]);
  });

  test('workbench view model creates workspace through workflow', () async {
    const created = WorkspaceSummary(
      id: 'workspace_new',
      name: 'New Workspace',
      path: r'D:\new',
    );
    final repository = _FakeWorkspaceRepository(
      createdWorkspace: created,
      listedWorkspaces: const <WorkspaceSummary>[_workspace, created],
    );
    final viewModel = WorkbenchViewModel(
      initialData: _snapshot(workspaces: const <WorkspaceSummary>[_workspace]),
      workspaceRepository: repository,
      workspaceCreationTimeout: const Duration(seconds: 1),
    );

    final outcome = await viewModel.createWorkspace(
      path: created.path,
      name: created.name,
    );

    expect(repository.calls, <String>[
      r'create:D:\new:New Workspace',
      'list',
    ]);
    expect(outcome, isA<CreateWorkspaceSuccess>());
    expect((outcome as CreateWorkspaceSuccess).workspace, created);
  });
}

const _workspace = WorkspaceSummary(
  id: 'workspace_1',
  name: 'Workspace',
  path: r'D:\workspace',
);

AppSnapshot _snapshot({
  required List<WorkspaceSummary> workspaces,
  List<AdapterStatus> adapters = const <AdapterStatus>[],
  List<ConversationSummary> conversations = const <ConversationSummary>[],
}) =>
    AppSnapshot(
      health: const DaemonHealth(
        status: 'ok',
        daemonVersion: '1.0.0',
        mode: 'lan',
        lanMode: true,
        bindAddress: '127.0.0.1',
        port: 4317,
        security: <String, Object?>{},
      ),
      workspaces: workspaces,
      workspace: workspaces.first,
      overview: ProjectOverview(
        workspaceId: workspaces.first.id,
        name: 'Workspace',
        path: workspaces.first.path,
        fileCount: 0,
        codeLineCount: 0,
        symbolCount: 0,
        analysisScore: 0,
        recentFiles: const <RecentFileSummary>[],
      ),
      adapters: adapters,
      runs: const <RunSummary>[],
      conversations: conversations,
      queue: const <QueueItem>[],
      templates: const <CommandTemplate>[],
      gitStatus: null,
      diffs: const <DiffSummary>[],
      commits: const <GitCommitSummary>[],
      fileTree: FileTreeResponse(
        workspaceId: workspaces.first.id,
        root: '',
        entries: const <FileTreeEntry>[],
      ),
      diagnostics: CodeDiagnosticsSummary(
        workspaceId: workspaces.first.id,
        available: false,
        diagnostics: const <CodeDiagnostic>[],
      ),
      extensions: const <ExtensionSummary>[],
    );

class _FakeConversationRepository implements ConversationRepository {
  final List<String> calls = <String>[];
  final List<ConversationMessageSendRequest> sentRequests =
      <ConversationMessageSendRequest>[];

  @override
  Future<ConversationSummary> createConversation({
    required String workspaceId,
    String adapter = 'claude',
    String permissionMode = 'default',
    String? model,
  }) async {
    calls.add('create:$workspaceId:$adapter:$permissionMode');
    return _conversation(
        id: 'conv_1', workspaceId: workspaceId, status: 'idle');
  }

  @override
  Future<ConversationSummary> sendConversationMessage(
    String conversationId,
    ConversationMessageSendRequest request,
  ) async {
    calls.add('send:$conversationId:${request.text}');
    sentRequests.add(request);
    return _conversation(
      id: conversationId,
      workspaceId: _workspace.id,
      status: 'idle',
    );
  }

  @override
  Future<ConversationSummary> answerConversationQuestion(
    String conversationId,
    String questionId,
    String text,
  ) async {
    calls.add('answer:$conversationId:$questionId:$text');
    return _conversation(
      id: conversationId,
      workspaceId: _workspace.id,
      status: 'idle',
    );
  }

  @override
  Future<ConversationSummary> cancelConversation(String conversationId) async {
    calls.add('cancelConversation:$conversationId');
    return _conversation(
      id: conversationId,
      workspaceId: _workspace.id,
      status: 'cancelled',
    );
  }

  @override
  Future<List<ConversationEvent>> fetchConversationEvents(
    String conversationId, {
    int afterSeq = 0,
  }) async {
    calls.add('events:$conversationId:$afterSeq');
    return <ConversationEvent>[
      ConversationEvent(
        seq: afterSeq + 1,
        conversationId: conversationId,
        type: 'assistant.message',
        createdAt: DateTime.parse('2026-05-12T00:00:02.000Z'),
        text: 'hello',
      ),
    ];
  }

  @override
  Future<List<ConversationSummary>> listConversations() async =>
      throw UnimplementedError();

  @override
  Future<ConversationSummary> respondConversationApproval(
    String conversationId,
    String approvalId,
    String decision,
  ) async {
    calls.add('approval:$conversationId:$approvalId:$decision');
    return _conversation(
      id: conversationId,
      workspaceId: _workspace.id,
      status: 'running',
    );
  }

  @override
  Future<ConversationSummary> updateConversationModel(
    String conversationId,
    String? model,
  ) async {
    calls.add('update-model:$conversationId:$model');
    return _conversation(
      id: conversationId,
      workspaceId: _workspace.id,
      status: 'idle',
      model: model,
    );
  }
}

class _FakeDiagnosticsRepository implements DiagnosticsRepository {
  final List<String> calls = <String>[];

  @override
  Future<DiagnosticBundleSummary> exportDiagnostics() async =>
      DiagnosticBundleSummary(
        bundleId: 'diag_1',
        createdAt: DateTime.utc(2026, 5, 14),
        path: r'C:\temp\diag_1.zip',
        redacted: true,
        items: const <String>['system', 'logs'],
      );

  @override
  Future<String> recordException({
    required String message,
    String severity = 'error',
    String? stack,
    String? path,
    String? method,
    String? conversationId,
    String? runId,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    calls.add([
      message,
      stack,
      path,
      method,
      conversationId,
      runId,
      severity,
      metadata['operation'],
      metadata['afterSeq'],
      metadata['returnedCount'],
      metadata['durationMs'],
      metadata['cancelled'],
      metadata['changed'],
      metadata['terminalDrainPending'],
      metadata['error'],
    ].join('|'));
    return 'trace_1';
  }
}

class _FakeAttachmentPreviewCache implements AttachmentPreviewCache {
  final List<String> remembered = <String>[];
  final List<String> bound = <String>[];
  final Map<String, CachedAttachmentPreview> _resolved =
      <String, CachedAttachmentPreview>{};
  Object? bindError;
  Object? resolveError;

  @override
  Future<AttachmentPreviewIdentity> rememberPending({
    required String conversationId,
    required String clientMessageId,
    required int attachmentIndex,
    required DraftAttachment draft,
  }) async {
    remembered.add('$conversationId|$clientMessageId|$attachmentIndex');
    return AttachmentPreviewIdentity(
      contentHash: 'hash_$attachmentIndex',
      name: draft.name,
      mimeType: draft.mimeType,
      sizeBytes: draft.sizeBytes,
      attachmentIndex: attachmentIndex,
    );
  }

  @override
  Future<void> bindCommitted({
    required String conversationId,
    required String clientMessageId,
    required List<CommittedAttachment> attachments,
    List<AttachmentPreviewIdentity>? pendingIdentities,
  }) async {
    final error = bindError;
    if (error != null) throw error;
    final identity = pendingIdentities?.single;
    final attachment = attachments.single;
    bound.add(
      '$conversationId|$clientMessageId|${attachment.id}|'
      '${identity?.contentHash}',
    );
    _resolved['$conversationId|${attachment.id}'] = CachedAttachmentPreview(
      attachmentId: attachment.id,
      contentHash: identity?.contentHash ?? 'missing',
      cachePath: r'C:\cache\screenshot.png',
      width: 320,
      height: 200,
      mimeType: attachment.mimeType,
      sizeBytes: attachment.sizeBytes,
      createdAt: DateTime.utc(2026, 5, 22),
      lastAccessedAt: DateTime.utc(2026, 5, 22),
    );
  }

  @override
  Future<CachedAttachmentPreview?> resolve({
    required String conversationId,
    required CommittedAttachment attachment,
  }) async {
    final error = resolveError;
    if (error != null) throw error;
    return _resolved['$conversationId|${attachment.id}'];
  }

  @override
  Future<void> markClientMessageOrphaned({
    required String conversationId,
    required String clientMessageId,
  }) async {}
}

class _FakeRunRepository implements RunRepository {
  final List<String> calls = <String>[];

  @override
  Future<RunSummary> cancelRun(String runId) async {
    calls.add('cancelRun:$runId');
    return RunSummary(
      id: runId,
      tool: 'codex',
      workspaceId: _workspace.id,
      status: 'cancelled',
    );
  }

  @override
  Future<RunSummary> createRun({
    required String tool,
    required String workspaceId,
    String? prompt,
    String? shortcutId,
    String permissionMode = 'default',
  }) async =>
      throw UnimplementedError();

  @override
  Future<List<AgentEvent>> fetchEvents(String runId,
          {int afterSeq = 0}) async =>
      throw UnimplementedError();

  @override
  Future<RunSummary> invokeCommandTemplate({
    required String templateId,
    required String workspaceId,
    String tool = 'claude',
  }) async =>
      throw UnimplementedError();

  @override
  Future<List<QueueItem>> listQueue() async => throw UnimplementedError();

  @override
  Future<List<RunSummary>> listRuns({
    String? tool,
    String? workspaceId,
    String? status,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> respondApproval(String approvalId, String decision) async {
    calls.add('approval:$approvalId:$decision');
  }

  @override
  Future<RunSummary> sendRunInput(
    String runId,
    String prompt, {
    String permissionMode = 'default',
  }) async =>
      throw UnimplementedError();
}

class _FakeWorkspaceRepository implements WorkspaceRepository {
  _FakeWorkspaceRepository({
    required this.createdWorkspace,
    required this.listedWorkspaces,
  });

  final WorkspaceSummary createdWorkspace;
  final List<WorkspaceSummary> listedWorkspaces;
  final List<String> calls = <String>[];

  @override
  Future<WorkspaceSummary> createWorkspace({
    required String path,
    String? name,
  }) async {
    calls.add('create:$path:$name');
    return createdWorkspace;
  }

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() async {
    calls.add('list');
    return listedWorkspaces;
  }

  @override
  Future<CodeDiagnosticsSummary> codeDiagnostics(String workspaceId) async =>
      throw UnimplementedError();

  @override
  Future<FileContent> fileContent(String workspaceId, String path) async =>
      throw UnimplementedError();

  @override
  Future<FileTreeResponse> fileTree(
    String workspaceId, {
    String path = '',
    int maxDepth = 8,
  }) async =>
      throw UnimplementedError();

  @override
  Future<List<DiffSummary>> gitDiff(String workspaceId) async =>
      throw UnimplementedError();

  @override
  Future<List<GitCommitSummary>> gitCommits(
    String workspaceId, {
    int limit = 20,
  }) async =>
      throw UnimplementedError();

  @override
  Future<GitStatusSummary> gitStatus(String workspaceId) async =>
      throw UnimplementedError();

  @override
  Future<DirectoryListing> listDirectory(String path) async =>
      throw UnimplementedError();

  @override
  Future<List<DirectoryEntrySummary>> listFileSystemRoots() async =>
      throw UnimplementedError();

  @override
  Future<ProjectOverview> projectOverview(String workspaceId) async =>
      throw UnimplementedError();
}

ConversationSummary _conversation({
  required String id,
  required String workspaceId,
  required String status,
  String adapter = 'codex',
  String? model,
  int userMessageCount = 0,
}) =>
    ConversationSummary(
      id: id,
      workspaceId: workspaceId,
      adapter: adapter,
      model: model,
      status: status,
      userMessageCount: userMessageCount,
      capabilities:
          ConversationCapabilities.fromJson(const <String, Object?>{}),
      createdAt: '2026-05-12T00:00:00.000Z',
      updatedAt: '2026-05-12T00:00:01.000Z',
    );

const _claudeAdapter = AdapterStatus(
  adapter: 'claude',
  available: true,
  status: 'available',
);

const _codexAdapter = AdapterStatus(
  adapter: 'codex',
  available: true,
  status: 'available',
);

ConversationEvent _event({
  required int seq,
  required String type,
  String conversationId = 'conv_1',
  String? text,
  String? questionId,
  String? approvalId,
  String? toolUseId,
  String? toolName,
  String? summary,
  Map<String, Object?> input = const <String, Object?>{},
  Map<String, Object?> raw = const <String, Object?>{},
}) =>
    ConversationEvent(
      seq: seq,
      conversationId: conversationId,
      type: type,
      createdAt: DateTime.parse('2026-05-12T00:00:0$seq.000Z'),
      text: text,
      questionId: questionId,
      approvalId: approvalId,
      toolUseId: toolUseId,
      toolName: toolName,
      summary: summary,
      input: input,
      raw: raw,
    );
