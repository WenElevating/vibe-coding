import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

void main() {
  test('creates sherpa online recognizer for local ASR model', () {
    final modelDirectory = Platform.environment['ASR_MODEL_DIR'];
    if (modelDirectory == null || modelDirectory.isEmpty) {
      markTestSkipped('Set ASR_MODEL_DIR to run the native recognizer smoke.');
      return;
    }

    final encoder = File('$modelDirectory/encoder.onnx');
    final decoder = File('$modelDirectory/decoder.onnx');
    final joiner = File('$modelDirectory/joiner.onnx');
    final tokens = File('$modelDirectory/tokens.txt');
    for (final file in [encoder, decoder, joiner, tokens]) {
      expect(file.existsSync(), true, reason: '${file.path} must exist');
      debugPrint('ASR_SMOKE file ${file.path} bytes=${file.lengthSync()}');
    }

    final sherpaDllDirectory = Platform.environment['SHERPA_DLL_DIR'];
    debugPrint('ASR_SMOKE before initBindings');
    if (sherpaDllDirectory == null || sherpaDllDirectory.isEmpty) {
      sherpa.initBindings();
    } else {
      DynamicLibrary.open('$sherpaDllDirectory\\onnxruntime.dll');
      sherpa.initBindings(sherpaDllDirectory);
    }
    debugPrint('ASR_SMOKE after initBindings');

    final config = sherpa.OnlineRecognizerConfig(
      feat: const sherpa.FeatureConfig(sampleRate: 16000, featureDim: 80),
      model: sherpa.OnlineModelConfig(
        transducer: sherpa.OnlineTransducerModelConfig(
          encoder: encoder.path,
          decoder: decoder.path,
          joiner: joiner.path,
        ),
        tokens: tokens.path,
        modelType: Platform.environment['ASR_MODEL_TYPE'] ?? 'zipformer2',
      ),
    );

    debugPrint('ASR_SMOKE before OnlineRecognizer');
    final recognizer = sherpa.OnlineRecognizer(config);
    debugPrint('ASR_SMOKE after OnlineRecognizer');

    debugPrint('ASR_SMOKE before createStream');
    final stream = recognizer.createStream();
    debugPrint('ASR_SMOKE after createStream $stream');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
