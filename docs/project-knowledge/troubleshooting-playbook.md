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
  arrived through event polling.
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
  transcript shows no visible file-change cards and the pending sentinel appears
  stuck during that gap.
- Action: inspect persisted `conversation_events` for `system.notice` rows with
  `noticeKind=codex_unknown_event`, `visible=0`, `raw.type=item.completed`, and
  `raw.item.type=file_change`. The Codex adapter should map completed
  `file_change` items to a visible `codex_file_change` notice with normalized
  relative paths.
- Verification:

```powershell
node scripts/run-tests.js
```

- Last verified: 2026-05-22

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
