# Workbench Composer Attachments Design

## Summary

The mobile workbench composer should support first-class message attachments for images and text documents, with PDF enabled only when the selected adapter and model can explicitly prove support. The first implementation should avoid a server-side pre-upload draft system. Attachments stay local to the mobile composer until the user sends the message, then the mobile client submits text, attachment metadata, and file bytes in one multipart request.

The daemon treats uploaded bytes as short-lived per-message scratch input for CLI adapters. The committed conversation record stores only attachment metadata on the `user.message` event. This keeps the source of truth clear: mobile owns unsent draft attachments, the daemon owns committed message metadata, and scratch files are internal implementation detail.

## Goals

- Let users attach images from the composer and send them to models that support image input.
- Let users attach small UTF-8 text documents such as `.txt`, `.md`, `.json`, `.log`, and `.csv`.
- Expose adapter and model attachment capabilities through the existing adapter status flow.
- Validate attachment type, size, and model support on the daemon before appending `user.message`.
- Reject oversized images by both byte size and pixel dimensions before invoking a CLI.
- Reject extracted text that is likely to exceed the selected model's context budget before committing the message.
- Avoid a server-side draft attachment state that must be synchronized with the mobile composer.
- Preserve old JSON text-only message sending for older clients and pure text sends.
- Make unsupported files fail explicitly with clear daemon error codes and mobile UI feedback.
- Keep original uploaded bytes out of long-term persistence, audit logs, and diagnostic bundles.

## Non-Goals

- No server-side pre-upload draft API.
- No resumable uploads in the first version.
- No cross-device draft synchronization.
- No long-term file library.
- No Office parsing for `.doc`, `.docx`, `.xls`, `.xlsx`, `.ppt`, or `.pptx`.
- No OCR.
- No image transcoding or resizing in the first version.
- No lossy text encoding fallback for UTF-16, Latin-1, GBK, or other legacy encodings.
- No PDF support unless adapter and model capability is explicit.
- No original-file replay from old messages.
- No silent downgrade from native image/PDF input to "read this local path" semantics.

## Research Findings

Large systems generally avoid making temporary uploaded bytes part of long-lived product state.

Discord's message API accepts files as part of the same create-message multipart request, with `payload_json` carrying message metadata and file parts carrying bytes. Attachments become part of the message only after the message create operation succeeds.

Slack's external upload flow uses a staged upload followed by `files.completeUploadExternal`. Uploaded bytes are not shared until the complete call succeeds, and incomplete uploads are discarded. This is a useful model for larger future uploads, but it is heavier than the first workbench composer need.

Google Drive resumable uploads and Amazon S3 multipart uploads use upload sessions, progress state, completion calls, abort paths, and lifecycle cleanup. Those patterns solve large-file and unreliable-network problems, but they introduce server-side state that should not be added until the product needs resumable or reusable files.

OpenAI and Anthropic file APIs use uploaded file identifiers that are referenced later by model requests. That model is useful conceptually, but this application controls local CLI adapters rather than calling provider APIs directly, so daemon capability and adapter conversion remain the authoritative boundary.

## Current State

Daemon:

- `POST /api/conversations/:id/messages` currently accepts only JSON text payloads.
- `normalizeMessagePayload()` requires text and returns `{ text }`.
- `ConversationManager.sendMessage()` appends `user.message`, marks the conversation running, starts the adapter, then sends text to the adapter handle.
- `publicConversation()` already includes adapter capabilities and conversation model state.
- The adapter registry already merges model metadata into `/api/adapters`.
- Codex capability detection already probes `codex exec --help` and `codex exec resume --help`.
- Claude conversation adapter already writes stream-json user messages to CLI stdin.

Mobile:

- `CodingComposer` has a `+` icon but it is not wired to attachment picking.
- `ConversationClient.sendMessage()` sends JSON `{ text }`.
- `WorkbenchViewModel.createAndSend()` and `sendExistingConversationPrompt()` only carry prompt text.
- The composer already separates CLI and model chips, and model selection is server-confirmed.

## Recommended Approach

Use a message-atomic multipart send:

1. Mobile stores selected files as local draft attachments.
2. Mobile shows draft attachments as a top-left thumbnail tray inside the composer.
3. On send, mobile submits text, `clientMessageId`, attachment metadata, and file bytes in a single multipart request.
4. The daemon validates the conversation state, idempotency key, files, adapter transport, and model modality before appending events.
5. The daemon may stream file parts to a per-message scratch directory during request parsing, but it appends no committed events until all validation passes.
6. The daemon appends `user.message` with attachment metadata, not file bytes or scratch paths.
7. The daemon passes normalized attachment inputs to the selected adapter.
8. Scratch files are removed according to each adapter path's declared `scratchLifetime`.

Rejected alternatives:

- Pre-upload server draft attachments: rejected because it creates synchronization problems between local mobile draft state and daemon temporary state.
- Base64 attachments inside JSON: rejected because it inflates request size, makes retries expensive, and is brittle for image/document sends.
- CLI-native-only support: rejected because it would unnecessarily block small text documents that can safely be extracted into text input.

## Capability Model

Attachment support has three independent dimensions:

- Adapter transport capability: whether the CLI invocation can carry an attachment kind.
- Model modality capability: whether the selected or default model accepts that attachment kind.
- Daemon handling mode: whether the daemon can convert the file into adapter input.

Allowed handling modes:

- `native`: the adapter receives the attachment as a native image/document/file input.
- `text_extract`: the daemon reads a UTF-8 text document and injects its content into the prompt or content blocks.
- `staged_path`: reserved for future adapters that explicitly support file path references as file inputs.
- `unsupported`: the attachment kind must be rejected.

Recommended `/api/adapters` model option extension:

```json
{
  "id": "gpt-5.3-codex",
  "label": "gpt-5.3-codex",
  "source": "codex_catalog",
  "selected": true,
  "inputModalities": ["text", "image"],
  "attachments": {
    "image": "native",
    "textDocument": "text_extract",
    "pdf": "unsupported"
  }
}
```

Recommended adapter-level fallback capability:

```json
{
  "capabilities": {
    "attachments": {
      "image": "native",
      "textDocument": "text_extract",
      "pdf": "unsupported"
    }
  }
}
```

Detection provenance such as `cli_help`, `codex_debug_models`, or `not_detected` is diagnostic data. Keep it out of the stable public capability contract unless the caller requests diagnostics explicitly, for example through a future diagnostics endpoint or dev-mode adapter status.

Model-level capability takes precedence over adapter defaults. If the selected model has no known image or PDF modality, those kinds are unsupported. `textDocument` is the exception because it is converted into plain text before reaching the model.

Adapter status responses should include an opaque `capabilityVersion`, computed from adapter id, CLI version/path, selected/default model metadata, and attachment capability metadata. Mobile must send the `capabilityVersion` used for draft validation with attachment sends. Text-only JSON sends do not require it.

`capabilityVersion` calculation:

- Build it from normalized capability data, not raw CLI probe output or raw help text.
- Normalize the semantic data first: sort unordered capability arrays, strip diagnostic provenance, preserve only fields that affect send compatibility, and then serialize with RFC 8785 JSON Canonicalization Scheme (JCS).
- Hash the exact UTF-8 bytes of the JCS output with SHA-256, truncate to the first 12 bytes, and encode as 24 lowercase hex characters.
- Do not use a timestamp or monotonic counter. Daemon restart must not invalidate mobile capability caches when the normalized capability data is unchanged.
- `cliPath` is included intentionally as the resolved executable identity, not raw user input. This is conservative: moving from one resolved binary path to another forces a capability refresh even when the visible version string is the same.
- If a multipart attachment send omits `capabilityVersion`, return `409 capability_stale` and require the client to fetch `/api/adapters` before retrying.
- If the daemon sees a stale version at send time, return `409 capability_stale` so the client refreshes adapter capabilities instead of receiving a misleading `422` for a model that appeared supported moments earlier.

Canonical JSON rules:

- Use RFC 8785 JCS for byte-level serialization after semantic normalization.
- JCS output has no insignificant whitespace and no trailing newline.
- Hash the UTF-8 encoded JCS byte string exactly as emitted.
- Object property ordering, string escaping, number rendering, and primitive rendering follow JCS. Do not use language-default pretty printers or ad hoc `JSON.stringify` wrappers unless tests prove byte-for-byte JCS output for the fixture cases.

Example normalized capability input:

```json
{
  "adapterId": "codex",
  "attachments": {
    "image": "native",
    "pdf": "unsupported",
    "textDocument": "text_extract"
  },
  "cliPath": "codex",
  "cliVersion": "0.21.0",
  "models": [
    {
      "id": "gpt-5.3-codex",
      "inputModalities": ["image", "text"]
    }
  ],
  "selectedModelId": "gpt-5.3-codex"
}
```

Expected JCS byte string:

```json
{"adapterId":"codex","attachments":{"image":"native","pdf":"unsupported","textDocument":"text_extract"},"cliPath":"codex","cliVersion":"0.21.0","models":[{"id":"gpt-5.3-codex","inputModalities":["image","text"]}],"selectedModelId":"gpt-5.3-codex"}
```

Expected SHA-256 hex:

```text
4bcf6aa44f7e2e074229f9cd64880e8dc42fa727917b9ef732209a3f0f776973
```

Expected `capabilityVersion` prefix:

```text
4bcf6aa44f7e2e074229f9cd
```

## Mobile Draft and UI

Mobile should introduce a local `DraftAttachment` model in the workbench feature:

```dart
class DraftAttachment {
  final String localPath;
  final String name;
  final String mimeType;
  final AttachmentKind kind;
  final int sizeBytes;
  final String? error;
}
```

The composer layout should be:

```text
composer shell
  top: left-aligned attachment thumbnail tray
  middle: text input
  bottom: CLI chip, model chip, attachment button, existing voice button, send button
```

Thumbnail tray behavior:

- Render above the input field, not below it.
- Left-align attachments.
- Use 44x44 or 48x48 thumbnails for images.
- Use same-size compact document tiles for text documents and PDFs.
- Put a small delete control at the top-right of each thumbnail.
- Use horizontal scrolling when attachments exceed available width.
- Do not wrap and do not resize the composer unpredictably on compact width.
- Mark unsupported or invalid attachments with a red error state and keep the delete control visible.

Draft rules:

- Selecting files creates local draft attachments only. It does not call the daemon.
- Removing a thumbnail deletes only local draft state.
- Sending succeeds only when there is non-empty text or at least one valid attachment.
- Sending is disabled while any attachment has a local validation error.
- A successful send clears both the text field and draft attachments.
- A pre-commit daemon error keeps both the text and draft attachments so the user can retry.
- A committed send failure clears local draft state because the message has already been committed. The transcript should show the committed attachment metadata plus `run.error`; retrying the same content requires the user to attach the local file again and send with a new `clientMessageId`.
- If a message has text documents but no user text, mobile should show a weak prompt suggestion such as "Add an instruction for these files." The daemon may still accept a text-document-only send by prepending a neutral instruction to inspect the attached text.
- Switching model invalidates incompatible draft attachments locally. Mobile should immediately mark affected draft attachments as unsupported and disable send until the user deletes them or switches back to a compatible model, without contacting the daemon.

Recommended first-version limits:

- Maximum attachments per message: 4.
- Maximum Codex image size: 10 MB each.
- Maximum Claude image size: 5 MB each because base64 over stream-json expands bytes by roughly one third and must fit on one JSONL stdin line.
- Maximum text document size: 1 MB each.
- Maximum total multipart payload: 20 MB.
- Minimum file size: 1 byte.
- Maximum image long edge: 8192 pixels.
- Maximum image total pixels: 100 megapixels.
- Allowed images: `.png`, `.jpg`, `.jpeg`, `.webp`.
- Allowed text documents: `.txt`, `.md`, `.markdown`, `.json`, `.log`, `.csv`.
- PDF is visible but enabled only when capability is explicit.
- Office documents are unsupported in the first version.

The first version rejects images that exceed byte or pixel limits with `413 payload_too_large`. It does not resize, transcode, or recompress uploads. A later image preprocessing feature can be designed separately if model rejection rates justify it.

Upload progress:

- Mobile should show a local uploading/sending progress indicator for multipart sends when the platform HTTP stack exposes upload progress.
- If progress callbacks are not available in the first implementation, show a sending state that is distinct from "CLI is running" so weak-network upload time is not confused with model execution time.
- Cancelling during upload should abort the HTTP request and keep the local draft attachments. The daemon must delete any partially written scratch directory in the multipart error/finally path.
- A transport timeout before commit keeps draft state and must not auto-retry multipart upload.

## Daemon API

Keep the existing JSON endpoint for text-only clients:

```text
POST /api/conversations/:id/messages
Content-Type: application/json
```

Add multipart handling on the same route:

```text
POST /api/conversations/:id/messages
Content-Type: multipart/form-data

fields:
  payload: JSON string
  files[]: attachment binaries
```

`payload` shape:

```json
{
  "text": "Please inspect this screenshot.",
  "clientMessageId": "mobile-generated-uuid",
  "capabilityVersion": "adapter-capability-version-used-by-mobile",
  "attachments": [
    {
      "field": "files[0]",
      "name": "screenshot.png",
      "mimeType": "image/png",
      "kind": "image",
      "sizeBytes": 120034
    }
  ]
}
```

Daemon processing order:

1. Authorize device and require the conversation.
2. Normalize multipart payload metadata without buffering full file bodies in memory.
3. Check active state, `sendLock`, and `modelUpdateLock`.
4. Validate `clientMessageId` idempotency.
5. Validate declared file count, declared size when present, filename, extension, and client MIME hint. Multipart parts without declared per-file size are allowed, but the stream counter must still enforce single-file and total payload limits.
6. Resolve adapter and selected/default model attachment capability, applying model-level capability before adapter-level fallback.
7. Reject stale or missing `capabilityVersion` with `409 capability_stale` before appending any event.
8. Reject unsupported attachments before appending any event.
9. Create a per-message scratch directory.
10. Stream file parts directly to scratch using daemon-generated safe names while enforcing byte limits, computing `contentSha256`, sniffing MIME/magic bytes, parsing image dimensions, and validating text encoding.
11. On any pre-commit failure after scratch creation, delete the scratch directory in `finally` and do not append events.
12. For text extraction, estimate rough context budget against the selected model before committing.
13. Append `user.message` with text and attachment metadata.
14. Append `conversation.status_changed` with `running`.
15. Ensure the adapter is started.
16. Send adapter message with normalized attachments.
17. Clean scratch according to the adapter-declared `scratchLifetime`.
18. On daemon startup, remove expired scratch directories that are not marked active.

Multipart parsing must stream file parts directly to scratch instead of buffering complete request bodies or complete files in memory. The first implementation should add a small concurrency gate for multipart uploads, for example one active multipart upload per authenticated device and four active multipart uploads per daemon process, returning `429 upload_rate_limited` when the gate is saturated.

If validation fails during streaming, the daemon should stop reading the request body and abort or close the upload stream as soon as the HTTP framework permits. It should not intentionally drain the remaining multipart bytes just to return a clean error response. This applies to byte-limit overflow, early magic-byte rejection, and late UTF-8 validation failures.

## File Type Validation

The daemon must treat client MIME, filename, and declared kind as hints only. Validation order is extension allowlist, then server-side sniffing, then client MIME as a diagnostic hint. The accepted kind and MIME are derived from extension class plus sniffed bytes.

Decision table:

| Case | Result |
| --- | --- |
| Extension is not in the allowlist | `415 unsupported_media_type` |
| File has zero bytes | `415 unsupported_media_type` |
| Image extension and sniffed bytes are an allowed image subtype | Accept as `image` using the sniffed MIME if size and pixel limits pass |
| Image extension says one allowed subtype but sniff says another allowed subtype | Accept as `image`, normalize `mimeType` to the sniffed MIME, and keep the original display name |
| Image extension but magic bytes are missing or sniff says a non-image known type | `415 unsupported_media_type` |
| Image dimensions cannot be determined | `415 unsupported_media_type` |
| PDF extension and PDF magic bytes agree | Accept only when capability allows PDF |
| Office extension or ZIP/container signature for document upload | `415 unsupported_media_type` in v1 |
| Text extension with valid UTF-8 and low binary/control-byte ratio | Accept as `textDocument` |
| Text extension with UTF-16, Latin-1, GBK, invalid UTF-8, NUL bytes, or high binary-byte ratio | `415 unsupported_media_type` |
| Client MIME disagrees with extension/sniff but extension/sniff are accepted | Accept and normalize to sniffed MIME, recording no audit unless needed for diagnostics |
| Client MIME says image/PDF but extension/sniff says text | Use extension/sniff result or reject if ambiguous |

The first implementation should avoid adding a file-type dependency unless the built-in sniffing becomes insufficient. It can recognize PNG, JPEG, WebP, PDF, UTF-8 text, and obvious ZIP/Office/container signatures with small header reads. WebP sniffing must read at least the 12-byte RIFF container header: bytes 0-3 are `RIFF`, bytes 4-7 are size, and bytes 8-11 must be `WEBP`; `RIFF` alone is not enough because WAV and AVI also use it. PNG, JPEG, and WebP dimension parsing is required for the pixel limits before dispatch.

PNG dimensions are available in the IHDR chunk near the start of the file. WebP dimensions are available in the VP8, VP8L, or VP8X headers. JPEG dimensions require scanning for a SOF marker, which can appear after large EXIF or ICC segments. The daemon may keep a 128 KB sniff buffer while streaming and may scan the scratch file once after streaming, but it must not load the whole image into memory. If dimensions still cannot be determined, reject with `415 unsupported_media_type` before committing the message.

Text encoding rules:

- Accept UTF-8.
- Accept UTF-8 with BOM and strip the BOM before text extraction.
- Preserve original line endings; do not normalize CRLF to LF.
- Reject UTF-16 LE/BE, Latin-1, GBK, and other legacy encodings in v1.
- Reject text files with NUL bytes or invalid UTF-8.
- Do not use a Latin-1 fallback for CSV in v1. If real CSV usage needs legacy encodings later, add an explicit encoding selector instead of guessing.

Text context budget rules:

- Before appending `user.message`, estimate text extraction cost using a tokenizer when an approved tokenizer is already available for the adapter. Do not block v1 on adding a provider-specific tokenizer dependency.
- Fallback estimate: `estimatedTokens = ceil((asciiChars + wrapperChars) / 3.0 + nonAsciiChars / 1.0)`.
- Count Unicode code points, not UTF-16 code units. Surrogate pairs and 4-byte UTF-8 sequences must count as one non-ASCII character for this estimate.
- Include user prompt text, extracted text, attachment wrapper overhead, and a reserve for system/CLI context.
- If the model context window is known, reserve `max(2048, ceil(contextWindow * 0.20))` tokens for system prompt, adapter scaffolding, and response headroom.
- If the model context window is unknown, use a conservative default context window of 8192 tokens.
- If `estimatedTokens` exceeds `contextWindow - reserve`, return `422 context_budget_exceeded` before committing the message.

Text extraction wrapper:

Use the same wrapper text for all adapters that receive extracted text so the model can distinguish attachment content from the user's instruction:

```text
<attachment name="foo.md" mime="text/markdown">
...
</attachment>
```

The wrapper content preserves original line endings after UTF-8/BOM handling.

## Scratch Files

Scratch path:

```text
data/attachments/scratch/<conversationId>/<clientMessageId>/
```

Scratch files must use daemon-generated safe filenames such as:

```text
att_0_<sha256-prefix>.png
att_1_<sha256-prefix>.txt
```

Original filenames are stored only as metadata. The daemon must never send scratch absolute paths back to mobile and must not record them in conversation events.

Adapters must declare scratch lifetime for each dispatch path:

```text
send_time
  Daemon can delete scratch after it has transformed bytes into adapter input.
  Examples: Claude base64 image content block, text_extract document content.

turn
  Daemon must keep scratch until the active CLI turn reaches a terminal state.
  Example: Codex --image <scratchPath>, because the spawned process must be able to read the path during the turn.

conversation
  Reserved for future staged_path support where an adapter explicitly promises that a path can be referenced after the current turn.
  Not used in v1.
```

Default scratch TTL is 24 hours and should be configurable through an environment variable. Each scratch directory should include metadata that marks `conversationId`, `clientMessageId`, `scratchLifetime`, `createdAt`, and active owner information such as process id or handle id when applicable. Startup cleanup removes expired scratch directories left by crashes, but it must skip directories associated with currently running conversations or live process ids.

## Conversation Events

`user.message` becomes attachment-aware:

```json
{
  "type": "user.message",
  "text": "Please inspect this screenshot.",
  "clientMessageId": "mobile-generated-uuid",
  "attachments": [
    {
      "id": "att_0_abc123",
      "name": "screenshot.png",
      "kind": "image",
      "mimeType": "image/png",
      "sizeBytes": 120034,
      "handling": "native"
    }
  ]
}
```

Event replay displays metadata only:

- Image attachments show image chips, not original image downloads.
- Text documents show file name, type, and size chips.
- If dispatch fails after the message is committed, the message metadata remains visible and the transcript also shows `run.error`.

Attachment metadata should not include a generic `status` field in v1 if every committed attachment is already accepted. Use `handling` instead to explain how the attachment was dispatched: `native`, `text_extract`, or future `staged_path`.

## Idempotency

`conversationId + clientMessageId` is the idempotency key.

Rules:

- If the same `clientMessageId` has already appended `user.message` with the same payload hash, return the current public conversation and do not call the adapter again.
- If the same `clientMessageId` is currently under `sendLock`, return `409 message_already_in_flight`.
- If the same `clientMessageId` is reused with a different payload hash, return `409 idempotency_conflict`.
- Pre-commit failures do not consume the `clientMessageId`. Mobile may keep the same `clientMessageId` while the user fixes validation errors, and a changed payload hash is not an idempotency conflict because no committed event exists.
- Committed failures consume the `clientMessageId`. If adapter dispatch later writes `run.error`, retrying the same human intent must use a new `clientMessageId` and requires the user to reattach local files because scratch bytes are not long-lived.
- Network timeouts must be resolved by polling conversation events for the same `clientMessageId`. If a `user.message` event with that id appears, the message is committed and the client must not auto-resend the multipart request.
- Mobile should generate a new `clientMessageId` only after an idempotency conflict, after a committed failure that the user chooses to retry, or after the user meaningfully starts a new send attempt.

Payload hash:

- Compute `payloadHash` on the daemon after validation and scratch streaming, not from client-declared metadata alone.
- Use the same semantic normalization plus RFC 8785 JCS serialization rules as `capabilityVersion`, then compute `sha256(canonicalPayloadJsonUtf8Bytes)`.
- `canonicalPayloadJson` contains normalized `text` and an `attachments` array in the user-declared attachment order.
- Each attachment hash entry contains `index`, sanitized `name`, normalized `mimeType`, normalized `kind`, validated `sizeBytes`, and `contentSha256Prefix`.
- `contentSha256Prefix` is the first 16 bytes of the daemon-computed content SHA-256 encoded as 32 lowercase hex characters. The full hash may be stored internally if useful, but it should not appear in user-visible events.
- Keep attachment arrays in user-declared order because order is semantically visible to prompt construction.

Example canonical payload input:

```json
{
  "attachments": [
    {
      "contentSha256Prefix": "0123456789abcdeffedcba9876543210",
      "index": 0,
      "kind": "image",
      "mimeType": "image/png",
      "name": "screenshot.png",
      "sizeBytes": 120034
    }
  ],
  "text": "Please inspect this screenshot."
}
```

Expected JCS byte string:

```json
{"attachments":[{"contentSha256Prefix":"0123456789abcdeffedcba9876543210","index":0,"kind":"image","mimeType":"image/png","name":"screenshot.png","sizeBytes":120034}],"text":"Please inspect this screenshot."}
```

Expected payload SHA-256 hex:

```text
760cab258596d09e0ca1f9b9a8821a03ad4da63461e1ead383a790123f153f26
```

The daemon should avoid scanning the full event log on every send. Maintain a persisted or restored per-conversation index from `clientMessageId` to event sequence plus payload hash. Rebuild the index from persisted events on startup if no dedicated database table exists yet.

## Adapter Conversion

### Codex

Codex image support:

- Transport detection requires `codex exec --help` and `codex exec resume --help` to expose `-i` or `--image`.
- Model detection should use `codex debug models`, preferring refreshed catalog when safe and falling back to `--bundled` if refresh is unavailable.
- The selected model must have `input_modalities` containing `image`.
- New conversations pass images with `codex exec --json --image <scratchPath>`.
- Resumed conversations pass images with `codex exec resume --json --image <scratchPath>`.
- Codex image scratch lifetime is `turn`.

Codex text documents:

- Codex CLI has no generic file parameter in the verified help text.
- The daemon extracts UTF-8 text and appends it as attachment wrapper blocks in the prompt. See "Text extraction wrapper" for the canonical wrapper format.

Codex PDF:

- Unsupported in the first version unless future CLI/API capability explicitly proves PDF/file input.

### Claude Code

Claude image support:

- Transport detection requires stream-json input support through help text or existing capability detection.
- Model detection should prefer Anthropic Models API capability data when available.
- A local static/config fallback may mark known Claude models as image/PDF capable.
- Unknown model image/PDF capability is unsupported.
- Images should be sent as stream-json image content blocks, not as local file paths for the model to read.
- Claude image scratch lifetime is `send_time` after the daemon has encoded the bytes into the stream-json content block.
- Claude native image input uses the stricter 5 MB per-image limit unless testing proves a local-path image reference or chunked file API that avoids one large JSONL stdin line.
- Do not implement `staged_path` for Claude image input until the CLI contract explicitly documents local path image references with the same semantics as native image content.

Recommended image content shape:

```json
{
  "type": "user",
  "message": {
    "role": "user",
    "content": [
      { "type": "text", "text": "Please inspect this screenshot." },
      {
        "type": "image",
        "source": {
          "type": "base64",
          "media_type": "image/png",
          "data": "..."
        }
      }
    ]
  }
}
```

Claude text documents:

- The daemon can extract UTF-8 text and include it as a stream-json text content block using the canonical "Text extraction wrapper" format.
- Claude text document scratch lifetime is `send_time`.

Claude PDF:

- Enabled only if model and adapter capability explicitly support document/PDF input.
- Otherwise return `422 attachment_kind_unsupported`.

### OpenCode

OpenCode conversation attachments are unsupported in the first version because the current conversation adapter is not implemented. It should expose `attachments.* = unsupported`.

## Error Handling

Pre-commit errors:

- Occur before `user.message` is appended.
- Do not change conversation status.
- Do not write committed events.
- Mobile keeps text and draft attachments.

Committed send errors:

- Occur after `user.message` and running status are appended.
- Append `run.error` and set conversation status to `failed`.
- Mobile does not restore draft because the message is already committed.

Cleanup errors:

- Do not affect conversation result.
- Record audit entries and rely on startup cleanup.

Error codes:

- `413 payload_too_large`: file count, single-file size, or total payload exceeds limits.
- `415 unsupported_media_type`: extension, MIME, magic bytes, or text encoding is not allowed.
- `422 attachment_kind_unsupported`: adapter or model does not support the attachment kind.
- `422 context_budget_exceeded`: extracted text would exceed the selected model's conservative context budget.
- `409 message_already_in_flight`: send is already running.
- `409 idempotency_conflict`: same `clientMessageId` with different payload.
- `409 capability_stale`: mobile validated against an older adapter/model capability version.
- `429 upload_rate_limited`: multipart upload concurrency or per-device send rate limit is saturated. The daemon should return a `Retry-After` hint based on which gate fired and the expected release time; absent better information, use `Retry-After: 5`.
- `502 attachment_dispatch_failed`: validation passed but the adapter conversion or CLI dispatch failed.
- `500 internal_error`: daemon-local infrastructure failed before or during dispatch, for example scratch root is not writable, disk is full, or an optional tokenizer initialization failed.

The existing API style uses `409` for lock/conflict states, so this design keeps `message_already_in_flight` as `409` rather than introducing `423 Locked`. Adapter dispatch failures should use `502` because the daemon accepted the request but the downstream CLI boundary failed.

All attachment send error responses should include a stable machine-readable `code` field matching the table above and a human-readable `message`. Optional `details` must not include file bytes, extracted text, base64 data, or scratch paths.

## Diagnostics and Audit

Audit records:

- `conversation.attachment_validation_failed`
- `conversation.attachment_dispatch_failed`
- `conversation.attachment_cleanup_failed`
- `conversation.attachment_idempotency_conflict`

Diagnostic bundle:

- Include attachment metadata and audit errors.
- Do not include original file bytes.
- Do not include base64 payloads.
- Do not include scratch absolute paths.
- Do not include extracted text document content unless a later explicit diagnostic policy allows it.
- Audit retention and diagnostic bundle retention follow the existing daemon retention policy. This design does not add a separate retention window.

## Security and Privacy

- Never trust client-provided `mimeType`, `kind`, `name`, or `sizeBytes` without daemon validation.
- Do not store original bytes long term.
- Do not write base64 image data or extracted text into event store or audit logs.
- Do not expose local scratch paths to mobile.
- Sanitize display names and reject path separators, control characters, and empty filenames.
- Normalize display names to Unicode NFC before storing metadata.
- Reject Unicode bidirectional override/control characters such as U+202A through U+202E and U+2066 through U+2069.
- Reject display names longer than 255 UTF-8 bytes after normalization.
- Reject Windows reserved base names such as `CON`, `PRN`, `AUX`, `NUL`, `COM1` through `COM9`, and `LPT1` through `LPT9`, even though scratch filenames are daemon-generated. This check is case-insensitive and applies after removing the extension, so `con.txt`, `Con.txt`, and `CON.TXT` are all rejected.
- Reject trailing spaces or dots in display names.
- Resolve all scratch paths under the configured scratch root before writing or deleting.
- Use per-message directories to make cleanup scoped and auditable.

## Mobile Error UX

- Local validation errors mark the thumbnail red and disable send.
- Daemon `413`, `415`, and `422` keep the composer text and attachments.
- Capability failures should refresh adapter capabilities after the error.
- `409 capability_stale` must refresh adapter capabilities and revalidate local draft attachments.
- `409 message_already_in_flight` keeps draft state and asks the user to wait for the active send.
- `429 upload_rate_limited` keeps draft state and uses the `Retry-After` response header for retry UI timing.
- Acknowledgement timeout should not automatically resend multipart payloads. Existing event polling should determine whether the message committed.

## Testing Plan

Daemon API tests:

- JSON text-only send still works.
- RFC 8785/JCS fixture for `capabilityVersion` produces `4bcf6aa44f7e2e074229f9cd`.
- RFC 8785/JCS fixture for `payloadHash` produces `760cab258596d09e0ca1f9b9a8821a03ad4da63461e1ead383a790123f153f26`.
- Multipart text plus image appends `user.message` metadata.
- Multipart text document extracts UTF-8 content and passes it to the adapter.
- UTF-8 BOM text is accepted and BOM is stripped.
- UTF-16 and Latin-1 text documents return `415`.
- Text extraction over context budget returns `422 context_budget_exceeded` before `user.message`.
- Unsupported PDF returns `422` and does not append `user.message`.
- Unsupported Office document returns `415` or `422` and does not append `user.message`.
- Zero-byte files return `415` and do not append `user.message`.
- Zero-byte text extension files return `415` and do not pass as empty valid UTF-8.
- Too many files returns `413`.
- Oversized image returns `413`.
- Over-pixel-limit image returns `413`.
- Multipart file parts without declared per-part size are accepted only if stream counters stay within configured limits.
- MIME/extension mismatch returns `415`.
- Allowed image extension with a different allowed sniffed image subtype is accepted and normalized to the sniffed MIME.
- WebP sniffing requires `RIFF` plus `WEBP`, and a non-WebP RIFF file returns `415`.
- JPEG dimension parsing scans SOF markers past large metadata, and dimension parse failure returns `415`.
- Invalid display names with path separators, bidi controls, reserved Windows names, trailing dots/spaces, or overlong UTF-8 byte length return `415`.
- Stale capability version returns `409 capability_stale`.
- Missing capability version on multipart attachment send returns `409 capability_stale`.
- Stable normalized capability data produces the same `capabilityVersion` across daemon restart.
- Pre-commit failures do not consume `clientMessageId`.
- Duplicate `clientMessageId` with same payload does not call adapter twice.
- Duplicate `clientMessageId` with same text but different attachment bytes returns `409`.
- Duplicate `clientMessageId` with different payload returns `409`.
- Multipart parser streams file parts to scratch and enforces concurrency gates without buffering full files in memory.
- Early streaming validation failure aborts request-body reading and cleans scratch.
- Saturated multipart concurrency gate returns `429 upload_rate_limited` with `Retry-After`.
- Adapter dispatch failure writes `run.error` and failed status.
- Adapter dispatch failure consumes `clientMessageId`; retry requires a new id.
- Scratch cleanup failure records audit but does not change the conversation result.
- Startup cleanup removes expired scratch directories.
- Startup cleanup skips active scratch directories for running conversations.

Adapter tests:

- Codex detects `--image` from both exec and resume help.
- Codex parses `debug models` `input_modalities`.
- Codex image dispatch includes `--image <scratchPath>`.
- Codex image scratch lifetime is `turn`.
- Codex text document dispatch injects attachment blocks.
- Claude stream-json image content block shape is correct.
- Claude image size limit is stricter than Codex to account for base64 JSONL expansion.
- Claude image scratch lifetime is `send_time`.
- Claude unknown model rejects image.
- OpenCode attachment capability remains unsupported.

Mobile tests:

- Adapter/model attachment capability parsing has safe defaults.
- `+` opens image/document choices.
- Selected attachments render as top-left thumbnails above the input field.
- Thumbnail delete removes local draft state.
- Unsupported attachment shows an error and disables send.
- Switching to a model that does not support an existing draft attachment marks that attachment unsupported locally and disables send.
- Multipart send includes text, `clientMessageId`, files, and metadata.
- Multipart send includes the last validated `capabilityVersion`.
- Upload timeout keeps draft attachments and does not auto-resend.
- Daemon `422` keeps draft attachments and text.
- Daemon `409 capability_stale` refreshes capabilities and keeps draft attachments.
- Successful send clears draft attachments and text.
- Committed adapter failure does not restore draft attachments and prompts the user to reattach files before retrying.
- Compact width does not overflow.

## Rollout Notes

- The protocol is additive. Old daemons ignore mobile attachment UI because old mobile clients do not send multipart.
- New mobile clients talking to old daemons should treat `404`, `405`, or non-multipart failures on attachment send as "daemon does not support attachments" and keep draft state.
- The first implementation should keep attachment code on the conversation path only. Legacy `/api/runs` support is out of scope.
- If CLI detection is unstable, disable image/PDF attachment capability and keep text-only sends working.
- First version mobile should refresh `/api/adapters` when opening the composer and after `409 capability_stale`. Periodic foreground revalidation and an `adapter.capability_changed` event are future improvements, not v1 requirements.
- Per-device send rate limiting is assumed to be handled at the existing auth/gateway layer. This design adds only a narrow multipart concurrency gate to protect daemon memory and scratch disk pressure.
- Short term, use the existing `POST /api/conversations/:id/messages` route with content-type negotiation for JSON and multipart compatibility.
- Medium term, consider moving multipart sends to an explicit endpoint such as `POST /api/conversations/:id/messages/multipart` or `POST /api/conversations/:id/messages:multipart`, leaving the JSON route as the stable text-only path.

## References

- Discord message attachments: https://docs.discord.com/developers/resources/message
- Slack external file upload completion: https://docs.slack.dev/reference/methods/files.completeUploadExternal/
- Google Drive resumable uploads: https://developers.google.com/workspace/drive/api/guides/manage-uploads
- Amazon S3 multipart upload cleanup: https://docs.aws.amazon.com/AmazonS3/latest/userguide/abort-mpu.html
- OpenAI model input modalities: https://developers.openai.com/api/docs/models
- OpenAI image inputs: https://developers.openai.com/api/docs/guides/images-vision
- OpenAI Files API: https://developers.openai.com/api/reference/resources/files
- Codex CLI reference: https://developers.openai.com/codex/cli/reference
- Claude docs home: https://docs.claude.com/
- Claude Code TypeScript SDK: https://platform.claude.com/docs/en/agent-sdk/typescript
- Anthropic Models API: https://platform.claude.com/docs/en/api/models
- Anthropic Files API: https://platform.claude.com/docs/en/build-with-claude/files
- JSON Canonicalization Scheme: https://www.rfc-editor.org/rfc/rfc8785
