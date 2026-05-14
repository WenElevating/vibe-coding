import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/services/speech_input_contract.dart'
    as speech_contract;
import 'package:lan_ai_cli_control/src/services/speech_input_service.dart';

void main() {
  tearDown(resetSherpaOnnxInitializationForTest);

  test('pcm16 little endian samples convert to normalized floats', () {
    final bytes = Uint8List.fromList(<int>[
      0x00,
      0x00,
      0x00,
      0x40,
      0x00,
      0x80,
    ]);

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

  test('voice input is available on Windows desktop', () {
    expect(speech_contract.isVoiceInputPlatformSupported, isTrue);
  }, skip: !Platform.isWindows);
}
