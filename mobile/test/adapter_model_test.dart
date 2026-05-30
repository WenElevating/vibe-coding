import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/data/repositories/cached_conversation_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/cached_run_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/cli_adapter_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/workspace_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/adapter_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/conversation_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/run_repository.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/ui/features/workbench/attachments/attachment_preview_cache.dart';
import 'package:lan_ai_cli_control/src/ui/features/workbench/attachments/draft_attachment.dart';
import 'package:lan_ai_cli_control/src/ui/features/workbench/view_models/workbench_view_model.dart';

void main() {
  group('AdapterStatus model parsing', () {
    test('uses safe defaults for old daemon payloads', () {
      final status = AdapterStatus.fromJson(<String, Object?>{
        'adapter': 'codex',
        'available': true,
        'status': 'available',
      });

      expect(status.models, isEmpty);
      expect(status.selectedModel, isNull);
      expect(status.canSelectModel, isFalse);
    });

    test('parses selected model rows from new daemon payloads', () {
      final status = AdapterStatus.fromJson(<String, Object?>{
        'adapter': 'codex',
        'available': true,
        'status': 'available',
        'models': <Object?>[
          <String, Object?>{
            'id': 'gpt-5-codex',
            'label': 'GPT-5 Codex',
            'source': 'codex_config',
            'selected': true,
          },
        ],
        'selectedModel': 'gpt-5-codex',
        'canSelectModel': true,
      });

      expect(status.canSelectModel, isTrue);
      expect(status.selectedModel, 'gpt-5-codex');
      expect(status.models, hasLength(1));
      expect(
        status.models.single,
        isA<AdapterModelOption>()
            .having((model) => model.id, 'id', 'gpt-5-codex')
            .having((model) => model.label, 'label', 'GPT-5 Codex')
            .having((model) => model.source, 'source', 'codex_config')
            .having((model) => model.selected, 'selected', isTrue),
      );
    });
  });

  group('WorkbenchViewModel model state', () {
    test('initial selected model comes from the selected adapter', () {
      final viewModel = _workbenchViewModel(
        adapters: const <AdapterStatus>[_codexModels],
      );

      expect(viewModel.selectedAdapter, 'codex');
      expect(viewModel.selectedAdapterStatus, _codexModels);
      expect(viewModel.availableModels, _codexModels.models);
      expect(viewModel.selectedModel, 'gpt-5-codex');
      expect(viewModel.draftModel, 'gpt-5-codex');
      expect(viewModel.confirmedConversationModel, isNull);
      expect(viewModel.modelNotice, isNull);
    });

    test('selectModel updates draft model state', () async {
      final viewModel = _workbenchViewModel(
        adapters: const <AdapterStatus>[_codexModels],
      );

      final selected = await viewModel.selectModel('gpt-5-mini');

      expect(selected, isTrue);
      expect(viewModel.selectedModel, 'gpt-5-mini');
      expect(viewModel.draftModel, 'gpt-5-mini');
      expect(viewModel.modelNotice, isNull);
    });

    test('selectModel ignores unsupported model ids', () async {
      final viewModel = _workbenchViewModel(
        adapters: const <AdapterStatus>[_codexModels],
      );

      final selected = await viewModel.selectModel('not-configured');

      expect(selected, isFalse);
      expect(viewModel.selectedModel, 'gpt-5-codex');
    });

    test('snapshot refresh selects a model when one becomes available', () {
      final adapterRepository = _FakeCliAdapterRepository();
      final viewModel = _workbenchViewModel(
        adapterRepository: adapterRepository,
      );

      adapterRepository.replaceAdapters(const <AdapterStatus>[_codexModels]);

      expect(viewModel.selectedAdapter, 'codex');
      expect(viewModel.selectedModel, 'gpt-5-codex');
      expect(viewModel.modelNotice, isNull);
    });

    test('snapshot refresh falls back when the selected model disappears', () {
      final adapterRepository = _FakeCliAdapterRepository(
        adapters: const <AdapterStatus>[_codexModels],
      );
      final viewModel = _workbenchViewModel(
        adapterRepository: adapterRepository,
      );

      adapterRepository.replaceAdapters(const <AdapterStatus>[_codexMiniOnly]);

      expect(viewModel.selectedModel, 'gpt-5-mini');
      expect(
        viewModel.modelNotice,
        WorkbenchModelNotice.changedToAvailableOption,
      );

      viewModel.clearModelNotice();
      expect(viewModel.modelNotice, isNull);
    });

    test('existing conversation model update waits for repository success',
        () async {
      final repository = _FakeConversationRepository();
      final updateCompleter = Completer<ConversationSummary>();
      repository.updateCompleter = updateCompleter;
      final viewModel = _workbenchViewModel(
        adapters: const <AdapterStatus>[_codexModels],
        conversationRepository: repository,
      );
      viewModel.updateActiveConversation(
        _conversation(adapter: 'codex', model: 'gpt-5-codex'),
      );

      final pendingSelection = viewModel.selectModel('gpt-5-mini');

      expect(viewModel.modelUpdating, isTrue);
      expect(viewModel.selectedModel, 'gpt-5-codex');
      expect(viewModel.confirmedConversationModel, 'gpt-5-codex');
      expect(repository.calls, <String>['update-model:conv_1:gpt-5-mini']);

      updateCompleter.complete(_conversation(model: 'gpt-5-mini'));
      final selected = await pendingSelection;

      expect(selected, isTrue);
      expect(viewModel.selectedModel, 'gpt-5-mini');
      expect(viewModel.confirmedConversationModel, 'gpt-5-mini');
      expect(viewModel.modelUpdating, isFalse);
      expect(viewModel.modelUpdateError, isNull);
    });

    test('dispose suppresses in-flight model update completion notification',
        () async {
      final repository = _FakeConversationRepository();
      final updateCompleter = Completer<ConversationSummary>();
      repository.updateCompleter = updateCompleter;
      final viewModel = _workbenchViewModel(
        adapters: const <AdapterStatus>[_codexModels],
        conversationRepository: repository,
      );
      viewModel.updateActiveConversation(
        _conversation(adapter: 'codex', model: 'gpt-5-codex'),
      );

      final pendingSelection = viewModel.selectModel('gpt-5-mini');
      expect(viewModel.modelUpdating, isTrue);

      viewModel.dispose();
      updateCompleter.complete(_conversation(model: 'gpt-5-mini'));

      expect(await pendingSelection, isFalse);
    });

    test('existing conversation model update failure keeps confirmed model',
        () async {
      final repository = _FakeConversationRepository()
        ..updateError = const ConversationRepositoryException(
          statusCode: 500,
          code: 'SERVER_ERROR',
          message: 'update failed',
        );
      final viewModel = _workbenchViewModel(
        adapters: const <AdapterStatus>[_codexModels],
        conversationRepository: repository,
      );
      viewModel.updateActiveConversation(
        _conversation(adapter: 'codex', model: 'gpt-5-codex'),
      );

      final selected = await viewModel.selectModel('gpt-5-mini');

      expect(selected, isFalse);
      expect(viewModel.selectedModel, 'gpt-5-codex');
      expect(viewModel.confirmedConversationModel, 'gpt-5-codex');
      expect(viewModel.modelUpdating, isFalse);
      expect(viewModel.modelUpdateError, 'update failed');
      expect(viewModel.conversationModelUpdatesUnsupported, isFalse);
    });

    test('old daemon model endpoint disables existing conversation updates',
        () async {
      final repository = _FakeConversationRepository()
        ..updateError = const ConversationRepositoryException(statusCode: 405);
      final viewModel = _workbenchViewModel(
        adapters: const <AdapterStatus>[_codexModels],
        conversationRepository: repository,
      );
      viewModel.updateActiveConversation(
        _conversation(adapter: 'codex', model: 'gpt-5-codex'),
      );

      final selected = await viewModel.selectModel('gpt-5-mini');

      expect(selected, isFalse);
      expect(viewModel.selectedModel, 'gpt-5-codex');
      expect(viewModel.conversationModelUpdatesUnsupported, isTrue);
      expect(
        viewModel.modelUpdateError,
        'existing conversation model updates require a newer daemon',
      );

      final secondSelection = await viewModel.selectModel('gpt-5-mini');

      expect(secondSelection, isFalse);
      expect(repository.calls, <String>['update-model:conv_1:gpt-5-mini']);
    });

    test('missing conversation response does not disable model updates',
        () async {
      final repository = _FakeConversationRepository()
        ..updateError = const ConversationRepositoryException(
          statusCode: 404,
          code: 'NOT_FOUND',
          message: 'conversation not found',
        );
      final viewModel = _workbenchViewModel(
        adapters: const <AdapterStatus>[_codexModels],
        conversationRepository: repository,
      );
      viewModel.updateActiveConversation(
        _conversation(adapter: 'codex', model: 'gpt-5-codex'),
      );

      final selected = await viewModel.selectModel('gpt-5-mini');

      expect(selected, isFalse);
      expect(viewModel.selectedModel, 'gpt-5-codex');
      expect(viewModel.conversationModelUpdatesUnsupported, isFalse);
      expect(viewModel.modelUpdateError, 'conversation not found');
    });

    test('status transitions preserve confirmed conversation model', () {
      final viewModel = _workbenchViewModel(
        adapters: const <AdapterStatus>[_codexModels],
      );
      viewModel.updateActiveConversation(
        _conversation(adapter: 'codex', model: 'gpt-5-codex'),
      );

      viewModel.markConversationRunning(notify: false);

      expect(viewModel.selectedModel, 'gpt-5-codex');
      expect(viewModel.confirmedConversationModel, 'gpt-5-codex');

      viewModel.applyConversationEvents(
        <ConversationEvent>[
          _event(
            seq: 1,
            type: 'conversation.status_changed',
            raw: const <String, Object?>{'status': 'waiting_input'},
          ),
        ],
        streamOutput: false,
        notify: false,
      );

      expect(viewModel.selectedModel, 'gpt-5-codex');
      expect(viewModel.confirmedConversationModel, 'gpt-5-codex');
    });

    test('stale model update success does not overwrite active conversation',
        () async {
      final repository = _FakeConversationRepository();
      final updateCompleter = Completer<ConversationSummary>();
      repository.updateCompleter = updateCompleter;
      final viewModel = _workbenchViewModel(
        adapters: const <AdapterStatus>[_codexModels],
        conversationRepository: repository,
      );
      viewModel.updateActiveConversation(
        _conversation(id: 'conv_1', adapter: 'codex', model: 'gpt-5-codex'),
      );

      final pendingSelection = viewModel.selectModel('gpt-5-mini');
      viewModel.updateActiveConversation(
        _conversation(id: 'conv_2', adapter: 'codex', model: 'gpt-5-codex'),
      );
      updateCompleter.complete(
        _conversation(id: 'conv_1', adapter: 'codex', model: 'gpt-5-mini'),
      );

      final selected = await pendingSelection;

      expect(selected, isFalse);
      expect(viewModel.activeConversationId, 'conv_2');
      expect(viewModel.selectedModel, 'gpt-5-codex');
      expect(viewModel.confirmedConversationModel, 'gpt-5-codex');
      expect(viewModel.modelUpdating, isFalse);
      expect(viewModel.modelUpdateError, isNull);
      expect(viewModel.conversationModelUpdatesUnsupported, isFalse);
    });

    test(
        'stale model update failure does not mark new conversation unsupported',
        () async {
      final repository = _FakeConversationRepository();
      final updateCompleter = Completer<ConversationSummary>();
      repository.updateCompleter = updateCompleter;
      final viewModel = _workbenchViewModel(
        adapters: const <AdapterStatus>[_codexModels],
        conversationRepository: repository,
      );
      viewModel.updateActiveConversation(
        _conversation(id: 'conv_1', adapter: 'codex', model: 'gpt-5-codex'),
      );

      final pendingSelection = viewModel.selectModel('gpt-5-mini');
      viewModel.updateActiveConversation(
        _conversation(id: 'conv_2', adapter: 'codex', model: 'gpt-5-codex'),
      );
      updateCompleter.completeError(
        const ConversationRepositoryException(statusCode: 405),
      );

      final selected = await pendingSelection;

      expect(selected, isFalse);
      expect(viewModel.activeConversationId, 'conv_2');
      expect(viewModel.selectedModel, 'gpt-5-codex');
      expect(viewModel.modelUpdating, isFalse);
      expect(viewModel.modelUpdateError, isNull);
      expect(viewModel.conversationModelUpdatesUnsupported, isFalse);
    });

    test('sending operation state refuses adapter and model changes', () async {
      final viewModel = _workbenchViewModel(
        adapters: const <AdapterStatus>[_codexModels, _claudeAvailable],
      );

      viewModel.setSelectedAdapter('codex');
      viewModel.beginOperation();
      viewModel.setSelectedAdapter('claude');
      final selected = await viewModel.selectModel('gpt-5-mini');

      expect(selected, isFalse);
      expect(viewModel.selectedAdapter, 'codex');
      expect(viewModel.selectedModel, 'gpt-5-codex');
    });

    test('createAndSend forwards the ViewModel selected model', () async {
      final repository = _FakeConversationRepository();
      final viewModel = _workbenchViewModel(
        adapters: const <AdapterStatus>[_codexModels],
        workspaces: const <WorkspaceSummary>[_workspace],
        conversationRepository: repository,
      );

      final result = await viewModel.createAndSend(
        workspace: _workspace,
        prompt: 'hello',
        adapter: 'codex',
        permissionMode: 'default',
      );
      await result.updatedConversation;

      expect(repository.calls, <String>[
        'create:workspace_1:codex:default:gpt-5-codex',
        'send:conv_1:hello',
      ]);
      expect(viewModel.modelNotice, isNull);
    });

    test('repository updateConversationModel records selected model', () async {
      final repository = _FakeConversationRepository();

      final updated =
          await repository.updateConversationModel('conv_1', 'gpt-5-mini');

      expect(updated.model, 'gpt-5-mini');
      expect(repository.calls, <String>['update-model:conv_1:gpt-5-mini']);
    });

    test('createAndSend omits model when adapter cannot select models',
        () async {
      final repository = _FakeConversationRepository();
      final viewModel = _workbenchViewModel(
        adapters: const <AdapterStatus>[_codexWithoutModelSelection],
        workspaces: const <WorkspaceSummary>[_workspace],
        conversationRepository: repository,
      );

      final result = await viewModel.createAndSend(
        workspace: _workspace,
        prompt: 'hello',
        adapter: 'codex',
        permissionMode: 'default',
        model: 'gpt-5-codex',
      );
      await result.updatedConversation;

      expect(repository.calls, <String>[
        'create:workspace_1:codex:default:null',
        'send:conv_1:hello',
      ]);
    });

    test('keeps draft attachments local until send', () {
      final viewModel = _workbenchViewModel(
        adapters: const <AdapterStatus>[_codexImageModel],
      );

      viewModel.addDraftAttachmentForTest(const DraftAttachment(
        localPath: r'D:\tmp\screenshot.png',
        name: 'screenshot.png',
        mimeType: 'image/png',
        kind: AttachmentKind.image,
        sizeBytes: 120034,
      ));

      expect(viewModel.draftAttachments.single.name, 'screenshot.png');
      expect(viewModel.canSendComposer(text: ''), isTrue);
    });

    test('marks image draft unsupported after switching to text-only model',
        () async {
      final viewModel = _workbenchViewModel(
        adapters: const <AdapterStatus>[_codexImageAndTextOnlyModels],
      );
      viewModel.addDraftAttachmentForTest(const DraftAttachment(
        localPath: r'D:\tmp\screenshot.png',
        name: 'screenshot.png',
        mimeType: 'image/png',
        kind: AttachmentKind.image,
        sizeBytes: 120034,
      ));

      final selected = await viewModel.selectModel('text-only-model');

      expect(selected, isTrue);
      expect(
        viewModel.draftAttachments.single.errorCode,
        'attachment_kind_unsupported',
      );
      expect(viewModel.canSendComposer(text: 'inspect'), isFalse);
    });

    test('existing conversation send forwards draft attachment metadata',
        () async {
      final repository = _FakeConversationRepository();
      final cache = _FakeAttachmentPreviewCache();
      final viewModel = _workbenchViewModel(
        adapters: const <AdapterStatus>[_codexImageModel],
        conversationRepository: repository,
        attachmentPreviewCache: cache,
      );
      viewModel.addDraftAttachmentForTest(const DraftAttachment(
        localPath: r'D:\tmp\screenshot.png',
        name: 'screenshot.png',
        mimeType: 'image/png',
        kind: AttachmentKind.image,
        sizeBytes: 120034,
      ));

      await viewModel.sendExistingConversationPrompt(
        conversationId: 'conv_1',
        prompt: 'inspect',
      );

      final request = repository.sentRequests.single;
      expect(request.text, 'inspect');
      expect(request.capabilityVersion, '4bcf6aa44f7e2e074229f9cd');
      expect(request.clientMessageId, isNotNull);
      expect(request.attachments.single.name, 'screenshot.png');
      expect(request.attachments.single.kind, AttachmentKind.image);
      expect(cache.remembered, <String>[
        'conv_1|${request.clientMessageId}|0|screenshot.png|image/png|120034',
      ]);
      expect(viewModel.draftAttachments, isEmpty);
    });

    test('attachment preview cache failure does not block send', () async {
      final repository = _FakeConversationRepository();
      final cache = _FakeAttachmentPreviewCache()
        ..rememberError = StateError('preview cache unavailable');
      final viewModel = _workbenchViewModel(
        adapters: const <AdapterStatus>[_codexImageModel],
        conversationRepository: repository,
        attachmentPreviewCache: cache,
      );
      viewModel.addDraftAttachmentForTest(const DraftAttachment(
        localPath: r'D:\tmp\screenshot.png',
        name: 'screenshot.png',
        mimeType: 'image/png',
        kind: AttachmentKind.image,
        sizeBytes: 120034,
      ));

      await viewModel.sendExistingConversationPrompt(
        conversationId: 'conv_1',
        prompt: 'inspect',
      );

      final request = repository.sentRequests.single;
      expect(request.text, 'inspect');
      expect(request.clientMessageId, isNotNull);
      expect(request.attachments.single.name, 'screenshot.png');
      expect(cache.remembered, isEmpty);
    });

    test('pending question follows current blocking input request only', () {
      final viewModel = _workbenchViewModel(
        adapters: const <AdapterStatus>[_claudeAvailable],
      );
      viewModel.updateActiveConversation(
        _conversation(
          adapter: 'claude',
          status: 'running',
        ),
      );

      viewModel.applyConversationEvents(
        <ConversationEvent>[
          ConversationEvent.fromJson(const <String, Object?>{
            'seq': 1,
            'conversationId': 'conv_1',
            'type': 'assistant.question',
            'createdAt': '2026-05-18T00:00:02.000Z',
            'questionId': 'question_1',
            'text': 'Pick one',
            'suggestions': <String>['A'],
          }),
        ],
        streamOutput: false,
      );

      expect(viewModel.pendingQuestionId, 'question_1');

      viewModel.applyConversationEvents(
        <ConversationEvent>[
          ConversationEvent.fromJson(const <String, Object?>{
            'seq': 2,
            'conversationId': 'conv_1',
            'type': 'run.error',
            'createdAt': '2026-05-18T00:00:03.000Z',
            'message': 'AskUserQuestion failed',
          }),
        ],
        streamOutput: false,
      );

      expect(viewModel.effectiveConversationStatus, 'failed');
      expect(viewModel.pendingQuestionId, isNull);
    });

    test('pre-commit attachment failure keeps draft and client message id',
        () async {
      final repository = _FakeConversationRepository()
        ..sendError = const ConversationRepositoryException(
          statusCode: 422,
          code: 'attachment_context_too_large',
        );
      final viewModel = _workbenchViewModel(
        adapters: const <AdapterStatus>[_codexImageModel],
        conversationRepository: repository,
      );
      viewModel.addDraftAttachmentForTest(const DraftAttachment(
        localPath: r'D:\tmp\screenshot.png',
        name: 'screenshot.png',
        mimeType: 'image/png',
        kind: AttachmentKind.image,
        sizeBytes: 120034,
      ));

      await expectLater(
        viewModel.sendExistingConversationPrompt(
          conversationId: 'conv_1',
          prompt: 'inspect',
        ),
        throwsA(isA<ConversationRepositoryException>()),
      );
      final firstId = repository.sentRequests.single.clientMessageId;

      repository.sendError = null;
      await viewModel.sendExistingConversationPrompt(
        conversationId: 'conv_1',
        prompt: 'inspect',
      );

      expect(viewModel.draftAttachments, isEmpty);
      expect(repository.sentRequests.last.clientMessageId, firstId);
    });

    test(
        'changing draft attachments after retryable failure starts a new preview identity',
        () async {
      final repository = _FakeConversationRepository()
        ..sendError = const ConversationRepositoryException(
          statusCode: 422,
          code: 'attachment_context_too_large',
        );
      final cache = _FakeAttachmentPreviewCache();
      final viewModel = _workbenchViewModel(
        adapters: const <AdapterStatus>[_codexImageModel],
        conversationRepository: repository,
        attachmentPreviewCache: cache,
      );
      viewModel.addDraftAttachmentForTest(const DraftAttachment(
        localPath: r'D:\tmp\first.png',
        name: 'first.png',
        mimeType: 'image/png',
        kind: AttachmentKind.image,
        sizeBytes: 120034,
      ));

      await expectLater(
        viewModel.sendExistingConversationPrompt(
          conversationId: 'conv_1',
          prompt: 'inspect',
        ),
        throwsA(isA<ConversationRepositoryException>()),
      );
      final firstId = repository.sentRequests.single.clientMessageId;
      expect(firstId, isNotNull);

      viewModel.removeDraftAttachment(0);
      await pumpEventQueue();
      viewModel.addDraftAttachmentForTest(const DraftAttachment(
        localPath: r'D:\tmp\second.png',
        name: 'second.png',
        mimeType: 'image/png',
        kind: AttachmentKind.image,
        sizeBytes: 120034,
      ));

      repository.sendError = null;
      await viewModel.sendExistingConversationPrompt(
        conversationId: 'conv_1',
        prompt: 'inspect',
      );
      final secondId = repository.sentRequests.last.clientMessageId;

      expect(secondId, isNot(firstId));
      expect(cache.orphaned, <String>['conv_1|$firstId']);
      expect(cache.remembered, <String>[
        'conv_1|$firstId|0|first.png|image/png|120034',
        'conv_1|$secondId|0|second.png|image/png|120034',
      ]);
    });
  });
}

const _workspace = WorkspaceSummary(
  id: 'workspace_1',
  name: 'Workspace',
  path: r'D:\workspace',
);

const _codexModels = AdapterStatus(
  adapter: 'codex',
  available: true,
  status: 'available',
  canSelectModel: true,
  selectedModel: 'gpt-5-codex',
  models: <AdapterModelOption>[
    AdapterModelOption(
      id: 'gpt-5-codex',
      label: 'GPT-5 Codex',
      source: 'codex_config',
      selected: true,
    ),
    AdapterModelOption(
      id: 'gpt-5-mini',
      label: 'GPT-5 Mini',
      source: 'codex_catalog',
      selected: false,
    ),
  ],
);

const _codexMiniOnly = AdapterStatus(
  adapter: 'codex',
  available: true,
  status: 'available',
  canSelectModel: true,
  selectedModel: 'gpt-5-mini',
  models: <AdapterModelOption>[
    AdapterModelOption(
      id: 'gpt-5-mini',
      label: 'GPT-5 Mini',
      source: 'codex_catalog',
      selected: true,
    ),
  ],
);

const _codexWithoutModelSelection = AdapterStatus(
  adapter: 'codex',
  available: true,
  status: 'available',
  canSelectModel: false,
  selectedModel: 'gpt-5-codex',
  models: <AdapterModelOption>[
    AdapterModelOption(
      id: 'gpt-5-codex',
      label: 'GPT-5 Codex',
      source: 'codex_config',
      selected: true,
    ),
  ],
);

const _codexImageModel = AdapterStatus(
  adapter: 'codex',
  available: true,
  status: 'available',
  capabilityVersion: '4bcf6aa44f7e2e074229f9cd',
  canSelectModel: true,
  selectedModel: 'gpt-5-codex',
  models: <AdapterModelOption>[
    AdapterModelOption(
      id: 'gpt-5-codex',
      label: 'GPT-5 Codex',
      source: 'codex_catalog',
      selected: true,
      attachmentCapabilities: AttachmentCapabilities(
        image: AttachmentHandling.native,
        textDocument: AttachmentHandling.textExtract,
      ),
    ),
  ],
);

const _codexImageAndTextOnlyModels = AdapterStatus(
  adapter: 'codex',
  available: true,
  status: 'available',
  capabilityVersion: '4bcf6aa44f7e2e074229f9cd',
  canSelectModel: true,
  selectedModel: 'gpt-5-codex',
  models: <AdapterModelOption>[
    AdapterModelOption(
      id: 'gpt-5-codex',
      label: 'GPT-5 Codex',
      source: 'codex_catalog',
      selected: true,
      attachmentCapabilities: AttachmentCapabilities(
        image: AttachmentHandling.native,
        textDocument: AttachmentHandling.textExtract,
      ),
    ),
    AdapterModelOption(
      id: 'text-only-model',
      label: 'Text Only',
      source: 'codex_catalog',
      selected: false,
      attachmentCapabilities: AttachmentCapabilities(
        image: AttachmentHandling.unsupported,
        textDocument: AttachmentHandling.textExtract,
      ),
    ),
  ],
);

const _claudeAvailable = AdapterStatus(
  adapter: 'claude',
  available: true,
  status: 'available',
);

WorkbenchViewModel _workbenchViewModel({
  List<AdapterStatus> adapters = const <AdapterStatus>[],
  List<WorkspaceSummary> workspaces = const <WorkspaceSummary>[_workspace],
  _FakeCliAdapterRepository? adapterRepository,
  _FakeConversationRepository? conversationRepository,
  AttachmentPreviewCache attachmentPreviewCache =
      const NoopAttachmentPreviewCache(),
}) {
  return WorkbenchViewModel(
    workspaceRepository: _FakeWorkspaceRepository(workspaces: workspaces),
    adapterRepository:
        adapterRepository ?? _FakeCliAdapterRepository(adapters: adapters),
    conversationRepository: CachedConversationRepository(
      delegate: conversationRepository ?? _FakeConversationRepository(),
    ),
    runRepository: CachedRunRepository(delegate: _NoOpRunRepository()),
    attachmentPreviewCache: attachmentPreviewCache,
  );
}

class _FakeWorkspaceRepository extends WorkspaceRepository {
  _FakeWorkspaceRepository({
    required List<WorkspaceSummary> workspaces,
  }) : _workspaces = List<WorkspaceSummary>.of(workspaces);

  List<WorkspaceSummary> _workspaces;
  WorkspaceSummary? _selectedWorkspace;

  @override
  List<WorkspaceSummary> get workspaces => List.unmodifiable(_workspaces);

  @override
  WorkspaceSummary? get selectedWorkspace =>
      _selectedWorkspace ?? (_workspaces.isEmpty ? null : _workspaces.first);

  @override
  bool get loading => false;

  @override
  Object? get error => null;

  @override
  Future<void> load() async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<WorkspaceSummary> create({
    required String path,
    String? name,
  }) async {
    final workspace = WorkspaceSummary(
      id: 'workspace_created',
      name: name ?? path,
      path: path,
    );
    _workspaces = <WorkspaceSummary>[..._workspaces, workspace];
    _selectedWorkspace = workspace;
    notifyListeners();
    return workspace;
  }

  @override
  bool select(String workspaceId) {
    for (final workspace in _workspaces) {
      if (workspace.id == workspaceId) {
        _selectedWorkspace = workspace;
        notifyListeners();
        return true;
      }
    }
    return false;
  }

  @override
  void applyBootstrapCatalog({
    required WorkspaceSummary? selectedWorkspace,
    required List<WorkspaceSummary> workspaces,
  }) {
    _workspaces = List<WorkspaceSummary>.of(workspaces);
    _selectedWorkspace = selectedWorkspace;
  }

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() async =>
      List<WorkspaceSummary>.of(_workspaces);

  @override
  Future<WorkspaceSummary> createWorkspace({
    required String path,
    String? name,
  }) =>
      create(path: path, name: name);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCliAdapterRepository extends CliAdapterRepository {
  _FakeCliAdapterRepository({
    List<AdapterStatus> adapters = const <AdapterStatus>[],
  })  : _adapters = List<AdapterStatus>.of(adapters),
        super(delegate: _NoOpAdapterRepository());

  List<AdapterStatus> _adapters;

  @override
  List<AdapterStatus> get adapters => List.unmodifiable(_adapters);

  void replaceAdapters(List<AdapterStatus> adapters) {
    _adapters = List<AdapterStatus>.of(adapters);
    notifyListeners();
  }
}

class _NoOpAdapterRepository implements AdapterRepository {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoOpRunRepository implements RunRepository {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ConversationSummary _conversation({
  String id = 'conv_1',
  String adapter = 'codex',
  String status = 'idle',
  String? model,
  ConversationBlockingItem? blockingItem,
}) =>
    ConversationSummary(
      id: id,
      workspaceId: _workspace.id,
      adapter: adapter,
      model: model,
      status: status,
      capabilities:
          ConversationCapabilities.fromJson(const <String, Object?>{}),
      createdAt: '2026-05-18T00:00:00.000Z',
      updatedAt: '2026-05-18T00:00:01.000Z',
      blockingItem: blockingItem,
    );

ConversationEvent _event({
  required int seq,
  required String type,
  Map<String, Object?> raw = const <String, Object?>{},
}) =>
    ConversationEvent(
      seq: seq,
      conversationId: 'conv_1',
      type: type,
      createdAt: DateTime.parse('2026-05-18T00:00:02.000Z'),
      raw: raw,
    );

class _FakeConversationRepository implements ConversationRepository {
  final List<String> calls = <String>[];
  final List<ConversationMessageSendRequest> sentRequests =
      <ConversationMessageSendRequest>[];
  Completer<ConversationSummary>? updateCompleter;
  ConversationRepositoryException? updateError;
  ConversationRepositoryException? sendError;

  @override
  Future<ConversationSummary> createConversation({
    required String workspaceId,
    String adapter = 'claude',
    String permissionMode = 'default',
    String? model,
  }) async {
    calls.add('create:$workspaceId:$adapter:$permissionMode:$model');
    return _conversation(adapter: adapter, model: model);
  }

  @override
  Future<ConversationSummary> sendConversationMessage(
    String conversationId,
    ConversationMessageSendRequest request,
  ) async {
    calls.add('send:$conversationId:${request.text}');
    sentRequests.add(request);
    final error = sendError;
    if (error != null) throw error;
    return _conversation();
  }

  @override
  Future<ConversationSummary> updateConversationModel(
    String conversationId,
    String? model,
  ) async {
    calls.add('update-model:$conversationId:$model');
    final error = updateError;
    if (error != null) throw error;
    final completer = updateCompleter;
    if (completer != null) return completer.future;
    return _conversation(model: model);
  }

  @override
  Future<List<ConversationSummary>> listConversations() async =>
      const <ConversationSummary>[];

  @override
  Future<List<ConversationEvent>> fetchConversationEvents(
    String conversationId, {
    int afterSeq = 0,
  }) async =>
      const <ConversationEvent>[];

  @override
  Stream<ConversationEvent> watchConversationEvents(
    String conversationId, {
    required int afterSeq,
  }) =>
      const Stream<ConversationEvent>.empty();

  @override
  Future<ConversationSummary> answerConversationQuestion(
    String conversationId,
    String questionId,
    String text,
  ) async =>
      _conversation();

  @override
  Future<ConversationSummary> respondConversationApproval(
    String conversationId,
    String approvalId,
    String decision,
  ) async =>
      _conversation();

  @override
  Future<ConversationSummary> cancelConversation(String conversationId) async =>
      _conversation();
}

class _FakeAttachmentPreviewCache implements AttachmentPreviewCache {
  final List<String> remembered = <String>[];
  final List<String> orphaned = <String>[];
  Object? rememberError;

  @override
  Future<AttachmentPreviewIdentity> rememberPending({
    required String conversationId,
    required String clientMessageId,
    required int attachmentIndex,
    required DraftAttachment draft,
  }) async {
    final error = rememberError;
    if (error != null) throw error;
    remembered.add(
      '$conversationId|$clientMessageId|$attachmentIndex|'
      '${draft.name}|${draft.mimeType}|${draft.sizeBytes}',
    );
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
  }) async {}

  @override
  Future<CachedAttachmentPreview?> resolve({
    required String conversationId,
    required CommittedAttachment attachment,
  }) async =>
      null;

  @override
  Future<void> markClientMessageOrphaned({
    required String conversationId,
    required String clientMessageId,
  }) async {
    orphaned.add('$conversationId|$clientMessageId');
  }
}
