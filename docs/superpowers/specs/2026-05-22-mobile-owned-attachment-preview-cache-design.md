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
contentSha256Prefix or contentHash
dimensions.width
dimensions.height
```

`contentHash` is the best long-term cache key because names and sizes can
collide. Dimensions let the UI reserve a stable preview area before the cached
thumbnail loads.

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
    required int attachmentIndex,
    required DraftAttachment draft,
  });

  Future<void> bindCommitted({
    required String conversationId,
    required String clientMessageId,
    required List<CommittedAttachment> attachments,
  });
}
```

The cache record should contain:

```text
conversationId
clientMessageId
attachmentId
attachmentIndex
contentHash or contentSha256Prefix
cachePath
width
height
createdAt
lastAccessedAt
```

The first implementation can store the index in a lightweight local JSON file or
an existing local persistence mechanism if one is already appropriate. It does
not need a new database unless the implementation naturally fits an existing
local DB boundary.

## Send Flow

When a user sends an image attachment:

```text
1. The picker returns the source localPath.
2. The ViewModel builds a message request with a clientMessageId.
3. The mobile cache generates a bounded thumbnail from the source file.
4. Before the daemon returns attachment ids, the cache records the preview under
   conversationId + clientMessageId + attachmentIndex/hash.
5. The daemon persists the user.message event with attachment metadata only.
6. After the committed attachments are received or replayed, mobile binds the
   pending preview record to conversationId + attachmentId/hash.
7. The UI resolves committed attachments against the local cache.
```

Thumbnail generation failure must not block message sending. A failed thumbnail
only means the historical message renders as a normal attachment card.

If message sending fails before the daemon commits the message, the pending
preview should remain usable for the current draft or retry path, but it must not
be bound as a historical preview until a committed message exists.

## Cache Storage And Eviction

Thumbnail files should live in app-specific storage under a dedicated directory
such as:

```text
attachment_previews/
```

Use bounded thumbnails instead of full original images. A reasonable initial
target is a longest edge around 512-720 px with compressed JPEG/WebP output.

Cache reads must always verify that the file still exists:

```text
If index exists and file exists:
  return the cached preview and update lastAccessedAt.

If index exists but file is gone:
  remove or ignore the stale index entry and return cache miss.

If no index exists:
  return cache miss.
```

Eviction can be simple in the first implementation. A later pass can add an LRU
cap such as total bytes or maximum record count. Cache eviction is a normal
state and must not damage message history.

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
cache resolve hit produces an image-preview display model
cache resolve miss produces a normal attachment card
thumbnail generation failure does not block send
missing cache file removes or ignores stale index and returns miss
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
