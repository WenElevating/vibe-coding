# Conversation History Pagination Design

Date: 2026-05-30

## Problem

Large historical conversations can now open the workbench detail route before
stored events finish loading, but the transcript can look empty while mobile
waits for a full `afterSeq=0` replay. The previous change fixed the route
navigation stall, but the data path still loads every persisted event, parses
the whole response, and rebuilds the conversation view from the full event
stream before the user sees useful content.

The desired behavior is:

```text
Open an existing conversation quickly.
Show the latest messages first.
Load older messages only when the user scrolls upward.
Keep live WebSocket events working from the newest loaded sequence.
```

## Current Constraints

- Daemon exposes `GET /api/conversations/:id/events?afterSeq=n`.
- `afterSeq` means forward replay and is used by existing mobile code and the
  notification backfill model.
- SQLite currently returns all rows matching `conversation_id` and `seq > ?`,
  ordered ascending.
- Mobile `ConversationRepository.fetchConversationEvents` only models
  forward replay.
- `CodingWorkbenchPage` already renders the transcript with
  `ListView.builder`, and historical conversations use reverse rendering for
  bottom anchoring.
- `WorkbenchViewModel` stores a single ordered event list plus reducer-derived
  message state.

## Goals

- Load the latest historical transcript window on first open instead of the
  full event history.
- Support upward pagination for older conversation events.
- Preserve `afterSeq` semantics for live event replay and reconnect repair.
- Keep daemon event ordering stable: API responses always return ascending
  `seq` order.
- Keep changes inside existing ownership boundaries.
- Avoid new dependencies.

## Non-Goals

- Full transcript search.
- Jump-to-message or arbitrary date/sequence navigation.
- Rewriting the conversation reducer into a general virtual data source.
- Paginating legacy run detail events.
- Changing WebSocket subscription protocol.

## API Design

`GET /api/conversations/:id/events` gains two historical paging modes while
keeping the current default replay behavior.

### Forward Replay

```text
GET /api/conversations/:id/events?afterSeq=120
```

This remains the existing mode. It returns all events with `seq > afterSeq` in
ascending order. Existing clients remain compatible.

### Initial Tail Window

```text
GET /api/conversations/:id/events?tail=80
```

Returns the latest 80 events for the conversation. The daemon may query SQLite
in descending order for efficiency, but the HTTP response must be ascending by
`seq`.

### Older Page

```text
GET /api/conversations/:id/events?beforeSeq=420&limit=80
```

Returns up to 80 events with `seq < 420`, choosing the newest matching rows and
returning them ascending by `seq`.

### Query Rules

- Only one historical mode is active per request:
  - `tail`
  - `beforeSeq`
  - existing `afterSeq`
- If no query is provided, preserve current behavior as `afterSeq=0`.
- If incompatible mode parameters are combined, return `400` with a stable
  error code such as `invalid_event_page_query`.
- Clamp `tail` and `limit` to a daemon-owned range, recommended `1..200`.
- Default historical page size is 80. Mobile should normally pass the explicit
  page size for both `tail` and `beforeSeq` requests so behavior is visible in
  tests. The daemon default exists for manual callers and defensive API
  compatibility.
- Treat invalid sequence values as `400`, not as silent `0`.

### Response Shape

Existing clients read only `events`, so the response can add page metadata
without breaking compatibility:

```json
{
  "events": [],
  "page": {
    "mode": "tail",
    "oldestSeq": 341,
    "newestSeq": 420,
    "hasMoreBefore": true
  }
}
```

For forward replay, `page` can be omitted or use `mode: "after"`. Mobile's new
history pagination path should use the metadata when present.

## Daemon Design

Add explicit event-store methods instead of overloading the existing
`list(conversationId, afterSeq)` method:

```text
listAfter(conversationId, afterSeq)
listTail(conversationId, limit)
listBefore(conversationId, beforeSeq, limit)
```

`list` can remain as a compatibility alias for `listAfter`.

SQLite implementation:

```sql
-- tail
SELECT ...
FROM conversation_events
WHERE conversation_id = ?
ORDER BY seq DESC
LIMIT ?

-- before
SELECT ...
FROM conversation_events
WHERE conversation_id = ? AND seq < ?
ORDER BY seq DESC
LIMIT ?
```

`hasMoreBefore` must not assume contiguous sequence numbers. Event deletion,
cleanup, migration, or test fixtures can create sequence gaps, so the store
must compute the value with an existence check:

```sql
SELECT EXISTS (
  SELECT 1
  FROM conversation_events
  WHERE conversation_id = ? AND seq < ?
)
```

The additional lookup is cheap on the `(conversation_id, seq)` primary key and
keeps pagination semantics correct even when the event stream has gaps.

The store must reverse descending query results before deserializing them. This
keeps deserialization and caller-facing tests on one invariant: event rows are
processed in ascending `seq` order.

## Mobile Data Contract

Keep existing methods for live replay:

```dart
fetchConversationEvents(conversationId, afterSeq: n)
watchConversationEvents(conversationId, afterSeq: n)
```

Add a separate historical page method so call sites cannot confuse replay with
windowed history:

```dart
Future<ConversationEventPage> fetchConversationEventPage(
  String conversationId, {
  int? beforeSeq,
  required int limit,
});
```

When `beforeSeq` is null, the data implementation calls `tail=<limit>`. When
`beforeSeq` is provided, it calls `beforeSeq=<beforeSeq>&limit=<limit>`.

`ConversationEventPage` belongs with conversation protocol models and contains:

```text
events
oldestSeq
newestSeq
hasMoreBefore
```

The daemon client parses the new `page` object. For compatibility with older
daemons, if `page` is missing it derives `oldestSeq` and `newestSeq` from the
events and uses `events.length == limit` as a conservative `hasMoreBefore`
fallback. That fallback can cause one extra older-page request when the older
daemon returns exactly `limit` events but has no more history. The UI should
treat an empty older-page result as end-of-history and clear the loading state
without surfacing a noisy error.

## Workbench State Design

`WorkbenchViewModel` keeps logical event order but adds pagination state:

```text
oldestLoadedConversationSeq: int?
hasMoreHistoricalConversationEvents: bool
loadingOlderConversationEvents: bool
historicalConversationLoadError: Object?
```

`oldestLoadedConversationSeq = null` means no historical event page has been
loaded for the active conversation. It must not use `0`; `0` is reserved for
the live replay cursor fallback when an empty tail page starts WebSocket watch
with `afterSeq=0`.

Opening a historical conversation:

1. Clear previous active conversation display.
2. Enter the conversation route immediately.
3. Capture a conversation-load generation/current-target token before starting
   the tail request. The initial tail request and older-page requests must use
   the same stale-result discard rule.
4. Fetch the tail page.
5. Apply the page events only if the generation/current-target token is still
   current.
6. If the tail page has events, set `oldestLoadedConversationSeq`,
   `hasMoreHistoricalConversationEvents`, and `_lastSeq` from the loaded page.
7. If the tail page is empty, leave `oldestLoadedConversationSeq = null`, set
   `hasMoreHistoricalConversationEvents = false`, and keep `_lastSeq = 0`.
8. Start WebSocket watch with `afterSeq = _lastSeq`.

Loading older events:

1. Ignore the request if there is no active conversation, no loaded
   `oldestLoadedConversationSeq`, no older history, or an older-page request is
   already active.
2. Fetch `beforeSeq = oldestLoadedConversationSeq`.
3. Merge the returned events into the ViewModel's ordered event window by
   `seq`.
4. Rebuild the visible conversation state from the combined loaded window.
5. Update `oldestLoadedConversationSeq` and `hasMoreHistoricalConversationEvents`.

This design still rebuilds the visible state from the loaded window. It does
not require the reducer to understand partial historical insertion internally.

The ViewModel is the single owner of event-window merging and de-duplication.
Repositories and services return events as received from the daemon; they do
not silently drop duplicates. The ViewModel merge rule is:

```text
combined = existingEvents + incomingEvents
dedupe by seq, preferring the existing event when seq already exists
sort by seq ASC
```

This handles WebSocket races while an older page is in flight. For example, if
the stream delivers `seq=425` and the older-page response later returns
`seq=421..425`, the final window contains one copy of `425` and remains
ascending.

## Scroll Behavior

`CodingWorkbenchPage` already owns scroll behavior, so pagination triggers stay
in the widget.

For reverse historical transcript rendering, older messages are visually near
the top of the conversation. The widget should watch scroll position and call
the ViewModel when the user approaches the older edge.

Implementation guidance:

- Use the existing `ScrollController`.
- Trigger older-page loading near the older edge, not only at the exact edge.
- Preserve scroll position after prepending old events with an explicit
  post-frame correction. Capture the current offset and `maxScrollExtent`
  before applying the page, wait for the rebuild with
  `WidgetsBinding.instance.addPostFrameCallback`, then jump to
  `oldOffset + (newMaxScrollExtent - oldMaxScrollExtent)` if the controller is
  still attached and the route is still current.
- Do not auto-scroll to bottom after older-page loads.
- Continue auto-following live events only when the user is already near the
  newest edge.

## Error Handling

- Initial tail load failure should keep the user on the conversation detail
  route and surface the existing operation error UI.
- Older-page failure should leave the already loaded transcript visible and
  expose a retry affordance or inline status near the older edge.
- WebSocket failures keep using the current diagnostics path and reconnect
  strategy.
- If a new event arrives while an older page is loading, keep it. The ViewModel
  sequence merge is responsible for de-duplicating races between stream events
  and older-page responses.
- If the user navigates away during any page load, including the initial tail
  request, discard the result using the shared generation/current-target check.

## Testing Plan

Daemon tests:

- `tail` returns the newest N events in ascending sequence order.
- `beforeSeq + limit` returns the previous page in ascending sequence order.
- `hasMoreBefore` uses an `EXISTS` lookup and remains correct when sequence
  numbers have gaps.
- `afterSeq` behavior remains unchanged.
- Invalid mixed query modes return `400`.

Mobile client/repository tests:

- Tail page calls `tail=<limit>` and parses metadata.
- Older page calls `beforeSeq=<seq>&limit=<limit>`.
- Missing page metadata falls back safely for older daemon compatibility.

Workbench tests:

- Opening a large historical conversation requests a tail page, not
  `afterSeq=0`, and renders the latest sentinel.
- Opening a conversation whose tail page is empty starts WebSocket watch with
  `afterSeq=0`.
- WebSocket watch starts from the newest loaded event sequence.
- Scrolling to the older edge requests `beforeSeq=oldestLoadedSeq`.
- Rapid repeated older-edge scrolls while a page is already loading trigger only
  one older-page request.
- A WebSocket event that arrives while an older page is in flight is retained
  and not duplicated when the older response overlaps its sequence.
- Older-page events become visible without losing newer loaded messages.
- Older-page prepends preserve visible content after the required post-frame
  scroll correction.
- Older-page load failure keeps the loaded transcript visible.
- Navigating away while the initial tail load is in flight discards the result
  and does not mutate the next route's transcript.
- The historical page contract requires an explicit `limit` at every mobile
  call site.

Verification commands:

```powershell
node scripts/run-tests.js
cd mobile
flutter test --no-pub test\daemon_client_test.dart test\coding_workbench_controller_test.dart test\widget_test.dart --plain-name "conversation"
dart run tool\check_architecture_imports.dart
```

## Risks

- The reducer currently assumes ordered input and derives conversation state
  from event order. Rebuilding from a loaded window is safer than trying to
  mutate reducer state with prepended events, but very old omitted events may
  contain status transitions that are no longer represented. The active status
  should continue to come from the current `ConversationSummary` plus loaded
  recent events. Implementation should audit all conversation-level metadata
  used by the transcript header, composer gating, blocking prompts, title, and
  status badges; those fields should come from `ConversationSummary` or another
  daemon-owned summary source, not from assumptions reconstructed from a partial
  event window.
- Scroll offset preservation can be sensitive with variable-height cards.
  Implementation must use a post-frame correction after the prepended page is
  laid out. Tests should assert content continuity and stable route state rather
  than exact pixel offsets.
- Older daemon compatibility is only useful if mobile can still parse the old
  `events` response. True pagination requires a daemon with the new API.

## Accepted Approach

Use the split design:

```text
Historical windows: tail / beforeSeq
Live replay: afterSeq / WebSocket
```

This directly fixes the empty/slow historical open path while preserving the
current real-time event model and keeping the scope below a full transcript
state rewrite.
