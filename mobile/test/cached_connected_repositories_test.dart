import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/data/repositories/cached_adapter_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/cached_conversation_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/cached_run_repository.dart';
import 'package:lan_ai_cli_control/src/data/services/conversation_event_cache_store.dart';
import 'package:lan_ai_cli_control/src/domain/models/approval_response.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/adapter_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/conversation_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/run_repository.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';

void main() {
  group('CachedAdapterRepository', () {
    test('loads once and exposes cached adapters', () async {
      final delegate = _FakeAdapterRepository();
      final repository = CachedAdapterRepository(delegate: delegate);

      await repository.load();
      final adapters = await repository.listAdapters();

      expect(delegate.listAdaptersCalls, 1);
      expect(delegate.listShortcutsCalls, 1);
      expect(delegate.listCommandTemplatesCalls, 1);
      expect(delegate.listExtensionsCalls, 1);
      expect(
        adapters.map((adapter) => adapter.adapter),
        const <String>['codex'],
      );
      expect(
        repository.adapters.map((adapter) => adapter.adapter),
        const <String>['codex'],
      );
      expect(repository.shortcuts.map((shortcut) => shortcut.id), const ['s1']);
      expect(repository.templates.map((template) => template.id), const ['t1']);
      expect(
        repository.extensions.map((extension) => extension.id),
        const ['e1'],
      );

      await repository.listAdapters();

      expect(delegate.listAdaptersCalls, 1);
    });

    test('refresh failure preserves previous data and exposes error', () async {
      final delegate = _FakeAdapterRepository();
      final repository = CachedAdapterRepository(delegate: delegate);
      await repository.load();
      delegate.loadError = StateError('adapter refresh failed');

      await expectLater(repository.load(), throwsA(isA<StateError>()));

      expect(
        repository.adapters.map((adapter) => adapter.adapter),
        const <String>['codex'],
      );
      expect(repository.error, isA<StateError>());
      expect(repository.loading, isFalse);
    });

    test('empty load is valid and is not reloaded on second list call',
        () async {
      final delegate = _FakeAdapterRepository()
        ..adapters = const <AdapterStatus>[]
        ..shortcuts = const <ShortcutCommand>[]
        ..templates = const <CommandTemplate>[]
        ..extensions = const <ExtensionSummary>[];
      final repository = CachedAdapterRepository(delegate: delegate);

      await repository.load();
      final adapters = await repository.listAdapters();
      final shortcuts = await repository.listShortcuts();
      final templates = await repository.listCommandTemplates();
      final extensions = await repository.listExtensions();

      expect(adapters, isEmpty);
      expect(shortcuts, isEmpty);
      expect(templates, isEmpty);
      expect(extensions, isEmpty);
      expect(delegate.listAdaptersCalls, 1);
      expect(delegate.listShortcutsCalls, 1);
      expect(delegate.listCommandTemplatesCalls, 1);
      expect(delegate.listExtensionsCalls, 1);
    });

    test('list methods await an in-flight load', () async {
      final adapters = Completer<List<AdapterStatus>>();
      final delegate = _FakeAdapterRepository()
        ..queuedAdapters.add(adapters.future);
      final repository = CachedAdapterRepository(delegate: delegate);

      final pendingLoad = repository.load();
      await pumpEventQueue();
      final pendingList = repository.listAdapters();
      await pumpEventQueue();
      expect(delegate.listAdaptersCalls, 1);

      adapters.complete(const <AdapterStatus>[
        AdapterStatus(adapter: 'loaded', available: true, status: 'available'),
      ]);
      await pendingLoad;

      expect(
        (await pendingList).map((adapter) => adapter.adapter),
        const <String>['loaded'],
      );
    });

    test('listAdapters succeeds when templates fail independently', () async {
      final delegate = _FakeAdapterRepository()
        ..templatesError = StateError('templates failed');
      final repository = CachedAdapterRepository(delegate: delegate);

      final adapters = await repository.listAdapters();

      expect(
        adapters.map((adapter) => adapter.adapter),
        const <String>['codex'],
      );
      await expectLater(
        repository.listCommandTemplates(),
        throwsA(isA<StateError>()),
      );
    });

    test('stale overlapping load does not overwrite newer load', () async {
      final staleAdapters = Completer<List<AdapterStatus>>();
      final delegate = _FakeAdapterRepository()
        ..queuedAdapters.add(staleAdapters.future);
      final repository = CachedAdapterRepository(delegate: delegate);

      final staleLoad = repository.load();
      await pumpEventQueue();
      delegate.adapters = const <AdapterStatus>[
        AdapterStatus(adapter: 'newer', available: true, status: 'available'),
      ];
      await repository.load();
      staleAdapters.complete(const <AdapterStatus>[
        AdapterStatus(adapter: 'stale', available: true, status: 'available'),
      ]);
      await staleLoad;

      expect(
        repository.adapters.map((adapter) => adapter.adapter),
        const <String>['newer'],
      );
    });

    test('dispose during in-flight load does not notify after dispose',
        () async {
      final adapters = Completer<List<AdapterStatus>>();
      final delegate = _FakeAdapterRepository()
        ..queuedAdapters.add(adapters.future);
      final repository = CachedAdapterRepository(delegate: delegate);
      var notifications = 0;
      repository.addListener(() => notifications++);

      final pending = repository.load();
      await pumpEventQueue();
      final notificationsBeforeDispose = notifications;
      repository.dispose();
      adapters.complete(const <AdapterStatus>[
        AdapterStatus(adapter: 'late', available: true, status: 'available'),
      ]);
      await pending;

      expect(notificationsBeforeDispose, greaterThanOrEqualTo(1));
      expect(notifications, notificationsBeforeDispose);
      expect(repository.adapters, isEmpty);
    });
  });

  group('CachedConversationRepository', () {
    test('refreshes and upserts a mutated conversation', () async {
      final delegate = _FakeConversationRepository(
        conversations: <ConversationSummary>[
          _conversation(id: 'c1', model: 'old'),
        ],
      );
      final repository = CachedConversationRepository(delegate: delegate);

      await repository.refresh();
      await repository.updateConversationModel('c1', 'gpt-5');

      expect(repository.conversations.single.id, 'c1');
      expect(repository.conversations.single.model, 'gpt-5');
    });

    test('refresh failure preserves previous data', () async {
      final delegate = _FakeConversationRepository(
        conversations: <ConversationSummary>[_conversation(id: 'c1')],
      );
      final repository = CachedConversationRepository(delegate: delegate);
      await repository.refresh();
      delegate.refreshError = StateError('conversation refresh failed');

      await expectLater(repository.refresh(), throwsA(isA<StateError>()));

      expect(
        repository.conversations.map((conversation) => conversation.id),
        const <String>['c1'],
      );
      expect(repository.error, isA<StateError>());
      expect(repository.loading, isFalse);
    });

    test('empty conversation list is valid and is not reloaded', () async {
      final delegate = _FakeConversationRepository(
        conversations: const <ConversationSummary>[],
      );
      final repository = CachedConversationRepository(delegate: delegate);

      await repository.refresh();
      final conversations = await repository.listConversations();

      expect(conversations, isEmpty);
      expect(delegate.listConversationsCalls, 1);
    });

    test('upserted conversations are sorted by newest updatedAt', () async {
      final delegate = _FakeConversationRepository(
        conversations: <ConversationSummary>[
          _conversation(
            id: 'old',
            updatedAt: '2026-05-28T00:00:01.000Z',
          ),
          _conversation(
            id: 'newer',
            updatedAt: '2026-05-28T00:00:03.000Z',
          ),
        ],
      );
      final repository = CachedConversationRepository(delegate: delegate);

      await repository.refresh();
      await repository.updateConversationModel('old', 'gpt-5');

      expect(
        repository.conversations.map((conversation) => conversation.id),
        const <String>['old', 'newer'],
      );
    });

    test('stale refresh does not overwrite newer mutation result', () async {
      final staleRefresh = Completer<List<ConversationSummary>>();
      final delegate = _FakeConversationRepository(
        conversations: <ConversationSummary>[_conversation(id: 'c1')],
      )..queuedConversations.add(staleRefresh.future);
      final repository = CachedConversationRepository(delegate: delegate);

      final pendingRefresh = repository.refresh();
      await pumpEventQueue();
      await repository.updateConversationModel('c1', 'gpt-5');
      staleRefresh.complete(<ConversationSummary>[
        _conversation(id: 'c1', model: 'stale'),
      ]);
      await pendingRefresh;

      expect(repository.conversations.single.model, 'gpt-5');
    });

    test('overlapping refresh merges unrelated conversations', () async {
      final refresh = Completer<List<ConversationSummary>>();
      final mutation = Completer<ConversationSummary>();
      final delegate = _FakeConversationRepository(
        conversations: <ConversationSummary>[_conversation(id: 'c1')],
      )
        ..queuedConversations.add(refresh.future)
        ..queuedModelUpdates.add(mutation.future);
      final repository = CachedConversationRepository(delegate: delegate);

      final pendingRefresh = repository.refresh();
      await pumpEventQueue();
      final pendingMutation = repository.updateConversationModel('c1', 'gpt-5');
      mutation.complete(_conversation(
        id: 'c1',
        model: 'gpt-5',
        updatedAt: '2026-05-28T00:00:04.000Z',
      ));
      await pendingMutation;
      refresh.complete(<ConversationSummary>[
        _conversation(id: 'c1', model: 'stale'),
        _conversation(
          id: 'c2',
          model: 'claude-sonnet',
          updatedAt: '2026-05-28T00:00:03.000Z',
        ),
      ]);
      await pendingRefresh;

      expect(
        repository.conversations.map((conversation) => conversation.id),
        const <String>['c1', 'c2'],
      );
      expect(repository.conversations.first.model, 'gpt-5');
      expect(repository.conversations.last.model, 'claude-sonnet');
    });

    test('overlapping refresh updates existing unrelated conversation',
        () async {
      final refresh = Completer<List<ConversationSummary>>();
      final mutation = Completer<ConversationSummary>();
      final delegate = _FakeConversationRepository(
        conversations: <ConversationSummary>[
          _conversation(id: 'c1', model: 'old-local'),
          _conversation(id: 'c2', model: 'old-unrelated'),
        ],
      );
      final repository = CachedConversationRepository(delegate: delegate);
      await repository.refresh();
      delegate
        ..queuedConversations.add(refresh.future)
        ..queuedModelUpdates.add(mutation.future);

      final pendingRefresh = repository.refresh();
      await pumpEventQueue();
      final pendingMutation = repository.updateConversationModel('c1', 'gpt-5');
      mutation.complete(_conversation(
        id: 'c1',
        model: 'gpt-5',
        updatedAt: '2026-05-28T00:00:04.000Z',
      ));
      await pendingMutation;
      refresh.complete(<ConversationSummary>[
        _conversation(id: 'c1', model: 'stale-refresh'),
        _conversation(
          id: 'c2',
          model: 'fresh-unrelated',
          updatedAt: '2026-05-28T00:00:03.000Z',
        ),
      ]);
      await pendingRefresh;

      final byId = <String, ConversationSummary>{
        for (final conversation in repository.conversations)
          conversation.id: conversation,
      };
      expect(byId['c1']?.model, 'gpt-5');
      expect(byId['c2']?.model, 'fresh-unrelated');
    });

    test('refresh started after pending mutation does not drop mutation result',
        () async {
      final mutation = Completer<ConversationSummary>();
      final delegate = _FakeConversationRepository(
        conversations: <ConversationSummary>[_conversation(id: 'c1')],
      )..queuedModelUpdates.add(mutation.future);
      final repository = CachedConversationRepository(delegate: delegate);
      await repository.refresh();

      final pendingMutation = repository.updateConversationModel('c1', 'gpt-5');
      await pumpEventQueue();
      await repository.refresh();
      mutation.complete(_conversation(id: 'c1', model: 'gpt-5'));
      await pendingMutation;

      expect(repository.conversations.single.model, 'gpt-5');
    });

    test('independent overlapping mutations are both merged', () async {
      final firstMutation = Completer<ConversationSummary>();
      final secondMutation = Completer<ConversationSummary>();
      final delegate = _FakeConversationRepository(
        conversations: <ConversationSummary>[
          _conversation(id: 'c1'),
          _conversation(id: 'c2'),
        ],
      )
        ..queuedModelUpdates.add(firstMutation.future)
        ..queuedModelUpdates.add(secondMutation.future);
      final repository = CachedConversationRepository(delegate: delegate);
      await repository.refresh();

      final pendingFirst = repository.updateConversationModel('c1', 'gpt-5');
      final pendingSecond = repository.updateConversationModel('c2', 'gpt-4.1');
      firstMutation.complete(_conversation(id: 'c1', model: 'gpt-5'));
      secondMutation.complete(_conversation(id: 'c2', model: 'gpt-4.1'));
      await Future.wait([pendingFirst, pendingSecond]);

      expect(
        repository.conversations.map((conversation) => conversation.model),
        containsAll(<String>['gpt-5', 'gpt-4.1']),
      );
    });

    test('dispose during in-flight refresh does not notify or mutate',
        () async {
      final conversations = Completer<List<ConversationSummary>>();
      final delegate = _FakeConversationRepository(
        conversations: const <ConversationSummary>[],
      )..queuedConversations.add(conversations.future);
      final repository = CachedConversationRepository(delegate: delegate);
      var notifications = 0;
      repository.addListener(() => notifications++);

      final pending = repository.refresh();
      await pumpEventQueue();
      repository.dispose();
      conversations.complete(<ConversationSummary>[
        _conversation(id: 'late'),
      ]);
      await pending;

      expect(notifications, 1);
      expect(repository.conversations, isEmpty);
    });

    test('event page requests are delegated without refreshing cache',
        () async {
      final delegate = _FakeConversationRepository(
        conversations: <ConversationSummary>[_conversation(id: 'c1')],
      );
      final repository = CachedConversationRepository(delegate: delegate);

      final page = await repository.fetchConversationEventPage(
        'c1',
        beforeSeq: 9,
        limit: 2,
      );

      expect(delegate.eventPageCalls, const <String>['c1:9:2']);
      expect(delegate.listConversationsCalls, 0);
      expect(page.events.map((event) => event.seq), const <int>[7, 8]);
      expect(page.oldestSeq, 7);
      expect(page.newestSeq, 8);
      expect(page.hasMoreBefore, isFalse);
    });

    test('cached tail page avoids daemon event page request', () async {
      final delegate = _FakeConversationRepository(
        conversations: <ConversationSummary>[_conversation(id: 'c1')],
      );
      final eventCache = _MemoryConversationEventCacheStore()
        ..tailPage = ConversationEventPage(
          events: <ConversationEvent>[
            _conversationEvent(conversationId: 'c1', seq: 11),
          ],
          oldestSeq: 11,
          newestSeq: 11,
          hasMoreBefore: false,
        );
      final repository = CachedConversationRepository(
        delegate: delegate,
        eventCache: eventCache,
        eventCacheNamespace: 'daemon',
      );

      final page = await repository.fetchConversationEventPage(
        'c1',
        limit: 80,
      );

      expect(delegate.eventPageCalls, isEmpty);
      expect(page.events.single.seq, 11);
    });

    test('daemon event page is persisted on cache miss', () async {
      final delegate = _FakeConversationRepository(
        conversations: <ConversationSummary>[_conversation(id: 'c1')],
      );
      final eventCache = _MemoryConversationEventCacheStore();
      final repository = CachedConversationRepository(
        delegate: delegate,
        eventCache: eventCache,
        eventCacheNamespace: 'daemon',
      );

      await repository.fetchConversationEventPage('c1', limit: 2);
      await pumpEventQueue();

      expect(delegate.eventPageCalls, const <String>['c1:null:2']);
      expect(eventCache.upsertedPages.single.events.map((event) => event.seq),
          const <int>[7, 8]);
    });

    test('fetched conversation events filter mismatched conversation events',
        () async {
      final delegate = _FakeConversationRepository(
        conversations: <ConversationSummary>[_conversation(id: 'c1')],
      )..fetchedEvents = <ConversationEvent>[
          _conversationEvent(conversationId: 'c2', seq: 8),
          _conversationEvent(conversationId: 'c1', seq: 9),
        ];
      final eventCache = _MemoryConversationEventCacheStore();
      final repository = CachedConversationRepository(
        delegate: delegate,
        eventCache: eventCache,
        eventCacheNamespace: 'daemon',
      );

      final events =
          await repository.fetchConversationEvents('c1', afterSeq: 0);
      await pumpEventQueue();

      expect(
        events.map((event) => event.conversationId),
        const <String>['c1'],
      );
      expect(
        eventCache.upsertedEvents.single.map((event) => event.conversationId),
        const <String>['c1'],
      );
    });

    test('daemon event page filters mismatched conversation events', () async {
      final delegate = _FakeConversationRepository(
        conversations: <ConversationSummary>[_conversation(id: 'c1')],
      )..eventPage = ConversationEventPage(
          events: <ConversationEvent>[
            _conversationEvent(conversationId: 'c2', seq: 6),
            _conversationEvent(conversationId: 'c1', seq: 7),
          ],
          oldestSeq: 6,
          newestSeq: 7,
          hasMoreBefore: false,
        );
      final eventCache = _MemoryConversationEventCacheStore();
      final repository = CachedConversationRepository(
        delegate: delegate,
        eventCache: eventCache,
        eventCacheNamespace: 'daemon',
      );

      final page = await repository.fetchConversationEventPage('c1', limit: 2);
      await pumpEventQueue();

      expect(
        page.events.map((event) => event.conversationId),
        const <String>['c1'],
      );
      expect(
        eventCache.upsertedPages.single.events.map(
          (event) => event.conversationId,
        ),
        const <String>['c1'],
      );
    });

    test('streamed conversation events are persisted', () async {
      final delegate = _FakeConversationRepository(
        conversations: <ConversationSummary>[_conversation(id: 'c1')],
      );
      final eventCache = _MemoryConversationEventCacheStore();
      final repository = CachedConversationRepository(
        delegate: delegate,
        eventCache: eventCache,
        eventCacheNamespace: 'daemon',
      );

      final events = repository.watchConversationEvents('c1', afterSeq: 8);
      final firstEvent = events.first;
      delegate.emitConversationEvent(
        _conversationEvent(conversationId: 'c1', seq: 9),
      );
      await firstEvent;
      await pumpEventQueue();

      expect(
        eventCache.upsertedEvents.single.map((event) => event.seq),
        const <int>[9],
      );
    });

    test('streamed mismatched conversation events are not delivered or cached',
        () async {
      final delegate = _FakeConversationRepository(
        conversations: <ConversationSummary>[_conversation(id: 'c1')],
      );
      final eventCache = _MemoryConversationEventCacheStore();
      final repository = CachedConversationRepository(
        delegate: delegate,
        eventCache: eventCache,
        eventCacheNamespace: 'daemon',
      );

      final firstMatchingEvent =
          repository.watchConversationEvents('c1', afterSeq: 0).first;
      delegate
        ..emitConversationEvent(_conversationEvent(
          conversationId: 'c2',
          seq: 1,
        ))
        ..emitConversationEvent(_conversationEvent(
          conversationId: 'c1',
          seq: 2,
        ));
      final event = await firstMatchingEvent;
      await pumpEventQueue();

      expect(event.conversationId, 'c1');
      expect(
        eventCache.upsertedEvents.expand((events) => events).map(
              (event) => event.conversationId,
            ),
        const <String>['c1'],
      );
    });

    test('streamed terminal events update cached conversation status',
        () async {
      final delegate = _FakeConversationRepository(
        conversations: <ConversationSummary>[
          _conversation(id: 'c1', status: 'running'),
        ],
      );
      final repository = CachedConversationRepository(delegate: delegate);
      await repository.refresh();
      final subscription =
          repository.watchConversationEvents('c1', afterSeq: 0).listen((_) {});

      delegate
        ..emitConversationEvent(_conversationEvent(
          conversationId: 'c1',
          seq: 1,
          type: 'tool.started',
        ))
        ..emitConversationEvent(_conversationEvent(
          conversationId: 'c1',
          seq: 2,
          type: 'tool.completed',
        ))
        ..emitConversationEvent(_conversationEvent(
          conversationId: 'c1',
          seq: 3,
          type: 'conversation.completed',
        ))
        ..emitConversationEvent(_conversationEvent(
          conversationId: 'c1',
          seq: 4,
          type: 'conversation.status_changed',
          raw: const <String, Object?>{'status': 'idle'},
        ));
      await pumpEventQueue();
      await subscription.cancel();

      expect(repository.conversations.single.status, 'idle');
    });

    test('late approval resolution does not reactivate terminal conversation',
        () async {
      final delegate = _FakeConversationRepository(
        conversations: <ConversationSummary>[
          _conversation(id: 'c1', status: 'running'),
        ],
      );
      final repository = CachedConversationRepository(delegate: delegate);
      await repository.refresh();
      final subscription =
          repository.watchConversationEvents('c1', afterSeq: 0).listen((_) {});

      delegate
        ..emitConversationEvent(_conversationEvent(
          conversationId: 'c1',
          seq: 1,
          type: 'conversation.completed',
        ))
        ..emitConversationEvent(_conversationEvent(
          conversationId: 'c1',
          seq: 2,
          type: 'approval.resolved',
          approvalId: 'approval_late',
          raw: const <String, Object?>{'decision': 'deny'},
        ));
      await pumpEventQueue();
      await subscription.cancel();

      expect(repository.conversations.single.status, 'idle');
      expect(repository.conversations.single.blockingItem, isNull);
    });

    test('streamed blocking cancellations clear cached conversation status',
        () async {
      final delegate = _FakeConversationRepository(
        conversations: <ConversationSummary>[
          _conversation(id: 'c1', status: 'running'),
        ],
      );
      final repository = CachedConversationRepository(delegate: delegate);
      await repository.refresh();
      final subscription =
          repository.watchConversationEvents('c1', afterSeq: 0).listen((_) {});

      delegate
        ..emitConversationEvent(_conversationEvent(
          conversationId: 'c1',
          seq: 1,
          type: 'approval.requested',
          approvalId: 'approval_cancelled',
        ))
        ..emitConversationEvent(_conversationEvent(
          conversationId: 'c1',
          seq: 2,
          type: 'blocking.request_cancelled',
          approvalId: 'approval_cancelled',
          raw: const <String, Object?>{'blockingType': 'approval_request'},
        ));
      await pumpEventQueue();
      await subscription.cancel();

      expect(repository.conversations.single.status, 'running');
      expect(repository.conversations.single.blockingItem, isNull);
    });

    test('streamed non-current approval resolution preserves waiting status',
        () async {
      const blockingItem = ConversationBlockingItem(
        type: 'approval_request',
        approvalId: 'approval_current',
      );
      final delegate = _FakeConversationRepository(
        conversations: <ConversationSummary>[
          _conversation(
            id: 'c1',
            status: 'waiting_approval',
            blockingItem: blockingItem,
          ),
        ],
      );
      final repository = CachedConversationRepository(delegate: delegate);
      await repository.refresh();
      final subscription =
          repository.watchConversationEvents('c1', afterSeq: 0).listen((_) {});

      delegate.emitConversationEvent(_conversationEvent(
        conversationId: 'c1',
        seq: 1,
        type: 'approval.resolved',
        approvalId: 'approval_queued',
        raw: const <String, Object?>{'decision': 'deny'},
      ));
      await pumpEventQueue();
      await subscription.cancel();

      expect(repository.conversations.single.status, 'waiting_approval');
      expect(repository.conversations.single.blockingItem?.approvalId,
          'approval_current');
    });

    test('streamed uncorrelated approval resolution preserves waiting status',
        () async {
      final delegate = _FakeConversationRepository(
        conversations: <ConversationSummary>[
          _conversation(
            id: 'c1',
            status: 'waiting_approval',
          ),
        ],
      );
      final repository = CachedConversationRepository(delegate: delegate);
      await repository.refresh();
      final subscription =
          repository.watchConversationEvents('c1', afterSeq: 0).listen((_) {});

      delegate.emitConversationEvent(_conversationEvent(
        conversationId: 'c1',
        seq: 1,
        type: 'approval.resolved',
        approvalId: 'approval_queued',
        raw: const <String, Object?>{'decision': 'deny'},
      ));
      await pumpEventQueue();
      await subscription.cancel();

      expect(repository.conversations.single.status, 'waiting_approval');
      expect(repository.conversations.single.blockingItem, isNull);
    });

    test('streamed waiting status preserves cached approval request', () async {
      final delegate = _FakeConversationRepository(
        conversations: <ConversationSummary>[
          _conversation(id: 'c1', status: 'running'),
        ],
      );
      final repository = CachedConversationRepository(delegate: delegate);
      await repository.refresh();
      final subscription =
          repository.watchConversationEvents('c1', afterSeq: 0).listen((_) {});

      delegate
        ..emitConversationEvent(_conversationEvent(
          conversationId: 'c1',
          seq: 1,
          type: 'approval.requested',
          approvalId: 'approval_waiting',
        ))
        ..emitConversationEvent(_conversationEvent(
          conversationId: 'c1',
          seq: 2,
          type: 'conversation.status_changed',
          raw: const <String, Object?>{'status': 'waiting_approval'},
        ));
      await pumpEventQueue();
      await subscription.cancel();

      expect(repository.conversations.single.status, 'waiting_approval');
      expect(repository.conversations.single.blockingItem?.approvalId,
          'approval_waiting');
    });
  });

  group('CachedRunRepository', () {
    test('refreshes runs and queue together', () async {
      final delegate = _FakeRunRepository(
        runs: const <RunSummary>[
          RunSummary(
            id: 'r1',
            tool: 'codex',
            workspaceId: 'w1',
            status: 'running',
          ),
        ],
        queue: const <QueueItem>[
          QueueItem(
            runId: 'r1',
            workspaceId: 'w1',
            position: 1,
            status: 'queued',
            reason: 'busy',
          ),
        ],
      );
      final repository = CachedRunRepository(delegate: delegate);

      await repository.refresh();

      expect(repository.runs.map((run) => run.id), const <String>['r1']);
      expect(repository.queue.map((item) => item.runId), const <String>['r1']);
    });

    test('refresh failure preserves previous data', () async {
      final delegate = _FakeRunRepository(
        runs: const <RunSummary>[
          RunSummary(
            id: 'r1',
            tool: 'codex',
            workspaceId: 'w1',
            status: 'running',
          ),
        ],
        queue: const <QueueItem>[],
      );
      final repository = CachedRunRepository(delegate: delegate);
      await repository.refresh();
      delegate.refreshError = StateError('run refresh failed');

      await expectLater(repository.refresh(), throwsA(isA<StateError>()));

      expect(repository.runs.map((run) => run.id), const <String>['r1']);
      expect(repository.error, isA<StateError>());
      expect(repository.loading, isFalse);
    });

    test('empty runs and queue are valid and are not reloaded', () async {
      final delegate = _FakeRunRepository(
        runs: const <RunSummary>[],
        queue: const <QueueItem>[],
      );
      final repository = CachedRunRepository(delegate: delegate);

      await repository.refresh();
      final runs = await repository.listRuns();
      final queue = await repository.listQueue();

      expect(runs, isEmpty);
      expect(queue, isEmpty);
      expect(delegate.unfilteredListRunsCalls, 1);
      expect(delegate.listQueueCalls, 1);
    });

    test('list methods await an in-flight refresh', () async {
      final runs = Completer<List<RunSummary>>();
      final delegate = _FakeRunRepository(
        runs: const <RunSummary>[],
        queue: const <QueueItem>[],
      )..queuedRuns.add(runs.future);
      final repository = CachedRunRepository(delegate: delegate);

      final pendingRefresh = repository.refresh();
      await pumpEventQueue();
      final pendingList = repository.listRuns();
      await pumpEventQueue();
      expect(delegate.unfilteredListRunsCalls, 1);

      runs.complete(const <RunSummary>[
        RunSummary(
          id: 'loaded',
          tool: 'codex',
          workspaceId: 'w1',
          status: 'running',
        ),
      ]);
      await pendingRefresh;

      expect(
          (await pendingList).map((run) => run.id), const <String>['loaded']);
    });

    test('stale refresh does not overwrite newer mutation result', () async {
      final staleRuns = Completer<List<RunSummary>>();
      final delegate = _FakeRunRepository(
        runs: const <RunSummary>[
          RunSummary(
            id: 'r1',
            tool: 'codex',
            workspaceId: 'w1',
            status: 'running',
          ),
        ],
        queue: const <QueueItem>[],
      )..queuedRuns.add(staleRuns.future);
      final repository = CachedRunRepository(delegate: delegate);

      final pendingRefresh = repository.refresh();
      await pumpEventQueue();
      await repository.cancelRun('r1');
      staleRuns.complete(const <RunSummary>[
        RunSummary(
          id: 'r1',
          tool: 'codex',
          workspaceId: 'w1',
          status: 'running',
        ),
      ]);
      await pendingRefresh;

      expect(repository.runs.single.status, 'cancelled');
    });

    test('overlapping refresh merges unrelated runs and queue', () async {
      final refresh = Completer<List<RunSummary>>();
      final mutation = Completer<RunSummary>();
      final delegate = _FakeRunRepository(
        runs: const <RunSummary>[
          RunSummary(
            id: 'r1',
            tool: 'codex',
            workspaceId: 'w1',
            status: 'running',
          ),
        ],
        queue: const <QueueItem>[
          QueueItem(
            runId: 'r2',
            workspaceId: 'w1',
            position: 1,
            status: 'queued',
            reason: 'busy',
          ),
        ],
      )
        ..queuedRuns.add(refresh.future)
        ..queuedCancelRuns.add(mutation.future);
      final repository = CachedRunRepository(delegate: delegate);

      final pendingRefresh = repository.refresh();
      await pumpEventQueue();
      final pendingMutation = repository.cancelRun('r1');
      mutation.complete(const RunSummary(
        id: 'r1',
        tool: 'codex',
        workspaceId: 'w1',
        status: 'cancelled',
      ));
      await pendingMutation;
      refresh.complete(const <RunSummary>[
        RunSummary(
          id: 'r1',
          tool: 'codex',
          workspaceId: 'w1',
          status: 'running',
        ),
        RunSummary(
          id: 'r2',
          tool: 'codex',
          workspaceId: 'w1',
          status: 'queued',
        ),
      ]);
      await pendingRefresh;

      final byId = <String, RunSummary>{
        for (final run in repository.runs) run.id: run,
      };
      expect(byId['r1']?.status, 'cancelled');
      expect(byId['r2']?.status, 'queued');
      expect(repository.queue.map((item) => item.runId), const <String>['r2']);
    });

    test('overlapping refresh updates existing unrelated run and queue',
        () async {
      final refresh = Completer<List<RunSummary>>();
      final mutation = Completer<RunSummary>();
      final delegate = _FakeRunRepository(
        runs: const <RunSummary>[
          RunSummary(
            id: 'r1',
            tool: 'codex',
            workspaceId: 'w1',
            status: 'running',
          ),
          RunSummary(
            id: 'r2',
            tool: 'codex',
            workspaceId: 'w1',
            status: 'running',
          ),
        ],
        queue: const <QueueItem>[
          QueueItem(
            runId: 'r2',
            workspaceId: 'w1',
            position: 1,
            status: 'queued',
            reason: 'busy',
          ),
        ],
      );
      final repository = CachedRunRepository(delegate: delegate);
      await repository.refresh();
      delegate
        ..queuedRuns.add(refresh.future)
        ..queuedCancelRuns.add(mutation.future);

      final pendingRefresh = repository.refresh();
      await pumpEventQueue();
      final pendingMutation = repository.cancelRun('r1');
      mutation.complete(const RunSummary(
        id: 'r1',
        tool: 'codex',
        workspaceId: 'w1',
        status: 'cancelled',
      ));
      await pendingMutation;
      refresh.complete(const <RunSummary>[
        RunSummary(
          id: 'r1',
          tool: 'codex',
          workspaceId: 'w1',
          status: 'running',
        ),
        RunSummary(
          id: 'r2',
          tool: 'codex',
          workspaceId: 'w1',
          status: 'completed',
        ),
      ]);
      await pendingRefresh;

      final byId = <String, RunSummary>{
        for (final run in repository.runs) run.id: run,
      };
      expect(byId['r1']?.status, 'cancelled');
      expect(byId['r2']?.status, 'completed');
      expect(repository.queue.map((item) => item.runId), const <String>['r2']);
    });

    test('refresh started after pending mutation does not drop mutation result',
        () async {
      final mutation = Completer<RunSummary>();
      final delegate = _FakeRunRepository(
        runs: const <RunSummary>[
          RunSummary(
            id: 'r1',
            tool: 'codex',
            workspaceId: 'w1',
            status: 'running',
          ),
        ],
        queue: const <QueueItem>[],
      )..queuedCancelRuns.add(mutation.future);
      final repository = CachedRunRepository(delegate: delegate);
      await repository.refresh();

      final pendingMutation = repository.cancelRun('r1');
      await pumpEventQueue();
      await repository.refresh();
      mutation.complete(const RunSummary(
        id: 'r1',
        tool: 'codex',
        workspaceId: 'w1',
        status: 'cancelled',
      ));
      await pendingMutation;

      expect(repository.runs.single.status, 'cancelled');
    });

    test('independent overlapping run mutations are both merged', () async {
      final firstMutation = Completer<RunSummary>();
      final secondMutation = Completer<RunSummary>();
      final delegate = _FakeRunRepository(
        runs: const <RunSummary>[
          RunSummary(
            id: 'r1',
            tool: 'codex',
            workspaceId: 'w1',
            status: 'running',
          ),
          RunSummary(
            id: 'r2',
            tool: 'codex',
            workspaceId: 'w1',
            status: 'running',
          ),
        ],
        queue: const <QueueItem>[],
      )
        ..queuedCancelRuns.add(firstMutation.future)
        ..queuedCancelRuns.add(secondMutation.future);
      final repository = CachedRunRepository(delegate: delegate);
      await repository.refresh();

      final pendingFirst = repository.cancelRun('r1');
      final pendingSecond = repository.cancelRun('r2');
      firstMutation.complete(const RunSummary(
        id: 'r1',
        tool: 'codex',
        workspaceId: 'w1',
        status: 'cancelled',
      ));
      secondMutation.complete(const RunSummary(
        id: 'r2',
        tool: 'codex',
        workspaceId: 'w1',
        status: 'cancelled',
      ));
      await Future.wait([pendingFirst, pendingSecond]);

      expect(
        repository.runs.map((run) => run.status),
        everyElement('cancelled'),
      );
    });

    test('respondApproval refreshes runs and queue', () async {
      final delegate = _FakeRunRepository(
        runs: const <RunSummary>[
          RunSummary(
            id: 'r1',
            tool: 'codex',
            workspaceId: 'w1',
            status: 'waiting_approval',
          ),
        ],
        queue: const <QueueItem>[],
      );
      final repository = CachedRunRepository(delegate: delegate);
      await repository.refresh();
      delegate.runs = const <RunSummary>[
        RunSummary(
          id: 'r1',
          tool: 'codex',
          workspaceId: 'w1',
          status: 'running',
        ),
      ];

      await repository.respondApproval('approval-1', 'approved');

      expect(delegate.respondApprovalCalls, 1);
      expect(repository.runs.single.status, 'running');
    });

    test('cancelRun removes cancelled queued run from cached queue', () async {
      final delegate = _FakeRunRepository(
        runs: const <RunSummary>[
          RunSummary(
            id: 'r1',
            tool: 'codex',
            workspaceId: 'w1',
            status: 'running',
          ),
          RunSummary(
            id: 'r2',
            tool: 'codex',
            workspaceId: 'w1',
            status: 'queued',
          ),
          RunSummary(
            id: 'r3',
            tool: 'codex',
            workspaceId: 'w1',
            status: 'queued',
          ),
        ],
        queue: const <QueueItem>[
          QueueItem(
            runId: 'r2',
            workspaceId: 'w1',
            position: 1,
            status: 'queued',
            reason: 'busy',
          ),
          QueueItem(
            runId: 'r3',
            workspaceId: 'w1',
            position: 2,
            status: 'queued',
            reason: 'busy',
          ),
        ],
      );
      final repository = CachedRunRepository(delegate: delegate);
      await repository.refresh();

      await repository.cancelRun('r2');

      expect(repository.runs.firstWhere((run) => run.id == 'r2').status,
          'cancelled');
      expect(
        repository.queue
            .map((item) => (runId: item.runId, position: item.position)),
        const <({String runId, int position})>[(runId: 'r3', position: 1)],
      );
    });

    test('filtered listRuns semantics are delegated', () async {
      final delegate = _FakeRunRepository(
        runs: const <RunSummary>[
          RunSummary(
            id: 'r1',
            tool: 'codex',
            workspaceId: 'w1',
            status: 'running',
          ),
          RunSummary(
            id: 'r2',
            tool: 'claude',
            workspaceId: 'w2',
            status: 'completed',
          ),
        ],
        queue: const <QueueItem>[],
      );
      final repository = CachedRunRepository(delegate: delegate);
      await repository.refresh();

      final filtered = await repository.listRuns(
        tool: 'codex',
        workspaceId: 'w1',
        status: 'running',
      );

      expect(filtered.map((run) => run.id), const <String>['r1']);
      expect(delegate.filteredListRunsCalls, 1);
    });

    test('dispose during in-flight refresh does not notify after dispose',
        () async {
      final runs = Completer<List<RunSummary>>();
      final delegate = _FakeRunRepository(
        runs: const <RunSummary>[],
        queue: const <QueueItem>[],
      )..queuedRuns.add(runs.future);
      final repository = CachedRunRepository(delegate: delegate);
      var notifications = 0;
      repository.addListener(() => notifications++);

      final pending = repository.refresh();
      await pumpEventQueue();
      repository.dispose();
      runs.complete(const <RunSummary>[
        RunSummary(
          id: 'late',
          tool: 'codex',
          workspaceId: 'w1',
          status: 'running',
        ),
      ]);
      await pending;

      expect(notifications, 1);
      expect(repository.runs, isEmpty);
    });
  });
}

class _FakeAdapterRepository implements AdapterRepository {
  var listAdaptersCalls = 0;
  var listShortcutsCalls = 0;
  var listCommandTemplatesCalls = 0;
  var listExtensionsCalls = 0;
  Object? loadError;
  Object? templatesError;
  final queuedAdapters = <Future<List<AdapterStatus>>>[];
  List<AdapterStatus> adapters = const <AdapterStatus>[
    AdapterStatus(adapter: 'codex', available: true, status: 'available'),
  ];
  List<ShortcutCommand> shortcuts = const <ShortcutCommand>[
    ShortcutCommand(
      id: 's1',
      label: 'Shortcut',
      prompt: 'Do it',
      tool: 'codex',
    ),
  ];
  List<CommandTemplate> templates = const <CommandTemplate>[
    CommandTemplate(
      id: 't1',
      label: 'Template',
      prompt: 'Do it',
      requiresApproval: false,
    ),
  ];
  List<ExtensionSummary> extensions = const <ExtensionSummary>[
    ExtensionSummary(
      id: 'e1',
      name: 'Extension',
      version: '1.0.0',
      installed: true,
      status: 'enabled',
      description: 'Test extension',
    ),
  ];

  @override
  Future<List<AdapterStatus>> listAdapters() async {
    listAdaptersCalls += 1;
    if (queuedAdapters.isNotEmpty) return queuedAdapters.removeAt(0);
    final error = loadError;
    if (error != null) throw error;
    return adapters;
  }

  @override
  Future<List<ShortcutCommand>> listShortcuts() async {
    listShortcutsCalls += 1;
    final error = loadError;
    if (error != null) throw error;
    return shortcuts;
  }

  @override
  Future<List<CommandTemplate>> listCommandTemplates() async {
    listCommandTemplatesCalls += 1;
    final specificError = templatesError;
    if (specificError != null) throw specificError;
    final error = loadError;
    if (error != null) throw error;
    return templates;
  }

  @override
  Future<List<ExtensionSummary>> listExtensions() async {
    listExtensionsCalls += 1;
    final error = loadError;
    if (error != null) throw error;
    return extensions;
  }
}

class _FakeConversationRepository implements ConversationRepository {
  _FakeConversationRepository(
      {required List<ConversationSummary> conversations})
      : _conversations = conversations;

  List<ConversationSummary> _conversations;
  Object? refreshError;
  var listConversationsCalls = 0;
  final queuedConversations = <Future<List<ConversationSummary>>>[];
  final queuedModelUpdates = <Future<ConversationSummary>>[];
  final eventPageCalls = <String>[];
  List<ConversationEvent>? fetchedEvents;
  ConversationEventPage? eventPage;
  final _conversationEvents = StreamController<ConversationEvent>.broadcast();

  void emitConversationEvent(ConversationEvent event) {
    _conversationEvents.add(event);
  }

  @override
  Future<List<ConversationSummary>> listConversations() async {
    listConversationsCalls += 1;
    if (queuedConversations.isNotEmpty) {
      return queuedConversations.removeAt(0);
    }
    final error = refreshError;
    if (error != null) throw error;
    return _conversations;
  }

  @override
  Future<ConversationSummary> updateConversationModel(
    String conversationId,
    String? model,
  ) async {
    if (queuedModelUpdates.isNotEmpty) {
      return queuedModelUpdates.removeAt(0);
    }
    final existing = _conversations.singleWhere(
      (conversation) => conversation.id == conversationId,
    );
    final updated = _copyConversation(existing, model: model);
    _conversations = <ConversationSummary>[updated];
    return updated;
  }

  @override
  Future<ConversationSummary> updateConversationPermissionMode(
    String conversationId,
    String permissionMode,
  ) async {
    final existing = _conversations.singleWhere(
      (conversation) => conversation.id == conversationId,
    );
    final updated = _copyConversation(existing);
    _conversations = <ConversationSummary>[updated];
    return updated;
  }

  @override
  Future<ConversationSummary> createConversation({
    required String workspaceId,
    String adapter = 'claude',
    String permissionMode = 'default',
    String? model,
  }) async {
    final created = _conversation(id: 'created', workspaceId: workspaceId);
    _conversations = <ConversationSummary>[created, ..._conversations];
    return created;
  }

  @override
  Future<ConversationSummary> sendConversationMessage(
    String conversationId,
    ConversationMessageSendRequest request,
  ) async =>
      _conversation(id: conversationId, status: 'running');

  @override
  Future<ConversationSummary> answerConversationQuestion(
    String conversationId,
    String questionId,
    String text,
  ) async =>
      _conversation(id: conversationId, status: 'running');

  @override
  Future<ConversationSummary> respondConversationApproval(
    String conversationId,
    String approvalId,
    ApprovalResponse response,
  ) async =>
      _conversation(id: conversationId, status: 'running');

  @override
  Future<ConversationSummary> cancelConversation(String conversationId) async =>
      _conversation(id: conversationId, status: 'cancelled');

  @override
  Future<List<ConversationEvent>> fetchConversationEvents(
    String conversationId, {
    int afterSeq = 0,
  }) async =>
      fetchedEvents ?? const <ConversationEvent>[];

  @override
  Future<ConversationEventPage> fetchConversationEventPage(
    String conversationId, {
    int? beforeSeq,
    required int limit,
  }) async {
    eventPageCalls.add('$conversationId:$beforeSeq:$limit');
    final configuredPage = eventPage;
    if (configuredPage != null) return configuredPage;
    return ConversationEventPage(
      events: <ConversationEvent>[
        _conversationEvent(conversationId: conversationId, seq: 7),
        _conversationEvent(conversationId: conversationId, seq: 8),
      ],
      oldestSeq: 7,
      newestSeq: 8,
      hasMoreBefore: false,
    );
  }

  @override
  Stream<ConversationEvent> watchConversationEvents(
    String conversationId, {
    required int afterSeq,
  }) =>
      _conversationEvents.stream;
}

class _FakeRunRepository implements RunRepository {
  _FakeRunRepository({
    required List<RunSummary> runs,
    required List<QueueItem> queue,
  })  : _runs = runs,
        _queue = queue;

  List<RunSummary> _runs;
  final List<QueueItem> _queue;
  Object? refreshError;
  var filteredListRunsCalls = 0;
  var unfilteredListRunsCalls = 0;
  var listQueueCalls = 0;
  var respondApprovalCalls = 0;
  final queuedRuns = <Future<List<RunSummary>>>[];
  final queuedCancelRuns = <Future<RunSummary>>[];

  set runs(List<RunSummary> value) {
    _runs = value;
  }

  @override
  Future<List<RunSummary>> listRuns({
    String? tool,
    String? workspaceId,
    String? status,
  }) async {
    final hasFilter = tool != null || workspaceId != null || status != null;
    if (hasFilter) filteredListRunsCalls += 1;
    if (!hasFilter) unfilteredListRunsCalls += 1;
    if (!hasFilter && queuedRuns.isNotEmpty) return queuedRuns.removeAt(0);
    final error = refreshError;
    if (error != null) throw error;
    return _runs
        .where((run) => tool == null || run.tool == tool)
        .where((run) => workspaceId == null || run.workspaceId == workspaceId)
        .where((run) => status == null || run.status == status)
        .toList(growable: false);
  }

  @override
  Future<List<QueueItem>> listQueue() async {
    listQueueCalls += 1;
    final error = refreshError;
    if (error != null) throw error;
    return _queue;
  }

  @override
  Future<RunSummary> createRun({
    required String tool,
    required String workspaceId,
    String? prompt,
    String? shortcutId,
    String permissionMode = 'default',
  }) async {
    final run = RunSummary(
      id: 'created',
      tool: tool,
      workspaceId: workspaceId,
      status: 'running',
    );
    _runs = <RunSummary>[run, ..._runs];
    return run;
  }

  @override
  Future<RunSummary> sendRunInput(
    String runId,
    String prompt, {
    String permissionMode = 'default',
  }) async =>
      _runs.singleWhere((run) => run.id == runId);

  @override
  Future<RunSummary> cancelRun(String runId) async {
    if (queuedCancelRuns.isNotEmpty) {
      return queuedCancelRuns.removeAt(0);
    }
    final run = _runs.singleWhere((candidate) => candidate.id == runId);
    final cancelled = RunSummary(
      id: run.id,
      tool: run.tool,
      workspaceId: run.workspaceId,
      status: 'cancelled',
      cliSessionId: run.cliSessionId,
    );
    _runs = _runs
        .map((candidate) => candidate.id == runId ? cancelled : candidate)
        .toList(growable: false);
    return cancelled;
  }

  @override
  Future<RunSummary> invokeCommandTemplate({
    required String templateId,
    required String workspaceId,
    String tool = 'claude',
  }) async =>
      createRun(tool: tool, workspaceId: workspaceId);

  @override
  Future<List<AgentEvent>> fetchEvents(String runId,
          {int afterSeq = 0}) async =>
      const <AgentEvent>[];

  @override
  Future<void> respondApproval(String approvalId, String decision) async {
    respondApprovalCalls += 1;
  }
}

ConversationSummary _conversation({
  required String id,
  String workspaceId = 'w1',
  String adapter = 'codex',
  String status = 'running',
  String? model,
  String updatedAt = '2026-05-28T00:00:01.000Z',
  ConversationBlockingItem? blockingItem,
}) =>
    ConversationSummary(
      id: id,
      workspaceId: workspaceId,
      adapter: adapter,
      model: model,
      status: status,
      capabilities:
          ConversationCapabilities.fromJson(const <String, Object?>{}),
      createdAt: '2026-05-28T00:00:00.000Z',
      updatedAt: updatedAt,
      blockingItem: blockingItem,
    );

ConversationSummary _copyConversation(
  ConversationSummary conversation, {
  String? model,
}) =>
    ConversationSummary(
      id: conversation.id,
      workspaceId: conversation.workspaceId,
      adapter: conversation.adapter,
      model: model,
      status: conversation.status,
      cliSessionId: conversation.cliSessionId,
      sessionBinding: conversation.sessionBinding,
      title: conversation.title,
      userMessageCount: conversation.userMessageCount,
      blockingItem: conversation.blockingItem,
      idleExpiresAt: conversation.idleExpiresAt,
      createdAt: conversation.createdAt,
      updatedAt: '2026-05-28T00:00:04.000Z',
      capabilities: conversation.capabilities,
      protocolVersion: conversation.protocolVersion,
      requestedPermissionMode: conversation.requestedPermissionMode,
      effectivePermissionMode: conversation.effectivePermissionMode,
      permissionSupport: conversation.permissionSupport,
    );

ConversationEvent _conversationEvent({
  required String conversationId,
  required int seq,
  String type = 'assistant.message',
  String? approvalId,
  String? questionId,
  Map<String, Object?> raw = const <String, Object?>{},
}) =>
    ConversationEvent(
      seq: seq,
      conversationId: conversationId,
      type: type,
      createdAt: DateTime.parse('2026-05-30T00:00:00.000Z'),
      text: 'event $seq',
      approvalId: approvalId,
      questionId: questionId,
      raw: raw,
    );

class _MemoryConversationEventCacheStore
    implements ConversationEventCacheStore {
  ConversationEventPage? tailPage;
  ConversationEventPage? beforePage;
  final upsertedPages = <ConversationEventPage>[];
  final upsertedEvents = <List<ConversationEvent>>[];

  @override
  Future<ConversationEventPage?> readTail(
    String namespace,
    String conversationId, {
    required int limit,
  }) async =>
      tailPage;

  @override
  Future<ConversationEventPage?> readBefore(
    String namespace,
    String conversationId, {
    required int beforeSeq,
    required int limit,
  }) async =>
      beforePage;

  @override
  Future<void> upsertPage(
    String namespace,
    String conversationId,
    ConversationEventPage page,
  ) async {
    upsertedPages.add(page);
  }

  @override
  Future<void> upsertEvents(
    String namespace,
    String conversationId,
    List<ConversationEvent> events,
  ) async {
    upsertedEvents.add(events);
  }

  @override
  Future<void> clearConversation(
      String namespace, String conversationId) async {}
}
