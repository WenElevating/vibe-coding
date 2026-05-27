# Troubleshooting Playbook

- Status: active seed
- Last verified: 2026-05-22

## Symptom: Flutter Test Fails With HttpException On 127.0.0.1

- Symptom: `HttpException: Connection closed before full header was received`
  for `http://127.0.0.1:<port>` while loading Flutter tests.
- Action: check proxy configuration before changing test code.
- Verification:

```powershell
cd D:\AIProject\vibe-coding\mobile
$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test --no-pub test\conversation_reducer_test.dart -r expanded
```

- Last verified: 2026-05-22
## Symptom: Codex Conversation Shows No Visible Output

- Symptom: mobile transcript shows little or no assistant output even though the
  daemon or CLI may have emitted failure events.
- Action: inspect persisted conversation events and look for visible `run.error`
  before treating the issue as UI-only.
- Evidence: previous error visibility fix centered on `conversation_reducer.dart`
  and persisted daemon events.
- Verification:

```powershell
node scripts/run-tests.js
cd mobile
flutter test --no-pub test\conversation_reducer_test.dart -r expanded
```

- Last verified: 2026-05-22

## Symptom: Historical Workbench Conversation Opens Away From Latest Message

- Symptom: entering an existing session shows the transcript near the middle or
  top instead of the latest assistant/tool output.
- Action: prefer a bottom-anchored list (`ListView.builder(reverse: true)`) over
  post-frame `jumpTo(maxScrollExtent)` correction. Builder lists can estimate
  `maxScrollExtent` before all historical content is laid out.
- Related file: [coding_workbench_page.dart](../../mobile/lib/src/ui/features/workbench/coding_workbench_page.dart)
- Verification:

```powershell
cd D:\AIProject\vibe-coding\mobile
flutter test --no-pub test\widget_test.dart -r expanded --plain-name "opening existing conversation scrolls to latest message"
```

- Last verified: 2026-05-22

## Symptom: Workbench Shows Completed Command As Still Running

- Symptom: a command card can show completed while the bottom pending sentinel
  still says `正在运行 command_execution...`.
- Action: inspect the full event chain before changing daemon completion logic.
  A `tool.completed` event only completes one command; the turn remains running
  until `conversation.completed` or a terminal assistant message. The pending
  status text must correlate `tool.started` and `tool.completed` by
  `toolUseId`, and send acknowledgements must not overwrite terminal state that
  arrived through the conversation event stream.
- Verification:

```powershell
cd D:\AIProject\vibe-coding\mobile
$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test --no-pub test\coding_workbench_controller_test.dart -r expanded --plain-name "pending status does not report completed tool activity"
```

- Last verified: 2026-05-22

## Symptom: Codex Conversation Hides File Changes And Looks Stalled

- Symptom: Codex says it is changing backend/mobile code, but the workbench
  transcript shows no visible file-change cards, or shows weak generic
  `System notice` rows such as `File changed: updated path`. The pending
  sentinel can appear stuck as `正在运行 command_execution...` during a real
  long-running command.
- Action: inspect persisted `conversation_events` for `system.notice` rows with
  `noticeKind=codex_unknown_event` or `noticeKind=codex_file_change`. Unknown
  completed `raw.item.type=file_change` events should be mapped to visible
  `codex_file_change` notices with normalized relative paths. Mobile should
  preserve `changes` as structured `file_change` messages instead of projecting
  them as generic notices, and pending `command_execution` text should show the
  actual command from `tool.started.input.command` when present. If later
  content only appears after reopening the conversation, compare mobile event
  trace rows against persisted event `seq`: a gap means the page stopped
  receiving foreground events even though daemon events continued. Restart the
  event subscription after send acknowledgement timeouts and keep stale terminal
  acknowledgements from overwriting active reducer state.
- Verification:

```powershell
node scripts/run-tests.js
```

- Additional targeted Flutter coverage lives in `conversation_reducer_test.dart`
  and `coding_workbench_controller_test.dart`; run the relevant tests manually
  if the local Flutter tool times out in an agent run.

- Last verified: 2026-05-23

## Symptom: Codex CLI Events Are Persisted But Invisible

- Symptom: the daemon persists `system.notice` rows with
  `noticeKind=codex_unknown_event` and `visible=false`; mobile then filters
  them from the transcript.
- Action: group ignored events by `payload_json.raw.type` and
  `payload_json.raw.item.type` before treating them as harmless lifecycle
  noise. Lifecycle events such as `thread.started` and `turn.started` are
  intentionally hidden, but item payloads such as `file_change` or
  `mcp_tool_call` should be mapped to visible product events when they carry
  user-relevant work. If old rows were already persisted as
  `codex_unknown_event`, keep storage immutable and remap them from preserved
  `raw` payloads during replay/fetch.
- Verification:

```powershell
sqlite3 -json data\app\app.sqlite "select json_extract(payload_json,'$.noticeKind') as noticeKind, json_extract(payload_json,'$.raw.type') as rawType, json_extract(payload_json,'$.raw.item.type') as itemType, count(*) as count, max(created_at) as latest from conversation_events where type='system.notice' group by noticeKind, rawType, itemType order by latest desc, count desc;"
node scripts/run-tests.js
```

- Last verified: 2026-05-23

## Symptom: Sent Image Preview Turns Into Placeholder After Commit

- Symptom: an uploaded image preview renders initially from the optimistic
  local draft path, then turns into a large image frame with a placeholder icon
  after the committed `user.message` event arrives.
- Action: inspect the committed attachment metadata and the mobile preview
  cache binding path before changing UI rendering. A file can have a `.png`
  name while daemon byte sniffing records `mimeType=image/jpeg`; mobile preview
  binding should treat image MIME variants as compatible when name, size, and
  client message identity still match.
- Evidence: latest local `conversation_events` rows showed `.png` attachment
  names committed with `mimeType=image/jpeg`, while mobile picker drafts infer
  `image/png` from the extension.
- Verification:

```powershell
sqlite3 -json data\app\app.sqlite "select conversation_id, seq, payload_json from conversation_events where type='user.message' order by created_at desc, seq desc limit 5;"
cd mobile
$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test --no-pub test\attachment_preview_cache_test.dart -r expanded --plain-name "bindCommitted tolerates daemon-sniffed image MIME mismatch"
```

- Last verified: 2026-05-23

## Symptom: Workbench WebSocket Stream Appears Stalled

- Symptom: daemon persists later `conversation_events`, but the foreground transcript does not update over the WebSocket notification path.
- Action: inspect WebSocket notification trace rows first. Confirm the active `topic + scope`, latest applied `seq`, reconnect status, and whether REST backfill ran after `REPLAY_TRUNCATED`, `TOKEN_EXPIRED`, or socket close. If persisted seq advances while mobile seq does not, force reconnect from the last applied seq before changing reducer logic.
  A successful socket upgrade alone must not reset the mobile failed-attempt backfill counter; reset that counter only after an event is applied or REST backfill advances the cursor, otherwise connect-then-fail loops can starve the repair path.
  Non-retryable protocol errors such as `FORBIDDEN`, `UNKNOWN_TOPIC`, and `INVALID_MESSAGE` should surface through the stream error path instead of leaving a subscribed UI silently waiting forever.
  The mobile notification client is session-level multiplexed: route changes must wake any delayed reconnect wait, otherwise switching conversations after a socket failure can wait for the full backoff before opening the next subscription.
  REST backfill failures during reconnect repair must be contained inside the notification client. A failed backfill means the cursor did not advance; it should not escape the connection loop or restart immediately without the normal reconnect delay.
  Daemon replay lookup failures after subscription registration must remove the subscription, emit `INTERNAL_ERROR`, and close the WebSocket with 1011 so the mobile client does not keep listening on a route that the hub has already removed.
- Verification:

```powershell
node scripts/run-tests.js
cd mobile
$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test --no-pub test\daemon_notification_client_test.dart test\coding_workbench_controller_test.dart -r expanded
```

- Last verified: 2026-05-24

## Symptom: Claude Conversation Counts Events But Shows No New Text

- Symptom: the workbench status banner says Claude has processed many events,
  but the transcript appears blank or unchanged until a later assistant/tool
  event arrives.
- Action: inspect persisted `conversation_events` before changing WebSocket or
  reducer logic. Claude Code 2.1.119 can emit empty lifecycle frames such as
  `system/hook_started`, `system/status`, `message_delta`, and `message_stop`.
  These should not be persisted as `protocol.warning` rows because they advance
  the visible event counter without rendering user-facing content.
- Related file:
  [claude-conversation-adapter.js](../../daemon/src/claude-conversation-adapter.js)
- Verification:

```powershell
node scripts/run-tests.js
npm run lint
```

- Last verified: 2026-05-25

## Symptom: Claude Permission Request Ends Without Mobile Approval UI

- Symptom: a Claude Bash/tool card shows `This command requires approval`, then
  the conversation completes or asks the user to retry, but no actionable mobile
  approval card appears.
- Action: confirm whether Claude emitted a `control_request` with
  `request.subtype=can_use_tool`. If not, mobile cannot approve that already
  completed tool call; treat the tool result as a non-interactive permission
  failure, mark `permissionError=true`, and surface a visible system notice
  explaining that the CLI did not provide a responsive mobile approval request.
- Related file:
  [claude-conversation-adapter.js](../../daemon/src/claude-conversation-adapter.js)
- Verification:

```powershell
node scripts/run-tests.js
npm run lint
```

- Last verified: 2026-05-25

## Symptom: Workbench Running Timer Resets After Reopening Conversation

- Symptom: the pending/running transition card timer starts from `00:00` after
  leaving and reopening an active conversation, even though the CLI turn was
  already running.
- Action: do not use widget mount time as the source of truth for persisted
  conversation state. Derive the pending timer anchor from stored
  `conversation_events`, preferring the latest active
  `conversation.status_changed` segment and falling back to the current
  `conversation.started` or `user.message` event. The widget may keep a local
  counter only when no persisted anchor exists.
- Related files:
  [workbench_messages.dart](../../mobile/lib/src/ui/features/workbench/workbench_messages.dart),
  [workbench_event_cards.dart](../../mobile/lib/src/ui/features/workbench/workbench_event_cards.dart)
- Verification:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test --no-pub test\coding_workbench_controller_test.dart test\widget_test.dart
```

- Last verified: 2026-05-25

## Symptom: Codex command_execution Times Out But The Same Command Works In PowerShell

- Symptom: the workbench command card reports output such as
  `120 seconds timed out`, while copying the same command into PowerShell
  finishes successfully.
- Action: treat this as Codex CLI tool execution timeout first, not as a daemon
  HTTP timeout or PowerShell failure. The daemon starts Codex without wrapping
  model-generated shell commands itself, so the 120-second limit comes from
  Codex. Conversation launches pass `-c tool_timeout_sec=<seconds>` before
  `exec`; the product default is 600 seconds and can be changed with
  `CODEX_TOOL_TIMEOUT_SEC`.
- Related file:
  [codex-conversation-adapter.js](../../daemon/src/codex-conversation-adapter.js)
- Verification:

```powershell
npm test
npm run lint
```

- Last verified: 2026-05-27

## Symptom: ASR Model Download Fails With Missing `.zip.part`

- Symptom: mobile voice-model preparation fails with a missing
  `<version>.zip.part` path, or one preparation flow appears to delete or move
  the partial download while another flow is still writing it.
- Action: check for concurrent `AsrModelManager.ensureReady()` calls before
  changing archive extraction or filesystem paths. ASR model preparation must be
  single-flight: while an active preparation future is running, later callers
  should reuse that future instead of opening a second download against the same
  `.zip.part` file.
- Related file:
  [asr_model_manager.dart](../../mobile/lib/src/services/asr_model_manager.dart)
- Verification:

```powershell
cd D:\AIProject\vibe-coding\mobile
flutter test --no-pub test\asr_model_manager_test.dart -r expanded --plain-name "concurrent ensureReady calls share the active preparation"
```

- Last verified: 2026-05-27

## Symptom: Workbench Send Reports StreamSink Is Closed

- Symptom: a prompt or attachment send succeeds in daemon persistence, but
  mobile records `Bad state: StreamSink is closed` under `operation=sendMessage`
  and leaves the draft visible as a failed send.
- Action: verify persisted `conversation_events` before debugging attachment
  upload. If the user message and later assistant message are present, inspect
  mobile event subscription lifecycle. Sending to an existing conversation
  should not cancel/restart the current WebSocket event subscription; only new
  conversation navigation, acknowledgement timeout recovery, lifecycle resume,
  and approval recovery should restart it. Also check that cancelling the last
  watcher clears the cached notification socket reference before closing it, so
  a quick resubscribe cannot write `subscribe` to an already closed sink.
  Cancelling a watcher also treats `unsubscribe` writes as best-effort; if the
  socket sink is already closed, `subscription.cancel()` must still complete and
  the notification client should close/reconnect the socket path instead of
  surfacing the write failure to UI lifecycle code.
- Related files:
  [coding_workbench_page.dart](../../mobile/lib/src/ui/features/workbench/coding_workbench_page.dart),
  [workbench_view_model.dart](../../mobile/lib/src/ui/features/workbench/view_models/workbench_view_model.dart),
  [daemon_notification_client.dart](../../mobile/lib/src/services/daemon_notification_client.dart)
- Verification:

```powershell
cd D:\AIProject\vibe-coding\mobile
dart analyze lib test
flutter test --no-pub test\daemon_notification_client_test.dart -r expanded --plain-name "resubscribing after last watcher cancel waits for a fresh socket"
flutter test --no-pub test\daemon_notification_client_test.dart -r expanded --plain-name "cancel ignores unsubscribe write failures and closes current socket"
flutter test --no-pub test\widget_test.dart -r expanded --plain-name "sending existing conversation keeps current event subscription"
```

- Last verified: 2026-05-27

## Symptom: Workspace Is Missing Until Re-adding The Same Path

- Symptom: a previously created workspace is absent from the mobile workspace
  list, but adding the same folder again opens the old session list instead of
  creating an empty workspace.
- Action: inspect `workspaces` and `workspace_device_authorizations` in
  `data/app/app.sqlite`. An active row whose `owner_device_id` matches the
  device but lacks the matching authorization row is hidden by
  `GET /api/workspaces`; adding the same path calls `saveWorkspaceForDevice`,
  finds the existing owner row, and repairs authorization as a side effect.
  Startup should repair missing owner authorizations before list queries.
- Verification:

```powershell
node scripts/run-tests.js
```

- Last verified: 2026-05-25
