import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/services/speech_input_contract.dart'
    as speech_contract;
import 'package:lan_ai_cli_control/src/services/speech_input_service.dart';

import 'support/fake_speech.dart';

void main() {
  tearDown(resetSherpaOnnxInitializationForTest);

  test('pcm16 little endian samples convert to normalized floats', () {
    final bytes = Uint8List.fromList(<int>[0x00, 0x00, 0x00, 0x40, 0x00, 0x80]);

    final samples = pcm16LittleEndianToFloatSamples(bytes);

    expect(samples, hasLength(3));
    expect(samples[0], 0);
    expect(samples[1], closeTo(0.5, 0.0001));
    expect(samples[2], -1);
  });

  test('sherpa onnx initialization is lazy and idempotent', () {
    var calls = 0;
    sherpaOnnxInitializer = () {
      calls++;
    };

    ensureSherpaOnnxInitialized();
    ensureSherpaOnnxInitialized();

    expect(calls, 1);
  });

  test('failed sherpa onnx initialization can be retried', () {
    var calls = 0;
    sherpaOnnxInitializer = () {
      calls++;
      if (calls == 1) throw StateError('missing native library');
    };

    expect(ensureSherpaOnnxInitialized, throwsStateError);
    ensureSherpaOnnxInitialized();

    expect(calls, 2);
  });

  test('test speech fakes compile against speech seams', () async {
    final permission = FakeSpeechPermission();
    final recorder = FakeSpeechRecorder();
    final recognizer = FakeSpeechRecognizer()..partials.add('partial');

    expect(await permission.request(), isTrue);
    expect(await recorder.startStream(), isA<Stream<List<int>>>());
    expect(recognizer.acceptWaveform(<int>[0, 0]), 'partial');

    recognizer.cancel();
    recorder.dispose();
    recognizer.dispose();

    expect(recognizer.canceled, isTrue);
    expect(recorder.disposed, isTrue);
    expect(recognizer.disposed, isTrue);
  });

  test('permission denied does not start recorder', () async {
    final permission = FakeSpeechPermission(granted: false);
    final recorder = FakeSpeechRecorder();
    var recognizerCreated = false;
    final service = SherpaSpeechInputService(
      modelDirectory: 'unused',
      permissionFactory: () => permission,
      recorderFactory: () => recorder,
      recognizerFactory: (_) {
        recognizerCreated = true;
        return FakeSpeechRecognizer();
      },
    );

    await expectLater(
      service.start(onPartial: (_) {}),
      throwsA(isA<StateError>()),
    );

    expect(recorder.started, isFalse);
    expect(recorder.stopped, isFalse);
    expect(recognizerCreated, isFalse);
  });

  test('recorder start failure cleans up and can be retried', () async {
    final permission = FakeSpeechPermission();
    final recorder = FakeSpeechRecorder()
      ..startError = StateError('recorder unavailable');
    final recognizer = FakeSpeechRecognizer();
    final partials = <String>[];
    final service = SherpaSpeechInputService(
      modelDirectory: 'unused',
      permissionFactory: () => permission,
      recorderFactory: () => recorder,
      recognizerFactory: (_) => recognizer,
    );

    await expectLater(
      service.start(onPartial: partials.add),
      throwsA(isA<StateError>()),
    );

    expect(recorder.started, isFalse);
    expect(recorder.stopped, isTrue);
    expect(recognizer.canceled, isTrue);

    recorder.startError = null;
    recognizer.canceled = false;
    recognizer.partials.add('retry partial');

    await service.start(onPartial: partials.add);
    recorder.controller.add(<int>[0, 0]);
    await pumpEventQueue();

    expect(recorder.started, isTrue);
    expect(recognizer.canceled, isTrue);
    expect(partials, <String>['retry partial']);

    await service.stop();
    expect(recorder.stopped, isTrue);
  });

  test('recognizer setup failure can be retried', () async {
    final recorder = FakeSpeechRecorder();
    var recognizerAttempts = 0;
    final service = SherpaSpeechInputService(
      modelDirectory: 'unused',
      permissionFactory: () => FakeSpeechPermission(),
      recorderFactory: () => recorder,
      recognizerFactory: (_) {
        recognizerAttempts++;
        if (recognizerAttempts == 1) {
          throw StateError('recognizer unavailable');
        }
        return FakeSpeechRecognizer()..partials.add('retry partial');
      },
    );

    await expectLater(
      service.start(onPartial: (_) {}),
      throwsA(isA<StateError>()),
    );

    expect(recorder.started, isFalse);
    expect(recorder.stopped, isTrue);

    final partials = <String>[];
    await service.start(onPartial: partials.add);
    recorder.controller.add(<int>[0, 0]);
    await pumpEventQueue();

    expect(recognizerAttempts, 2);
    expect(recorder.started, isTrue);
    expect(partials, <String>['retry partial']);
  });

  test('cancel stops recorder and cancels recognizer', () async {
    final recorder = FakeSpeechRecorder();
    final recognizer = FakeSpeechRecognizer()..partials.add('partial');
    final service = SherpaSpeechInputService(
      modelDirectory: 'unused',
      permissionFactory: () => FakeSpeechPermission(),
      recorderFactory: () => recorder,
      recognizerFactory: (_) => recognizer,
    );

    await service.start(onPartial: (_) {});
    recognizer.canceled = false;

    await service.cancel();

    expect(recorder.stopped, isTrue);
    expect(recognizer.canceled, isTrue);
  });

  test('stop cancels subscription and returns final text', () async {
    final recorder = FakeSpeechRecorder();
    final recognizer = FakeSpeechRecognizer()
      ..partials.add('partial')
      ..partials.add('final');
    final partials = <String>[];
    final service = SherpaSpeechInputService(
      modelDirectory: 'unused',
      permissionFactory: () => FakeSpeechPermission(),
      recorderFactory: () => recorder,
      recognizerFactory: (_) => recognizer,
    );

    await service.start(onPartial: partials.add);
    recorder.controller.add(<int>[0, 0]);
    await pumpEventQueue();

    expect(partials, <String>['partial']);
    expect(recorder.hasListener, isTrue);

    final finalText = await service.stop();

    expect(finalText, 'final');
    expect(recorder.stopped, isTrue);
    expect(recorder.hasListener, isFalse);
  });

  test('dispose tears down recorder and recognizer', () async {
    final recorder = FakeSpeechRecorder();
    final recognizer = FakeSpeechRecognizer();
    final service = SherpaSpeechInputService(
      modelDirectory: 'unused',
      permissionFactory: () => FakeSpeechPermission(),
      recorderFactory: () => recorder,
      recognizerFactory: (_) => recognizer,
    );

    await service.start(onPartial: (_) {});
    service.dispose();

    expect(recorder.disposed, isTrue);
    expect(recognizer.disposed, isTrue);
  });

  test('voice input is available on Windows desktop', () {
    expect(speech_contract.isVoiceInputPlatformSupported, isTrue);
  }, skip: !Platform.isWindows);
}
