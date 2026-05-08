import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../features/workbench/voice_input.dart';

const _sampleRate = 16000;

typedef SherpaOnnxInitializer = void Function();

@visibleForTesting
SherpaOnnxInitializer sherpaOnnxInitializer = _initializeSherpaOnnxBindings;

bool _sherpaOnnxInitialized = false;
DynamicLibrary? _onnxRuntimeLibrary;

void ensureSherpaOnnxInitialized() {
  if (_sherpaOnnxInitialized) return;
  sherpaOnnxInitializer();
  _sherpaOnnxInitialized = true;
}

@visibleForTesting
void resetSherpaOnnxInitializationForTest() {
  _sherpaOnnxInitialized = false;
  sherpaOnnxInitializer = _initializeSherpaOnnxBindings;
}

void _initializeSherpaOnnxBindings() {
  final libraryDirectory = _sherpaOnnxLibraryDirectory();
  if (libraryDirectory == null) {
    sherpa.initBindings();
    return;
  }
  final onnxRuntime = File('$libraryDirectory\\onnxruntime.dll');
  if (onnxRuntime.existsSync()) {
    _onnxRuntimeLibrary ??= DynamicLibrary.open(onnxRuntime.path);
  }
  sherpa.initBindings(libraryDirectory);
}

String? _sherpaOnnxLibraryDirectory() {
  if (!Platform.isWindows) return null;
  final executableDirectory = File(Platform.resolvedExecutable).parent;
  final sherpaDll = File('${executableDirectory.path}\\sherpa-onnx-c-api.dll');
  if (sherpaDll.existsSync()) return executableDirectory.path;
  return null;
}

Float32List pcm16LittleEndianToFloatSamples(Uint8List bytes) {
  final data =
      bytes.buffer.asByteData(bytes.offsetInBytes, bytes.lengthInBytes);
  final samples = Float32List(bytes.length ~/ 2);
  for (var index = 0; index < samples.length; index++) {
    samples[index] = data.getInt16(index * 2, Endian.little) / 32768.0;
  }
  return samples;
}

class SherpaSpeechInputService implements SpeechInputService {
  SherpaSpeechInputService({required this.modelDirectory});

  final String modelDirectory;
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _audioSubscription;
  sherpa.OnlineRecognizer? _recognizer;
  sherpa.OnlineStream? _recognizerStream;
  bool _started = false;
  String _latestText = '';

  @override
  Future<void> start({required void Function(String text) onPartial}) async {
    if (_started) return;
    final permission = await Permission.microphone.request();
    if (!permission.isGranted) {
      throw StateError('Microphone permission denied');
    }
    await _ensureRecognizer();
    final recognizer = _recognizer!;
    final stream = _recognizerStream!;
    _started = true;
    final audioStream = await _recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: 1));
    _audioSubscription = audioStream.listen((data) {
      final samples = pcm16LittleEndianToFloatSamples(data);
      stream.acceptWaveform(samples: samples, sampleRate: _sampleRate);
      while (recognizer.isReady(stream)) {
        recognizer.decode(stream);
      }
      _latestText = recognizer.getResult(stream).text;
      onPartial(_latestText);
    });
  }

  Future<void> _ensureRecognizer() async {
    if (_recognizer != null) return;
    ensureSherpaOnnxInitialized();
    final model = sherpa.OnlineModelConfig(
        transducer: sherpa.OnlineTransducerModelConfig(
            encoder: '$modelDirectory/encoder.onnx',
            decoder: '$modelDirectory/decoder.onnx',
            joiner: '$modelDirectory/joiner.onnx'),
        tokens: '$modelDirectory/tokens.txt',
        modelType: 'zipformer');
    final config = sherpa.OnlineRecognizerConfig(
        feat:
            const sherpa.FeatureConfig(sampleRate: _sampleRate, featureDim: 80),
        model: model);
    _recognizer = sherpa.OnlineRecognizer(config);
    _recognizerStream = _recognizer!.createStream();
  }

  @override
  Future<String> stop() async {
    _started = false;
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _recorder.stop();
    return _latestText;
  }

  @override
  Future<void> cancel() async {
    _latestText = '';
    _started = false;
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _recorder.stop();
  }

  @override
  void dispose() {
    unawaited(_audioSubscription?.cancel());
    _recorder.dispose();
  }
}
