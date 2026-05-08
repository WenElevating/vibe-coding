# Voice Input STT Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add offline-first voice input to the Coding composer so microphone speech becomes editable prompt text and uses the existing send flow.

**Architecture:** Keep `TextEditingController` as the single submitted text source. `VoiceInputController` owns UI state and merge/cancel semantics, `SpeechInputService` owns microphone/ASR details, and `AsrModelManager` gates first-use model download before creating `SherpaSpeechInputService`.

**Tech Stack:** Flutter/Dart, `record`, `permission_handler`, `sherpa_onnx`, `path_provider`, daemon HTTP ASR model endpoint, existing Flutter widget/unit tests.

---

## File Structure

- Modify: `mobile/pubspec.yaml` — declare voice input dependencies and bundled plugin support.
- Modify: `mobile/lib/src/features/workbench/voice_input.dart` — export the public voice input controller boundary.
- Modify: `mobile/lib/src/features/workbench/voice_input_controller.dart` — define state machine, merge policy, duplicate-start guard, cancellation, and friendly errors.
- Modify: `mobile/lib/src/services/speech_input_service.dart` — implement `SherpaSpeechInputService`, permission checks, lazy recognizer initialization, PCM16 streaming, and platform fallback.
- Modify: `mobile/lib/src/services/asr_model_client.dart` — call daemon metadata/download endpoints and expose range-aware download streams.
- Modify: `mobile/lib/src/services/asr_model_manager.dart` — ensure model readiness, resume `.part` downloads, verify SHA-256, extract required files, and publish progress state.
- Modify: `mobile/lib/src/features/workbench/coding_composer.dart` — add microphone affordance, press/release callbacks, semantics, and recording visuals without sending automatically.
- Modify: `mobile/lib/src/features/workbench/coding_workbench_page.dart` — wire composer to `VoiceInputController`, `AsrModelManager`, route/lifecycle cancellation, model download dialog, and service replacement.
- Modify: `daemon/src/asr-model-asset.js` and daemon route registration file — serve metadata and range downloads for `daemon/asset/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20-mobile.zip`.
- Modify: `.gitignore` — ignore `daemon/asset/` so the 325 MB ZIP never enters Git.
- Test: `mobile/test/voice_input_controller_test.dart` — controller state/merge/cancel/duplicate-start coverage.
- Test: `mobile/test/speech_input_service_test.dart` — PCM16 conversion and service error mapping coverage without real microphone.
- Test: `mobile/test/asr_model_client_test.dart` — metadata, range, trace ID, and client failure coverage.
- Test: `mobile/test/asr_model_manager_test.dart` — ready detection, resume, checksum, extraction, cancel/pause coverage.
- Test: `mobile/test/widget_test.dart` — composer semantics and no-auto-send UI behavior.
- Test: `scripts/run-tests.js` — daemon ASR metadata/range endpoint regression coverage.

---

### Task 1: Lock Voice Controller Behavior

**Files:**
- Modify: `mobile/test/voice_input_controller_test.dart`
- Modify: `mobile/lib/src/features/workbench/voice_input_controller.dart`

- [ ] **Step 1: Write tests for merge, no auto-send, duplicate start, and cancellation**

Add or update `mobile/test/voice_input_controller_test.dart` with these tests. Keep fake services local to the test file so no native microphone or ASR runtime is used.

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/features/workbench/voice_input_controller.dart';

class FakeSpeechInputService implements SpeechInputService {
  int starts = 0;
  int stops = 0;
  int cancels = 0;
  String finalText = 'voice result';
  Completer<void>? startCompleter;
  void Function(String text)? partial;

  @override
  Future<void> start({required void Function(String text) onPartial}) {
    starts += 1;
    partial = onPartial;
    final completer = startCompleter;
    if (completer != null) return completer.future;
    return Future<void>.value();
  }

  @override
  Future<String> stop() async {
    stops += 1;
    return finalText;
  }

  @override
  Future<void> cancel() async {
    cancels += 1;
  }

  @override
  void dispose() {}
}

void main() {
  test('appends voice text at the end with a newline', () async {
    final service = FakeSpeechInputService()..finalText = 'run tests';
    final controller = VoiceInputController(service: service);

    await controller.start(currentPrompt: 'please update docs');
    final merged = await controller.stop(currentPrompt: 'please update docs');

    expect(merged, 'please update docs\nrun tests');
    expect(controller.state, VoiceInputState.idle);
  });

  test('partial text previews without committing until stop', () async {
    final service = FakeSpeechInputService();
    final controller = VoiceInputController(service: service);

    await controller.start(currentPrompt: 'typed context');
    service.partial?.call('partial voice');

    expect(controller.previewText(), 'typed context\npartial voice');
    expect(controller.restoreBaseText(), 'typed context');
  });

  test('cancel discards uncommitted partial text and restores base text', () async {
    final service = FakeSpeechInputService();
    final controller = VoiceInputController(service: service);

    await controller.start(currentPrompt: 'safe typed text');
    service.partial?.call('discard this');
    await controller.cancel();

    expect(service.cancels, 1);
    expect(controller.restoreBaseText(), 'safe typed text');
    expect(controller.partialText, isEmpty);
    expect(controller.state, VoiceInputState.idle);
  });

  test('duplicate starts while initializing are ignored', () async {
    final service = FakeSpeechInputService()
      ..startCompleter = Completer<void>();
    final controller = VoiceInputController(service: service);

    final first = controller.start(currentPrompt: 'base');
    await controller.start(currentPrompt: 'base');
    service.startCompleter!.complete();
    await first;

    expect(service.starts, 1);
    expect(controller.state, VoiceInputState.listening);
  });

  test('stop returns current prompt when not listening', () async {
    final controller = VoiceInputController(service: FakeSpeechInputService());

    final result = await controller.stop(currentPrompt: 'unchanged');

    expect(result, 'unchanged');
  });
}
```

- [ ] **Step 2: Run controller tests and verify they fail for missing behavior**

Run: `cd mobile && flutter test test\voice_input_controller_test.dart`

Expected: failures should mention missing `cancelling`, duplicate-start, preview, or newline merge behavior if the implementation has not already been applied.

- [ ] **Step 3: Implement the controller state machine**

Update `mobile/lib/src/features/workbench/voice_input_controller.dart` so the public boundary matches this shape.

```dart
enum VoiceInputState {
  idle,
  initializing,
  listening,
  stopping,
  cancelling,
  failed,
}

abstract class SpeechInputService {
  Future<void> start({required void Function(String text) onPartial});
  Future<String> stop();
  Future<void> cancel();
  void dispose();
}

class VoiceInputController extends ChangeNotifier {
  VoiceInputController({
    required SpeechInputService service,
    Duration initializeTimeout = const Duration(seconds: 5),
  })  : _service = service,
        _initializeTimeout = initializeTimeout;

  SpeechInputService _service;
  final Duration _initializeTimeout;
  VoiceInputState _state = VoiceInputState.idle;
  String _partialText = '';
  String _baseText = '';
  String? _error;

  VoiceInputState get state => _state;
  String get partialText => _partialText;
  String? get error => _error;
  bool get isBusy =>
      _state == VoiceInputState.initializing ||
      _state == VoiceInputState.listening ||
      _state == VoiceInputState.stopping ||
      _state == VoiceInputState.cancelling;

  void updateService(SpeechInputService service) {
    if (identical(_service, service)) return;
    if (isBusy) {
      throw StateError('Cannot replace voice input service while it is active.');
    }
    _service.dispose();
    _service = service;
    _error = null;
    if (_state == VoiceInputState.failed) _setState(VoiceInputState.idle);
  }

  Future<void> start({required String currentPrompt}) async {
    if (isBusy) return;
    _baseText = currentPrompt;
    _partialText = '';
    _error = null;
    _setState(VoiceInputState.initializing);
    try {
      await _service
          .start(onPartial: _setPartialText)
          .timeout(_initializeTimeout);
      if (_state == VoiceInputState.initializing) {
        _setState(VoiceInputState.listening);
      }
    } on TimeoutException {
      _error = 'Voice input unavailable';
      _setState(VoiceInputState.failed);
      await _service.cancel();
    } catch (error) {
      _error = friendlyVoiceInputError(error);
      _setState(VoiceInputState.failed);
    }
  }

  Future<String> stop({required String currentPrompt}) async {
    if (_state != VoiceInputState.listening) return currentPrompt;
    _setState(VoiceInputState.stopping);
    try {
      final finalText = await _service.stop();
      final merged = mergeVoiceText(currentPrompt, finalText);
      _partialText = '';
      _baseText = merged;
      _error = null;
      _setState(VoiceInputState.idle);
      return merged;
    } catch (error) {
      _error = friendlyVoiceInputError(error);
      _setState(VoiceInputState.failed);
      return currentPrompt;
    }
  }

  Future<void> cancel() async {
    if (_state == VoiceInputState.idle) return;
    _setState(VoiceInputState.cancelling);
    try {
      await _service.cancel();
    } finally {
      _partialText = '';
      _setState(VoiceInputState.idle);
    }
  }

  String restoreBaseText() => _baseText;

  String previewText() {
    if (_partialText.trim().isEmpty) return _baseText;
    return mergeVoiceText(_baseText, _partialText);
  }

  String mergeVoiceText(String currentPrompt, String voiceText) {
    final trimmedVoice = voiceText.trim();
    if (trimmedVoice.isEmpty) return currentPrompt;
    final trimmedPrompt = currentPrompt.trimRight();
    if (trimmedPrompt.isEmpty) return trimmedVoice;
    return '$trimmedPrompt\n$trimmedVoice';
  }

  void _setPartialText(String text) {
    _partialText = text;
    notifyListeners();
  }

  void _setState(VoiceInputState state) {
    _state = state;
    notifyListeners();
  }
}
```

- [ ] **Step 4: Run controller tests and verify pass**

Run: `cd mobile && flutter test test\voice_input_controller_test.dart`

Expected: `All tests passed!`

- [ ] **Step 5: Commit controller behavior**

Run:

```bash
git add mobile/lib/src/features/workbench/voice_input_controller.dart mobile/test/voice_input_controller_test.dart
git commit -m "Stabilize editable voice input state" -m "Voice input must never discard typed text or auto-submit dictated text, so the controller keeps typed prompt text as the durable base and treats speech as preview text until a normal stop finalizes it.\n\nConstraint: Speech recognition is asynchronous and may be interrupted by route changes or app lifecycle changes.\nRejected: Insert recognized text at the cursor | surprising when the cursor is in the middle of a coding prompt.\nConfidence: high\nScope-risk: narrow\nTested: cd mobile && flutter test test\\voice_input_controller_test.dart"
```

---

### Task 2: Implement Speech Service Boundary

**Files:**
- Modify: `mobile/pubspec.yaml`
- Modify: `mobile/lib/src/services/speech_input_service.dart`
- Modify: `mobile/test/speech_input_service_test.dart`

- [ ] **Step 1: Add dependency declarations**

Ensure `mobile/pubspec.yaml` contains these dependencies under `dependencies:`.

```yaml
  permission_handler: ^12.0.1
  record: ^6.2.0
  sherpa_onnx: ^1.12.36
```

- [ ] **Step 2: Run dependency resolution**

Run: `cd mobile && flutter pub get`
Expected: dependencies resolve and `mobile/pubspec.lock` updates.

- [ ] **Step 3: Write service tests for PCM16 conversion and friendly errors**

Add or update `mobile/test/speech_input_service_test.dart`.

```dart
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/features/workbench/voice_input_controller.dart';
import 'package:lan_ai_cli_control/src/services/speech_input_service.dart';

void main() {
  test('pcm16BytesToSamples decodes little endian signed samples', () {
    final bytes = Uint8List.fromList(<int>[
      0x00, 0x00,
      0xff, 0x7f,
      0x00, 0x80,
      0xff, 0xff,
    ]);

    final samples = pcm16BytesToSamples(bytes);

    expect(samples, <double>[
      0,
      32767 / 32768,
      -1,
      -1 / 32768,
    ]);
  });

  test('friendlyVoiceInputError maps permission denial', () {
    final message = friendlyVoiceInputError(
      PlatformException(code: 'permission_denied', message: 'microphone denied'),
    );

    expect(message, contains('Microphone permission'));
  });

  test('friendlyVoiceInputError maps missing input device', () {
    final message = friendlyVoiceInputError(
      PlatformException(code: 'record', message: 'No recording device found'),
    );

    expect(message, contains('No microphone'));
  });
}
```

- [ ] **Step 4: Run service tests and verify they fail if helpers are missing**

Run: `cd mobile && flutter test test\speech_input_service_test.dart`
Expected: failures mention missing `pcm16BytesToSamples` or error mapping if not implemented.

- [ ] **Step 5: Implement service helpers and platform fallback**

In `mobile/lib/src/services/speech_input_service.dart`, expose the PCM helper and a factory that hides or disables unsupported platforms.

```dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../features/workbench/voice_input_controller.dart';

const voiceInputSampleRate = 16000;

bool get isVoiceInputPlatformSupported =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isLinux);

SpeechInputService createSpeechInputService({String? modelDirectory}) {
  if (!isVoiceInputPlatformSupported || modelDirectory == null) {
    return const DisabledSpeechInputService();
  }
  return SherpaSpeechInputService(modelDirectory: modelDirectory);
}

List<double> pcm16BytesToSamples(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final samples = <double>[];
  for (var offset = 0; offset + 1 < bytes.length; offset += 2) {
    samples.add(data.getInt16(offset, Endian.little) / 32768.0);
  }
  return samples;
}
```

- [ ] **Step 6: Implement lazy Sherpa start/stop/cancel**

Continue in `mobile/lib/src/services/speech_input_service.dart` and keep native objects behind nullable fields so tests can avoid constructing them.

```dart
class SherpaSpeechInputService implements SpeechInputService {
  SherpaSpeechInputService({required this.modelDirectory});

  final String modelDirectory;
  final AudioRecorder _recorder = AudioRecorder();
  sherpa.OnlineRecognizer? _recognizer;
  sherpa.OnlineStream? _stream;
  StreamSubscription<Uint8List>? _subscription;
  String _lastText = '';
  bool _active = false;

  @override
  Future<void> start({required void Function(String text) onPartial}) async {
    if (_active) return;
    final permission = await Permission.microphone.request();
    if (!permission.isGranted) {
      throw const VoiceInputPermissionDeniedException();
    }
    _recognizer ??= await _createRecognizer();
    _stream = _recognizer!.createStream();
    _lastText = '';
    _active = true;
    final input = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: voiceInputSampleRate,
        numChannels: 1,
      ),
    );
    _subscription = input.listen((chunk) {
      final stream = _stream;
      final recognizer = _recognizer;
      if (stream == null || recognizer == null) return;
      stream.acceptWaveform(
        samples: Float32List.fromList(pcm16BytesToSamples(chunk)),
        sampleRate: voiceInputSampleRate,
      );
      while (recognizer.isReady(stream)) {
        recognizer.decode(stream);
      }
      final result = recognizer.getResult(stream).text.trim();
      if (result.isNotEmpty && result != _lastText) {
        _lastText = result;
        onPartial(result);
      }
    });
  }

  Future<sherpa.OnlineRecognizer> _createRecognizer() async {
    final config = sherpa.OnlineRecognizerConfig(
      modelConfig: sherpa.OnlineModelConfig(
        transducer: sherpa.OnlineTransducerModelConfig(
          encoder: '$modelDirectory/encoder.onnx',
          decoder: '$modelDirectory/decoder.onnx',
          joiner: '$modelDirectory/joiner.onnx',
        ),
        tokens: '$modelDirectory/tokens.txt',
        numThreads: 1,
        debug: false,
      ),
      decodingMethod: 'greedy_search',
    );
    return sherpa.OnlineRecognizer(config);
  }

  @override
  Future<String> stop() async {
    if (!_active) return _lastText;
    await _subscription?.cancel();
    _subscription = null;
    await _recorder.stop();
    final stream = _stream;
    final recognizer = _recognizer;
    if (stream != null && recognizer != null) {
      recognizer.inputFinished(stream);
      while (recognizer.isReady(stream)) {
        recognizer.decode(stream);
      }
      final result = recognizer.getResult(stream).text.trim();
      if (result.isNotEmpty) _lastText = result;
    }
    _stream?.free();
    _stream = null;
    _active = false;
    return _lastText;
  }

  @override
  Future<void> cancel() async {
    await _subscription?.cancel();
    _subscription = null;
    if (await _recorder.isRecording()) await _recorder.stop();
    _stream?.free();
    _stream = null;
    _lastText = '';
    _active = false;
  }

  @override
  void dispose() {
    unawaited(cancel());
    _recognizer?.free();
    _recognizer = null;
    _recorder.dispose();
  }
}

class VoiceInputPermissionDeniedException implements Exception {
  const VoiceInputPermissionDeniedException();
}
```

- [ ] **Step 7: Run service tests and analyze**

Run:

```bash
cd mobile && flutter test test\speech_input_service_test.dart
cd mobile && flutter analyze
```

Expected: both commands pass.

- [ ] **Step 8: Commit service boundary**

Run:

```bash
git add mobile/pubspec.yaml mobile/pubspec.lock mobile/lib/src/services/speech_input_service.dart mobile/test/speech_input_service_test.dart
git commit -m "Prepare offline speech recognition service" -m "Voice input needs a narrow service boundary so composer and send logic stay independent from microphone permissions, PCM streams, and sherpa-onnx lifecycle.\n\nConstraint: Unit tests must not require a real microphone or native recognizer.\nRejected: Cloud ASR fallback | violates offline-first privacy goal.\nConfidence: medium\nScope-risk: moderate\nTested: cd mobile && flutter test test\\speech_input_service_test.dart; cd mobile && flutter analyze"
```

---

### Task 3: Serve ASR Model From Daemon

**Files:**
- Modify: `daemon/src/asr-model-asset.js`
- Modify: daemon HTTP route registration file that handles `/api/*`
- Modify: `scripts/run-tests.js`
- Modify: `.gitignore`

- [ ] **Step 1: Ignore local ASR asset directory**

Add this line to `.gitignore` if missing.

```gitignore
daemon/asset/
```

- [ ] **Step 2: Write daemon range tests**

In `scripts/run-tests.js`, add tests equivalent to the following assertions near existing daemon API tests.

```js
test('ASR model metadata exposes fixed daemon asset without leaking paths', async () => {
  const asset = new AsrModelAsset({ filePath: fixtureZipPath });
  const metadata = await asset.metadata();
  assert.equal(metadata.fileName, path.basename(fixtureZipPath));
  assert.equal(metadata.downloadPath, '/api/asr-model/download');
  assert.equal(metadata.sizeBytes, fs.statSync(fixtureZipPath).size);
  assert.match(metadata.sha256, /^[a-f0-9]{64}$/);
  assert.equal(Object.hasOwn(metadata, 'filePath'), false);
});

test('ASR model range parser accepts open-ended and suffix ranges', () => {
  assert.deepEqual(parseRange('bytes=10-', 100), { start: 10, end: 99 });
  assert.deepEqual(parseRange('bytes=10-19', 100), { start: 10, end: 19 });
  assert.deepEqual(parseRange('bytes=-10', 100), { start: 90, end: 99 });
  assert.deepEqual(parseRange('bytes=100-', 100), { unsatisfiable: true });
});
```

- [ ] **Step 3: Run daemon tests and verify fail if endpoint is absent**

Run: `npm test`
Expected: failures mention missing `AsrModelAsset`, missing route, or range behavior if not implemented.

- [ ] **Step 4: Implement `AsrModelAsset`**

Create or update `daemon/src/asr-model-asset.js` with this module.

```js
'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const fsp = require('node:fs/promises');
const path = require('node:path');

const DEFAULT_MODEL_FILE =
  'sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20-mobile.zip';

class AsrModelAsset {
  constructor({
    filePath = path.join(__dirname, '..', 'asset', DEFAULT_MODEL_FILE),
    version = path.basename(filePath, '.zip'),
    downloadPath = '/api/asr-model/download',
  } = {}) {
    this.filePath = filePath;
    this.version = version;
    this.fileName = path.basename(filePath);
    this.downloadPath = downloadPath;
    this._metadata = null;
    this._metadataStatKey = null;
  }

  async metadata() {
    const stat = await this._statReadable();
    const statKey = `${stat.size}:${stat.mtimeMs}`;
    if (this._metadata && this._metadataStatKey === statKey) return this._metadata;
    const sha256 = await sha256File(this.filePath);
    this._metadata = {
      version: this.version,
      fileName: this.fileName,
      sizeBytes: stat.size,
      sha256,
      downloadPath: this.downloadPath,
    };
    this._metadataStatKey = statKey;
    return this._metadata;
  }

  async streamDownload(req, res) {
    const stat = await this._statReadable();
    const size = stat.size;
    const range = parseRange(req.headers.range, size);
    if (range.unsatisfiable) {
      res.writeHead(416, {
        'accept-ranges': 'bytes',
        'content-range': `bytes */${size}`,
      });
      res.end();
      return;
    }
    const start = range.start;
    const end = range.end;
    const partial = start !== 0 || end !== size - 1;
    res.writeHead(partial ? 206 : 200, {
      'accept-ranges': 'bytes',
      'content-type': 'application/zip',
      'content-length': end - start + 1,
      ...(partial ? { 'content-range': `bytes ${start}-${end}/${size}` } : {}),
    });
    fs.createReadStream(this.filePath, { start, end }).pipe(res);
  }

  async _statReadable() {
    try {
      const stat = await fsp.stat(this.filePath);
      if (!stat.isFile()) throw new Error('configured ASR model asset is not a file');
      await fsp.access(this.filePath, fs.constants.R_OK);
      return stat;
    } catch (error) {
      const wrapped = new Error(`ASR model asset is unavailable: ${error.message}`);
      wrapped.status = 503;
      wrapped.code = 'ASR_MODEL_UNAVAILABLE';
      wrapped.recoverable = true;
      wrapped.userAction = 'Place the configured ASR model ZIP under daemon/asset and retry from the mobile app.';
      throw wrapped;
    }
  }
}

function parseRange(header, size) {
  if (!header) return { start: 0, end: size - 1 };
  const match = String(header).match(/^bytes=(\d*)-(\d*)$/);
  if (!match) return { unsatisfiable: true };
  const startText = match[1];
  const endText = match[2];
  if (!startText && !endText) return { unsatisfiable: true };
  if (!startText) {
    const suffixLength = Number(endText);
    if (!Number.isSafeInteger(suffixLength) || suffixLength <= 0) {
      return { unsatisfiable: true };
    }
    return { start: Math.max(size - suffixLength, 0), end: size - 1 };
  }
  const start = Number(startText);
  const requestedEnd = endText ? Number(endText) : size - 1;
  if (
    !Number.isSafeInteger(start) ||
    !Number.isSafeInteger(requestedEnd) ||
    start < 0 ||
    requestedEnd < start ||
    start >= size
  ) {
    return { unsatisfiable: true };
  }
  return { start, end: Math.min(requestedEnd, size - 1) };
}

function sha256File(filePath) {
  return new Promise((resolve, reject) => {
    const hash = crypto.createHash('sha256');
    const stream = fs.createReadStream(filePath);
    stream.on('data', (chunk) => hash.update(chunk));
    stream.on('error', reject);
    stream.on('end', () => resolve(hash.digest('hex')));
  });
}

module.exports = { AsrModelAsset, parseRange };
```

- [ ] **Step 5: Register daemon routes with existing auth/error handling**

In the daemon route file that defines paired-device APIs, instantiate one asset and add these handlers inside the existing authenticated `/api` routing path.

```js
const { AsrModelAsset } = require('./asr-model-asset');
const asrModelAsset = new AsrModelAsset();

if (req.method === 'GET' && pathname === '/api/asr-model') {
  const metadata = await asrModelAsset.metadata();
  sendJson(res, 200, metadata);
  return;
}

if (req.method === 'GET' && pathname === '/api/asr-model/download') {
  await asrModelAsset.streamDownload(req, res);
  return;
}
```

Use the repository's existing structured error wrapper so missing assets return a body containing `traceId`.

- [ ] **Step 6: Run daemon tests and lint**

Run:

```bash
npm test
npm run lint
```

Expected: both commands pass.

- [ ] **Step 7: Commit daemon model endpoint**

Run:

```bash
git add .gitignore daemon/src/asr-model-asset.js scripts/run-tests.js <daemon-route-file>
git commit -m "Expose resumable local ASR model downloads" -m "The mobile client needs a paired-daemon source for the large offline ASR model, so the daemon serves fixed metadata and byte-range downloads without exposing arbitrary filesystem paths.\n\nConstraint: The 325 MB ZIP must stay out of Git history.\nRejected: Public internet model URL | pairing flow should work on LAN and avoid external dependencies.\nConfidence: high\nScope-risk: moderate\nTested: npm test; npm run lint"
```

Replace `<daemon-route-file>` with the actual file that registers `/api` handlers.

---

### Task 4: Implement Resumable Client Model Preparation

**Files:**
- Modify: `mobile/lib/src/services/asr_model_client.dart`
- Modify: `mobile/lib/src/services/asr_model_manager.dart`
- Modify: `mobile/test/asr_model_client_test.dart`
- Modify: `mobile/test/asr_model_manager_test.dart`

- [ ] **Step 1: Write client API tests**

In `mobile/test/asr_model_client_test.dart`, cover metadata parsing, range headers, and trace IDs.

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/services/asr_model_client.dart';

void main() {
  test('metadata parses daemon model response', () async {
    final client = FakeAsrModelClient(metadataBody: jsonEncode({
      'version': 'model-v1',
      'fileName': 'model-v1.zip',
      'sizeBytes': 12,
      'sha256': '0' * 64,
      'downloadPath': '/api/asr-model/download',
    }));

    final metadata = await client.metadata();

    expect(metadata.version, 'model-v1');
    expect(metadata.sizeBytes, 12);
    expect(metadata.downloadPath, '/api/asr-model/download');
  });

  test('download sends range header when start is nonzero', () async {
    final client = FakeAsrModelClient(downloadBytes: <int>[1, 2, 3]);

    await client.download('/api/asr-model/download', start: 5).drain<void>();

    expect(client.lastRangeHeader, 'bytes=5-');
  });

  test('client exception exposes structured trace id', () {
    const error = AsrModelClientException(503, {
      'error': {'message': 'missing model', 'traceId': 'tr_123'}
    });

    expect(error.message, 'missing model');
    expect(error.traceId, 'tr_123');
  });
}
```

If the repository already uses a different HTTP fake, adapt `FakeAsrModelClient` to the existing test helper style but keep these exact expectations.

- [ ] **Step 2: Write manager tests for ready, resume, checksum failure, and cancel**

In `mobile/test/asr_model_manager_test.dart`, add tests around a temporary support directory.

```dart
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/services/asr_model_manager.dart';

void main() {
  test('returns existing ready model directory without downloading', () async {
    final temp = await Directory.systemTemp.createTemp('asr-ready-');
    final modelDir = Directory('${temp.path}/asr_models/model-v1');
    await modelDir.create(recursive: true);
    for (final name in AsrModelManager.requiredFiles) {
      await File('${modelDir.path}/$name').writeAsString('x');
    }
    final manager = AsrModelManager(
      client: FakeAsrModelClient(metadata: fakeMetadata()),
      supportDirectoryProvider: () async => temp,
    );

    final path = await manager.ensureReady();

    expect(path, modelDir.path);
    expect(manager.state.status, AsrModelStatus.ready);
  });

  test('resumes from existing part file with range request', () async {
    final temp = await Directory.systemTemp.createTemp('asr-resume-');
    final part = File('${temp.path}/asr_models/model-v1.zip.part');
    await part.create(recursive: true);
    await part.writeAsBytes(<int>[1, 2]);
    final remaining = <int>[3, 4];
    final metadata = fakeMetadata(
      sizeBytes: 4,
      sha256: sha256.convert(<int>[1, 2, 3, 4]).toString(),
    );
    final client = FakeAsrModelClient(metadata: metadata, chunks: [remaining]);
    final manager = AsrModelManager(
      client: client,
      supportDirectoryProvider: () async => temp,
    );

    await expectLater(manager.ensureReady(), completes);

    expect(client.downloadStarts, contains(2));
  });

  test('checksum mismatch fails and does not mark ready', () async {
    final temp = await Directory.systemTemp.createTemp('asr-bad-hash-');
    final manager = AsrModelManager(
      client: FakeAsrModelClient(
        metadata: fakeMetadata(sizeBytes: 2, sha256: '0' * 64),
        chunks: [<int>[1, 2]],
      ),
      supportDirectoryProvider: () async => temp,
    );

    await expectLater(manager.ensureReady(), throwsA(isA<Object>()));

    expect(manager.state.status, AsrModelStatus.failed);
  });

  test('cancel during download leaves part file reusable', () async {
    final temp = await Directory.systemTemp.createTemp('asr-cancel-');
    final client = SlowFakeAsrModelClient(metadata: fakeMetadata(sizeBytes: 4));
    final manager = AsrModelManager(
      client: client,
      supportDirectoryProvider: () async => temp,
    );

    final future = manager.ensureReady();
    await client.waitUntilDownloadStarted();
    manager.cancel();
    await expectLater(future, throwsA(isA<Object>()));

    expect(manager.state.status, AsrModelStatus.cancelled);
    expect(await File('${temp.path}/asr_models/model-v1.zip.part').exists(), isTrue);
  });
}
```

- [ ] **Step 3: Run ASR model tests and verify failure before implementation**

Run: `cd mobile && flutter test test\asr_model_client_test.dart test\asr_model_manager_test.dart`
Expected: failures mention missing range/resume/extraction behavior if not already implemented.

- [ ] **Step 4: Implement client methods and range stream metadata**

In `mobile/lib/src/services/asr_model_client.dart`, expose this boundary.

```dart
class AsrModelMetadata {
  const AsrModelMetadata({
    required this.version,
    required this.fileName,
    required this.sizeBytes,
    required this.sha256,
    required this.downloadPath,
  });

  final String version;
  final String fileName;
  final int sizeBytes;
  final String sha256;
  final String downloadPath;

  factory AsrModelMetadata.fromJson(Map<String, Object?> json) {
    return AsrModelMetadata(
      version: json['version'] as String,
      fileName: json['fileName'] as String,
      sizeBytes: json['sizeBytes'] as int,
      sha256: json['sha256'] as String,
      downloadPath: json['downloadPath'] as String,
    );
  }
}

abstract class AsrModelClient {
  Future<AsrModelMetadata> metadata();
  Stream<List<int>> download(String downloadPath, {int start = 0});
}
```

The concrete HTTP client must add `Range: bytes=<start>-` when `start > 0`, accept both `200` and `206`, and throw `AsrModelClientException` with `traceId` extracted from structured error bodies for HTTP `>= 400`.

- [ ] **Step 5: Implement manager state and storage paths**

In `mobile/lib/src/services/asr_model_manager.dart`, keep this state surface.

```dart
enum AsrModelStatus {
  idle,
  checking,
  downloading,
  paused,
  verifying,
  extracting,
  ready,
  failed,
  cancelled,
}

class AsrModelState {
  const AsrModelState({
    required this.status,
    this.version,
    this.modelDirectory,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.speedBytesPerSecond = 0,
    this.errorMessage,
    this.traceId,
  });

  final AsrModelStatus status;
  final String? version;
  final String? modelDirectory;
  final int downloadedBytes;
  final int totalBytes;
  final double speedBytesPerSecond;
  final String? errorMessage;
  final String? traceId;

  double get progress => totalBytes <= 0 ? 0 : (downloadedBytes / totalBytes).clamp(0, 1);
}
```

- [ ] **Step 6: Implement `ensureReady()` resume/verify/extract flow**

Use this exact sequence in `AsrModelManager.ensureReady()`:

```dart
Future<String> ensureReady() async {
  _cancelRequested = false;
  _pauseRequested = false;
  _emit(const AsrModelState(status: AsrModelStatus.checking));
  try {
    final metadata = await _client.metadata();
    final paths = await _paths(metadata.version);
    if (await _isReady(paths.modelDirectory)) {
      _emit(AsrModelState(
        status: AsrModelStatus.ready,
        version: metadata.version,
        modelDirectory: paths.modelDirectory.path,
        downloadedBytes: metadata.sizeBytes,
        totalBytes: metadata.sizeBytes,
      ));
      return paths.modelDirectory.path;
    }
    final zip = await _download(metadata, paths);
    _throwIfStopped();
    _emit(_state.copyWith(status: AsrModelStatus.verifying));
    await _verifyZip(zip, metadata);
    _throwIfStopped();
    _emit(_state.copyWith(status: AsrModelStatus.extracting));
    await _extract(zip, paths);
    _emit(_state.copyWith(
      status: AsrModelStatus.ready,
      modelDirectory: paths.modelDirectory.path,
      downloadedBytes: metadata.sizeBytes,
      totalBytes: metadata.sizeBytes,
    ));
    return paths.modelDirectory.path;
  } on AsrModelClientException catch (error) {
    _emit(_state.copyWith(
      status: AsrModelStatus.failed,
      errorMessage: error.message,
      traceId: error.traceId,
    ));
    rethrow;
  } catch (error) {
    _emit(_state.copyWith(status: AsrModelStatus.failed, errorMessage: error.toString()));
    rethrow;
  }
}
```

Implementation details that must be present:

```dart
static const requiredFiles = <String>[
  'encoder.onnx',
  'decoder.onnx',
  'joiner.onnx',
  'tokens.txt',
];
```

- Resume with `Range` from `.zip.part` length when `0 < partLength < sizeBytes`.
- Delete `.part` and restart from zero when `partLength > sizeBytes` or the server restarts with a full `200 OK` response.
- Compute SHA-256 over the downloaded ZIP before extraction.
- Extract to `<version>.staging/`, verify `requiredFiles`, then promote to `<version>/`.
- Keep `.part` when cancelled or paused so retry can resume.
- Surface daemon `traceId` on failures.

- [ ] **Step 7: Run model tests**

Run: `cd mobile && flutter test test\asr_model_client_test.dart test\asr_model_manager_test.dart`
Expected: `All tests passed!`

- [ ] **Step 8: Commit client model preparation**

Run:

```bash
git add mobile/lib/src/services/asr_model_client.dart mobile/lib/src/services/asr_model_manager.dart mobile/test/asr_model_client_test.dart mobile/test/asr_model_manager_test.dart
git commit -m "Prepare resumable ASR model installation" -m "Voice input should only pay the model download cost when the user asks for the microphone, so the client prepares the daemon-hosted ZIP on demand with range resume and verified extraction.\n\nConstraint: The model is hundreds of MB and unreliable as a one-shot mobile download.\nRejected: App startup predownload | would slow normal text-only usage and history browsing.\nConfidence: high\nScope-risk: moderate\nTested: cd mobile && flutter test test\\asr_model_client_test.dart test\\asr_model_manager_test.dart"
```

---

### Task 5: Wire Composer Voice UI

**Files:**
- Modify: `mobile/lib/src/features/workbench/coding_composer.dart`
- Modify: `mobile/test/widget_test.dart`

- [ ] **Step 1: Write widget tests for semantics and no auto-send**

In `mobile/test/widget_test.dart`, add or update composer-focused tests.

```dart
testWidgets('coding composer exposes voice input semantics', (tester) async {
  await tester.pumpWidget(buildComposer(
    voiceEnabled: true,
    voiceState: VoiceInputState.idle,
  ));

  expect(
    find.bySemanticsLabel('Voice input'),
    findsOneWidget,
  );
});

testWidgets('coding composer release voice input does not send prompt', (tester) async {
  var sends = 0;
  var starts = 0;
  var stops = 0;
  await tester.pumpWidget(buildComposer(
    voiceEnabled: true,
    voiceState: VoiceInputState.idle,
    onSend: (_) => sends += 1,
    onVoiceStart: () => starts += 1,
    onVoiceStop: () => stops += 1,
  ));

  final mic = find.bySemanticsLabel('Voice input');
  final gesture = await tester.startGesture(tester.getCenter(mic));
  await tester.pump();
  await gesture.up();
  await tester.pump();

  expect(starts, 1);
  expect(stops, 1);
  expect(sends, 0);
});

testWidgets('coding composer shows listening helper while recording', (tester) async {
  await tester.pumpWidget(buildComposer(
    voiceEnabled: true,
    voiceState: VoiceInputState.listening,
  ));

  expect(find.textContaining('Listening'), findsOneWidget);
});
```

Use the existing `buildComposer` helper if present; otherwise create one that pumps `MaterialApp(home: Scaffold(body: CodingComposer(...)))`.

- [ ] **Step 2: Run composer widget tests and verify fail before UI work**

Run: `cd mobile && flutter test test\widget_test.dart --plain-name "coding composer"`
Expected: failures mention missing semantics/helper/callback behavior if not implemented.

- [ ] **Step 3: Add voice props to `CodingComposer`**

Add these constructor fields to `CodingComposer` in `mobile/lib/src/features/workbench/coding_composer.dart`.

```dart
final VoiceInputState voiceState;
final bool voiceEnabled;
final String? voiceError;
final VoidCallback? onVoiceStart;
final VoidCallback? onVoiceStop;
final VoidCallback? onVoiceCancel;
```

Default them for existing call sites:

```dart
this.voiceState = VoiceInputState.idle,
this.voiceEnabled = false,
this.voiceError,
this.onVoiceStart,
this.onVoiceStop,
this.onVoiceCancel,
```

- [ ] **Step 4: Add microphone affordance with press/release behavior**

In the composer action row, add this button while preserving the existing send button.

```dart
Semantics(
  label: 'Voice input',
  button: true,
  enabled: voiceEnabled,
  child: GestureDetector(
    onLongPressStart: voiceEnabled ? (_) => onVoiceStart?.call() : null,
    onLongPressEnd: voiceEnabled ? (_) => onVoiceStop?.call() : null,
    onLongPressCancel: voiceEnabled ? () => onVoiceCancel?.call() : null,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _voiceAccentColor(context).withValues(
          alpha: voiceState == VoiceInputState.listening ? 0.18 : 0.08,
        ),
      ),
      child: Icon(
        voiceState == VoiceInputState.listening
            ? Icons.mic_rounded
            : Icons.mic_none_rounded,
        color: voiceEnabled ? _voiceAccentColor(context) : Theme.of(context).disabledColor,
      ),
    ),
  ),
)
```

If the current implementation uses tap instead of long-press to support desktop tests, keep `onTapDown`/`onTapUp` only if it preserves the same start/stop semantics and passes mobile press-hold usage.

- [ ] **Step 5: Add recording helper text**

Show this text near the input field while `voiceState` is active.

```dart
String? _voiceHelperText() {
  return switch (voiceState) {
    VoiceInputState.initializing => 'Preparing voice input...',
    VoiceInputState.listening => 'Listening... release to finish',
    VoiceInputState.stopping => 'Finishing voice input...',
    VoiceInputState.cancelling => 'Cancelling voice input...',
    VoiceInputState.failed => voiceError,
    VoiceInputState.idle => null,
  };
}
```

- [ ] **Step 6: Run composer widget tests**

Run: `cd mobile && flutter test test\widget_test.dart --plain-name "coding composer"`
Expected: `All tests passed!`

- [ ] **Step 7: Commit composer UI**

Run:

```bash
git add mobile/lib/src/features/workbench/coding_composer.dart mobile/test/widget_test.dart
git commit -m "Add editable voice input composer affordance" -m "The composer needs a visible microphone path that behaves like text entry, not submission, so voice callbacks update prompt text while the existing send affordance remains the only submit action.\n\nConstraint: Users must be able to correct recognition before sending.\nRejected: Auto-send on release | misrecognition would submit irreversible prompts.\nConfidence: high\nScope-risk: narrow\nTested: cd mobile && flutter test test\\widget_test.dart --plain-name \"coding composer\""
```

---

### Task 6: Wire Workbench Lifecycle and Model Dialog

**Files:**
- Modify: `mobile/lib/src/features/workbench/coding_workbench_page.dart`
- Modify: `mobile/test/widget_test.dart`

- [ ] **Step 1: Write widget tests for route/lifecycle cancellation and download retry UI**

In `mobile/test/widget_test.dart`, add workbench-level tests using existing fake daemon/session helpers.

```dart
testWidgets('workbench cancels voice input when leaving conversation', (tester) async {
  final service = FakeSpeechInputService();
  await tester.pumpWidget(buildWorkbenchWithVoiceService(service));

  await tester.longPress(find.bySemanticsLabel('Voice input'));
  await tester.pump();
  await navigateBackToSessions(tester);
  await tester.pumpAndSettle();

  expect(service.cancels, 1);
});

testWidgets('missing ASR model shows download dialog before voice starts', (tester) async {
  final manager = FakeAsrModelManager.initiallyMissing();
  final service = FakeSpeechInputService();
  await tester.pumpWidget(buildWorkbenchWithAsrManager(manager, service));

  await tester.longPress(find.bySemanticsLabel('Voice input'));
  await tester.pump();

  expect(find.textContaining('voice model'), findsOneWidget);
  expect(service.starts, 0);
});
```

Adapt helper names to the existing test harness, but keep the expectations: route change cancels microphone, model preparation precedes service start.

- [ ] **Step 2: Run workbench tests and verify fail before wiring**

Run: `cd mobile && flutter test test\widget_test.dart --plain-name "workbench"`
Expected: failures mention missing cancellation/download wiring if not implemented.

- [ ] **Step 3: Create controller and model manager in workbench state**

In `CodingWorkbenchPageState`, add fields like these.

```dart
late final VoiceInputController _voiceInput;
late final AsrModelManager _asrModelManager;
String? _voiceModelDirectory;
```

Initialize them in `initState()`.

```dart
_asrModelManager = AsrModelManager(client: AsrModelHttpClient(widget.daemonClient));
_voiceInput = VoiceInputController(service: const DisabledSpeechInputService())
  ..addListener(_syncVoicePreview);
```

Dispose them in `dispose()`.

```dart
_voiceInput.removeListener(_syncVoicePreview);
_voiceInput.dispose();
_asrModelManager.dispose();
```

- [ ] **Step 4: Implement voice start gate with first-use model preparation**

Add this flow in `CodingWorkbenchPageState`.

```dart
Future<void> _startVoiceInput() async {
  if (_voiceInput.isBusy) return;
  try {
    if (_voiceModelDirectory == null) {
      final directory = await _ensureAsrModelReady();
      if (directory == null) return;
      _voiceModelDirectory = directory;
      _voiceInput.updateService(createSpeechInputService(modelDirectory: directory));
    }
    await _voiceInput.start(currentPrompt: _prompt.text);
    _syncVoicePreview();
  } catch (error) {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _VoiceInputErrorDialog(message: friendlyVoiceInputError(error)),
    );
  }
}

Future<String?> _ensureAsrModelReady() async {
  final future = _asrModelManager.ensureReady();
  if (mounted) {
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AsrModelDownloadDialog(manager: _asrModelManager),
    ));
  }
  try {
    final directory = await future;
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
    return directory;
  } catch (_) {
    return null;
  }
}
```

Guard `BuildContext` after async gaps with `if (!mounted) return null;` before using `context`.

- [ ] **Step 5: Sync partial previews into the prompt controller**

Add helper methods to the workbench state.

```dart
void _syncVoicePreview() {
  final preview = _voiceInput.previewText();
  if (_prompt.text == preview) return;
  _prompt.value = TextEditingValue(
    text: preview,
    selection: TextSelection.collapsed(offset: preview.length),
  );
}

Future<void> _stopVoiceInput() async {
  final merged = await _voiceInput.stop(currentPrompt: _prompt.text);
  _prompt.value = TextEditingValue(
    text: merged,
    selection: TextSelection.collapsed(offset: merged.length),
  );
}

Future<void> _cancelVoiceInput() async {
  await _voiceInput.cancel();
  final restored = _voiceInput.restoreBaseText();
  _prompt.value = TextEditingValue(
    text: restored,
    selection: TextSelection.collapsed(offset: restored.length),
  );
}
```

- [ ] **Step 6: Cancel on lifecycle and route exit**

Make the state a `WidgetsBindingObserver` and cancel on backgrounding.

```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.inactive ||
      state == AppLifecycleState.paused ||
      state == AppLifecycleState.detached) {
    unawaited(_cancelVoiceInput());
  }
}
```

When the nested navigator leaves the conversation page or the workbench disposes, call `unawaited(_cancelVoiceInput())` if `_voiceInput.isBusy`.

- [ ] **Step 7: Pass voice state to composer**

Update the `CodingComposer` call site.

```dart
CodingComposer(
  controller: _prompt,
  voiceState: _voiceInput.state,
  voiceEnabled: isVoiceInputPlatformSupported,
  voiceError: _voiceInput.error,
  onVoiceStart: () => unawaited(_startVoiceInput()),
  onVoiceStop: () => unawaited(_stopVoiceInput()),
  onVoiceCancel: () => unawaited(_cancelVoiceInput()),
  onSend: _sendPrompt,
)
```

Windows should either pass `voiceEnabled: false` or hide the mic until manual platform verification is complete.

- [ ] **Step 8: Implement download dialog copyable trace ID**

Add `_AsrModelDownloadDialog` with progress, retry/cancel, and trace ID copy action.

```dart
if (state.traceId != null) ...[
  SelectableText('Trace ID: ${state.traceId}'),
  TextButton.icon(
    onPressed: () => Clipboard.setData(ClipboardData(text: state.traceId!)),
    icon: const Icon(Icons.copy_rounded),
    label: const Text('Copy trace ID'),
  ),
]
```

The dialog must keep `Retry` and `Cancel` visible when `AsrModelStatus.failed`, and `Cancel` must leave any `.part` file intact.

- [ ] **Step 9: Run workbench/composer widget tests**

Run:

```bash
cd mobile && flutter test test\widget_test.dart --plain-name "coding composer"
cd mobile && flutter test test\widget_test.dart --plain-name "workbench"
```

Expected: both pass.

- [ ] **Step 10: Commit workbench wiring**

Run:

```bash
git add mobile/lib/src/features/workbench/coding_workbench_page.dart mobile/test/widget_test.dart
git commit -m "Gate voice input through model preparation" -m "The first microphone press should prepare the local ASR model and then continue the same voice action, while route changes and app backgrounding must stop recording safely.\n\nConstraint: Text input and history navigation must stay fast when voice is unused.\nRejected: Load ASR model on daemon connect | slows unrelated history/session flows.\nConfidence: high\nScope-risk: moderate\nTested: cd mobile && flutter test test\\widget_test.dart --plain-name \"coding composer\"; cd mobile && flutter test test\\widget_test.dart --plain-name \"workbench\""
```

---

### Task 7: Full Verification and Documentation

**Files:**
- Modify: `docs/superpowers/specs/2026-05-07-voice-input-stt-design.md` if implementation decisions differ from the spec.
- Modify: `docs/superpowers/specs/2026-05-08-asr-model-download-design.md` if download behavior differs from the spec.

- [ ] **Step 1: Run Flutter static analysis**

Run: `cd mobile && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: Run focused Flutter tests**

Run:

```bash
cd mobile && flutter test test\voice_input_controller_test.dart test\speech_input_service_test.dart
cd mobile && flutter test test\asr_model_client_test.dart test\asr_model_manager_test.dart
cd mobile && flutter test test\widget_test.dart --plain-name "coding composer"
```

Expected: all pass.

- [ ] **Step 3: Run daemon verification**

Run:

```bash
npm test
npm run lint
```

Expected: both pass.

- [ ] **Step 4: Build Windows debug app**

Run: `cd mobile && flutter build windows --debug`
Expected: build succeeds, and Windows voice affordance is hidden or disabled.

- [ ] **Step 5: Manual Android smoke test**

Run the app on Android and verify these exact checks:

- Text prompt typing and send still work before touching the microphone.
- First microphone press shows model download dialog if model is missing.
- Cancelling download leaves text input unchanged.
- Retrying resumes from `.part` rather than restarting when the daemon supports range.
- After successful extraction, press-hold-release fills prompt text but does not send.
- Typed text plus recognized text uses a newline separator.
- Backgrounding during recording stops microphone and restores pre-recording text.
- Permission denial shows recoverable UI guidance.

- [ ] **Step 6: Update docs for any deviations**

If implementation differs from the design, edit the corresponding spec with a short “Implementation Notes” section. Use this format.

```markdown
## Implementation Notes

- Windows voice input remains disabled pending manual microphone/model verification.
- Model download is triggered only from the microphone action and resumes with HTTP Range when a `.part` file exists.
- Route changes and app lifecycle pauses cancel active recording and preserve only committed text.
```

- [ ] **Step 7: Commit verification notes if docs changed**

Run:

```bash
git add docs/superpowers/specs/2026-05-07-voice-input-stt-design.md docs/superpowers/specs/2026-05-08-asr-model-download-design.md
git commit -m "Record voice input implementation constraints" -m "The voice input design should preserve the operational constraints discovered during implementation so future changes do not reintroduce startup downloads or unsupported Windows behavior.\n\nConstraint: Manual Android and Windows behavior may diverge until device verification is complete.\nConfidence: medium\nScope-risk: narrow\nTested: cd mobile && flutter analyze; focused Flutter tests; npm test; npm run lint; cd mobile && flutter build windows --debug\nNot-tested: Full Android microphone recognition unless completed in manual smoke test"
```

- [ ] **Step 8: Final status check**

Run: `git status --short`
Expected: no unexpected generated or asset files. `daemon/asset/` must remain untracked/ignored.

---

## Self-Review

- Spec coverage: The plan covers editable composer voice input, newline append policy, no auto-send, lazy initialization timeout, permission errors, duplicate start protection, cancellation/background behavior, Windows fallback, daemon-hosted model distribution, Range resume, SHA-256 verification, extraction readiness, and trace ID display.
- Placeholder scan: No task uses unresolved placeholder wording. The only variable path is `<daemon-route-file>` because the exact route registration file must be selected from the current daemon layout before committing.
- Type consistency: `VoiceInputState`, `SpeechInputService`, `VoiceInputController`, `AsrModelClient`, `AsrModelManager`, and `AsrModelStatus` names are consistent across tasks.
- Known implementation note: The current branch may already contain parts of this work. If so, execute each task as a verification checklist: keep passing code, add missing tests/docs only, and commit only real deltas.
