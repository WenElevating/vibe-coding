# Mobile-Owned Attachment Preview Cache Design

Date: 2026-05-22

## Problem

Historical user messages can contain image attachments. The temporary fix copied
image preview bytes into the daemon and returned `previewPath` values that the
mobile client resolved into `previewUrl` network images.

That fixes display in one narrow case, but it gives the daemon a new durable
media-storage responsibility. The daemon in this repository is a LAN control
surface for CLI adapters and conversation metadata. It should not become a
historical image preview service unless the product explicitly chooses a
cross-device media-store model.

The accepted product scope is narrower:

```text
Guarantee historical image previews only on the mobile device that sent the
image, after app restart. If that device cache is cleared or another device
opens the same conversation, show the attachment record without a preview.
```

## Research Summary

Large chat products separate message metadata from media bytes and client cache:

- Slack-style products use a real file/media service. Message file records carry
  stable ids, private URLs, thumbnail variants, dimensions, and auth rules.
- Discord-style products expose attachment metadata plus CDN/proxy URLs,
  placeholder fields, dimensions, and explicit ephemeral states.
- Telegram-style products reuse server-side file ids and thumbnail variants when
  the platform owns the media object.
- WhatsApp-style APIs use stable media ids that exchange for short-lived
  authorized URLs rather than storing a permanent display URL in message text.
- Signal-style private messaging keeps message/media history on user devices;
  server-side recoverability is intentionally limited unless backups or linked
  devices exist.

This project should follow the local-device-cache side of that split. The
daemon remains the conversation metadata authority. The sending mobile client
owns durable local previews for its own history.

## Accepted Architecture

The daemon owns:

```text
conversation id
message events
attachment metadata
send-time attachment scratch files for CLI adapters
```

The mobile app owns:

```text
thumbnail generation
local thumbnail file storage
thumbnail index persistence
thumbnail cache lookup
thumbnail cache eviction
cache-miss UI behavior
```

The daemon must not persist image preview bytes for historical display. It may
temporarily receive multipart attachment files during send because adapters need
them. That scratch storage is an executor input, not a media archive.

## Non-Negotiable Protocol Change

`previewPath`, `previewUrl`, and `previewHeaders` are removed from the committed
attachment model.

The next implementation should not keep compatibility for those fields:

```text
Do not write previewPath.
Do not read previewPath.
Do not derive previewUrl.
Do not render Image.network for historical attachment previews.
Do not migrate old previewPath data.
```

Old conversations that contain the temporary fields are treated as old temporary
data. The user-visible fallback is the normal attachment card.

## Attachment Metadata

Committed attachments remain part of user-message history. They describe what
the message contained, not where a preview image lives.

Required committed attachment fields:

```text
id
name
kind
mimeType
sizeBytes
handling
```

Required containing-message context:

```text
conversationId
clientMessageId
attachment index/order
```

`clientMessageId` may live on the containing user message rather than being
duplicated onto every attachment. The cache binding logic needs that context,
but the wire protocol does not need redundant per-attachment fields if the
message already carries it.

Recommended cache-stability fields:

```text
contentSha256Prefix or contentHash, preferably computed before send
dimensions.width
dimensions.height
```

`contentHash` is the best long-term cache key because names and sizes can
collide. Dimensions let the UI reserve a stable preview area before the cached
thumbnail loads.

The daemon already validates attachment content hashes for multipart messages.
The mobile cache design should treat a hash computed from the picked local file
as the primary attachment identity from the start of the send flow.
`attachmentIndex` is only a tie-breaker and ordering hint. It must not be the
only key used to bind pending previews to committed attachments.

Hashing must not run synchronously on the Flutter UI isolate. The cache service
should compute file hashes in a background isolate/thread and expose the work as
a `Future` that the send flow can await while the UI remains responsive. If an
implementation later wants an inline fast path, it must be limited to small
files after measurement; the default design is background hashing for all image
attachments.

`clientMessageId` is the message-level bridge between pending previews and the
committed `user.message` event. Attachment-message retries must reuse the same
`clientMessageId` while the user is retrying the same draft. If the app creates
a new `clientMessageId`, the previous pending preview records become
uncommitted draft leftovers and are eligible for cleanup rather than historical
binding.

## Mobile Cache Model

The mobile app should add a small service boundary, for example:

```dart
abstract class AttachmentPreviewCache {
  Future<CachedAttachmentPreview?> resolve({
    required String conversationId,
    required CommittedAttachment attachment,
  });

  Future<void> rememberPending({
    required String conversationId,
    required String clientMessageId,
    required DraftAttachment draft,
    required AttachmentPreviewIdentity identity,
  });

  Future<void> bindCommitted({
    required String conversationId,
    required String clientMessageId,
    required List<CommittedAttachment> attachments,
  });
}
```

`AttachmentPreviewIdentity` should be derived before the network send begins:

```text
contentHash/contentSha256Prefix
name
mimeType
sizeBytes
attachmentIndex
```

Use the hash first. Use name, MIME type, size, and index only to disambiguate or
diagnose unexpected mismatches.

Two cache data shapes should be kept separate:

```text
AttachmentPreviewCacheRecord
  persisted cache/index schema

CachedAttachmentPreview
  read-only resolved result returned to ViewModel/UI
```

`AttachmentPreviewCacheRecord` should contain:

```text
conversationId
attachmentId
clientMessageId
contentHash or contentSha256Prefix
cachePath
width
height
mimeType
sizeBytes
state: pending | ready | failed
failureCode
createdAt
lastAccessedAt
lastAttemptedAt
```

`CachedAttachmentPreview` should be explicit rather than passing raw file paths
through UI state:

```text
attachmentId
contentHash or contentSha256Prefix
cachePath
width
height
mimeType
sizeBytes
createdAt
lastAccessedAt
```

The resolved result can omit pending/failure bookkeeping because callers only
receive it when the cache entry is ready and the file exists.

The persisted cache record also needs enough draft/orphan bookkeeping to clean
unfinished sends:

```text
attachmentIndex
draftLocalPath, optional and redacted from diagnostics
orphanedAt, optional
committedAt, optional
```

The first implementation can store the index in a lightweight local JSON file or
an existing local persistence mechanism if one is already appropriate. It does
not need a new database unless the implementation naturally fits an existing
local DB boundary.

If the first implementation uses JSON, index writes must be serialized through a
single cache service queue or mutex and written atomically through a temporary
file plus rename. Concurrent sends with multiple images must not interleave
read-modify-write cycles and lose records. If an existing local SQLite-style
store is already available in the mobile layer, prefer it for the cache index.

## Send Flow

When a user sends an image attachment:

```text
1. The picker returns the source localPath.
2. The ViewModel builds a message request with a clientMessageId.
3. For every image draft, mobile computes the attachment identity hash before
   sending, or records a pending identity failure before sending.
4. Mobile starts thumbnail generation and pending-cache recording before the
   daemon request is allowed to bind committed attachments.
5. The daemon persists the user.message event with attachment metadata only.
6. After the committed attachments are received or replayed, mobile binds the
   pending preview record to conversationId + attachmentId/hash.
7. The UI resolves committed attachments against the local cache.
```

There must be no race where `bindCommitted` runs before the relevant
`rememberPending` operation has either completed or recorded a failure. The
implementation can satisfy this in either of two ways:

```text
Option A:
  Await identity calculation and pending-cache registration before sending the
  daemon request. Thumbnail encoding may continue in the background if the
  pending record can later transition to ready/failed.

Option B:
  Let thumbnail work run concurrently, but make bindCommitted wait for, observe,
  or subscribe to the pending operation keyed by clientMessageId + content hash.
  If pending is still in progress, binding must retry or finalize when the
  pending operation completes.
```

Prefer Option A for the first implementation unless profiling proves it hurts
send latency. It is simpler and avoids silent preview loss.

`bindCommitted` must stay focused on binding metadata. It must not own thumbnail
generation. If a pending record exists but its thumbnail generation failed or is
still incomplete, the cache service schedules or observes the one allowed
background retry from its own pending-record state machine after the committed
message is known. The trigger is the cache service learning the committed
attachment identity through `bindCommitted`, not the ViewModel embedding
thumbnail generation inside binding.

Thumbnail generation failure must not block message sending. A failed thumbnail
only means the historical message renders as a normal attachment card.

Failures must still be observable:

```text
record failure state in the cache index for the pending identity
log/report a non-fatal diagnostic with conversationId, clientMessageId,
attachment identity, and error category
do not retry indefinitely
```

Retry policy:

```text
Try once during the send preparation path.
If identity calculation succeeds but thumbnail encoding fails, allow one
background retry after the message is committed.
After the background retry fails, mark the preview as failed until the user
changes the attachment or the cache entry is purged.
```

If message sending fails before the daemon commits the message, the pending
preview should remain usable for the current draft or retry path, but it must not
be bound as a historical preview until a committed message exists.

If the user retries the same attachment message after a recoverable send failure,
reuse the same `clientMessageId` and pending preview identity so the cache and
daemon idempotency stay aligned.

If the user abandons the draft, changes attachments enough to create a new
`clientMessageId`, or the app restarts before commit, the old pending preview
records become orphans. The cache service should mark them with `orphanedAt`
when it can observe the transition. Orphans do not need immediate deletion, but
they must be excluded from historical binding and should be the first records
eligible for cleanup before normal LRU eviction.

## Cache Storage And Eviction

Thumbnail files should live in app-specific storage under a dedicated directory
such as:

```text
attachment_previews/
```

Use bounded thumbnails instead of full original images. A reasonable initial
target is a longest edge around 512-720 px with compressed JPEG/WebP output.

The first implementation should still enforce a conservative default cap:

```text
maximum preview bytes: 100 MB
maximum records: 500
eviction: least-recently-accessed cache records first
never evict records for a message currently being sent
evict orphaned pending records before ready historical records
```

These values are defaults, not product promises. They protect device storage
while keeping the local-device guarantee realistic.

Cache reads must always verify that the file still exists:

```text
If index exists and file exists:
  return the cached preview and update lastAccessedAt.

If index exists but file is gone:
  remove or ignore the stale index entry and return cache miss.

If no index exists:
  return cache miss.
```

Eviction is required in the first implementation, but it can stay simple: enforce
the default byte and record caps with least-recently-accessed ordering, and clean
orphaned pending records before ready historical previews. Cache eviction is a
normal state and must not damage message history.

Eviction may race with UI usage. A cached image that was already decoded can
remain visible in memory, but every later action that needs the file path, such
as opening the image viewer, must resolve the cache again or handle file-missing
errors by falling back to the normal attachment card. The UI must never show a
permanent broken-image state because eviction removed a file between list render
and tap.

## UI Behavior

Historical user-message attachments render as follows:

```text
If attachment.kind == image and local cache resolve succeeds:
  show the image preview card.
  tapping opens the existing image viewer using the cached thumbnail.

If cache resolve misses:
  show the normal attachment card with image icon, file name, and size.
  do not show a broken image state.
  do not issue a daemon preview request.
```

The preview is an enhancement, not the source of truth. Message text and
attachment metadata remain visible even when the preview cache is unavailable.

## Daemon Removal Scope

Remove the temporary daemon preview feature:

```text
delete AttachmentPreviewStore
delete attachmentPreviewStore construction in daemon startup
delete ConversationManager preview-copy logic
delete ConversationManager.getAttachmentPreview()
delete /api/conversations/:conversationId/attachments/:attachmentId/preview
delete streamAttachmentPreview()
stop writing previewPath into committed attachment metadata
```

Keep `AttachmentScratchStore`. It is still needed for multipart send and CLI
adapter input.

## Mobile Removal Scope

Remove the temporary protocol dependency:

```text
remove previewPath, previewUrl, previewHeaders from CommittedAttachment
remove DaemonClient preview URL resolution
remove Image.network attachment preview rendering
replace in-memory-only localPath preview maps with AttachmentPreviewCache
```

The UI can still use a local file image provider for cached previews, but the
file path must come from the mobile cache service, not from daemon metadata.

## Testing

Daemon regression coverage:

```text
sending an image attachment stores metadata without previewPath/previewUrl
the old preview route returns 404 or is absent
attachment scratch behavior still works for adapter send-time files
attachment cleanup still handles send_time and turn scratch lifetimes
```

Mobile model/client coverage:

```text
CommittedAttachment no longer exposes previewPath/previewUrl/previewHeaders
DaemonClient does not synthesize previewUrl from daemon response data
legacy response fields, if present, are ignored by the model
```

Mobile ViewModel/cache coverage:

```text
send image calls AttachmentPreviewCache.rememberPending
committed attachment replay calls bindCommitted
bindCommitted cannot miss a preview because rememberPending is still running
content hash is the primary pending-to-committed binding key
attachmentIndex mismatch does not bind the wrong cached thumbnail
same-draft retry reuses clientMessageId and pending cache records
cache resolve hit produces an image-preview display model
cache resolve miss produces a normal attachment card
thumbnail generation failure does not block send
thumbnail generation failure records a non-fatal diagnostic
background retry can bind a preview after commit
missing cache file removes or ignores stale index and returns miss
concurrent sends with multiple image attachments do not corrupt the cache index
app restart during an in-flight send does not bind orphaned pending previews as
historical previews
eviction while a historical message is visible does not break the list item or
viewer; the UI falls back to the normal attachment card or a dismissible miss
state
```

Mobile widget coverage:

```text
cached image attachment renders preview
cache-miss image attachment renders normal attachment card
no Image.network path is used for historical attachment previews
viewer opens only when a cached preview exists
```

## Non-Goals

This design does not provide cross-device media preview recovery.

This design does not preserve or migrate `previewPath` or `previewUrl`.

This design does not introduce a daemon media service, object store, thumbnail
service, or CDN-like route.

This design does not store original full-size images in the mobile cache. It
stores only bounded thumbnails for historical preview display.

## Re-Evaluate When

- The product requires any phone connected to the same daemon to see historical
  image previews.
- The product requires long-term backup/restore of image previews.
- Attachments become first-class files with download, sharing, or retention
  policies.
- The app introduces a real shared media store with access control and cleanup.
- The product treats a tablet, desktop companion, or linked device as part of
  the same preview-availability guarantee rather than a separate device.
