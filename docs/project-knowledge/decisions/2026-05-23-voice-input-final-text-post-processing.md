# Decision: Voice Input Post-Processing Is Final-Text Only

- Status: accepted
- Date: 2026-05-23
- Last verified: 2026-05-23

## Context

The mobile app uses sherpa-onnx for local ASR and shows partial recognition
while the user is speaking. Raw ASR output often lacks Chinese punctuation and
can mis-capitalize coding terms such as Codex, Flutter, Git, and README.

A proposed daemon-side MacBERT correction path would add a large server-side
model and correct Chinese spelling, but it does not directly solve punctuation
restoration and would increase daemon dependency and packaging complexity.

## Decision

Speech text post-processing belongs in the mobile voice-input finalization
path. It runs only after `SpeechInputService.stop()` returns final text and
before `VoiceInputController` merges voice text into the prompt.

Partial recognition remains raw so the live preview does not jump or rewrite
while the user is speaking. The first implementation is conservative: normalize
common coding terms, add simple Chinese punctuation, and avoid semantic
rewrites.

Final and partial voice text are merged at the captured text cursor without
inserting an automatic newline. If the user wants a new line, the prompt should
already contain that line break before voice input is appended.

## Alternatives

- Daemon-side MacBERT CSC: rejected for the first implementation because it is
  heavier, primarily fixes spelling rather than punctuation, and expands the
  CommonJS daemon dependency surface.
- LLM rewrite: deferred behind an explicit future setting because it introduces
  privacy, latency, and over-rewrite risks.
- Offline punctuation model: deferred until the local rule-based finalizer is
  measured against real voice samples.

## Evidence

- `mobile/lib/src/services/speech_text_post_processor.dart`
- `mobile/lib/src/ui/features/workbench/voice_input_controller.dart`
- `mobile/test/speech_text_post_processor_test.dart`
- `mobile/test/voice_input_controller_test.dart`

## Verification

Target command attempted on 2026-05-23 but timed out in the agent environment:

```powershell
cd D:\AIProject\vibe-coding\mobile
$env:NO_PROXY='localhost,127.0.0.1,::1'
$env:no_proxy='localhost,127.0.0.1,::1'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test --no-pub test\speech_text_post_processor_test.dart test\voice_input_controller_test.dart -r expanded
```

`git diff --check` passed on 2026-05-23.

## Re-Evaluate When

- The user collects a small ASR evaluation set showing the rule-based finalizer
  is not enough.
- sherpa-onnx punctuation models are packaged and benchmarked for the app.
- A user-controlled LLM correction setting is introduced with timeout and
  privacy handling.
