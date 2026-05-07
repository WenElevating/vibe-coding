# Voice Input STT Design

## Problem

Coding 对话页当前只支持文本输入。移动端长文本输入成本高，用户需要一种语音转文本的输入方式：按住说话后识别为文字，并进入现有发送流程。

本设计聚焦 STT/ASR（speech-to-text，语音转文字）。用户原文提到的 TTS 在语音领域通常表示 text-to-speech（文字转语音），不属于本阶段目标。

## Goals

- Composer 支持两种输入方式：文本输入和语音输入转文本。
- 语音识别结果先填入现有输入框，由用户确认后点击发送。
- 语音 UI 参考常见移动端输入体验：麦克风入口、按住说话状态、实时识别文本、松手结束。
- 语音识别优先离线运行，避免把用户语音上传到第三方服务。
- 语音实现和发送逻辑解耦，复用当前 `_sendPrompt()`。

## Non-Goals

- 不做文字转语音朗读回复。
- 不做自动发送作为默认行为，避免误识别直接提交。
- 不做云端 ASR 服务。
- 不在第一阶段实现唤醒词、连续免按住对话、语音打断、标点润色或 LLM 纠错。
- 不要求本阶段解决模型下载分发策略；先按 bundled assets 设计，后续可独立演进为首次启动下载。

## External References

- Local project note: `docs/flutter_speech_to_text.md`
- `sherpa_onnx`: Flutter package supports local ASR/STT and streaming recognition across mobile/desktop platforms.
- `record`: Flutter package supports microphone recording to stream, including `pcm16bits` stream mode.
- `permission_handler`: Flutter package for requesting microphone permission where platform APIs require it.

## Recommended Approach

Use a dual-mode composer with one source of truth: the existing `TextEditingController`.

1. Text input remains unchanged.
2. A microphone button starts voice input.
3. While recording, partial recognition text updates the same text controller.
4. Releasing the microphone stops recording and leaves recognized text in the input box.
5. User taps the existing send button to submit.

This keeps send behavior predictable and preserves all current validation: selected adapter, running/cancel state, empty prompt checks, workspace checks, and traceable send errors.

## UI Design

### Idle Text Mode

- Keep the current text field as the primary composer surface.
- Replace one of the unused composer icons with a microphone action.
- The send button remains the only submit affordance.
- If the input is empty, the microphone action is visually available.
- If the input has text, recognized voice text appends to the end of the current input.

### Recording Mode

- Press-and-hold microphone starts recording.
- Composer switches to a recording state:
  - prominent mic indicator,
  - “Listening…” / “松开结束” helper text,
  - subtle animated pulse or active color,
  - partial recognized text shown in the text field.
- Release stops recording and returns to idle mode.
- If recognition text is empty, keep existing text unchanged and show a small failure/empty hint.

### Text Merge Policy

Default policy: append voice text to the end of the existing input. If the input is non-empty, insert one newline before the recognized text. If the input is empty, insert the recognized text directly.

The append target is always the end of the text, not the current cursor position. After merge, place the cursor at the end. This matches Coding prompts where a dictated follow-up is often a new instruction, command, or context block.

Rationale: users may type context first and then dictate the rest. This avoids destructive replacement and avoids surprising mid-text insertions when the cursor happens to be in the middle.

Future option: add “replace current text” as a long-press menu or setting if users ask for it.

## State Model

Add voice state above the composer, owned by `CodingWorkbenchPageState` or a small controller owned by that state.

Proposed states:

- `idle`: no active voice input.
- `initializing`: loading recognizer or requesting permission.
- `listening`: recording microphone stream and decoding partial text.
- `stopping`: normal stop; finalize recognition and merge text into the prompt.
- `cancelling`: interrupted or intentionally cancelled stop; stop recorder and discard uncommitted partial text.
- `failed`: recoverable error, shown inline/snackbar.

Key fields:

- `VoiceInputState _voiceState`
- `String _voicePartialText`
- `String _voiceBaseText` captured when recording starts
- `String? _voiceError`
- `SpeechInputService _speechInputService`

The existing `_prompt` remains the only text submitted by `_sendPrompt()`.

## Speech Service Design

Create a bounded service, for example `mobile/lib/src/services/speech_input_service.dart`.

Responsibilities:

- Lazily initialize sherpa-onnx recognizer once on the first microphone press.
- Request/check microphone permission.
- Start `record` microphone stream as 16 kHz mono PCM16.
- Convert `Uint8List` PCM16 bytes to float samples.
- Feed samples into sherpa-onnx streaming recognizer.
- Emit partial/final text via callbacks or stream.
- Stop/cancel recording and dispose native resources.
- Guard against concurrent starts so rapid mic taps cannot create multiple recognizers or recorder streams.

The service should not know about workspaces, conversations, adapters, or sending messages.

Initialization policy: use lazy initialization on first microphone interaction. While initializing, show the recording surface in an initializing state and allow cancellation. If recognizer initialization takes longer than 5 seconds, fail with a recoverable “voice input unavailable” state and keep text input enabled. Subsequent mic attempts may retry initialization.

## Dependencies

Add mobile dependencies after implementation approval:

```yaml
record: ^6.2.0
sherpa_onnx: ^1.12.36
permission_handler: ^12.0.1
```

Version notes:

- The local note references `record: ^6.1.1` and `sherpa_onnx: ^1.13.0`; current pub.dev search showed `record 6.2.0` and `sherpa_onnx 1.12.36` as available package versions. Implementation should verify exact resolvable versions with `flutter pub add` or `flutter pub get` before committing dependency constraints.
- No new dependency should be added outside `mobile/pubspec.yaml`.

## Platform Configuration

Android:

- Add `android.permission.RECORD_AUDIO`.
- Keep `INTERNET` only if already needed by the app; offline STT itself should not require network.

iOS:

- Add `NSMicrophoneUsageDescription` if iOS target is supported.

Windows:

- The app currently builds Windows debug. Until manually verified, Windows should not present voice input as a working feature. Prefer hiding the mic button on Windows; if platform detection is not convenient in the first patch, render it disabled with a tooltip/helper text: “Voice input is not available on this platform yet.”

## Model Assets

Model distribution is a blocking implementation decision. Before adding STT code that depends on a concrete asset path, implementation must inspect the selected model size and choose one distribution strategy.

The likely bundled candidate is a sherpa-onnx streaming bilingual zh/en model under:

```text
mobile/assets/models/sherpa-onnx-streaming-zipformer-bilingual-zh-en/
  encoder.onnx
  decoder.onnx
  joiner.onnx
  tokens.txt
```

Register assets in `mobile/pubspec.yaml` only for the model directory required by implementation.

Risks:

- A bilingual streaming Zipformer model is expected to add roughly 50?150 MB, so package size impact is significant rather than hypothetical.
- Large model files may exceed normal Git hosting limits such as the common 100 MB single-file limit.
- Do not commit model files blindly. If the selected model is too large for the repository, choose documented manual placement or first-run download before implementing asset-path-dependent code.

Blocking decision before implementation:

1. Identify the exact model package and file sizes.
2. Decide one distribution path: bundled assets, manual local assets for development, or runtime download.
3. Only then wire `pubspec.yaml` assets and service model paths.

## Error Handling

- Permission denied: request permission only when the user presses the mic. If denied, show inline message near composer and keep text mode usable. On repeated attempts after a permanent denial, guide the user to system settings instead of repeatedly showing the OS prompt.
- Model missing/init failed: disable mic button and show “voice input unavailable”.
- Recording failure: stop recording, keep any existing text, discard uncommitted partial text, show recoverable error.
- Recognition empty: do not send; keep composer open and show “未识别到内容”.

Errors should not use the conversation exception table unless they occur inside message send/poll paths. Voice input errors are local UI/service errors and should be visible without polluting daemon exception traces.

## Lifecycle and Concurrency

- App backgrounding, phone calls, route changes, or composer disposal while listening should force a transition to `cancelling`, stop the recorder, and preserve only the text that was committed before recording began.
- A normal pointer release transitions to `stopping` and may merge final recognized text.
- State transitions must be serialized: `initializing`, `listening`, `stopping`, and `cancelling` reject additional start attempts.
- If the active route leaves conversation detail while recording, cancel recording rather than keeping the microphone active in the background.

## Recognition Language

Use the bilingual zh/en model in its automatic bilingual mode if supported by the selected model/runtime. Do not add a language picker in the first phase. If implementation discovers the chosen sherpa-onnx model requires an explicit language setting, default to Chinese-first bilingual behavior and document the limitation in the plan before coding.

## Accessibility and Safety

- Mic button needs semantic label: “Voice input”.
- Recording state needs clear visual affordance and release/cancel instructions.
- No auto-send in first phase.
- Existing typed text must not be discarded by a failed voice session.

## Testing Plan

Unit/widget tests should avoid real microphone and native ASR.

- Add an injectable speech service interface/fake.
- Widget test: mic partial text updates the existing composer text.
- Widget test: releasing voice input does not call `onSend` automatically.
- Widget test: typed text plus voice text appends at the end with a newline separator instead of replacing.
- Widget test: cancellation/background-style interruption discards uncommitted partial text.
- Widget test: initializing/listening ignores duplicate start attempts.
- Service unit test: PCM16 byte conversion handles little-endian samples.
- Existing composer send tests remain valid because `_sendPrompt()` still reads `_prompt.text`.

Manual checks after implementation:

- Android: grant/deny microphone permission.
- Android: press-hold-release records and fills text.
- Android: deny permission, then retry and verify settings guidance.
- Android: background app while recording and verify recorder stops.
- Windows debug: app still builds; mic button is hidden or disabled until support is verified.

## Open Implementation Decisions

- Whether press-and-hold should support slide-to-cancel in the first implementation. The state machine already reserves `cancelling` either way.
- Whether Windows support should be enabled after manual verification or remain disabled for the first release.

## Blocking Implementation Decisions

- Model distribution must be decided before adding service code that assumes a model asset path. The implementation plan must start with model size inspection and distribution choice.

## Acceptance Criteria

- Text input still works exactly as before.
- Composer exposes a microphone voice input affordance.
- Holding the mic starts voice recognition after permission is granted.
- Recognized speech appears in the existing text input, appended at the end with a newline separator when typed text already exists.
- Releasing the mic stops recording and does not auto-send.
- User can edit recognized text before sending.
- Send button sends recognized text through the existing conversation flow.
- Permission/model/recording failures do not break text input.
- Lazy recognizer initialization times out after 5 seconds and surfaces a recoverable UI error.
- Duplicate mic starts cannot create multiple active recorder streams.
- Backgrounding or navigating away during recording stops the microphone and does not commit partial text.
- Windows voice UI is hidden or disabled until the platform is manually verified.
