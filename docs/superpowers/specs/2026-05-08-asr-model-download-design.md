# ASR Model Download Design

## Context

Mobile voice input already has a `SpeechInputService` boundary and a `SherpaSpeechInputService` scaffold, but the app keeps voice input disabled by default because no production model distribution path existed. The ASR model ZIP is now available to the local daemon at:

`daemon/asset/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20-mobile.zip`

The ZIP is approximately 325 MB, so the client must not require a single fragile full download. The mobile app should detect the missing model only when the user chooses voice input, show a download dialog, request the daemon download endpoint, support chunked transfer through HTTP Range requests, and resume interrupted downloads.

## Goals

- Keep text input immediately usable and unaffected by model availability.
- Trigger model detection only when the user taps the microphone.
- Download the model from the paired daemon, not from the public internet.
- Support resumable downloads using HTTP Range and a local `.part` file.
- Verify the downloaded ZIP before extracting and enabling ASR.
- Store extracted model files in the app private support directory.
- Continue the original microphone action after a successful first-time download.

## Non-Goals

- Do not commit the 325 MB model ZIP to Git.
- Do not implement background auto-download after daemon connection.
- Do not implement remote internet model download.
- Do not add a model management UI for multiple model versions.
- Do not promise Windows voice recognition works until it is manually verified.

## Daemon API

The daemon exposes a fixed ASR model asset. The client never supplies a filesystem path.

### `GET /api/asr-model`

Returns JSON metadata for the configured model ZIP.

Response fields:

- `version`: stable model identifier, for example `sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20-mobile`.
- `fileName`: ZIP file name.
- `sizeBytes`: exact byte size.
- `sha256`: SHA-256 digest of the ZIP.
- `downloadPath`: `/api/asr-model/download`.

The endpoint uses the same bearer token authorization as existing paired-device APIs.

### `GET /api/asr-model/download`

Streams the ZIP file. It must support standard HTTP Range semantics:

- No `Range` header returns `200 OK` with the full file.
- Valid `Range: bytes=<start>-<end>` returns `206 Partial Content`.
- Valid `Range: bytes=<start>-` returns bytes from `start` through EOF.
- Responses include `Accept-Ranges: bytes`, `Content-Length`, and, for partial responses, `Content-Range`.
- Invalid or unsatisfiable ranges return `416 Range Not Satisfiable` with `Content-Range: bytes */<size>`.

If the ZIP is missing, unreadable, or metadata cannot be computed, the daemon returns the existing structured error format with `traceId` so the mobile UI can show a copyable trace ID.

## Client Storage

The mobile app stores model files under the platform app support directory:

`<ApplicationSupportDirectory>/asr_models/<version>/`

Temporary paths:

- Download part: `<ApplicationSupportDirectory>/asr_models/<version>.zip.part`
- Verified ZIP: `<ApplicationSupportDirectory>/asr_models/<version>.zip`
- Extraction staging: `<ApplicationSupportDirectory>/asr_models/<version>.staging/`

The final model directory is considered ready only when these files exist:

- `encoder.onnx`
- `decoder.onnx`
- `joiner.onnx`
- `tokens.txt`

After extraction succeeds, the app removes stale staging data and may remove the verified ZIP to save disk space. If keeping the ZIP simplifies future verification, the implementation may keep it, but readiness must depend on extracted model files, not on ZIP presence.

## Client Flow

When the user taps the microphone:

1. `CodingWorkbenchPage` asks an `AsrModelManager` to `ensureReady()`.
2. If the final model directory is ready, the workbench creates or reuses `SherpaSpeechInputService(modelDirectory: readyPath)` and starts voice input.
3. If the model is missing, the app opens a modal download dialog.
4. The manager fetches `/api/asr-model` metadata.
5. If a `.part` file exists, the manager resumes with `Range: bytes=<partLength>-`.
6. If the daemon returns matching `206 Partial Content`, the client appends to `.part`.
7. If the daemon returns `200 OK` or a mismatched `Content-Range`, the client deletes `.part` and restarts from byte zero.
8. When the byte count reaches `sizeBytes`, the client computes SHA-256.
9. If SHA-256 matches metadata, the client renames `.part` to `.zip` or treats it as the verified ZIP.
10. The manager extracts into `.staging`, verifies required files, and atomically promotes `.staging` to the final version directory.
11. The dialog closes and the original microphone action continues without requiring a second tap.

If the user cancels during download or extraction, the manager stops work, keeps any reusable `.part` file, and leaves text input unchanged.

## Download Dialog UX

The dialog appears only after the user taps the microphone and the model is missing.

It shows:

- Model name or short label.
- Total size and downloaded bytes.
- Progress percentage.
- Current state: checking, downloading, paused, verifying, extracting, failed.
- Approximate speed when downloading.
- Controls: `Pause/Resume`, `Retry`, `Cancel`.

Failure behavior:

- The dialog stays open.
- It shows the error message and any daemon `traceId`.
- The trace ID has a copy button.
- `Retry` resumes from `.part` when safe.
- `Cancel` closes the dialog and returns to normal text input.

## Client State Machine

`AsrModelManager` exposes a small observable state for UI and tests:

- `idle`: no active model preparation.
- `checking`: local files and daemon metadata are being checked.
- `downloading`: bytes are being downloaded.
- `paused`: download is intentionally paused.
- `verifying`: ZIP size and SHA-256 are being checked.
- `extracting`: ZIP is being expanded into staging.
- `ready`: extracted model directory is usable.
- `failed`: preparation failed and can be retried or cancelled.
- `cancelled`: user cancelled the preparation flow.

Voice recording has a separate state machine in `VoiceInputController`. Model preparation failure must not move voice input into a misleading recording state.

## Component Boundaries

### Daemon

- Add a small ASR model asset module for locating the fixed ZIP, computing metadata, and streaming byte ranges.
- Keep route handling in `daemon/src/server.js` consistent with existing API style.
- Reuse existing authorization and structured exception handling.

### Mobile Services

- Add `AsrModelClient` to call daemon metadata and download endpoints.
- Add `AsrModelManager` to own local readiness checks, resumable download, verification, extraction, cancellation, and progress state.
- Keep `SpeechInputService` focused on recording and recognition; it should receive a ready model directory and should not download models.

### Mobile UI

- The composer remains a text input plus microphone affordance.
- The workbench handles mic-tap orchestration: ensure model, then start voice input.
- The download dialog observes `AsrModelManager` state and never sends chat messages.

## Error Handling

- Missing daemon ZIP: show failed dialog with daemon trace ID.
- Unauthorized request: show pairing/session error using existing daemon error decoding.
- Network interruption: keep `.part`, enter `failed`, allow retry/resume.
- Range mismatch: delete `.part` and restart from byte zero.
- SHA-256 mismatch: delete corrupted ZIP/part and require retry.
- Extraction failure: delete staging, keep verified ZIP if available, allow retry extraction.
- Required model files missing after extraction: fail, clean staging, and do not enable ASR.

## Testing Plan

### Daemon Tests

- Metadata endpoint returns `version`, `fileName`, `sizeBytes`, `sha256`, and `downloadPath`.
- Full download returns `200 OK` and the full file bytes.
- Valid Range returns `206 Partial Content` with correct `Content-Range` and bytes.
- Invalid Range returns `416 Range Not Satisfiable`.
- Unauthorized model requests fail with existing authorization behavior.
- Missing ZIP returns structured error with trace ID.

### Flutter Unit Tests

- Ready model directory skips download.
- Existing `.part` resumes from the correct offset.
- Mismatched `206` response resets the partial download.
- SHA-256 mismatch fails and removes corrupted data.
- Extraction validates required model files.
- Cancel keeps text input untouched and leaves resumable partial data.

### Flutter Widget Tests

- Tapping microphone with no model opens the download dialog.
- Successful download closes the dialog and starts voice initialization without auto-send.
- Download failure shows retry, cancel, and copyable trace ID.
- Cancelling the dialog returns to normal composer state.

## Open Implementation Notes

- Use a ZIP extraction dependency only if Flutter/Dart does not already provide a suitable project-approved path; otherwise prefer the smallest existing-compatible option.
- Add ignore rules for local model ZIP assets before implementation so `daemon/asset/*.zip` is not accidentally committed.
- Keep the first implementation single-version. Future versions can reuse the same metadata shape by changing `version`.
