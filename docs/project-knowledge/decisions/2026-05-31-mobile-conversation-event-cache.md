# Decision: Mobile conversation events use a local read-through cache

- Status: accepted
- Date: 2026-05-31
- Last verified: 2026-05-31

## Context

Opening a mobile workbench conversation fetched the latest daemon event page
every time. This kept daemon as the only event store but made repeated history
loads slow and left no cached transcript when daemon connectivity was poor.

## Decision

Mobile stores already-synced `ConversationEvent` rows in a local read-through
cache keyed by daemon base URI and `conversationId`. The daemon remains the
authoritative event store. Mobile uses the cache to render history immediately,
then relies on daemon WebSocket replay/backfill and event-page fetches to fill
new or missing events.

The mobile cache does not enforce an app-level size limit. Users can still clear
the app data to remove cached history.

## Alternatives

- Memory-only cache: rejected because app restarts would still reload history
  from daemon.
- Tail-only cache: rejected because longer conversations would still request
  daemon repeatedly when paging older history.
- Mobile authoritative history: rejected because daemon already owns persisted
  protocol events and authorization.

## Evidence

- `mobile/lib/src/data/services/conversation_event_cache_store.dart` owns local
  cache persistence.
- `CachedConversationRepository` reads cached event pages before falling back to
  the daemon repository and writes fetched/streamed events back to the cache.

## Verification

```powershell
cd mobile
flutter test --no-pub test\conversation_event_cache_store_test.dart test\cached_connected_repositories_test.dart -r expanded
dart analyze lib test
dart run tool\check_architecture_imports.dart
```

## Re-evaluate When

- Cached history grows large enough to cause storage pressure.
- Users need a manual "clear conversation cache" control.
- Conversation event wire shape stops being JSON-round-trippable from mobile.
