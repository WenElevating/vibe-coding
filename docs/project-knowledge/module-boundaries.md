# Module Boundaries

- Status: active seed
- Last verified: 2026-05-27

## Mobile Ownership

- UI widgets own rendering, layout, scroll behavior, and local interaction.
- ViewModels own UI state snapshots and presentation orchestration.
- Domain owns repository contracts and pure decisions.
- Data owns daemon/API JSON parsing and repository implementations.
- Workflows own ordered side-effect sequences across repositories.

## Boundary Rules

- `domain/` must not import Flutter, HTTP clients, `SharedPreferences`, UI code,
  `data/`, `services/`, workflows, shell code, or concrete `DaemonClient`.
- `services/`, `data/`, `domain/`, and `workflows/` must not import UI feature
  code. Shared platform contracts, such as speech input interfaces, belong in a
  lower layer and may be exported through UI barrels only for compatibility.
- Main-shell and Home code belongs under `mobile/lib/src/ui/main/`, not under
  `ui/features/`. Use `ui/features/<feature>/` only for true feature areas.
- New production code should not be added to retired migration roots:
  `mobile/lib/src/features`, `mobile/lib/src/widgets`, `mobile/lib/src/theme`,
  or `mobile/lib/src/state`.
- `mobile/lib/src/models/protocol.dart` is a compatibility barrel. Prefer new
  model ownership under `data/models/`.
- UI may render daemon data, but daemon-owned identity and metadata should not
  be invented locally.

## Current Specific Boundaries

### Conversation title

- Status: accepted
- Decision: `Conversation.title` is daemon-owned metadata.
- `cliSessionId` is an adapter resume token, not a display title.
- Mobile uses title when present and falls back only for older or missing data.
- Related: [stable conversation title decision](decisions/2026-05-22-stable-conversation-title.md).

### Workbench transcript scroll

- Status: accepted
- Decision: transcript latest-message anchoring is UI rendering responsibility.
- The ViewModel keeps logical message order. `CodingWorkbenchPage` may invert
  only the ListView rendering layer.
- Related: [bottom anchored transcript decision](decisions/2026-05-22-bottom-anchored-transcript.md).

### Attachment previews

- Status: accepted; implemented
- Decision: historical image previews are mobile-owned local cache, not daemon
  media storage.
- Daemon owns attachment metadata and send-time scratch only. It must not keep
  `previewPath`, `previewUrl`, or `previewHeaders` in the committed attachment
  protocol.
- Mobile owns thumbnail generation, local preview index persistence, cache
  lookup, and cache-miss UI fallback for images sent from that mobile device.
- Related: [mobile-owned attachment preview cache decision](decisions/2026-05-22-mobile-owned-attachment-preview-cache.md).

### Conversation event cache

- Status: accepted; implemented
- Decision: daemon remains the source of truth for conversation events; mobile
  owns a local read-through cache for already-synced `ConversationEvent` rows.
- Mobile may render cached events immediately when opening a conversation, then
  use daemon replay/backfill to append newer events.
- Related: [mobile conversation event cache decision](decisions/2026-05-31-mobile-conversation-event-cache.md).

## Verification

```powershell
cd mobile
dart run tool\check_architecture_imports.dart
```

Manual inspection target when changing workbench state:

- [coding_workbench_page.dart](../../mobile/lib/src/ui/features/workbench/coding_workbench_page.dart)
- [workbench_view_model.dart](../../mobile/lib/src/ui/features/workbench/view_models/workbench_view_model.dart)
