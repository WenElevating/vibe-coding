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
