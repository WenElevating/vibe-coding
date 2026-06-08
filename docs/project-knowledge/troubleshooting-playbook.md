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

## Symptom: Workbench Command Group Expansion Jumps Up In History

- Symptom: in an existing bottom-anchored conversation, expanding a folded
  command group makes the transcript content move upward and leaves the user
  near the bottom of the expanded command output instead of keeping the tapped
  header in place.
- Action: preserve the `ListView.builder(reverse: true)` bottom-anchor decision
  and keep the command group on the simple inline expand/collapse path for now.
  The attempted offstage measurement plus temporary translate/padding workaround
  was rejected after real-app inspection because it still produced visible
  flicker when tapped. If this is optimized later, prefer a non-height-changing
  details surface such as a bottom sheet/detail panel, or require real rendered
  visual verification before accepting a new reverse-list scroll strategy.
- Related files:
  [workbench_message_list.dart](../../mobile/lib/src/ui/features/workbench/widgets/workbench_message_list.dart),
  [codex_command_run_card.dart](../../mobile/lib/src/ui/features/workbench/messages/codex_command_run_card.dart)
- Verification:

```powershell
cd D:\AiProject\vibe-coding\mobile
flutter test --no-pub test\widget_test.dart -r expanded --plain-name command
```

- Last verified: 2026-06-05

## Symptom: Workbench Shows Completed Command As Still Running

- Symptom: a command card can show completed while the bottom pending sentinel
  still says `正在运行 command_execution...`.
- Action: inspect the full event chain before changing daemon completion logic.
  A `tool.completed` event only completes one command; the turn remains running
  until `conversation.completed` or a terminal assistant message. The pending
  status text must correlate `tool.started` and `tool.completed` by
  `toolUseId`, and send acknowledgements must not overwrite terminal state that
  arrived through the conversation event stream.
  Cached mobile conversation summaries must also project streamed terminal
  events such as `conversation.completed` and `conversation.status_changed` so
  reopening the page cannot reuse an old `running` summary after the reducer has
  already applied `idle`.
- Verification:

```powershell
cd D:\AIProject\vibe-coding\mobile
$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test --no-pub test\coding_workbench_controller_test.dart -r expanded --plain-name "pending status does not report completed tool activity"
```

- Last verified: 2026-06-07

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

## Symptom: Codex App-Server Image Upload Returns Attachment Capabilities Changed

- Symptom: sending an image in a `codex-app-server` conversation fails before
  committing `user.message` with HTTP 409 and
  `Attachment capabilities changed. Refresh adapter capabilities and retry.`
- Action: compare the `capabilityVersion` returned from `/api/adapters` with
  `ConversationManager.attachmentCapabilitiesForConversation()`. App-server
  exposes dynamic image support from `detectCapabilities()` without relying on
  `adapter.capability`, so attachment send validation must use the fresh
  detected status rather than only cached/static capability fields.
- Verification:

```powershell
node scripts/run-tests.js --grep "multipart codex-app-server image send accepts listed capabilityVersion"
```

- Last verified: 2026-06-07

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
  the visible event counter without rendering user-facing content. Do not apply
  that rule to `system/api_retry` authentication failures: a 401
  `authentication_failed` retry is meaningful user-facing progress and should
  emit one visible diagnostic, while repeated retries for the same failure stay
  persisted but hidden to avoid transcript spam.
- Related file:
  [claude-conversation-adapter.js](../../daemon/src/claude-conversation-adapter.js)
- Verification:

```powershell
node scripts/run-tests.js
npm run lint
```

- Last verified: 2026-05-29

## Symptom: Coding Tab Stays Loading CLI Or Times Out Loading Adapters

- Symptom: mobile Coding tab stays on `Loading CLI...` and then shows
  `Unable to load CLI adapters` with a 10-second `TimeoutException`.
- Action: keep the mobile adapter gate in place and inspect daemon adapter
  capability detection first. `GET /api/adapters` waits for
  `AdapterRegistry.listCapabilities()`, so one slow CLI probe can block the
  whole adapter list. Do not parse `claude --help` choices or run a
  `--permission-mode auto --print --max-turns 0` probe to discover permission
  modes; that probe can hang. Follow the Claude Agent SDK pattern instead:
  treat the product-supported mobile modes (`default`, `auto`) as a daemon
  contract and let actual conversation startup surface CLI incompatibility.
- Related files:
  [claude-adapter.js](../../daemon/src/claude-adapter.js),
  [adapter-registry.js](../../daemon/src/adapter-registry.js),
  [main_page.dart](../../mobile/lib/src/ui/main/main_page.dart)
- Verification:

```powershell
node --test daemon\test\claude-adapter.test.js
node scripts/run-tests.js
npm run lint
node scripts/check-project-knowledge.js
```

- Last verified: 2026-06-01

## Symptom: Claude Permission Request Ends Without Mobile Approval UI

- Symptom: a Claude Bash/tool card shows `This command requires approval`, then
  the conversation completes or asks the user to retry, but no actionable mobile
  approval card appears.
- Action: confirm whether Claude emitted a `control_request` with
  `request.subtype=can_use_tool`. If not, mobile cannot approve that already
  completed tool call; treat the tool result as a non-interactive permission
  failure, mark `permissionError=true`, and surface a visible system notice
  explaining that the CLI did not provide a responsive mobile approval request.
  For long-lived mobile conversations, mirror the Claude Agent SDK permission
  flow: run default permission mode with `--permission-prompt-tool stdio` and
  keep stream-json stdin open so Claude emits `control_request` frames that the
  mobile client can answer.
  Keep `--permission-prompt-tool stdio` enabled for all long-lived Claude
  conversation modes so the CLI can emit responsive control frames whenever it
  chooses to prompt, even though `auto` can still deny high-risk tools without
  prompting.
  The mobile settings default should remain `default`; `auto` is an explicit
  non-interactive mode for users who accept classifier denials instead of phone
  approval prompts.
  If Claude later sends `control_cancel_request` for a pending approval or
  `AskUserQuestion`, clear the blocking card with `blocking.request_cancelled`
  and restore the conversation to `running`.
  Claude `auto` mode classifier denials can also arrive only as ordinary
  `tool_result` text beginning `Permission for this action was denied`; these
  are not actionable approval requests and must be classified the same way.
- Related file:
  [claude-conversation-adapter.js](../../daemon/src/claude-conversation-adapter.js)
- Verification:

```powershell
node scripts/run-tests.js
npm run lint
```

- Last verified: 2026-05-30

## Symptom: Claude AskUserQuestion Suggestion Leaves Send Disabled Or Returns 409

- Symptom: a mobile Claude conversation shows an `AskUserQuestion`/question card
  with suggestion chips, but tapping a suggestion fills the composer while the
  send button stays disabled. A later send can fail with
  `ConversationRepositoryException(409, conversation is not waiting for input response)`.
- Action: inspect both composer state and pending-question state before changing
  daemon response handling. `waiting_input` is an active conversation status but
  it must still allow the composer to send an input response. Suggestion chips
  must trigger a widget rebuild after writing the `TextEditingController`, and
  the pending question id should come from the current conversation
  `blockingItem` only, not from stale historical question messages.
- Related files:
  [coding_workbench_controller.dart](../../mobile/lib/src/ui/features/workbench/coding_workbench_controller.dart),
  [coding_workbench_page.dart](../../mobile/lib/src/ui/features/workbench/coding_workbench_page.dart),
  [workbench_view_model.dart](../../mobile/lib/src/ui/features/workbench/view_models/workbench_view_model.dart)
- Verification:

```powershell
cd D:\AIProject\vibe-coding\mobile
$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test --no-pub test\coding_workbench_controller_test.dart test\adapter_model_test.dart --plain-name "pending"
flutter test --no-pub test\widget_test.dart --plain-name "question suggestion enables and sends an input response"
```

- Last verified: 2026-05-30

## Symptom: Claude Plan Mode Exit Or Session Open Looks Stuck

- Symptom: Claude Code plan mode shows an `ExitPlanMode` tool card with
  `Exit plan mode?`, but no obvious mobile action is available. Separately,
  tapping a historical session from the session list can appear to do nothing
  if stored event fetch or WebSocket setup is slow.
- Action: inspect persisted Claude `tool.output` / `tool.completed` rows and
  `result.permission_denials` before treating this as a generic approval UI
  bug. `ExitPlanMode` can arrive as a tool denial rather than a
  `control_request`; mobile should remap that prompt to a question card and
  hide the failed tool card. Session navigation should enter the conversation
  detail route before awaiting historical event backfill, then surface backfill
  failures inside the detail page.
- Related files:
  [claude-conversation-adapter.js](../../daemon/src/claude-conversation-adapter.js),
  [conversation_reducer.dart](../../mobile/lib/src/ui/features/workbench/conversation_reducer.dart),
  [coding_workbench_page.dart](../../mobile/lib/src/ui/features/workbench/coding_workbench_page.dart)
- Verification:

```powershell
node scripts/run-tests.js
cd mobile
flutter test --no-pub test\widget_test.dart --plain-name "ExitPlanMode prompt becomes a question instead of a failed tool card"
flutter test --no-pub test\widget_test.dart --plain-name "opening existing conversation navigates before history returns"
```

- Last verified: 2026-05-30

## Symptom: Claude Task Updates Or Question Suggestions Feel Stuck

- Symptom: Claude Code `TaskCreate` / `TaskUpdate` rows appear as generic
  tool cards instead of a task progress table, or tapping a question suggestion
  only fills the composer and still requires a separate send tap. A visible
  question card can also be followed by a failed `AskUserQuestion` tool card
  with output such as `Answer questions?`, and legacy persisted `TaskCreate`
  rows can remain as repeated `running` tool cards.
- Action: keep Claude task tools out of the generic `tool.started` /
  `tool.output` card path. The daemon should aggregate `TaskCreate` and
  `TaskUpdate` into `task.progress.updated` with `source=claude` as soon as the
  tool starts, while mobile consumes the existing task progress reducer/card.
  Mobile replay should also suppress legacy `AskUserQuestion`, `TaskCreate`,
  and `TaskUpdate` tool cards because older persisted events cannot be rewritten.
  If later updates regress to `Task #N`, check whether Claude resumed after the
  adapter lost its in-memory task map or whether a subagent emitted a bare
  `TaskUpdate`. Seed restarted Claude adapters from prior `task.progress.updated`
  rows, preserve non-fallback titles when replaying/merging progress, and use
  Claude `task_description` as a fallback title before showing `Task #N`.
  For question suggestions, if the active conversation has a `pendingQuestionId`,
  the chip should call `answerConversationQuestion` immediately; only fall back
  to composer fill when there is no pending question context.
- Related files:
  [claude-conversation-adapter.js](../../daemon/src/claude-conversation-adapter.js),
  [coding_workbench_page.dart](../../mobile/lib/src/ui/features/workbench/coding_workbench_page.dart),
  [conversation_reducer.dart](../../mobile/lib/src/ui/features/workbench/conversation_reducer.dart)
- Verification:

```powershell
node scripts/run-tests.js
cd mobile
flutter test --no-pub test\widget_test.dart --plain-name "question suggestion immediately sends an input response"
flutter test --no-pub test\conversation_reducer_test.dart
dart analyze lib test
```

- Last verified: 2026-05-31

## Symptom: Claude WebSearch Looks Stuck

- Symptom: mobile keeps showing a `WebSearch` tool as searching for minutes,
  even though the actual search call may have returned or another search call
  completed normally.
- Action: inspect persisted `conversation_events` grouped by `toolUseId`.
  If multiple Claude `control_request` frames arrive while one blocking item is
  active, the second approval must be queued rather than dropped. A dropped
  approval leaves Claude waiting for a `control_response` until its permission
  stream times out, making the UI look like web search itself is stuck.
- Related file:
  [conversation-manager.js](../../daemon/src/conversation-manager.js)
- Verification:

```powershell
npm test
npm run lint
```

- Last verified: 2026-05-31

## Symptom: Android Update Download Shows No Progress Or Offers Download Again

- Symptom: after tapping app update download, the mobile UI opens a blocking
  download dialog but only shows an indeterminate progress bar, so users cannot
  tell whether the APK is moving or stalled. After the APK is downloaded and
  verified, checking for updates can also regress the row to "download" instead
  of offering install.
- Action: keep progress wired through the whole private update chain. The
  downloader should emit byte progress while writing response chunks, the
  workflow should pass the optional progress callback through, the ViewModel
  should store `downloadedBytes`/`totalBytes`, and `AppUpdatePanel` should bind
  `LinearProgressIndicator.value` plus a percentage/byte label from that state.
  The UI download action should call `download(installWhenReady: true)` so a
  ready APK immediately opens the installer path, while non-UI callers can still
  stop at `readyToInstall`. Update checks should call
  `readDownloadedUpdate(manifest)` before writing `available`; a verified cached
  APK for the same manifest should leave state at `readyToInstall`.
- Related files:
  [app_update_download_manager.dart](../../mobile/lib/src/services/app_update_download_manager.dart),
  [app_update_workflow.dart](../../mobile/lib/src/workflows/app_update_workflow.dart),
  [settings_page.dart](../../mobile/lib/src/ui/features/settings/settings_page.dart),
  [app_update_view_model.dart](../../mobile/lib/src/ui/features/settings/view_models/app_update_view_model.dart),
  [app_update_panel.dart](../../mobile/lib/src/ui/features/settings/widgets/app_update_panel.dart)
- Verification:

```powershell
cd D:\AIProject\vibe-coding\mobile
flutter test --no-pub test\app_update_download_manager_test.dart
flutter test --no-pub test\app_update_view_model_test.dart
flutter test --no-pub test\widget_test.dart --plain-name "app update download dialog shows determinate progress"
flutter test --no-pub test\widget_test.dart --plain-name "app update"
```

- Last verified: 2026-05-30

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

## Symptom: Active Conversation Reopen Loses Or Misapplies Pending Animation

- Symptom: reopening an active conversation after daemon disconnect either
  hides the running transition while history is stalled, or shows it forever
  after historical events prove the turn already completed.
- Action: inspect the initial conversation event page path, not only the live
  stream reducer. Historical page replacement must apply status events back to
  the active `ConversationSummary`; the UI may delay pending briefly for stale
  summaries, but should reveal it for active sessions when history remains
  unavailable. When the user sends a new turn, clear any initial-history
  loading gate first; otherwise one daemon disconnect can suppress pending UI
  for every later turn in the same conversation.
- Related files:
  [coding_workbench_page.dart](../../mobile/lib/src/ui/features/workbench/coding_workbench_page.dart),
  [workbench_view_model.dart](../../mobile/lib/src/ui/features/workbench/view_models/workbench_view_model.dart)
- Verification:

```powershell
cd D:\AIProject\vibe-coding\mobile
flutter test --no-pub test\widget_test.dart --plain-name "opening stale active conversation waits for history before pending animation"
flutter test --no-pub test\widget_test.dart --plain-name "opening active conversation reveals pending animation when history stalls"
flutter test --no-pub test\widget_test.dart --plain-name "existing conversation send can recover pending animation after daemon disconnect"
```

- Last verified: 2026-05-31

## Symptom: CLI Command Kills The Mobile Daemon

- Symptom: an agent tries to clean up an "old server" on port `4317` with
  `taskkill`/`kill`, and the mobile app immediately gets connection refused
  errors because `4317` is the daemon API port.
- Action: protect the daemon at multiple layers. Claude stdio permission
  requests should deny shell kill commands that reference the daemon PID or
  port, and `start-daemon.bat` should run the Node process under its watchdog so
  an unexpected child exit restarts the service. This does not protect a batch
  parent that is killed explicitly.
- Related files:
  [daemon-self-protection.js](../../daemon/src/daemon-self-protection.js),
  [claude-conversation-adapter.js](../../daemon/src/claude-conversation-adapter.js),
  [start-daemon.bat](../../start-daemon.bat)
- Verification:

```powershell
npm test
npm run lint
```

- Last verified: 2026-05-31

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

## Symptom: Codex App Server Model List Only Shows Default Model

- Symptom: the mobile model picker for `codex-app-server` only shows
  `default model` even when Codex config contains selectable models.
- Action: inspect `/api/adapters` enrichment before changing mobile UI. The
  adapter registry only exposes model choices from `getModelCapability()` or
  status model metadata. `codex-app-server` availability probes must stay cheap
  and avoid app-server model-list RPCs; model choices should come from the same
  local Codex model discovery path as the CLI adapter.
- Related file:
  [codex-app-server-listing-adapter.js](../../daemon/src/codex-app-server-listing-adapter.js)
- Verification:

```powershell
node scripts/run-tests.js
npm run lint
```

- Last verified: 2026-06-04

## Symptom: Codex App Server Reopened Conversation Loses Tool Cards

- Symptom: a live `codex-app-server` turn shows tool cards, but leaving and
  reopening the conversation only shows the final assistant answer.
- Action: first inspect persisted `conversation_events` to distinguish storage
  loss from replay projection. Long app-server turns can emit many
  `assistant.partial` rows; a tail page can then contain only dense partials
  plus the final answer, pushing earlier `user.message`, `tool.started`, and
  `tool.completed` rows outside the first page. Historical open should fetch
  every earlier page up front instead of relying on upward scroll pagination.
  Compact historical `assistant.partial` runs before rebuilding the mobile event
  window so full-history loading does not inflate the transcript with invisible
  partial chunks.
- Related file:
  [workbench_view_model.dart](../../mobile/lib/src/ui/features/workbench/view_models/workbench_view_model.dart)
- Verification:

```powershell
cd mobile
flutter test --no-pub test\workbench_view_model_repository_state_test.dart -r expanded --plain-name "initial event page expands past dense partial tail to keep command context"
flutter test --no-pub test\workbench_view_model_repository_state_test.dart -r expanded --plain-name "initial event page keeps expanding dense partial history until user context is visible"
flutter test --no-pub test\workbench_view_model_repository_state_test.dart -r expanded --plain-name "initial event pages compact dense assistant partials"
flutter test --no-pub test\widget_test.dart -r expanded --plain-name "opening large historical conversation loads every history page"
```

- Last verified: 2026-06-06

## Symptom: Reopened Workbench History Shows Blank Before Appearing

- Symptom: tapping a historical conversation navigates to the transcript route,
  then shows a blank message area before the history suddenly appears.
- Action: keep full-history expansion for reopened conversations, but render
  the first fetched event page before fetching older pages. Older pages should
  continue loading immediately in the background, then apply the completed
  backfill in one transcript rebuild instead of rebuilding after every
  `hasMoreBefore` page. If this regresses, inspect
  `WorkbenchViewModel.loadInitialConversationEventPage` and ensure the page
  applies the tail page before `_expandInitialConversationHistory` continues.
- Related file:
  [workbench_view_model.dart](../../mobile/lib/src/ui/features/workbench/view_models/workbench_view_model.dart)
- Verification:

```powershell
cd D:\AiProject\vibe-coding\mobile
flutter test --no-pub test\widget_test.dart -r expanded --plain-name "opening paged conversation shows tail before older pages finish"
flutter test --no-pub test\widget_test.dart -r expanded --plain-name "opening large historical conversation loads every history page"
```

- Last verified: 2026-06-06

## Symptom: Codex App Server History Shows Maximum Process Limit Error

- Symptom: the mobile Codex app-server History, Discovery, or Risk Control page
  shows `DaemonClientException(500, ... maximum Codex app-server process limit
  reached ...)` instead of a controlled busy state or route data.
- Action: inspect the boundary between `CodexAppServerService` pool limits and
  the shared `CodexAppServerLifecycle` max process limit. The service uses
  physically separated discovery, conversation, and mutation pools; the
  lifecycle global limit must be at least the sum of those default pool
  capacities. If the lifecycle is left at its historical default of 1, the first
  active app-server process can make unrelated read-only History/Discovery
  requests fail with a raw lifecycle error.
- Related files:
  [main.js](../../daemon/src/main.js),
  [service.js](../../daemon/src/codex-app-server/service.js)
- Verification:

```powershell
node scripts/run-tests.js --plain-name "Codex app-server lifecycle default limit covers isolated service pools"
npm run lint
```

- Last verified: 2026-06-05

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

## Symptom: Mobile Downloads Stop After App Backgrounding

- Symptom: ASR model or Android update downloads pause/fail when the app is sent
  to the background.
- Action: keep byte transfers in the Android foreground download service and
  let Dart workflows verify/promote the completed `.part` file on resume. The
  Dart download managers still own checksum validation, metadata promotion, and
  ASR extraction. Do not treat denied `POST_NOTIFICATIONS` permission as a hard
  blocker for starting the foreground download service; Android still permits
  foreground service launch without that runtime notification grant, though the
  notification drawer entry may be hidden. If the native foreground service
  fails to start or reports `failed`, fall back to the original Dart foreground
  download path instead of surfacing `paused` immediately. Re-read the actual
  `.part` length before the fallback so any bytes written by the native service
  resume from the correct offset. The Android app must also allow cleartext
  traffic because the private daemon/update channel is LAN HTTP. If app update
  download still reaches `paused` or `failed`, keep the progress dialog open and
  show `errorMessage`; do not auto-dismiss the only visible failure reason.
- Related files:
  [BackgroundDownloadService.kt](../../mobile/android/app/src/main/kotlin/com/example/lan_ai_cli_control/BackgroundDownloadService.kt),
  [background_download_bridge.dart](../../mobile/lib/src/services/background_download_bridge.dart),
  [method_channel_background_download_bridge.dart](../../mobile/lib/src/services/method_channel_background_download_bridge.dart),
  [app_update_download_manager.dart](../../mobile/lib/src/services/app_update_download_manager.dart),
  [asr_model_manager.dart](../../mobile/lib/src/services/asr_model_manager.dart)
- Verification:

```powershell
cd mobile
flutter test --no-pub test\background_download_bridge_test.dart
flutter test --no-pub test\asr_model_manager_test.dart
flutter test --no-pub test\app_update_download_manager_test.dart
flutter test --no-pub test\app_update_panel_test.dart
node scripts/run-tests.js
flutter build apk --debug
```

- Last verified: 2026-05-31

## Symptom: Android Update Stuck On Confirm Install After Background Download

- Symptom: an Android update download finishes while the app is in the
  background; returning to the app shows "confirm install update" in the
  Flutter progress dialog, but the Android installer confirmation page never
  appears. Restarting the app can restore the same confirm state repeatedly.
- Action: do not start `PackageInstaller.Session` from a background
  `installWhenReady` completion. Track app lifecycle in `AppUpdateViewModel`,
  defer automatic install until `resumed`, and treat recovered
  `pendingUserAction` sessions as non-replayable: clear the persisted
  `installSessionId` and return to `readyToInstall` so the user can retry from
  the foreground.
- Related files:
  [main_page.dart](../../mobile/lib/src/ui/main/main_page.dart),
  [app_update_view_model.dart](../../mobile/lib/src/ui/features/settings/view_models/app_update_view_model.dart),
  [app_update_panel.dart](../../mobile/lib/src/ui/features/settings/widgets/app_update_panel.dart)
- Verification:

```powershell
cd D:\AiProject\vibe-coding\mobile
flutter test --no-pub test\app_update_view_model_test.dart -r expanded
flutter test --no-pub test\widget_test.dart -r expanded --plain-name "app update"
dart analyze lib test
```

- Last verified: 2026-06-01

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

## Symptom: Newly Created Workspace Disappears After Tab Switch

- Symptom: after creating a workspace from the mobile Coding tab, the app opens
  that workspace's session list. Switching to Settings and back to Coding makes
  the new workspace disappear from the in-memory workspace list, but restarting
  the app shows it again.
- Action: inspect the boundary between `WorkbenchViewModel` and
  `MainShellViewModel`. Workspace creation refreshes the daemon workspace
  catalog in the workbench flow; the refreshed catalog must also be written back
  to `MainShellViewModel.data`. Otherwise `CodingWorkbenchPage.didUpdateWidget`
  can rebuild from a stale `AppSnapshot` during a tab round trip and overwrite
  the workbench route state with the old workspace list.
- Verification:

```powershell
cd D:\AIProject\vibe-coding\mobile
$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test --no-pub test\widget_test.dart --plain-name "created workspace remains listed after settings tab round trip"
flutter test --no-pub test\main_shell_view_model_test.dart --plain-name "updates workspace catalog"
```

- Last verified: 2026-05-28

## Symptom: Cancelled Conversation Still Changes After Resend Or Slow Startup

- Symptom: after cancelling a conversation and sending again, a late event from
  the old adapter process can fail or complete the new turn. A related startup
  race can let a slow `startConversation()` return after cancel and dispatch a
  user message through a handle that should no longer be active.
- Action: keep adapter callback ownership in `ConversationManager`. Scope
  adapter events to the handle that was adopted by the conversation, drop
  startup events after the conversation leaves `running`, and dispose late
  startup handles instead of adopting or sending through them.
- Related file:
  [conversation-manager.js](../../daemon/src/conversation-manager.js)
- Verification:

```powershell
node scripts/run-tests.js --plain-name "conversation manager ignores stale events from a replaced handle after cancel and resend"
node scripts/run-tests.js --plain-name "conversation cancel during adapter startup does not adopt or dispatch late handle"
```

- Last verified: 2026-06-08

## Symptom: Missing Selected Workspace Shows Stale Scoped Data

- Symptom: mobile starts connected with no selected workspace, but old
  conversation, run, or Codex app-server data from a previous workspace remains
  visible until a manual refresh or restart.
- Action: treat absent selected workspace as an explicit scope transition.
  Bootstrap should clear workspace-scoped conversation/run caches, preserve the
  global workspace catalog, and invalidate in-flight Codex app-server loads.
- Related files:
  [bootstrap_hydration.dart](../../mobile/lib/src/data/repositories/bootstrap_hydration.dart),
  [open_workspace_use_case.dart](../../mobile/lib/src/workflows/connection/open_workspace_use_case.dart),
  [codex_app_server_view_model.dart](../../mobile/lib/src/ui/features/codex_app_server/view_models/codex_app_server_view_model.dart)
- Verification:

```powershell
cd D:\AIProject\vibe-coding\mobile
flutter test --no-pub test\open_workspace_use_case_test.dart test\connected_repository_bootstrap_test.dart -r expanded
flutter test --no-pub test\codex_app_server_view_model_test.dart -r expanded
```

- Last verified: 2026-06-08

## Symptom: Cancelled Queued Run Leaves Gaps Or Stale Queue Rows

- Symptom: cancelling a queued run removes or cancels that run, but remaining
  queue positions keep old numbers or the mobile queue keeps showing the
  cancelled item until a full refresh.
- Action: compact daemon queue positions after queued cancellation and apply the
  same mutation to the mobile cached run queue projection.
- Related files:
  [run-queue.js](../../daemon/src/run-queue.js),
  [cached_run_repository.dart](../../mobile/lib/src/data/repositories/cached_run_repository.dart)
- Verification:

```powershell
node scripts/run-tests.js --plain-name "run queue renumbers workspace positions after queued cancellation"
cd D:\AIProject\vibe-coding\mobile
flutter test --no-pub test\cached_connected_repositories_test.dart -r expanded --plain-name "cancelRun removes cancelled queued run from cached queue"
```

- Last verified: 2026-06-08

## Symptom: Diagnostic Bundle Redacts Keys But Leaks Secret Values

- Symptom: exported diagnostics redact sensitive object keys, but exception
  strings such as `message`, `stack`, `path`, or nested metadata can still
  contain bearer tokens, `sk-*` secrets, or sensitive URL query parameters.
- Action: diagnostic export redaction must scrub both object keys and string
  values before packaging recent errors or exception metadata.
- Related file:
  [diagnostic-bundle.js](../../daemon/src/diagnostic-bundle.js)
- Verification:

```powershell
node scripts/run-tests.js --plain-name "exceptions are persisted with trace ids and exported in diagnostics"
```

- Last verified: 2026-06-08
