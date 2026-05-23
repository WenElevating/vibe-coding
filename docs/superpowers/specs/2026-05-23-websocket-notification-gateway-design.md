# WebSocket Notification Gateway Design

Date: 2026-05-23

## Problem

Workbench conversation events currently reach the mobile client through repeated
HTTP polling:

```text
GET /api/conversations/:conversationId/events?afterSeq=:lastSeq
```

The daemon already persists conversation events with monotonically increasing
`seq` values. The event log is not the weak part of the system. The weak part is
the page-owned polling loop in the Flutter workbench. A foreground page timer
can stop, overlap, or make a stale lifecycle decision while the daemon continues
to append valid events. When that happens, the transcript appears stuck until
the user reopens the conversation and the mobile client replays from storage.

The replacement should not be another short-interval fetch loop. It should make
the daemon responsible for notifying connected clients when new events are
available, while preserving the existing persisted event log as the recovery
source.

## Research Summary

Large realtime products use a persistent event channel plus cursor recovery:

- Discord Gateway uses WebSocket connections with heartbeats, sequence numbers,
  and resume semantics. The socket is low-latency transport; the sequence is the
  reliability boundary.
- Slack Socket Mode delivers event envelopes over WebSocket and uses explicit
  acknowledgements so the platform can observe event handling.
- SignalR abstracts realtime delivery into hubs, connections, groups, and
  client-targeted messages. It prefers WebSockets and can fall back to other
  transports when needed.
- Classic WebSocket APIs do not provide automatic application-level
  backpressure. Servers must bound queued bytes/messages and close slow
  connections so clients can reconnect and replay from a cursor.

The useful common pattern for this project is:

```text
single realtime connection
topic subscription
heartbeat
bounded delivery queue
monotonic cursor
reconnect from last processed cursor
durable REST backfill remains available
```

## Accepted Direction

Build a daemon WebSocket notification gateway.

The first subscribed topic is conversation event delivery for the workbench:

```text
conversation.events
```

The gateway protocol must be topic-based from the beginning so future work can
add topics without replacing the transport:

```text
conversation.summary.changed
workspace.list.changed
adapter.status.changed
diagnostics.event
run.events
```

The implementation should not create one WebSocket per conversation. The mobile
app should keep one WebSocket per connected daemon session, then subscribe and
unsubscribe topics as the active UI changes.

REST event fetch remains part of the design:

```text
GET /api/conversations/:conversationId/events?afterSeq=:seq
```

It becomes the durable backfill and fallback path, not the foreground realtime
transport.

## Non-Goals

The first implementation does not need:

- APNs, FCM, or cross-network background push notifications.
- A cloud relay service.
- Delivery guarantees based on server-side deletion after client ack.
- WebSocket command execution or message sending. Existing HTTP POST endpoints
  remain the write path for send, approval, answer, cancel, and model updates.
- Replacement of legacy `/api/runs/:runId/events` behavior unless a future run
  topic is explicitly scoped.

## Daemon Architecture

Add a `NotificationHub` beside the existing HTTP server.

Suggested files:

```text
daemon/src/notification-hub.js
daemon/src/notification-protocol.js
```

The daemon currently creates a Node `http.Server` in `daemon/src/server.js`.
The gateway should attach to the same server through the HTTP `upgrade` event
and accept only:

```text
GET /api/notifications/ws
```

The server should use the existing bearer token model:

```text
Authorization: Bearer <access-token>
```

Authentication is performed during upgrade with `auth.authenticate()`. If the
token is missing or invalid, the upgrade is rejected before a WebSocket session
is established.

The hub owns:

- connection registry;
- authenticated device identity for each connection;
- connection auth expiration;
- topic subscription registry;
- heartbeat timers;
- bounded send queues and backpressure decisions;
- protocol validation and error frames.

`ConversationEventStore.append()` remains the single append point for
conversation events. After an event is persisted, the store or manager notifies
`NotificationHub`, which fans the event out to subscribers of
`conversation.events` for that conversation.

Ordering is important:

```text
persist event
publish notification
```

This guarantees that if the socket drops immediately after a notification, the
client can reconnect with its last processed `seq` and replay the same event
from storage.

Authorization is layered:

```text
connection authentication
topic authorization
event delivery authorization
```

The upgrade authenticates the bearer token and establishes device identity.
Each subscribe authorizes the requested topic and scope for that device. Before
fan-out, the hub must also confirm the subscription is still authorized for the
scoped resource. If access has been revoked, the hub sends `FORBIDDEN` for that
subscription and removes it.

## WebSocket Protocol

All application frames are JSON objects with a `type` field.

Topic-specific identifiers live under a `scope` object. The first topic uses:

```json
{
  "topic": "conversation.events",
  "scope": {
    "conversationId": "conv_32b58034"
  }
}
```

Future topics should keep the same frame shape and define their own scope keys,
for example `workspaceId` or `adapterId`. A topic with no narrower scope may use
an empty object:

```json
{
  "topic": "workspace.list.changed",
  "scope": {}
}
```

`afterSeq` is a cursor within a `topic + scope` sequence space, not a global
daemon sequence. For `conversation.events`, the cursor is the existing
per-conversation event `seq`.

### Server Hello

After accepting the connection, the server sends:

```json
{
  "type": "hello",
  "connectionId": "ws_4f15d3",
  "protocolVersion": 1,
  "heartbeatIntervalMs": 25000,
  "authExpiresAt": "2026-05-30T05:18:14.000Z",
  "daemonVersion": "1.3.0",
  "capabilities": {
    "topics": [
      "conversation.events"
    ],
    "maxReplayEvents": 1000
  }
}
```

### Subscribe

The client subscribes to a conversation event stream:

```json
{
  "type": "subscribe",
  "id": "req_1",
  "topic": "conversation.events",
  "scope": {
    "conversationId": "conv_32b58034"
  },
  "afterSeq": 241
}
```

The server validates:

- known topic;
- JSON shape;
- valid scope for that topic;
- authenticated device can access the scoped resource;
- `afterSeq` is a non-negative integer.

The server replies:

```json
{
  "type": "subscribed",
  "id": "req_1",
  "topic": "conversation.events",
  "scope": {
    "conversationId": "conv_32b58034"
  },
  "afterSeq": 241
}
```

Before forwarding live events, the server sends all persisted conversation
events with `seq > afterSeq`. The same event frame is used for replayed and live
events.

Subscription identity is `connectionId + topic + canonical scope`. If a client
sends a second subscribe for the same topic and scope on the same connection,
the newer subscribe replaces the earlier one and uses the newer `afterSeq`.
The server must not keep duplicate subscriptions that would deliver the same
event twice on the same connection. Any in-flight replay from the replaced
subscription must be cancelled or guarded by a subscription generation id so it
cannot keep sending stale replay frames after replacement.

The generation id should be a simple per-connection monotonically increasing
integer stored on the subscription record. Each subscribe replacement increments
the connection counter and writes the new value to the record. Replay workers
capture the generation id at start and compare it with the current subscription
record before sending each dequeued replay batch; a mismatch stops that replay.

### Replay Ordering

The subscribe path must preserve this invariant:

```text
No event with seq > afterSeq may be lost between replay and live delivery.
```

To satisfy it, the daemon must register the subscription before querying
persisted replay events. While replay is active, live appends for the same
`topic + scope` must be queued on that subscription instead of being delivered
ahead of replay. After replay finishes, the daemon flushes queued live events in
ascending `seq` order, dropping duplicates already sent by replay.

The acceptable result is duplicate events. The unacceptable result is a missing
sequence. Mobile reducers already ignore events with `seq <= lastSeq`.

Replay must also be bounded. A first implementation should use these defaults:

```text
maxReplayEvents: 1000
replayBatchSize: 100
```

If more than `maxReplayEvents` would be replayed, the daemon sends an error with
code `REPLAY_TRUNCATED`, removes that subscription, and leaves the client to use
REST backfill before subscribing again with a newer `afterSeq`.

Replay batches for one subscription must not monopolize the whole connection.
The daemon should yield between batches so other topics on the same WebSocket can
deliver live events. Per `topic + scope`, event delivery still remains ordered
by `seq`.

### Event

```json
{
  "type": "event",
  "topic": "conversation.events",
  "scope": {
    "conversationId": "conv_32b58034"
  },
  "seq": 242,
  "payload": {
    "seq": 242,
    "conversationId": "conv_32b58034",
    "type": "tool.completed",
    "createdAt": "2026-05-23T05:18:14.000Z",
    "toolUseId": "tool_command_execution_1",
    "exitCode": 124
  }
}
```

The top-level `seq` duplicates `payload.seq` for routing and diagnostics. The
payload remains the existing `ConversationEvent` JSON shape.

### Unsubscribe

```json
{
  "type": "unsubscribe",
  "id": "req_2",
  "topic": "conversation.events",
  "scope": {
    "conversationId": "conv_32b58034"
  }
}
```

The server removes only that subscription and keeps the socket open for other
topics.

### Ack

Acknowledgements are diagnostic checkpoints, not delivery guarantees:

```json
{
  "type": "ack",
  "topic": "conversation.events",
  "scope": {
    "conversationId": "conv_32b58034"
  },
  "seq": 286
}
```

The server may record the latest acknowledged sequence for traces. It must not
delete or suppress events because of the ack. Replay remains controlled by the
client's next `afterSeq`.

### Error

Recoverable protocol errors are sent as frames:

```json
{
  "type": "error",
  "id": "req_1",
  "topic": "conversation.events",
  "scope": {
    "conversationId": "conv_32b58034"
  },
  "code": "FORBIDDEN",
  "message": "Device is not authorized for this conversation."
}
```

`id` is optional because some errors are not responses to a client request. When
the error is scoped to a subscription, `topic` and `scope` should be included so
the client can route the failure to the right subscription.

Recommended error codes:

```text
AUTH_REQUIRED
TOKEN_EXPIRED
FORBIDDEN
UNKNOWN_TOPIC
INVALID_MESSAGE
REPLAY_TRUNCATED
BACKPRESSURE
INTERNAL_ERROR
```

Fatal errors close the socket after sending the error frame when possible.

## Heartbeat And Backpressure

The daemon sends WebSocket ping frames at the interval advertised in `hello`.
If a connection misses the expected pong window, the daemon closes the socket
and removes its subscriptions.

The daemon must bound pending output per connection. A practical first limit is
the first of:

```text
1 MB buffered bytes
500 queued frames
```

If either limit is exceeded, the daemon sends a `BACKPRESSURE` error when
possible, closes the connection, and relies on client reconnect with `afterSeq`
to recover. This is safer than unbounded memory growth.

## Mobile Architecture

Add a notification client under services/data, not inside the workbench page.

Suggested files:

```text
mobile/lib/src/services/daemon_notification_client.dart
mobile/lib/src/data/services/notification_service.dart
```

The client owns:

- converting `http`/`https` daemon base URIs to `ws`/`wss`;
- opening the WebSocket with the current access token;
- reusing the existing proxy/direct-host policy for local and private daemon
  addresses;
- decoding protocol frames;
- reconnecting with exponential backoff;
- exposing typed streams to repositories or feature coordinators;
- closing cleanly when the daemon session is closed.

Default reconnect backoff:

```text
initialDelay: 1 second
maxDelay: 30 seconds
jitter: +/-20%
```

The client should reset the backoff after a stable connection and should not
retry immediately in a tight loop after protocol errors such as `FORBIDDEN` or
`UNKNOWN_TOPIC`.

The workbench should consume a stream of `ConversationEvent` values or batches.
It should continue using the existing reducer path:

```text
ConversationEvent JSON
-> ConversationEvent.fromJson
-> WorkbenchViewModel.applyConversationEventsAsync
-> ConversationViewState.apply
```

The reducer remains protected by `seq` ordering and duplicate filtering.

`CodingWorkbenchPage` should stop owning the high-frequency poll timer. Its
responsibility becomes activating or deactivating a subscription based on the
current conversation route.

## Mobile Reconnect Flow

When a conversation becomes active:

1. Read `WorkbenchViewModel.lastSeq`.
2. Subscribe to `conversation.events` with `afterSeq = lastSeq`.
3. Apply replayed events and live events through the same path.
4. Update `lastSeq` only after events are applied.
5. Send optional diagnostic `ack` with the latest applied `seq`.

When the socket disconnects:

1. Mark notification status as reconnecting.
2. Start exponential backoff.
3. On reconnect, resubscribe active topics using the current `lastSeq`.
4. If reconnect repeatedly fails, run a REST backfill fetch and then retry the
   socket.

The REST fallback must not reintroduce 900 ms foreground polling. It is a repair
path for reconnect failure and an escape hatch for older daemons.

## Auth And Token Refresh

If the WebSocket upgrade is rejected or the server sends `AUTH_REQUIRED`, mobile
should use the existing refresh-token flow and then reconnect.

The WebSocket layer should not own refresh-token storage. It should call through
the same daemon client/session facilities used by HTTP requests, so token
lifecycle behavior remains consistent.

Long-lived sockets must not outlive their authorization indefinitely. The hub
should record the access-token expiration used during upgrade and include it in
connection state. New subscribe requests after expiration are rejected with
`TOKEN_EXPIRED`, and the server should close the socket with `TOKEN_EXPIRED` at
or shortly after the token expiry time. Mobile then refreshes through the
existing HTTP token flow and reconnects.

If the current auth store cannot expose token expiration to the hub in the first
implementation, the fallback is a bounded WebSocket connection lifetime, for
example:

```text
websocketMaxConnectionAgeMs: 3600000
```

That fallback forces periodic re-authentication until token-expiry metadata is
available to the WebSocket layer.

## Diagnostics

Record notification traces so future stalls are diagnosable without guessing.

Recommended trace names:

```text
ws.connecting
ws.connected
ws.auth_failed
ws.subscribed
ws.unsubscribed
ws.event
ws.ack
ws.reconnecting
ws.backfill_fetch
ws.fallback_poll
ws.closed
```

For `conversation.events`, trace rows should include:

```text
conversationId
topic
scope
afterSeq
eventSeq
eventCount
connectionId
durationMs
errorCode
```

The existing poll trace UI can either be generalized into notification trace
rows or kept temporarily beside the WebSocket trace while the migration is in
progress.

## Testing Plan

Daemon tests:

- rejects WebSocket upgrade without a valid bearer token;
- accepts upgrade with a valid token and sends `hello`;
- rejects unknown topics;
- rejects unauthorized conversation subscriptions;
- rejects subscribe after connection auth expiration;
- `subscribe` replays persisted events with `seq > afterSeq`;
- duplicate subscribe for the same topic and scope replaces the earlier
  subscription;
- subscribe registers before replay and queues live appends during replay, so an
  event appended during replay is delivered after replay and not lost;
- oversized replay returns `REPLAY_TRUNCATED` and requires REST backfill;
- appending a conversation event publishes to active subscribers;
- revoked conversation access removes an existing subscription before further
  fan-out;
- unsubscribe stops delivery for that topic only;
- missed heartbeat closes the connection and removes subscriptions;
- backpressure closes a slow connection without losing persisted events.

Mobile tests:

- constructs the correct `ws`/`wss` URI from daemon base URI;
- sends subscribe with current `lastSeq`;
- parses event frames into `ConversationEvent`;
- applies replayed and live events through the existing ViewModel path;
- reconnects with latest applied `lastSeq`;
- refreshes token after `AUTH_REQUIRED`;
- refreshes token after `TOKEN_EXPIRED`;
- uses REST backfill after `REPLAY_TRUNCATED`;
- falls back to REST backfill after repeated WebSocket failures;
- closing or switching conversations cancels the old subscription.

Integration/regression tests:

- start a conversation, receive tool started/completed and final assistant
  events without polling;
- drop the WebSocket while daemon appends events, reconnect, and verify all
  missing events are applied exactly once;
- simulate a 121-second command timeout and verify later assistant/file-change
  events appear without reopening the conversation;
- verify an older daemon without WebSocket support still works through REST
  fallback.

## Migration Strategy

Keep existing REST fetch support until the WebSocket path is verified.

The first implementation may use a feature switch or daemon capability flag:

```text
notifications.websocket: true
```

Mobile should choose:

```text
WebSocket notification gateway when supported
REST backfill/fallback otherwise
```

Once the WebSocket gateway is stable, remove the high-frequency workbench poll
timer. Keep explicit REST backfill calls for initial load, reconnect repair, and
diagnostics.

## Re-Evaluate When

Revisit this design if:

- the app needs reliable background notifications while closed or suspended;
- multiple mobile devices must receive cross-network updates outside the LAN;
- server-side event retention needs compaction based on client checkpoints;
- bidirectional low-latency commands become more important than HTTP writes;
- notification topics grow enough to need per-topic authorization policies or
  persistent subscription state.
