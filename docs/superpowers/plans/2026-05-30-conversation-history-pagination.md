# Conversation History Pagination Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Make historical workbench conversations open on the latest transcript window and load older events only when the user scrolls upward.

**Architecture:** Keep live replay and historical windows as separate concepts. Daemon adds `tail` and `beforeSeq` event-page queries while preserving existing `afterSeq` behavior. Mobile adds an explicit history-page contract, keeps `afterSeq` for WebSocket/backfill, and makes `WorkbenchViewModel` the single owner of event-window merge and de-duplication.

**Tech Stack:** Node.js daemon with `node:sqlite`, existing HTTP server and `scripts/run-tests.js`; Flutter/Dart mobile app with existing repository contracts, `ChangeNotifier` ViewModels, `ListView.builder`, and existing widget tests. No new dependencies.

---

## File Structure

- Modify `daemon/src/app-sqlite-store.js`: add `listEventsAfter`, `listEventsTail`, and `listEventsBefore`; keep `listEvents` as a compatibility alias.
- Modify `daemon/src/conversation-event-store.js`: expose `listAfter`, `listTail`, and `listBefore` for persistent and in-memory stores; keep `list` as a compatibility alias.
- Modify `daemon/src/conversation-manager.js`: add `listEventPage` with tail/before/after modes and legacy event normalization.
- Modify `daemon/src/server.js`: parse `/api/conversations/:id/events` query modes, validate mixed/invalid parameters, return page metadata for historical modes.
- Modify `scripts/run-tests.js`: add daemon regression coverage for tail, before, gap-aware `hasMoreBefore`, `afterSeq` compatibility, and invalid query modes.
- Modify `mobile/lib/src/data/models/conversation_models.dart`: add `ConversationEventPage`.
- Modify `mobile/lib/src/domain/repositories/conversation_repository.dart`: add `fetchConversationEventPage` with required `limit`.
- Modify `mobile/lib/src/data/services/conversation_service.dart`: add service-level event-page method/signature so service and repository contracts stay aligned.
- Modify `mobile/lib/src/services/daemon_client.dart`: implement event-page query construction and metadata fallback parsing.
- Modify `mobile/lib/src/data/repositories/daemon_conversation_repository.dart`: forward event-page requests to `DaemonClient`.
- Modify `mobile/lib/src/data/repositories/cached_conversation_repository.dart`: forward event-page requests to the delegate.
- Modify test fakes in `mobile/test/*.dart`: implement the new repository method where they implement `ConversationRepository`.
- Modify `mobile/lib/src/ui/features/workbench/view_models/workbench_view_model.dart`: add historical pagination state, tail/older page methods, and event-window merge/de-duplication.
- Modify `mobile/lib/src/ui/features/workbench/coding_workbench_page.dart`: open historical conversations with tail pages, start watch from newest loaded seq, trigger older-page loads near the older scroll edge, and preserve scroll position post-frame.
- Modify `mobile/test/daemon_client_test.dart`, `mobile/test/coding_workbench_controller_test.dart`, and `mobile/test/widget_test.dart`: add mobile regressions from the design.
- Update `docs/project-knowledge/troubleshooting-playbook.md` only if implementation reveals a durable troubleshooting lesson not already captured.

Run Flutter/Dart commands with this environment from `mobile/`:

```powershell
$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
```

If a Flutter/Dart command times out on the first attempt, stop automatic retries and report the exact command for manual execution.

---

## Task 1: Add Daemon Event Paging Store Semantics

**Files:**
- Modify: `daemon/src/app-sqlite-store.js`
- Modify: `daemon/src/conversation-event-store.js`
- Modify: `scripts/run-tests.js`

- [x] **Step 1: Write failing store tests**

In `scripts/run-tests.js`, add tests near the other conversation event store tests. Use the existing `test(...)` helper and `assert`.

```js
test('conversation event store returns tail window in ascending order', () => {
  const persistentStore = {
    events: [],
    nextEventSeq(conversationId) {
      return this.events.filter((event) => event.conversationId === conversationId).length + 1;
    },
    appendEvent(event) {
      this.events.push(event);
    },
    listEventsAfter(conversationId, afterSeq = 0) {
      return this.events
        .filter((event) => event.conversationId === conversationId && event.seq > afterSeq)
        .sort((left, right) => left.seq - right.seq);
    },
    listEventsTail(conversationId, limit) {
      return this.events
        .filter((event) => event.conversationId === conversationId)
        .sort((left, right) => right.seq - left.seq)
        .slice(0, limit)
        .reverse();
    },
    listEventsBefore(conversationId, beforeSeq, limit) {
      const events = this.events
        .filter((event) => event.conversationId === conversationId && event.seq < beforeSeq)
        .sort((left, right) => right.seq - left.seq)
        .slice(0, limit)
        .reverse();
      const oldestSeq = events[0]?.seq ?? null;
      return {
        events,
        hasMoreBefore: oldestSeq == null
          ? false
          : this.events.some((event) => event.conversationId === conversationId && event.seq < oldestSeq),
      };
    },
  };
  const store = new ConversationEventStore({ persistentStore });
  for (let index = 0; index < 6; index += 1) {
    store.append('conv_tail', 'assistant.message', { text: `message ${index}` });
  }

  const page = store.listTail('conv_tail', 3);

  assert.deepEqual(page.events.map((event) => event.seq), [4, 5, 6]);
  assert.equal(page.oldestSeq, 4);
  assert.equal(page.newestSeq, 6);
  assert.equal(page.hasMoreBefore, true);
});

test('conversation event store before page uses existence check for sequence gaps', () => {
  const sqlite = new AppSqliteStore({ dbPath: tempConversationDbPath('conversation-event-gap-page-') });
  try {
    sqlite.saveConversation({
      id: 'conv_gap',
      workspaceId: 'default',
      adapter: 'claude',
      status: 'idle',
      createdAt: '2026-05-30T00:00:00.000Z',
      updatedAt: '2026-05-30T00:00:00.000Z',
    });
    sqlite.appendEvent({
      conversationId: 'conv_gap',
      seq: 10,
      type: 'assistant.message',
      createdAt: '2026-05-30T00:00:00.000Z',
      text: 'old',
    });
    sqlite.appendEvent({
      conversationId: 'conv_gap',
      seq: 20,
      type: 'assistant.message',
      createdAt: '2026-05-30T00:00:01.000Z',
      text: 'middle',
    });
    sqlite.appendEvent({
      conversationId: 'conv_gap',
      seq: 30,
      type: 'assistant.message',
      createdAt: '2026-05-30T00:00:02.000Z',
      text: 'new',
    });
    const store = new ConversationEventStore({ persistentStore: sqlite });
    const all = store.listAfter('conv_gap', 0);
    assert.deepEqual(all.map((event) => event.seq), [10, 20, 30]);

    const page = store.listBefore('conv_gap', 30, 1);

    assert.deepEqual(page.events.map((event) => event.seq), [20]);
    assert.equal(page.oldestSeq, 20);
    assert.equal(page.newestSeq, 20);
    assert.equal(page.hasMoreBefore, true);
  } finally {
    sqlite.close();
  }
});
```

- [x] **Step 2: Run daemon tests and verify failure**

Run:

```powershell
npm test
```

Expected: FAIL because `ConversationEventStore.listTail` and `ConversationEventStore.listBefore` do not exist.

- [x] **Step 3: Implement store page methods**

In `daemon/src/conversation-event-store.js`, replace `list` with explicit methods while keeping `list` as an alias:

```js
  listAfter(conversationId, afterSeq = 0) {
    if (this.persistentStore) {
      if (typeof this.persistentStore.listEventsAfter === 'function') {
        return this.persistentStore.listEventsAfter(conversationId, afterSeq);
      }
      return this.persistentStore.listEvents(conversationId, afterSeq);
    }
    const seq = Number(afterSeq || 0);
    return (this.events.get(conversationId) || [])
      .filter((event) => event.seq > seq)
      .sort((left, right) => left.seq - right.seq);
  }

  listTail(conversationId, limit) {
    if (this.persistentStore) return this.persistentStore.listEventsTail(conversationId, limit);
    const events = (this.events.get(conversationId) || [])
      .slice()
      .sort((left, right) => right.seq - left.seq)
      .slice(0, clampEventPageLimit(limit))
      .reverse();
    return eventPage(events, this.hasEventsBefore(conversationId, events[0]?.seq));
  }

  listBefore(conversationId, beforeSeq, limit) {
    if (this.persistentStore) return this.persistentStore.listEventsBefore(conversationId, beforeSeq, limit);
    const seq = Number(beforeSeq);
    const events = (this.events.get(conversationId) || [])
      .filter((event) => event.seq < seq)
      .sort((left, right) => right.seq - left.seq)
      .slice(0, clampEventPageLimit(limit))
      .reverse();
    return eventPage(events, this.hasEventsBefore(conversationId, events[0]?.seq));
  }

  hasEventsBefore(conversationId, seq) {
    if (seq == null) return false;
    return (this.events.get(conversationId) || []).some((event) => event.seq < seq);
  }

  list(conversationId, afterSeq = 0) {
    return this.listAfter(conversationId, afterSeq);
  }
```

Add helpers below the class:

```js
function clampEventPageLimit(limit) {
  return Math.max(1, Math.min(Number(limit) || 80, 200));
}

function eventPage(events, hasMoreBefore) {
  return {
    events,
    oldestSeq: events[0]?.seq ?? null,
    newestSeq: events.at(-1)?.seq ?? null,
    hasMoreBefore: Boolean(hasMoreBefore),
  };
}
```

In `daemon/src/app-sqlite-store.js`, keep `listEvents` as an alias and add persistent methods:

```js
  listEventsAfter(conversationId, afterSeq = 0) {
    return this.db.prepare(`
      SELECT conversation_id, seq, type, created_at, payload_json
      FROM conversation_events
      WHERE conversation_id = ? AND seq > ?
      ORDER BY seq ASC
    `).all(conversationId, Number(afterSeq || 0)).map(deserializeEvent);
  }

  listEventsTail(conversationId, limit = 80) {
    const rows = this.db.prepare(`
      SELECT conversation_id, seq, type, created_at, payload_json
      FROM conversation_events
      WHERE conversation_id = ?
      ORDER BY seq DESC
      LIMIT ?
    `).all(conversationId, clampConversationEventPageLimit(limit)).reverse();
    const events = rows.map(deserializeEvent);
    return conversationEventPage(events, this.hasConversationEventsBefore(conversationId, events[0]?.seq));
  }

  listEventsBefore(conversationId, beforeSeq, limit = 80) {
    const rows = this.db.prepare(`
      SELECT conversation_id, seq, type, created_at, payload_json
      FROM conversation_events
      WHERE conversation_id = ? AND seq < ?
      ORDER BY seq DESC
      LIMIT ?
    `).all(conversationId, Number(beforeSeq), clampConversationEventPageLimit(limit)).reverse();
    const events = rows.map(deserializeEvent);
    return conversationEventPage(events, this.hasConversationEventsBefore(conversationId, events[0]?.seq));
  }

  listEvents(conversationId, afterSeq = 0) {
    return this.listEventsAfter(conversationId, afterSeq);
  }

  hasConversationEventsBefore(conversationId, seq) {
    if (seq == null) return false;
    const row = this.db.prepare(`
      SELECT EXISTS (
        SELECT 1 FROM conversation_events
        WHERE conversation_id = ? AND seq < ?
      ) AS has_more
    `).get(conversationId, Number(seq));
    return Boolean(row?.has_more);
  }
```

Add helpers near `deserializeEvent` helpers:

```js
function clampConversationEventPageLimit(limit) {
  return Math.max(1, Math.min(Number(limit) || 80, 200));
}

function conversationEventPage(events, hasMoreBefore) {
  return {
    events,
    oldestSeq: events[0]?.seq ?? null,
    newestSeq: events.at(-1)?.seq ?? null,
    hasMoreBefore: Boolean(hasMoreBefore),
  };
}
```

- [x] **Step 4: Run daemon tests and verify pass**

Run:

```powershell
npm test
```

Expected: PASS.

- [ ] **Step 5: Commit daemon store paging**

```powershell
git add daemon/src/app-sqlite-store.js daemon/src/conversation-event-store.js scripts/run-tests.js
git commit -m "Support paged conversation event store reads" -m "Historical workbench openings need latest-first event windows without changing live afterSeq replay semantics." -m "Constraint: hasMoreBefore must use an existence check so sequence gaps remain correct." -m "Tested: npm test"
```

---

## Task 2: Add Daemon HTTP Query Modes

**Files:**
- Modify: `daemon/src/conversation-manager.js`
- Modify: `daemon/src/server.js`
- Modify: `scripts/run-tests.js`

- [x] **Step 1: Write failing HTTP API tests**

In `scripts/run-tests.js`, add a test near the HTTP API conversation tests. Use `createApp`, `request`, and the app's stores directly so the test does not rely on a real CLI run.

```js
test('conversation events API supports tail and beforeSeq pages', async () => {
  const app = createApp({ port: 0, appDbPath: tempConversationDbPath('conversation-event-pages-') });
  const port = await new Promise((resolve) => app.server.listen(0, () => resolve(app.server.address().port)));
  try {
    const paired = await request(port, 'POST', '/api/pair', { label: 'phone' });
    const token = paired.body.token;
    const created = await request(port, 'POST', '/api/conversations', {
      workspaceId: 'default',
      adapter: 'claude',
      permissionMode: 'default',
    }, token);
    assert.equal(created.status, 201);
    const conversationId = created.body.conversation.id;
    app.conversationEventStore.append(conversationId, 'assistant.message', { text: 'one' });
    app.conversationEventStore.append(conversationId, 'assistant.message', { text: 'two' });
    app.conversationEventStore.append(conversationId, 'assistant.message', { text: 'three' });
    app.conversationEventStore.append(conversationId, 'assistant.message', { text: 'four' });

    const tail = await request(port, 'GET', `/api/conversations/${conversationId}/events?tail=2`, null, token);
    assert.equal(tail.status, 200);
    assert.deepEqual(tail.body.events.map((event) => event.seq), [3, 4]);
    assert.deepEqual(tail.body.page, {
      mode: 'tail',
      oldestSeq: 3,
      newestSeq: 4,
      hasMoreBefore: true,
    });

    const before = await request(port, 'GET', `/api/conversations/${conversationId}/events?beforeSeq=3&limit=2`, null, token);
    assert.equal(before.status, 200);
    assert.deepEqual(before.body.events.map((event) => event.seq), [1, 2]);
    assert.equal(before.body.page.mode, 'before');
    assert.equal(before.body.page.hasMoreBefore, false);
  } finally {
    app.server.close();
    app.notificationHub.stop();
    app.appSqliteStore.close();
  }
});

test('conversation events API rejects mixed pagination modes', async () => {
  const app = createApp({ port: 0, appDbPath: tempConversationDbPath('conversation-event-page-invalid-') });
  const port = await new Promise((resolve) => app.server.listen(0, () => resolve(app.server.address().port)));
  try {
    const paired = await request(port, 'POST', '/api/pair', { label: 'phone' });
    const token = paired.body.token;
    const created = await request(port, 'POST', '/api/conversations', {
      workspaceId: 'default',
      adapter: 'claude',
      permissionMode: 'default',
    }, token);
    for (const query of [
      'afterSeq=0&tail=2',
      'afterSeq=0&beforeSeq=3',
      'tail=2&beforeSeq=3',
    ]) {
      const response = await request(port, 'GET', `/api/conversations/${created.body.conversation.id}/events?${query}`, null, token);

      assert.equal(response.status, 400);
      assert.equal(response.body.error.code, 'invalid_event_page_query');
    }
  } finally {
    app.server.close();
    app.notificationHub.stop();
    app.appSqliteStore.close();
  }
});
```

- [x] **Step 2: Run daemon tests and verify failure**

Run:

```powershell
npm test
```

Expected: FAIL because the server treats all event requests as `afterSeq`.

- [x] **Step 3: Implement manager page method**

In `daemon/src/conversation-manager.js`, keep `listEvents` but switch it to `listAfter`, then add `listEventPage`:

```js
  listEvents(conversationId, afterSeq, device) {
    const conversation = this.requireConversation(conversationId, device);
    return this.eventStore
      .listAfter(conversation.id, afterSeq)
      .map((event) => normalizeLegacyConversationEventForReplay(event, conversation));
  }

  listEventPage(conversationId, pageRequest, device) {
    const conversation = this.requireConversation(conversationId, device);
    const page = pageRequest.mode === 'tail'
      ? this.eventStore.listTail(conversation.id, pageRequest.limit)
      : this.eventStore.listBefore(conversation.id, pageRequest.beforeSeq, pageRequest.limit);
    return {
      events: page.events.map((event) => normalizeLegacyConversationEventForReplay(event, conversation)),
      page: {
        mode: pageRequest.mode,
        oldestSeq: page.oldestSeq,
        newestSeq: page.newestSeq,
        hasMoreBefore: page.hasMoreBefore,
      },
    };
  }
```

- [x] **Step 4: Implement server query parsing**

In `daemon/src/server.js`, replace the conversation events block with a parser-backed branch:

```js
      const conversationEvents = url.pathname.match(/^\/api\/conversations\/([^/]+)\/events$/);
      if (method === 'GET' && conversationEvents) {
        const pageRequest = parseConversationEventPageRequest(url.searchParams);
        if (pageRequest.mode === 'after') {
          return json(res, 200, {
            events: conversations.listEvents(conversationEvents[1], pageRequest.afterSeq, device)
          });
        }
        return json(res, 200, conversations.listEventPage(conversationEvents[1], pageRequest, device));
      }
```

Add helper functions near other server helpers:

```js
function parseConversationEventPageRequest(searchParams) {
  const hasAfter = searchParams.has('afterSeq');
  const hasTail = searchParams.has('tail');
  const hasBefore = searchParams.has('beforeSeq');
  const modeCount = [hasAfter, hasTail, hasBefore].filter(Boolean).length;
  if (modeCount > 1) throw httpError(400, 'invalid_event_page_query', 'Use only one conversation event page mode.');
  if (hasTail) {
    return { mode: 'tail', limit: parseEventPageLimit(searchParams.get('tail'), 'tail') };
  }
  if (hasBefore) {
    return {
      mode: 'before',
      beforeSeq: parsePositiveSequence(searchParams.get('beforeSeq'), 'beforeSeq'),
      limit: parseEventPageLimit(searchParams.get('limit') || '80', 'limit')
    };
  }
  return { mode: 'after', afterSeq: parseNonNegativeSequence(searchParams.get('afterSeq') || '0', 'afterSeq') };
}

function parseEventPageLimit(value, field) {
  const parsed = parsePositiveSequence(value, field);
  return Math.max(1, Math.min(parsed, 200));
}

function parsePositiveSequence(value, field) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1) {
    throw httpError(400, 'invalid_event_page_query', `${field} must be a positive integer.`);
  }
  return parsed;
}

function parseNonNegativeSequence(value, field) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 0) {
    throw httpError(400, 'invalid_event_page_query', `${field} must be a non-negative integer.`);
  }
  return parsed;
}
```

Add this helper near the other local helper functions in `daemon/src/server.js`:

```js
function httpError(status, code, message) {
  const error = new Error(message);
  error.status = status;
  error.code = code;
  return error;
}
```

- [x] **Step 5: Run daemon tests and verify pass**

Run:

```powershell
npm test
```

Expected: PASS.

- [ ] **Step 6: Commit daemon API paging**

```powershell
git add daemon/src/conversation-manager.js daemon/src/server.js scripts/run-tests.js
git commit -m "Expose paged conversation event API" -m "Mobile needs a latest-history window and older-page reads while existing afterSeq replay remains unchanged for live streams." -m "Constraint: Mixed event page modes are rejected so clients cannot accidentally combine replay and history windows." -m "Tested: npm test"
```

---

## Task 3: Add Mobile Event Page Contract

**Files:**
- Modify: `mobile/lib/src/data/models/conversation_models.dart`
- Modify: `mobile/lib/src/domain/repositories/conversation_repository.dart`
- Modify: `mobile/lib/src/data/services/conversation_service.dart`
- Modify: `mobile/lib/src/services/daemon_client.dart`
- Modify: `mobile/lib/src/data/repositories/daemon_conversation_repository.dart`
- Modify: `mobile/lib/src/data/repositories/cached_conversation_repository.dart`
- Modify: mobile test fakes implementing `ConversationRepository`
- Test: `mobile/test/daemon_client_test.dart`
- Test: `mobile/test/daemon_conversation_repository_test.dart`
- Test: `mobile/test/cached_connected_repositories_test.dart`

- [x] **Step 1: Write failing daemon client tests**

In `mobile/test/daemon_client_test.dart`, add tests after `fetchConversationEvents ignores legacy attachment preview fields`.

```dart
  test('fetchConversationEventPage requests tail page and parses metadata',
      () async {
    final requests = <http.BaseRequest>[];
    final client = DaemonClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenStore: MemoryTokenStore(),
      httpClient: FakeHttpClient((request) {
        requests.add(request);
        return jsonResponse(const <String, Object?>{
          'events': <Object?>[
            <String, Object?>{
              'seq': 9,
              'conversationId': 'conv_1',
              'type': 'assistant.message',
              'createdAt': '2026-05-30T00:00:00.000Z',
              'text': 'latest',
            },
          ],
          'page': <String, Object?>{
            'mode': 'tail',
            'oldestSeq': 9,
            'newestSeq': 9,
            'hasMoreBefore': true,
          },
        });
      }),
    );

    final page = await client.fetchConversationEventPage(
      'conv_1',
      limit: 80,
    );

    expect(requests.single.url.path, '/api/conversations/conv_1/events');
    expect(requests.single.url.queryParameters, <String, String>{
      'tail': '80',
    });
    expect(page.events.single.text, 'latest');
    expect(page.oldestSeq, 9);
    expect(page.newestSeq, 9);
    expect(page.hasMoreBefore, isTrue);
  });

  test('fetchConversationEventPage requests older page and falls back without metadata',
      () async {
    final requests = <http.BaseRequest>[];
    final client = DaemonClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenStore: MemoryTokenStore(),
      httpClient: FakeHttpClient((request) {
        requests.add(request);
        return jsonResponse(const <String, Object?>{
          'events': <Object?>[
            <String, Object?>{
              'seq': 7,
              'conversationId': 'conv_1',
              'type': 'assistant.message',
              'createdAt': '2026-05-30T00:00:00.000Z',
              'text': 'older',
            },
          ],
        });
      }),
    );

    final page = await client.fetchConversationEventPage(
      'conv_1',
      beforeSeq: 9,
      limit: 1,
    );

    expect(requests.single.url.queryParameters, <String, String>{
      'beforeSeq': '9',
      'limit': '1',
    });
    expect(page.oldestSeq, 7);
    expect(page.newestSeq, 7);
    expect(page.hasMoreBefore, isTrue);
  });
```

- [x] **Step 2: Run targeted mobile client tests and verify failure**

Run from `mobile/`:

```powershell
flutter test --no-pub test\daemon_client_test.dart --plain-name "fetchConversationEventPage"
```

Expected: FAIL because `fetchConversationEventPage` and `ConversationEventPage` do not exist.

- [x] **Step 3: Add `ConversationEventPage` model**

In `mobile/lib/src/data/models/conversation_models.dart`, add after `ConversationEvent`:

```dart
class ConversationEventPage {
  const ConversationEventPage({
    required this.events,
    required this.oldestSeq,
    required this.newestSeq,
    required this.hasMoreBefore,
  });

  final List<ConversationEvent> events;
  final int? oldestSeq;
  final int? newestSeq;
  final bool hasMoreBefore;

  factory ConversationEventPage.fromJson(
    Map<String, Object?> json, {
    required int limit,
  }) {
    final events = _objectList(json['events'])
        .map(ConversationEvent.fromJson)
        .toList(growable: false);
    final page = _objectMap(json['page']);
    return ConversationEventPage(
      events: events,
      oldestSeq: page['oldestSeq'] as int? ?? _firstSeq(events),
      newestSeq: page['newestSeq'] as int? ?? _lastSeq(events),
      hasMoreBefore: page['hasMoreBefore'] as bool? ??
          (events.isNotEmpty && events.length == limit),
    );
  }
}

int? _firstSeq(List<ConversationEvent> events) =>
    events.isEmpty ? null : events.first.seq;

int? _lastSeq(List<ConversationEvent> events) =>
    events.isEmpty ? null : events.last.seq;
```

- [x] **Step 4: Add repository and service method signatures**

In `mobile/lib/src/domain/repositories/conversation_repository.dart`, add:

```dart
  Future<ConversationEventPage> fetchConversationEventPage(
    String conversationId, {
    int? beforeSeq,
    required int limit,
  });
```

In `mobile/lib/src/data/services/conversation_service.dart`, add the same signature to `ConversationService`.

- [x] **Step 5: Implement client and repository forwarding**

In `mobile/lib/src/services/daemon_client.dart`, add:

```dart
  Future<ConversationEventPage> fetchConversationEventPage(
    String conversationId, {
    int? beforeSeq,
    required int limit,
  }) async {
    final query = beforeSeq == null
        ? <String, String>{'tail': '$limit'}
        : <String, String>{'beforeSeq': '$beforeSeq', 'limit': '$limit'};
    final path = Uri(
      path: '/api/conversations/$conversationId/events',
      queryParameters: query,
    ).toString();
    final response = await _get(path);
    return ConversationEventPage.fromJson(response, limit: limit);
  }
```

In `DaemonConversationRepository` and `CachedConversationRepository`, forward the method to the delegate/client:

```dart
  @override
  Future<ConversationEventPage> fetchConversationEventPage(
    String conversationId, {
    int? beforeSeq,
    required int limit,
  }) =>
      _client.fetchConversationEventPage(
        conversationId,
        beforeSeq: beforeSeq,
        limit: limit,
      );
```

Use `_delegate` instead of `_client` in `CachedConversationRepository`.

- [x] **Step 6: Update test fakes to compile**

For each fake implementing `ConversationRepository`, add the method. For simple fakes:

```dart
  @override
  Future<ConversationEventPage> fetchConversationEventPage(
    String conversationId, {
    int? beforeSeq,
    required int limit,
  }) async {
    final filtered = beforeSeq == null
        ? messages.reversed.take(limit).toList().reversed.toList()
        : messages
            .where((event) => event.seq < beforeSeq)
            .toList()
            .reversed
            .take(limit)
            .toList()
            .reversed
            .toList();
    return ConversationEventPage(
      events: filtered,
      oldestSeq: filtered.isEmpty ? null : filtered.first.seq,
      newestSeq: filtered.isEmpty ? null : filtered.last.seq,
      hasMoreBefore: filtered.isNotEmpty &&
          messages.any((event) => event.seq < filtered.first.seq),
    );
  }
```

For fakes without a `messages` field, return an empty page:

```dart
  @override
  Future<ConversationEventPage> fetchConversationEventPage(
    String conversationId, {
    int? beforeSeq,
    required int limit,
  }) async =>
      const ConversationEventPage(
        events: <ConversationEvent>[],
        oldestSeq: null,
        newestSeq: null,
        hasMoreBefore: false,
      );
```

- [x] **Step 7: Run targeted mobile tests**

Run from `mobile/`:

```powershell
flutter test --no-pub test\daemon_client_test.dart test\daemon_conversation_repository_test.dart --plain-name "fetchConversationEventPage"
```

Expected: PASS. If the name filter selects only daemon client tests, also run:

```powershell
dart run tool\check_architecture_imports.dart
```

Expected: PASS.

- [ ] **Step 8: Commit mobile data contract**

```powershell
git add mobile/lib/src/data/models/conversation_models.dart mobile/lib/src/domain/repositories/conversation_repository.dart mobile/lib/src/data/services/conversation_service.dart mobile/lib/src/services/daemon_client.dart mobile/lib/src/data/repositories/daemon_conversation_repository.dart mobile/lib/src/data/repositories/cached_conversation_repository.dart mobile/test
git commit -m "Add mobile conversation event page contract" -m "Historical transcript loading needs a tail/before page API that is distinct from live afterSeq replay." -m "Constraint: Call sites must pass an explicit page limit so paging behavior is testable." -m "Tested: flutter test --no-pub test\\daemon_client_test.dart test\\daemon_conversation_repository_test.dart --plain-name \"fetchConversationEventPage\"" -m "Tested: dart run tool\\check_architecture_imports.dart"
```

---

## Task 4: Add Workbench ViewModel Historical Window State

**Files:**
- Modify: `mobile/lib/src/ui/features/workbench/view_models/workbench_view_model.dart`
- Test: `mobile/test/coding_workbench_controller_test.dart`

- [x] **Step 1: Write failing ViewModel tests**

In `mobile/test/coding_workbench_controller_test.dart`, add tests near the existing "workbench view model forwards conversation stream operations" test.

```dart
  test('workbench view model applies tail page and tracks historical cursor',
      () async {
    final repository = _FakeConversationRepository(
      eventPage: ConversationEventPage(
        events: <ConversationEvent>[
          _event(seq: 7, type: 'user.message', text: 'tail prompt'),
          _event(seq: 8, type: 'assistant.message', text: 'tail answer'),
        ],
        oldestSeq: 7,
        newestSeq: 8,
        hasMoreBefore: true,
      ),
    );
    final viewModel = _workbenchViewModel(conversationRepository: repository);
    viewModel.openSession(SessionItem(
      run: WorkbenchViewModel.runSummaryFromConversation(_conversation(
        id: 'conv_existing',
        workspaceId: _workspace.id,
        status: 'idle',
      )),
      conversation: _conversation(
        id: 'conv_existing',
        workspaceId: _workspace.id,
        status: 'idle',
      ),
    ));

    final changed = await viewModel.loadInitialConversationEventPage(
      conversationId: 'conv_existing',
      limit: 80,
      streamOutput: false,
    );

    expect(changed, isTrue);
    expect(repository.calls, <String>['page:conv_existing:null:80']);
    expect(viewModel.oldestLoadedConversationSeq, 7);
    expect(viewModel.hasMoreHistoricalConversationEvents, isTrue);
    expect(viewModel.lastSeq, 8);
    expect(viewModel.messages.map((message) => message.body),
        containsAll(<String>['tail prompt', 'tail answer']));
  });

  test('workbench view model dedupes stream overlap with older page', () async {
    final repository = _FakeConversationRepository(
      eventPage: ConversationEventPage(
        events: <ConversationEvent>[
          _event(seq: 1, type: 'user.message', text: 'older prompt'),
          _event(seq: 2, type: 'assistant.message', text: 'streamed answer'),
        ],
        oldestSeq: 1,
        newestSeq: 2,
        hasMoreBefore: false,
      ),
    );
    final viewModel = _workbenchViewModel(conversationRepository: repository);
    viewModel.openSession(SessionItem(
      run: WorkbenchViewModel.runSummaryFromConversation(_conversation(
        id: 'conv_existing',
        workspaceId: _workspace.id,
        status: 'running',
      )),
      conversation: _conversation(
        id: 'conv_existing',
        workspaceId: _workspace.id,
        status: 'running',
      ),
    ));
    viewModel.applyConversationEvents(<ConversationEvent>[
      _event(seq: 2, type: 'assistant.message', text: 'streamed answer'),
    ], streamOutput: true);

    final changed = await viewModel.loadOlderConversationEventPage(
      conversationId: 'conv_existing',
      limit: 80,
      streamOutput: true,
    );

    expect(changed, isTrue);
    expect(viewModel.conversationEvents.map((event) => event.seq),
        <int>[1, 2]);
    expect(viewModel.messages
        .where((message) => message.body == 'streamed answer'), hasLength(1));
  });
```

Update `_FakeConversationRepository` in `mobile/test/coding_workbench_controller_test.dart` so the class starts with:

```dart
class _FakeConversationRepository implements ConversationRepository {
  _FakeConversationRepository({this.eventPage});

  final ConversationEventPage? eventPage;
  final List<String> calls = <String>[];
  final List<ConversationMessageSendRequest> sentRequests =
      <ConversationMessageSendRequest>[];
  final StreamController<ConversationEvent> _events =
      StreamController<ConversationEvent>.broadcast();
```

Keep the existing `emitConversationEvent` method and repository method overrides after those fields.
```

Add a fake method:

```dart
  @override
  Future<ConversationEventPage> fetchConversationEventPage(
    String conversationId, {
    int? beforeSeq,
    required int limit,
  }) async {
    calls.add('page:$conversationId:$beforeSeq:$limit');
    return eventPage ??
        const ConversationEventPage(
          events: <ConversationEvent>[],
          oldestSeq: null,
          newestSeq: null,
          hasMoreBefore: false,
        );
  }
```

- [x] **Step 2: Run ViewModel tests and verify failure**

Run from `mobile/`:

```powershell
flutter test --no-pub test\coding_workbench_controller_test.dart --plain-name "workbench view model"
```

Expected: FAIL because the new ViewModel methods and getters do not exist.

- [x] **Step 3: Add ViewModel state and getters**

In `WorkbenchViewModel`, add fields near `_lastSeq`:

```dart
  int? _oldestLoadedConversationSeq;
  bool _hasMoreHistoricalConversationEvents = false;
  bool _loadingOlderConversationEvents = false;
  Object? _historicalConversationLoadError;
```

Add getters near `lastSeq`:

```dart
  int? get oldestLoadedConversationSeq => _oldestLoadedConversationSeq;
  bool get hasMoreHistoricalConversationEvents =>
      _hasMoreHistoricalConversationEvents;
  bool get loadingOlderConversationEvents => _loadingOlderConversationEvents;
  Object? get historicalConversationLoadError =>
      _historicalConversationLoadError;
```

In `resetConversationDisplay`, clear the new state:

```dart
    _oldestLoadedConversationSeq = null;
    _hasMoreHistoricalConversationEvents = false;
    _loadingOlderConversationEvents = false;
    _historicalConversationLoadError = null;
```

- [x] **Step 4: Add event-window merge helper**

Add private helper methods in `WorkbenchViewModel`:

```dart
  List<ConversationEvent> _mergeConversationEventWindow(
    List<ConversationEvent> incoming,
  ) {
    final bySeq = <int, ConversationEvent>{
      for (final event in _conversationEvents) event.seq: event,
    };
    for (final event in incoming) {
      bySeq.putIfAbsent(event.seq, () => event);
    }
    final merged = bySeq.values.toList(growable: false)
      ..sort((left, right) => left.seq.compareTo(right.seq));
    return merged;
  }

  bool _replaceConversationEventWindow(
    List<ConversationEvent> events, {
    required bool streamOutput,
  }) {
    final sorted = events.toList(growable: false)
      ..sort((left, right) => left.seq.compareTo(right.seq));
    _conversationEvents
      ..clear()
      ..addAll(sorted);
    _lastSeq = sorted.isEmpty ? 0 : sorted.last.seq;
    _conversationState =
        const ConversationViewState().apply(sorted, streamOutput: streamOutput);
    _rebuildMessagesFromConversationState();
    return true;
  }
```

This helper is used only for historical window rebuilds. Keep existing `applyConversationEvents` for live append.

- [x] **Step 5: Add initial tail and older page methods**

Add methods near `fetchConversationEvents`:

```dart
  Future<bool> loadInitialConversationEventPage({
    required String conversationId,
    required int limit,
    required bool streamOutput,
    WorkbenchEventApplicationIsCurrent? isCurrent,
  }) async {
    final stillCurrent = isCurrent ?? () => true;
    if (!stillCurrent()) return false;
    final page = await _requireConversationRepository()
        .fetchConversationEventPage(conversationId, limit: limit);
    if (!stillCurrent()) return false;
    _oldestLoadedConversationSeq = page.oldestSeq;
    _hasMoreHistoricalConversationEvents = page.hasMoreBefore;
    _historicalConversationLoadError = null;
    _replaceConversationEventWindow(page.events, streamOutput: streamOutput);
    _notifyListeners();
    final previewChanged = await _bindAndResolveAttachmentPreviews(
      page.events,
      isCurrent: stillCurrent,
    );
    if (!stillCurrent()) return false;
    if (previewChanged) _rebuildMessagesFromConversationState();
    if (previewChanged) _notifyListeners();
    return page.events.isNotEmpty || previewChanged;
  }

  Future<bool> loadOlderConversationEventPage({
    required String conversationId,
    required int limit,
    required bool streamOutput,
    WorkbenchEventApplicationIsCurrent? isCurrent,
  }) async {
    final beforeSeq = _oldestLoadedConversationSeq;
    if (beforeSeq == null ||
        !_hasMoreHistoricalConversationEvents ||
        _loadingOlderConversationEvents) {
      return false;
    }
    final stillCurrent = isCurrent ?? () => true;
    _loadingOlderConversationEvents = true;
    _historicalConversationLoadError = null;
    _notifyListeners();
    try {
      final page = await _requireConversationRepository()
          .fetchConversationEventPage(
        conversationId,
        beforeSeq: beforeSeq,
        limit: limit,
      );
      if (!stillCurrent()) return false;
      if (page.events.isEmpty) {
        _hasMoreHistoricalConversationEvents = false;
        return false;
      }
      _oldestLoadedConversationSeq = page.oldestSeq;
      _hasMoreHistoricalConversationEvents = page.hasMoreBefore;
      _replaceConversationEventWindow(
        _mergeConversationEventWindow(page.events),
        streamOutput: streamOutput,
      );
      // Release the visible loading state as soon as content is present.
      // Attachment preview binding can continue afterward; a very fast second
      // older-page request during that preview await is acceptable because the
      // ViewModel merge path is sequence-deduped.
      _loadingOlderConversationEvents = false;
      _notifyListeners();
      final previewChanged = await _bindAndResolveAttachmentPreviews(
        page.events,
        isCurrent: stillCurrent,
      );
      if (!stillCurrent()) return false;
      if (previewChanged) _rebuildMessagesFromConversationState();
      if (previewChanged) _notifyListeners();
      return true;
    } catch (error) {
      if (stillCurrent()) _historicalConversationLoadError = error;
      rethrow;
    } finally {
      if (stillCurrent() && _loadingOlderConversationEvents) {
        _loadingOlderConversationEvents = false;
        _notifyListeners();
      }
    }
  }
```

`_bindAndResolveAttachmentPreviews` already lives in `WorkbenchViewModel`; call it directly as shown. `_replaceConversationEventWindow` must run before preview binding so committed events are present while previews resolve.

- [x] **Step 6: Run ViewModel tests and analyzer**

Run from `mobile/`:

```powershell
flutter test --no-pub test\coding_workbench_controller_test.dart --plain-name "workbench view model"
dart run tool\check_architecture_imports.dart
```

Expected: PASS.

- [ ] **Step 7: Commit ViewModel pagination state**

```powershell
git add mobile/lib/src/ui/features/workbench/view_models/workbench_view_model.dart mobile/test/coding_workbench_controller_test.dart
git commit -m "Track paged historical conversation windows" -m "The workbench needs to rebuild visible messages from a bounded historical event window while live stream updates remain append-only." -m "Constraint: ViewModel owns sequence-based merge and de-duplication for overlapping stream and page events." -m "Tested: flutter test --no-pub test\\coding_workbench_controller_test.dart --plain-name \"workbench view model\"" -m "Tested: dart run tool\\check_architecture_imports.dart"
```

---

## Task 5: Wire Workbench UI To Tail Load And Upward Pagination

**Files:**
- Modify: `mobile/lib/src/ui/features/workbench/coding_workbench_page.dart`
- Test: `mobile/test/widget_test.dart`

- [x] **Step 1: Write failing widget tests for tail open and empty tail watch**

In `mobile/test/widget_test.dart`, replace or add tests near the existing historical conversation tests.

Add `dart:collection` at the top of the file:

```dart
import 'dart:collection';
```

Add these helpers near the existing `_workbenchMessageList` helper and conversation repository fakes:

```dart
Widget _pagedWorkbenchHarness({
  required ConversationRepository conversationRepository,
  required List<ConversationSummary> conversations,
}) {
  final dependencies = AppDependencies.createDefault();
  final client = _AdapterRefreshClient();
  final connectedData = dependencies.data.forDaemonClient(client);
  final workbenchDependencies = dependencies.features
      .createWorkbenchDependencies(client, connectedData);
  final testDependencies = AppDependencies(
    network: dependencies.network,
    data: dependencies.data,
    domain: dependencies.domain,
    features: _testFeatureDependencies(
      createDaemonConnectionViewModel:
          dependencies.features.createDaemonConnectionViewModel,
      createDiagnosticsViewModel:
          dependencies.features.createDiagnosticsViewModel,
      createRunDetailViewModel:
          dependencies.features.createRunDetailViewModel,
      createAppUpdateViewModel:
          dependencies.features.createAppUpdateViewModel,
      createWorkbenchDependencies: (_, connectedData) =>
          WorkbenchDependencies(
        adapterRepository: connectedData.cliAdapterRepository,
        asrModelManager: workbenchDependencies.asrModelManager,
        conversationRepository:
            CachedConversationRepository(delegate: conversationRepository),
        diagnosticsRepository: connectedData.diagnosticsRepository,
        runRepository: connectedData.runRepository,
        speechInputServiceBuilder:
            workbenchDependencies.speechInputServiceBuilder,
        workspaceRepository: connectedData.workspaceRepository,
      ),
    ),
  );
  return _MainTabsHarness(
    client: client,
    dependencies: testDependencies,
    snapshot: _testSnapshot(conversations: conversations),
  );
}

ConversationEvent _pagedConversationEvent({
  required int seq,
  required String text,
  String conversationId = 'conv_paged',
  String type = 'assistant.message',
}) =>
    ConversationEvent.fromJson(<String, Object?>{
      'seq': seq,
      'conversationId': conversationId,
      'type': type,
      'createdAt': '2026-05-30T00:00:00.000Z',
      'text': text,
    });
```

Create a repository fake that records page and watch calls:

```dart
class _PagedHistoryConversationRepository extends _LazyConversationRepository {
  _PagedHistoryConversationRepository({
    required this.pages,
    this.streamEvents = const <ConversationEvent>[],
  }) : super(const <ConversationEvent>[]);

  final Queue<ConversationEventPage> pages;
  final List<ConversationEvent> streamEvents;
  final List<String> pageCalls = <String>[];
  final List<int> watchAfterSeqs = <int>[];

  @override
  Future<ConversationEventPage> fetchConversationEventPage(
    String conversationId, {
    int? beforeSeq,
    required int limit,
  }) async {
    pageCalls.add('$conversationId:$beforeSeq:$limit');
    return pages.removeFirst();
  }

  @override
  Stream<ConversationEvent> watchConversationEvents(
    String conversationId, {
    required int afterSeq,
  }) {
    watchAfterSeqs.add(afterSeq);
    return Stream<ConversationEvent>.fromIterable(
      streamEvents.where((event) => event.seq > afterSeq),
    );
  }

  @override
  Future<List<ConversationSummary>> listConversations() async =>
      <ConversationSummary>[
        _conversationSummary(
          id: 'conv_paged',
          workspaceId: 'workspace_1',
          status: 'idle',
          sessionBinding: 'confirmed',
          userMessageCount: 120,
          title: 'Paged history conversation',
        ),
      ];
}
```

Add the tests:

```dart
  testWidgets('opening large historical conversation loads tail page first',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final repository = _PagedHistoryConversationRepository(
      pages: Queue<ConversationEventPage>.from(<ConversationEventPage>[
        ConversationEventPage(
          events: <ConversationEvent>[
            _pagedConversationEvent(seq: 119, text: 'recent prompt'),
            _pagedConversationEvent(seq: 120, text: 'latest sentinel'),
          ],
          oldestSeq: 119,
          newestSeq: 120,
          hasMoreBefore: true,
        ),
      ]),
    );

    await tester.pumpWidget(_pagedWorkbenchHarness(
      conversationRepository: repository,
      conversations: <ConversationSummary>[
        _conversationSummary(
          id: 'conv_paged',
          workspaceId: 'workspace_1',
          status: 'idle',
          sessionBinding: 'confirmed',
          userMessageCount: 120,
          title: 'Paged history conversation',
        ),
      ],
    ));
    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paged history conversation'));
    await tester.pumpAndSettle();

    expect(repository.pageCalls, <String>['conv_paged:null:80']);
    expect(repository.watchAfterSeqs, <int>[120]);
    expect(find.text('latest sentinel'), findsOneWidget);
  });

  testWidgets('empty tail starts conversation watch from zero', (tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final repository = _PagedHistoryConversationRepository(
      pages: Queue<ConversationEventPage>.from(const <ConversationEventPage>[
        ConversationEventPage(
          events: <ConversationEvent>[],
          oldestSeq: null,
          newestSeq: null,
          hasMoreBefore: false,
        ),
      ]),
    );

    await tester.pumpWidget(_pagedWorkbenchHarness(
      conversationRepository: repository,
      conversations: <ConversationSummary>[
        _conversationSummary(
          id: 'conv_paged',
          workspaceId: 'workspace_1',
          status: 'idle',
          sessionBinding: 'confirmed',
          userMessageCount: 1,
          title: 'Paged history conversation',
        ),
      ],
    ));
    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paged history conversation'));
    await tester.pumpAndSettle();

    expect(repository.pageCalls, <String>['conv_paged:null:80']);
    expect(repository.watchAfterSeqs, <int>[0]);
  });
```

Use `_pagedWorkbenchHarness` and `_pagedConversationEvent` in the new tests; do not reuse the preview-only helpers.

- [x] **Step 2: Run widget tests and verify failure**

Run from `mobile/`:

```powershell
flutter test --no-pub test\widget_test.dart --plain-name "historical conversation"
```

Expected: FAIL because `_openSession` still calls `fetchConversationEvents(afterSeq: 0)` and not the page method.

- [x] **Step 3: Replace initial stored-event load with tail page load**

In `CodingWorkbenchPage`, add a page size constant near existing constants:

```dart
  static const int _conversationHistoryPageSize = 80;
```

Replace `_loadStoredConversationEvents` with `_loadInitialConversationEventPage`:

```dart
  Future<void> _loadInitialConversationEventPage({
    required String conversationId,
    required String runId,
    required int generation,
    required bool streamOutput,
  }) async {
    await _workbenchViewModel.loadInitialConversationEventPage(
      conversationId: conversationId,
      limit: _conversationHistoryPageSize,
      streamOutput: streamOutput,
      isCurrent: () => _isCurrentConversationEventTarget(
        conversationId: conversationId,
        runId: runId,
        generation: generation,
      ),
    );
  }
```

In `_openSession`, call `_loadInitialConversationEventPage` instead of `_loadStoredConversationEvents`. Keep the existing generation and error tracing.

- [x] **Step 4: Add older-edge scroll trigger with post-frame correction**

Wrap the transcript list in a `NotificationListener<ScrollNotification>` where `_buildMessageList` is used, or attach detection inside `_buildMessageList` if that is cleaner.

Add helper methods to `CodingWorkbenchPage`:

```dart
  bool _isNearOlderTranscriptEdge() {
    if (!_scrollController.hasClients) return false;
    final position = _scrollController.position;
    if (_useReverseTranscript) {
      return position.pixels >= position.maxScrollExtent - 160;
    }
    return position.pixels <= position.minScrollExtent + 160;
  }

  void _maybeLoadOlderConversationEvents() {
    final conversationId = _activeConversationId;
    final runId = _activeRunId;
    if (conversationId == null || runId == null) return;
    if (!_isNearOlderTranscriptEdge()) return;
    if (!_workbenchViewModel.hasMoreHistoricalConversationEvents ||
        _workbenchViewModel.loadingOlderConversationEvents) {
      return;
    }
    unawaited(_loadOlderConversationEvents(
      conversationId: conversationId,
      runId: runId,
      generation: _conversationEventSubscriptionGeneration,
    ));
  }

  Future<void> _loadOlderConversationEvents({
    required String conversationId,
    required String runId,
    required int generation,
  }) async {
    if (!_scrollController.hasClients) return;
    // This preserves the user's viewport for the older-page prepend. Live
    // WebSocket events arriving during the await can also change extent; the
    // correction intentionally favors keeping the older-page anchor stable.
    final oldOffset = _scrollController.offset;
    final oldMaxExtent = _scrollController.position.maxScrollExtent;
    try {
      final changed = await _workbenchViewModel.loadOlderConversationEventPage(
        conversationId: conversationId,
        limit: _conversationHistoryPageSize,
        streamOutput: widget.streamOutput,
        isCurrent: () => _isCurrentConversationEventTarget(
          conversationId: conversationId,
          runId: runId,
          generation: generation,
        ),
      );
      if (!changed || !mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !_scrollController.hasClients ||
            !_isCurrentConversationEventTarget(
              conversationId: conversationId,
              runId: runId,
              generation: generation,
            )) {
          return;
        }
        final newMaxExtent = _scrollController.position.maxScrollExtent;
        final target = oldOffset + (newMaxExtent - oldMaxExtent);
        _scrollController.jumpTo(
          target.clamp(
            _scrollController.position.minScrollExtent,
            _scrollController.position.maxScrollExtent,
          ),
        );
      });
    } catch (error, stack) {
      await _recordWorkbenchException(
        error,
        stack,
        operation: 'loadOlderConversationEvents',
        path: '/api/conversations/$conversationId/events',
      );
    }
  }
```

Wire the scroll notification:

```dart
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.axis == Axis.vertical) {
          _maybeLoadOlderConversationEvents();
        }
        return false;
      },
      child: ListView.builder(
        key: ValueKey(
          'workbench-message-list-${useReverseTranscript ? 'reverse' : 'normal'}',
        ),
        controller: _scrollController,
        reverse: useReverseTranscript,
        ...
      ),
    );
```

- [x] **Step 5: Add widget tests for older page loading and duplicate guard**

Add tests:

```dart
  testWidgets('scrolling to older edge loads previous conversation page once',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final repository = _PagedHistoryConversationRepository(
      pages: Queue<ConversationEventPage>.from(<ConversationEventPage>[
        ConversationEventPage(
          events: List<ConversationEvent>.generate(
            40,
            (index) => _pagedConversationEvent(
              seq: index + 81,
              text: index == 39 ? 'latest sentinel' : 'recent $index',
            ),
          ),
          oldestSeq: 81,
          newestSeq: 120,
          hasMoreBefore: true,
        ),
        ConversationEventPage(
          events: <ConversationEvent>[
            _pagedConversationEvent(seq: 79, text: 'older prompt'),
            _pagedConversationEvent(seq: 80, text: 'older answer'),
          ],
          oldestSeq: 79,
          newestSeq: 80,
          hasMoreBefore: false,
        ),
      ]),
    );

    await tester.pumpWidget(_pagedWorkbenchHarness(
      conversationRepository: repository,
      conversations: <ConversationSummary>[
        _conversationSummary(
          id: 'conv_paged',
          workspaceId: 'workspace_1',
          status: 'idle',
          sessionBinding: 'confirmed',
          userMessageCount: 120,
          title: 'Paged history conversation',
        ),
      ],
    ));
    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paged history conversation'));
    await tester.pumpAndSettle();

    await tester.drag(_workbenchMessageList(), const Offset(0, -900));
    await tester.pump();
    await tester.drag(_workbenchMessageList(), const Offset(0, -900));
    await tester.pumpAndSettle();

    expect(repository.pageCalls.where((call) => call == 'conv_paged:81:80'),
        hasLength(1));
    expect(find.text('older prompt'), findsOneWidget);
    expect(find.text('latest sentinel'), findsOneWidget);
  });
```

Use `Offset(0, -900)` as shown. The workbench reverse transcript starts at the newest edge and negative vertical drags move toward older messages in this test harness.

- [x] **Step 6: Add navigation-away stale result test**

Adapt the existing hanging fetch test so it uses `fetchConversationEventPage`:

```dart
class _HangingPageConversationRepository extends _LazyConversationRepository {
  _HangingPageConversationRepository() : super(const <ConversationEvent>[]);

  final fetchCompleter = Completer<ConversationEventPage>();
  bool pageFetchStarted = false;

  @override
  Future<ConversationEventPage> fetchConversationEventPage(
    String conversationId, {
    int? beforeSeq,
    required int limit,
  }) {
    pageFetchStarted = true;
    return fetchCompleter.future;
  }

  @override
  Stream<ConversationEvent> watchConversationEvents(
    String conversationId, {
    required int afterSeq,
  }) =>
      const Stream<ConversationEvent>.empty();

  @override
  Future<List<ConversationSummary>> listConversations() async =>
      <ConversationSummary>[
        _conversationSummary(
          id: 'conv_slow_history',
          workspaceId: 'workspace_1',
          status: 'idle',
          sessionBinding: 'confirmed',
          userMessageCount: 1,
          title: 'Slow history conversation',
        ),
      ];
}
```

Test:

```dart
  testWidgets('leaving conversation before tail returns discards stale page',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final repository = _HangingPageConversationRepository();

    await tester.pumpWidget(_pagedWorkbenchHarness(
      conversationRepository: repository,
      conversations: <ConversationSummary>[
        _conversationSummary(
          id: 'conv_slow_history',
          workspaceId: 'workspace_1',
          status: 'idle',
          sessionBinding: 'confirmed',
          userMessageCount: 1,
          title: 'Slow history conversation',
        ),
      ],
    ));
    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Slow history conversation'));
    await tester.pump();
    expect(repository.pageFetchStarted, isTrue);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    repository.fetchCompleter.complete(ConversationEventPage(
      events: <ConversationEvent>[
        _pagedConversationEvent(
          seq: 1,
          conversationId: 'conv_slow_history',
          text: 'stale history',
        ),
      ],
      oldestSeq: 1,
      newestSeq: 1,
      hasMoreBefore: false,
    ));
    await tester.pumpAndSettle();

    expect(find.text('stale history'), findsNothing);
    expect(find.text('Slow history conversation'), findsOneWidget);
  });
```

The English test locale exposes the `Back` tooltip for this route; keep the stale-result assertions unchanged.

- [x] **Step 7: Run widget tests**

Run from `mobile/`:

```powershell
flutter test --no-pub test\widget_test.dart --plain-name "historical conversation"
flutter test --no-pub test\widget_test.dart --plain-name "tail"
```

Expected: PASS.

- [ ] **Step 8: Commit UI pagination wiring**

```powershell
git add mobile/lib/src/ui/features/workbench/coding_workbench_page.dart mobile/test/widget_test.dart
git commit -m "Load historical conversations from latest event pages" -m "Opening a stored workbench conversation should show recent transcript content quickly and fetch older messages only when the user scrolls upward." -m "Constraint: Initial tail loads and older-page loads use generation checks so stale pages cannot mutate another route." -m "Tested: flutter test --no-pub test\\widget_test.dart --plain-name \"historical conversation\"" -m "Tested: flutter test --no-pub test\\widget_test.dart --plain-name \"tail\""
```

---

## Task 6: Run Full Verification And Update Durable Knowledge

**Files:**
- Modify: `docs/project-knowledge/troubleshooting-playbook.md` only if a durable lesson is found.
- Modify: `docs/project-knowledge/build-and-test.md` only if verification commands or environment rules changed.

- [x] **Step 1: Run daemon regression suite**

Run from repo root:

```powershell
npm test
npm run lint
node scripts/check-project-knowledge.js
git diff --check
```

Expected: all PASS.

- [x] **Step 2: Run mobile architecture and targeted tests**

Run from `mobile/`:

```powershell
flutter test --no-pub test\daemon_client_test.dart test\daemon_conversation_repository_test.dart test\coding_workbench_controller_test.dart test\widget_test.dart --plain-name "conversation"
dart run tool\check_architecture_imports.dart
```

Expected: all PASS. If the broad `--plain-name "conversation"` filter misses a newly added test, run the exact test name shown in the test file.

- [x] **Step 3: Run broader mobile checks if targeted tests pass**

Run from `mobile/`:

```powershell
flutter test --no-pub test\daemon_client_test.dart test\coding_workbench_controller_test.dart test\widget_test.dart
```

Expected: PASS. If this command times out once, stop automatic retries and record the exact command in the final report.

- [x] **Step 4: Audit conversation metadata sources**

Inspect `mobile/lib/src/ui/features/workbench/view_models/workbench_view_model.dart` and `mobile/lib/src/ui/features/workbench/coding_workbench_page.dart`.

Confirm:

```text
Conversation title, status, blocking item, composer gating, and status badge inputs come from ConversationSummary or explicit ViewModel fields.
The partial event window is used for transcript messages, command/task cards, and pending timer anchors only.
```

If a field still derives conversation-level truth only from the partial event window, either fix it in the smallest local change or record it as a remaining risk in the final report.

- [x] **Step 5: Decide whether project knowledge needs an update**

Update `docs/project-knowledge/troubleshooting-playbook.md` only if implementation reveals a durable lesson. If needed, append:

```markdown
## Symptom: Historical Conversation Opens Empty Or Slowly

- Symptom: Opening a conversation with many persisted events enters the detail route but shows an empty transcript while history loads.
- Action: Use the conversation event page API. Initial open should fetch `tail=<limit>` and older scroll should fetch `beforeSeq=<oldestLoadedConversationSeq>&limit=<limit>`. Keep live WebSocket replay on `afterSeq=<lastSeq>`.
- Verification:

```powershell
npm test
cd mobile
flutter test --no-pub test\widget_test.dart --plain-name "historical conversation"
```

- Last verified: 2026-05-30
```

Do not add the entry if the tests and code already make the lesson obvious and no new operational debugging pattern was discovered.

- [x] **Step 6: Commit verification knowledge only if changed**

If project knowledge changed:

```powershell
git add docs/project-knowledge/troubleshooting-playbook.md
git commit -m "Document historical conversation paging recovery" -m "The pagination fix creates a durable troubleshooting path for conversations that open empty while full history replay is still loading." -m "Tested: node scripts/check-project-knowledge.js" -m "Tested: npm test"
```

If no project knowledge changed, do not create a documentation-only commit.

- [x] **Step 7: Final implementation report**

Report:

```text
Changed files:
- daemon/src/app-sqlite-store.js
- daemon/src/conversation-event-store.js
- daemon/src/conversation-manager.js
- daemon/src/server.js
- scripts/run-tests.js
- mobile/lib/src/data/models/conversation_models.dart
- mobile/lib/src/domain/repositories/conversation_repository.dart
- mobile/lib/src/data/services/conversation_service.dart
- mobile/lib/src/services/daemon_client.dart
- mobile/lib/src/data/repositories/daemon_conversation_repository.dart
- mobile/lib/src/data/repositories/cached_conversation_repository.dart
- mobile/lib/src/ui/features/workbench/view_models/workbench_view_model.dart
- mobile/lib/src/ui/features/workbench/coding_workbench_page.dart
- mobile/test/daemon_client_test.dart
- mobile/test/daemon_conversation_repository_test.dart
- mobile/test/coding_workbench_controller_test.dart
- mobile/test/widget_test.dart

Simplifications made:
- Live replay stays on afterSeq.
- Historical paging has a separate tail/before contract.
- ViewModel owns all page/stream event-window dedupe.

Verification:
- list exact commands and PASS/timeout status.

Remaining risks:
- note any timed-out Flutter command or metadata-source audit finding.
- note if live WebSocket events arriving during older-page loads cause a small
  scroll correction offset; the implementation deliberately favors preserving
  the older-page anchor over perfect isolation from concurrent live appends.
- note if rapid repeated older-edge scrolling during attachment preview binding
  starts the next older-page request before the previous preview pass finishes;
  this is acceptable only while event-window merging and preview binding remain
  idempotent for overlapping events.
```
