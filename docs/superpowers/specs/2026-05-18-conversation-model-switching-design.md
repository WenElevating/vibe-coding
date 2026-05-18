# Conversation Model Switching Design

## Summary

Existing conversations should allow model changes after the first message, but the change must be server-confirmed and must not hot-swap a currently running CLI process. A selected model becomes part of the persisted `conversation.model` state and takes effect on the next CLI start or resume.

This extends the existing workbench composer model picker design. The previous implementation already discovers adapter model capabilities, stores the model on conversation creation, and passes `conversation.model` into CLI startup. The missing part is updating that model for an existing conversation with clear daemon validation, mobile error handling, and CLI lifecycle rules.

## Goals

- Let users change the model for an existing conversation when the conversation is not actively running.
- Persist the selected model on the daemon conversation record.
- Apply the selected model on the next CLI start or resume, not by mutating a live CLI turn.
- Keep the CLI adapter fixed for the conversation; only the model can change.
- Avoid misleading optimistic UI. The composer chip should update only after the daemon confirms the new model.
- Return explicit errors for unsupported models, unsupported CLI capabilities, and disallowed active states.
- Treat `conversation.model` as the source of truth; diagnostic events are useful but not authoritative.

## Non-Goals

- Do not switch adapters inside an existing conversation.
- Do not hot-swap the model of a running or waiting CLI process.
- Do not invent free-form custom model entry in this change. The selected model must be `null` or one of the daemon-provided model options.
- Do not silently downgrade to default model when the user selected an unavailable model.
- Do not change provider discovery precedence in this design.

## Current State

Daemon:

- `POST /api/conversations` accepts optional `model`.
- `ConversationManager.createConversation()` stores `conversation.model`.
- `publicConversation()` returns `model`.
- `ensureStarted()` passes `conversation.model` to `adapter.startConversation()`.
- Codex and Claude adapters add `--model` only when capability probing says the CLI supports it.
- `POST /api/conversations/:id/messages` currently accepts only message text, so follow-up sends cannot request a model update.
- Existing persistence and event append APIs are not a single cross-resource transaction, so the update design must avoid claiming database-level atomicity where the codebase does not provide it.

Mobile:

- The composer has separate CLI and model chips.
- The CLI chip is locked for an active conversation.
- The model chip can be made selectable after a conversation exists.
- `WorkbenchViewModel` tracks `selectedModel`, but existing conversations do not yet have a server-confirmed update path.
- `ConversationSummary` should parse and expose `model` so mobile can distinguish confirmed daemon state from local draft state.

## Alternatives Considered

### Recommended: Server-Confirmed Conversation Model Update

Add `PATCH /api/conversations/:id/model`. The mobile picker sends the requested model, waits for daemon confirmation, and only then updates the composer chip. The daemon validates state and capability, persists the model, clears any idle handle if needed, and returns the updated public conversation.

Trade-offs:

- Strong consistency between UI and daemon state.
- Clear place for validation and error handling.
- Slightly slower visual feedback than optimistic UI, but avoids false state.
- Fits both Codex one-turn spawning and Claude long-lived/resume behavior.

### Alternative: Put `model` on Message Send

Extend `POST /api/conversations/:id/messages` to accept optional `model`.

Trade-offs:

- Fewer endpoints.
- Harder to explain as UI state because the model chip can appear changed before a message is sent.
- Blurs "select model" and "send prompt" responsibilities.
- More difficult to reject model changes before the user sends text.

Rejected because model selection is conversation state, not message text.

### Alternative: Optimistic Mobile Update with Rollback

Immediately update the chip, call the daemon, then roll back on failure.

Trade-offs:

- Feels responsive for simple preference toggles.
- Bad fit for model selection because the model affects backend execution, cost, capability, and CLI lifecycle.
- Error cases create confusing "selected but not really selected" states.

Rejected. Mature chat products generally treat model selection as a confirmed request state or a new-chat boundary rather than a risky optimistic mutation.

## API Design

### Update Conversation Model

Route:

```http
PATCH /api/conversations/:conversationId/model
```

Request body:

```json
{ "model": "gpt-5.5" }
```

Default model request:

```json
{ "model": null }
```

Rules:

- Request body must be an object.
- `model` may be `null` or a string.
- A blank string normalizes to `null`.
- Any non-string, non-null `model` is invalid.

Success response:

```json
{
  "conversation": {
    "id": "conv_...",
    "adapter": "codex",
    "model": "gpt-5.5",
    "status": "idle"
  }
}
```

The response uses the existing public conversation shape.

### Protocol Helper

Add `normalizeConversationModelUpdate(payload)` in `daemon/src/conversation-protocol.js`.

It returns:

```js
{ model: string | null }
```

It should reject malformed payloads with the same typed bad-request error pattern used by existing protocol helpers.

## Daemon Data Flow

Add `ConversationManager.updateModel(conversationId, payload, device)`.

Flow:

1. Load and authorize the conversation with `requireConversation(conversationId, device)`.
2. Normalize the payload with `normalizeConversationModelUpdate()`.
3. Reject if `conversation.modelUpdateLock` is truthy.
4. Set `conversation.modelUpdateLock = true` for the duration of the update. Clear it in `finally`.
5. Reject if the conversation is active:
   - `running`
   - `waiting_input`
   - `waiting_approval`
   - `sendLock` is truthy
6. Load the adapter and its current model capability.
7. Validate the requested model:
   - If `canSelectModel !== true`, reject non-null model selection.
   - If `models` is empty, allow only `null`.
   - If `models` is non-empty, a non-null model must match one `models[].id`.
8. If the model is unchanged, return `publicConversation(conversation)` without writing an event.
9. Save `previousModel`.
10. If an idle `conversation.handle` exists, dispose it before changing model and set it to `null`. Keep `cliSessionId`.
11. Assign `conversation.model = requestedModel`.
12. Touch and persist the conversation.
13. Best-effort append `conversation.model_changed` event with `previousModel` and `model`.
14. Return `publicConversation(conversation)`.

Consistency guarantee:

- If validation fails, do not mutate `conversation.model`.
- If handle disposal fails, do not mutate `conversation.model`.
- If persistence fails after assigning the new model, restore the in-memory model to `previousModel`, leave no `model_changed` event, and return an error.
- If handle disposal succeeds but persistence fails, do not try to reattach the disposed handle. Keep `conversation.handle = null`, restore `conversation.model = previousModel`, and preserve `cliSessionId`. This leaves the conversation idle and restartable; the next send resumes with the previous persisted model.
- This is a best-effort compensation model, not a true cross-resource transaction. The client should rely only on the returned `publicConversation()` and later list/get responses.

`sendMessage()` should also reject with `409` when `conversation.modelUpdateLock` is truthy, so a prompt cannot start while a model update is between validation and persistence.

## CLI Lifecycle

Model changes apply on next start/resume.

Codex:

- The capability remains `canSelectModel === true` only when both `codex exec --help` and `codex exec resume --help` expose `--model`.
- Updating the model clears an idle conversation handle while preserving `cliSessionId`.
- The next send calls `ensureStarted()`, which calls `adapter.startConversation({ sessionId: conversation.cliSessionId, model: conversation.model })`.
- The Codex adapter then builds `codex exec resume ... --model <id>` when session id exists.

Claude:

- The capability remains `canSelectModel === true` only when detection sees model flag support.
- Updating the model clears an idle long-lived handle while preserving `cliSessionId`.
- The next send starts Claude with `--resume <sessionId>` and `--model <id>` when supported.

No adapter should attempt to update a model inside an already running process.

## Mobile Architecture

Keep the current layered structure:

- UI view: picker and composer behavior.
- ViewModel: local selection state, pending update state, active conversation coordination.
- Domain repository: conversation operations.
- Data repository and daemon client: HTTP transport.

### Conversation Model Parsing

Extend `ConversationSummary` with:

```dart
final String? model;
```

Parse `json['model']` as nullable string, treating blank as `null` if local conventions already normalize optional text.

### Repository Surface

Add to `ConversationRepository`:

```dart
Future<ConversationSummary> updateConversationModel(
  String conversationId,
  String? model,
);
```

Implement in `DaemonConversationRepository` and `DaemonClient` with `PATCH /api/conversations/:id/model`.

### ViewModel State

Avoid giving one mutable field two meanings. Split local draft selection from confirmed conversation selection:

- `String? draftModel`
- `String? confirmedConversationModel`
- `bool modelUpdating`
- `String? modelUpdateError`

Keep `selectedModel` as a read-only compatibility getter for widgets:

- If `_activeConversationId == null`, return `draftModel`.
- If `_activeConversationId != null`, return `confirmedConversationModel`.

New conversation picker updates `draftModel` immediately. Existing conversation picker calls the server update path and changes `confirmedConversationModel` only after daemon success.

When opening an existing conversation, `_selectActiveConversationAdapter()` should also set `confirmedConversationModel = conversation.model`. If `conversation.model` is null, the chip should display the default model label.

### Existing Conversation Selection Flow

1. User opens the model picker in an idle existing conversation.
2. User taps a model row.
3. ViewModel refuses the request if `modelUpdating` is already true.
4. ViewModel sets `modelUpdating = true` and clears previous `modelUpdateError`.
5. Composer chip keeps the previously confirmed model.
6. Picker row shows a pending spinner and other rows are disabled.
7. Mobile calls `updateConversationModel(conversationId, model)`.
8. On success:
   - update active conversation from daemon response
   - set `confirmedConversationModel = conversation.model`
   - clear `modelUpdating`
   - close picker
9. On failure:
   - keep chip unchanged
   - clear `modelUpdating`
   - set `modelUpdateError`
   - keep picker open so the user can retry or choose another model

No request cancellation token is required for this flow. The ViewModel serializes updates by refusing a second update while `modelUpdating` is true. The daemon `modelUpdateLock` protects the same conversation from concurrent updates coming from another client or code path.

### New Conversation Draft Selection

For a not-yet-created conversation, model selection remains local and immediate because there is no remote conversation state to confirm.

### Default Model Display

`model == null` means "do not pass `--model`; let the CLI use its own default/configured model." It does not mean "use the first item in the discovered model list."

Display rules:

- Composer chip: use the localized `workbenchComposerDefaultModel` label.
- Picker: include a localized "Default model" row that sends `model: null`.
- If adapter capability includes `selectedModel`, the picker shows it as secondary text such as "CLI default: <id>", but the stored conversation value remains `null`.
- If adapter capability has no `selectedModel`, the picker uses a generic secondary text such as "Uses the CLI configured default."
- Reopening a conversation whose `conversation.model` is `null` selects the "Default model" row and shows the default label on the chip.

## UI Behavior

Composer:

- CLI chip remains locked after a conversation exists.
- Model chip remains selectable when the conversation is idle.
- Model chip is disabled while sending, running, waiting for user input, waiting for approval, or while a model update request is pending.
- The chip updates only after daemon confirmation for existing conversations.

Picker:

- For existing conversations, row taps start a server update.
- During update, show row-level pending UI and disable all choices.
- For active states, do not open the picker. Keep the model chip visually disabled and surface a short non-blocking notice if the existing composer notice path can do so without new UI surface.
- Include a "Default model" row that sends `model: null`.

## Error Handling

Daemon status codes:

- `400 Bad Request`: request body is malformed or `model` has an invalid type.
- `403 Forbidden`: device cannot access the conversation.
- `404 Not Found`: conversation does not exist or is not visible to the device.
- `409 Conflict`: current state does not allow model changes, such as running, waiting for input, waiting for approval, or message already in flight.
- `422 Unprocessable Entity`: adapter cannot select models, requested model is not in the model list, or the model capability is unavailable for the selected adapter.
- `500/503`: persistence, handle disposal, or adapter capability infrastructure failed.

Mobile handling:

- Do not change the composer chip on failure.
- Show a clear picker error message.
- For `403` and `404`, refresh conversation/session state.
- For `404` or `405` from the model update endpoint specifically, treat the daemon as older than the model-update protocol: keep existing new-conversation model selection, disable existing-conversation model updates for the current daemon connection, and show an unsupported-daemon message.
- For `409`, say the current turn must finish before changing model.
- For `422`, refresh adapter capabilities and keep the previous confirmed model.
- For `500/503`, show the existing operation error surface and include a trace id when the diagnostics repository returns one.

## Eventing

Add `conversation.model_changed`.

Payload:

```json
{
  "previousModel": "gpt-5-codex",
  "model": "gpt-5.5"
}
```

The event should be available in replay for diagnostics. It does not need to render as a visible chat transcript item in this change.

`conversation.model_changed` is diagnostic, not the source of truth. If event append fails after `conversation.model` has been persisted, do not roll back the model and do not fail the request solely because the diagnostic event failed. Catch the event append failure and record it through `auditLog.record('conversation.model_change_event_error', ...)`. Conversation list/get responses remain authoritative.

## Testing Plan

Daemon tests in `scripts/run-tests.js`:

- `normalizeConversationModelUpdate()` accepts string, blank, and null values and rejects malformed payloads.
- `PATCH /api/conversations/:id/model` updates and persists `conversation.model`.
- The endpoint rejects active states with `409`.
- The endpoint rejects unsupported adapter model selection with `422`.
- The endpoint rejects unknown models with `422`.
- Updating an idle conversation with an existing handle disposes the handle, preserves `cliSessionId`, and next send starts the adapter with the new model.
- Persistence failure restores the in-memory model, keeps any successfully disposed handle detached, preserves `cliSessionId`, and does not append `conversation.model_changed`.
- Event append failure does not roll back a successfully persisted model.
- Concurrent model updates on the same conversation return `409`.
- Sending a prompt while a model update lock is held returns `409`.

Mobile tests:

- `ConversationSummary.fromJson()` parses `model`.
- `WorkbenchViewModel` initializes `confirmedConversationModel` from `ConversationSummary.model`.
- New conversation model selection updates `draftModel` immediately.
- Existing conversation model update waits for repository success before changing `confirmedConversationModel`.
- Failure leaves `confirmedConversationModel` unchanged and exposes `modelUpdateError`.
- Sending state refuses model update.
- `modelUpdating` refuses concurrent update requests.
- Composer/model picker widget shows pending update state and keeps confirmed chip label until success.

Verification commands:

- `npm test`
- `npm run lint`
- Mobile architecture and focused tests:

```sh
cd mobile
PUB_HOSTED_URL=https://pub.flutter-io.cn FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn dart run tool/check_architecture_imports.dart
PUB_HOSTED_URL=https://pub.flutter-io.cn FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn flutter test test/adapter_model_test.dart test/widget_test.dart
```

On Windows/PowerShell, use the equivalent environment-variable syntax required by the local shell. If the first Flutter/Dart attempt times out, do not retry automatically. Report the timeout and provide the exact command for manual execution.

## Rollout Notes

- This is additive for old clients. Existing create/send endpoints continue to work.
- Old mobile clients will ignore `conversation.model` if they do not parse it.
- New mobile clients talking to an old daemon should handle `404` or `405` on `PATCH /api/conversations/:id/model` by disabling existing-conversation model updates for that connection while keeping new-conversation draft model selection available.
- The new endpoint should not be required for message sending.
- If model discovery returns no model list, the daemon should not accept arbitrary free-form models through the update endpoint.

## References

- GitHub Copilot Chat model selection: https://docs.github.com/en/copilot/how-tos/use-ai-models/change-the-chat-model?tool=vscode
- Claude model switching behavior: https://support.claude.com/en/articles/8664678-how-can-i-change-the-model-version-that-i-m-chatting-with
- Visual Studio Copilot model selection: https://learn.microsoft.com/en-us/visualstudio/ide/copilot-select-add-models?view=visualstudio
