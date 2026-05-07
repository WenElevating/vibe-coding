# Voice Input STT Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a mobile composer voice-input path that turns speech into editable prompt text while preserving the existing explicit send flow.

**Architecture:** Keep `TextEditingController` as the single source of prompt text. Add a pure Dart voice controller/service seam around the composer so UI behavior is testable without native microphone/ASR. Add the real `record + sherpa_onnx + permission_handler` service only after model distribution is decided; Windows remains hidden/disabled until manually verified.

**Tech Stack:** Flutter/Dart, `record`, `sherpa_onnx`, `permission_handler`, `CodingWorkbenchPage`, `CodingComposer`, Flutter widget tests.

---

## Pre-Flight Notes

- Current working tree contains unrelated nested-navigation Flutter changes. Do not commit, revert, or mix them into voice-input commits unless the user explicitly asks.
- `docs/` is ignored by `.gitignore`; force-add this plan when committing.
- The mobile tree currently has Android, web, and Windows targets. There is no `mobile/ios/Runner/Info.plist`, so iOS permission work is out of scope for this repository state.
- The spec is `docs/superpowers/specs/2026-05-07-voice-input-stt-design.md`.

## File Structure

- Create `mobile/lib/src/features/workbench/voice_input.dart`: export voice input abstractions.
- Create `mobile/lib/src/features/workbench/voice_input_controller.dart`: pure Dart state machine, merge policy, duplicate-start guard, cancellation behavior.
- Create `mobile/lib/src/services/speech_input_service.dart`: native service using `record`, `sherpa_onnx`, and `permission_handler`.
- Modify `mobile/lib/src/features/workbench/coding_composer.dart`: microphone button, recording status, disabled UI.
- Modify `mobile/lib/src/features/workbench/coding_workbench_page.dart`: own controller, pass state/callbacks, cancel on route/dispose/lifecycle changes.
- Modify `mobile/lib/src/features/workbench/workbench.dart`: export voice input types.
- Modify `mobile/lib/src/testing/debug_helpers.dart`: update preview constructor calls.
- Modify `mobile/pubspec.yaml` and `mobile/pubspec.lock`: add speech dependencies after model decision.
- Modify `mobile/android/app/src/main/AndroidManifest.xml`: add microphone permission.
- Test `mobile/test/voice_input_controller_test.dart`: pure controller behavior.
- Test `mobile/test/speech_input_service_test.dart`: PCM conversion only; no microphone/model required.
- Test `mobile/test/widget_test.dart`: composer UI and no-auto-send behavior.

---

### Task 1: Resolve Model Distribution Blocker

**Files:**
- Modify: `docs/superpowers/plans/2026-05-07-voice-input-stt.md`
- Inspect: `docs/flutter_speech_to_text.md`
- Inspect: selected sherpa-onnx model directory if available

- [ ] **Step 1: Inspect model availability and size**

Run if a local model exists:

```powershell
Get-ChildItem -Recurse -File D:\path\to\sherpa-onnx-streaming-zipformer-bilingual-zh-en | Select-Object FullName,Length
```

Run if no model exists:

```powershell
Write-Output "No local sherpa-onnx model is present; use manual local assets for development and keep runtime UI disabled until model files are installed."
```

Expected: concrete file sizes or a concrete “no local model” decision.

- [ ] **Step 2: Choose distribution path**

Decision rule:

```text
If any model file is > 95 MB or total model size is > 80 MB, choose manual local assets for development and do not commit model binaries.
If the full selected model is small enough, bundled assets are allowed only after explicit user confirmation.
```

Expected for likely bilingual Zipformer: manual local assets; do not commit ONNX files.

- [ ] **Step 3: Add the model decision to this plan**

Insert after “Pre-Flight Notes”:

```markdown
## Model Distribution Decision

- Decision: manual local assets for development; do not commit ONNX model files in this implementation.
- Model candidate: sherpa-onnx streaming bilingual zh/en Zipformer.
- Observed size: replace this sentence with the inspected file sizes, or write “not present locally during planning”.
- Runtime behavior when model files are absent: voice input is hidden or disabled with a recoverable “voice input unavailable” message; text input remains available.
```

- [ ] **Step 4: Commit the decision**

Run:

```powershell
git add -f docs\superpowers\plans\2026-05-07-voice-input-stt.md
git commit -m "Plan mobile voice input around explicit model distribution"
```

Expected: commit includes only this plan document.

---

### Task 2: Build Pure Voice Controller

**Files:**
- Create: `mobile/lib/src/features/workbench/voice_input.dart`
- Create: `mobile/lib/src/features/workbench/voice_input_controller.dart`
- Modify: `mobile/lib/src/features/workbench/workbench.dart`
- Test: `mobile/test/voice_input_controller_test.dart`

- [ ] **Step 1: Write failing tests**

Create `mobile/test/voice_input_controller_test.dart` covering:

```dart
test('stop appends voice text at end with newline', () async {});
test('cancel discards uncommitted partial text', () async {});
test('duplicate start while initializing is ignored', () async {});
test('initialize timeout returns failed state and cancels service', () async {});
```

Use a fake `SpeechInputService` with counters for `start`, `stop`, and `cancel`; expose `onPartial` so tests can simulate partial text.

- [ ] **Step 2: Run tests and verify failure**

```powershell
cd mobile
flutter test test\voice_input_controller_test.dart
```

Expected: FAIL because voice input abstractions do not exist.

- [ ] **Step 3: Implement abstractions**

Create `voice_input_controller.dart` with:

```dart
enum VoiceInputState { idle, initializing, listening, stopping, cancelling, failed }

abstract class SpeechInputService {
  Future<void> start({required void Function(String text) onPartial});
  Future<String> stop();
  Future<void> cancel();
  void dispose();
}
```

Implement `VoiceInputController extends ChangeNotifier` with:

```dart
VoiceInputController({required SpeechInputService service, Duration initializeTimeout = const Duration(seconds: 5)});
Future<void> start({required String currentPrompt});
Future<String> stop({required String currentPrompt});
Future<void> cancel();
String previewText();
String mergeVoiceText(String currentPrompt, String voiceText);
```

Required behavior:

```text
start: ignore duplicate calls in initializing/listening/stopping/cancelling; capture base text; timeout after 5 seconds; set failed on timeout/error.
previewText: merge base text and current partial text without duplicating previous partials.
stop: call service.stop, merge final text at end with newline if base text is non-empty, reset to idle.
cancel: call service.cancel, discard partial text, reset to idle.
```

Create `voice_input.dart`:

```dart
export 'voice_input_controller.dart';
```

Add to `workbench.dart`:

```dart
export 'voice_input.dart';
```

- [ ] **Step 4: Run controller tests**

```powershell
cd mobile
flutter test test\voice_input_controller_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit Task 2**

```powershell
git add mobile\lib\src\features\workbench\voice_input.dart mobile\lib\src\features\workbench\voice_input_controller.dart mobile\lib\src\features\workbench\workbench.dart mobile\test\voice_input_controller_test.dart
git commit -m "Add testable voice input state controller"
```

---

### Task 3: Add Composer Microphone UI

**Files:**
- Modify: `mobile/lib/src/features/workbench/coding_composer.dart`
- Modify: `mobile/lib/src/testing/debug_helpers.dart`
- Test: `mobile/test/widget_test.dart`

- [ ] **Step 1: Add failing widget tests**

Add tests for:

```dart
testWidgets('coding composer exposes voice input semantics', (tester) async {});
testWidgets('coding composer does not send when voice pointer is released', (tester) async {});
testWidgets('coding composer shows listening state while recording', (tester) async {});
```

Expected assertions:

```dart
expect(find.bySemanticsLabel('Voice input'), findsOneWidget);
expect(sends, 0); // releasing voice must not call onSend
expect(find.textContaining('Listening'), findsOneWidget);
```

- [ ] **Step 2: Run tests and verify failure**

```powershell
cd mobile
flutter test test\widget_test.dart --plain-name "coding composer exposes voice input semantics" --plain-name "coding composer does not send when voice pointer is released" --plain-name "coding composer shows listening state while recording"
```

Expected: FAIL because `CodingComposer` has no voice UI props yet.

- [ ] **Step 3: Extend `CodingComposer` API**

Add constructor parameters and fields:

```dart
final VoiceInputState voiceState;
final bool voiceEnabled;
final String? voiceError;
final VoidCallback onVoiceStart;
final VoidCallback onVoiceStop;
final VoidCallback onVoiceCancel;
```

Add import:

```dart
import 'voice_input.dart';
```

Replace one unused icon with `_VoiceInputButton`.

- [ ] **Step 4: Implement voice UI widgets**

Add private widgets in `coding_composer.dart`:

```dart
class _VoiceInputButton extends StatelessWidget {}
class _VoiceInputStatus extends StatelessWidget {}
```

Required behavior:

```text
Semantics label: Voice input.
Long press start: calls onVoiceStart only when enabled.
Long press end: calls onVoiceStop only when enabled.
Long press cancel: calls onVoiceCancel only when enabled.
Disabled tooltip/helper: Voice input is not available on this platform yet.
Active icon: mic filled with accent border.
Idle icon: mic outline.
Status text while initializing/listening/stopping: Listening… release to finish.
Error text: voiceError when non-null.
```

- [ ] **Step 5: Update previews**

In `mobile/lib/src/testing/debug_helpers.dart`, every `CodingComposer(` call gets:

```dart
voiceState: VoiceInputState.idle,
voiceEnabled: false,
voiceError: null,
onVoiceStart: () {},
onVoiceStop: () {},
onVoiceCancel: () {},
```

- [ ] **Step 6: Run widget tests**

```powershell
cd mobile
flutter test test\widget_test.dart --plain-name "coding composer exposes voice input semantics" --plain-name "coding composer does not send when voice pointer is released" --plain-name "coding composer shows listening state while recording"
```

Expected: PASS.

- [ ] **Step 7: Commit Task 3**

```powershell
git add mobile\lib\src\features\workbench\coding_composer.dart mobile\lib\src\testing\debug_helpers.dart mobile\test\widget_test.dart
git commit -m "Add voice affordance to the coding composer"
```

---

### Task 4: Wire Voice Controller Into Workbench

**Files:**
- Modify: `mobile/lib/src/features/workbench/coding_workbench_page.dart`
- Test: `mobile/test/widget_test.dart`

- [ ] **Step 1: Add injectable service field**

Modify `CodingWorkbenchPage`:

```dart
final SpeechInputService? speechInputService;
```

Constructor parameter:

```dart
this.speechInputService,
```

- [ ] **Step 2: Own controller in state**

Add:

```dart
late final VoiceInputController _voiceInput;
```

Initialize:

```dart
_voiceInput = VoiceInputController(service: widget.speechInputService ?? DisabledSpeechInputService())
  ..addListener(_syncVoicePreviewText);
```

Dispose:

```dart
if (_voiceInput.isBusy) unawaited(_voiceInput.cancel());
_voiceInput.removeListener(_syncVoicePreviewText);
_voiceInput.dispose();
```

- [ ] **Step 3: Add disabled service**

Add a `DisabledSpeechInputService` implementation that throws `StateError('Voice input is not available on this platform yet.')` from `start`, returns empty text from `stop`, and no-ops `cancel/dispose`.

- [ ] **Step 4: Add workbench callbacks**

Implement:

```dart
void _syncVoicePreviewText();
Future<void> _startVoiceInput();
Future<void> _stopVoiceInput();
Future<void> _cancelVoiceInput();
```

Required behavior:

```text
Partial text updates _prompt with controller.previewText().
Stop updates _prompt with final merged text and moves selection to end.
Cancel preserves only pre-recording committed text.
No callback calls _sendPrompt().
```

- [ ] **Step 5: Pass props to `CodingComposer`**

At `CodingComposer(` call:

```dart
voiceState: _voiceInput.state,
voiceEnabled: widget.speechInputService != null,
voiceError: _voiceInput.error,
onVoiceStart: () => unawaited(_startVoiceInput()),
onVoiceStop: () => unawaited(_stopVoiceInput()),
onVoiceCancel: () => unawaited(_cancelVoiceInput()),
```

- [ ] **Step 6: Cancel on route changes**

In `_setCurrentRoute`, when route is not `_routeConversation` and `_voiceInput.isBusy`, call `unawaited(_cancelVoiceInput())`.

- [ ] **Step 7: Run focused tests**

```powershell
cd mobile
flutter test test\voice_input_controller_test.dart
flutter test test\widget_test.dart --plain-name "coding composer"
```

Expected: PASS for voice-related tests.

- [ ] **Step 8: Commit Task 4**

```powershell
git add mobile\lib\src\features\workbench\coding_workbench_page.dart mobile\test\widget_test.dart
git commit -m "Wire voice input state into the coding workbench"
```

---

### Task 5: Add Native Speech Service Scaffold

**Files:**
- Modify: `mobile/pubspec.yaml`
- Modify: `mobile/pubspec.lock`
- Modify: `mobile/android/app/src/main/AndroidManifest.xml`
- Create: `mobile/lib/src/services/speech_input_service.dart`
- Test: `mobile/test/speech_input_service_test.dart`

- [ ] **Step 1: Add dependencies**

```powershell
cd mobile
flutter pub add record permission_handler sherpa_onnx
```

Expected: `pubspec.yaml` and `pubspec.lock` update with resolvable versions.

- [ ] **Step 2: Add Android microphone permission**

Add to `mobile/android/app/src/main/AndroidManifest.xml` at manifest level:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
```

- [ ] **Step 3: Write PCM conversion test**

Create `mobile/test/speech_input_service_test.dart` with a test for `pcm16LittleEndianToFloatSamples` using bytes for `0`, `16384`, and `-32768`; expected floats are `0`, about `0.5`, and `-1`.

- [ ] **Step 4: Implement service scaffold**

Create `mobile/lib/src/services/speech_input_service.dart` with:

```dart
List<double> pcm16LittleEndianToFloatSamples(Uint8List bytes);
class SherpaSpeechInputService implements SpeechInputService {}
```

Required behavior:

```text
Request microphone permission on start.
Lazy-create StreamingRecognizer.
Start record stream with pcm16bits, sampleRate 16000, one channel.
Convert PCM bytes to float samples.
Feed samples to sherpa-onnx stream.
Emit partial text callback.
stop returns latest recognized text.
cancel stops recorder and clears latest text.
```

If the installed `sherpa_onnx` API differs from `docs/flutter_speech_to_text.md`, use the package examples from the installed version and keep all changes isolated to this service.

- [ ] **Step 5: Keep real service disabled until model path exists**

Do not hardcode missing model paths into `CodingWorkbenchPage`. If Task 1 chose manual local assets and no model is present, keep `DisabledSpeechInputService` as the default and make the real service injectable for later manual verification.

- [ ] **Step 6: Run service test**

```powershell
cd mobile
flutter test test\speech_input_service_test.dart
```

Expected: PASS without microphone/model.

- [ ] **Step 7: Commit Task 5**

```powershell
git add mobile\pubspec.yaml mobile\pubspec.lock mobile\android\app\src\main\AndroidManifest.xml mobile\lib\src\services\speech_input_service.dart mobile\test\speech_input_service_test.dart
git commit -m "Add native speech input service scaffold"
```

---

### Task 6: Final Verification

**Files:**
- Inspect all files changed by Tasks 1-5.

- [ ] **Step 1: Format changed Dart files**

```powershell
cd mobile
dart format lib\src\features\workbench\coding_composer.dart lib\src\features\workbench\coding_workbench_page.dart lib\src\features\workbench\voice_input.dart lib\src\features\workbench\voice_input_controller.dart lib\src\services\speech_input_service.dart test\voice_input_controller_test.dart test\speech_input_service_test.dart test\widget_test.dart
```

Expected: formatter completes.

- [ ] **Step 2: Run focused tests**

```powershell
cd mobile
flutter test test\voice_input_controller_test.dart test\speech_input_service_test.dart
```

Expected: PASS.

- [ ] **Step 3: Run voice widget tests**

```powershell
cd mobile
flutter test test\widget_test.dart --plain-name "coding composer"
```

Expected: PASS for voice-related composer tests.

- [ ] **Step 4: Run analyzer**

```powershell
cd mobile
flutter analyze
```

Expected: no new analyzer errors.

- [ ] **Step 5: Build Windows debug**

```powershell
cd mobile
flutter build windows --debug
```

Expected: build succeeds; voice UI is hidden or disabled on Windows until support is verified.

- [ ] **Step 6: Manual Android checklist after model decision**

```text
1. Text input still sends normally.
2. First mic press requests microphone permission.
3. Permission denial keeps text input usable and repeated attempts guide to settings.
4. Press-hold-release fills recognized text but does not send.
5. Existing typed text plus voice text appends with a newline.
6. Backgrounding while recording stops microphone and does not commit partial text.
```

---

## Self-Review Checklist

- Spec coverage: text mode, voice affordance, no auto-send, newline append, lazy init timeout, cancellation, lifecycle, Windows disabled, model blocker, tests.
- Placeholder scan: no `TBD`, `TODO`, or unresolved implementation placeholders should remain before execution.
- Type consistency: `VoiceInputState`, `SpeechInputService`, and `VoiceInputController` names must match across controller, composer, workbench, and tests.
