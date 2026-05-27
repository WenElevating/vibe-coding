import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'speech_input_contract.dart';

export 'speech_input_contract.dart';

const _sampleRate = 16000;

typedef SherpaOnnxInitializer = void Function();
typedef SpeechPermissionFactory = SpeechPermission Function();
typedef SpeechRecorderFactory = SpeechRecorder Function();
typedef SpeechRecognizerFactory = SpeechRecognizer Function(
    String modelDirectory);

abstract class SpeechPermission {
  Future<bool> request();
}

abstract class SpeechRecorder {
  Future<Stream<List<int>>> startStream();
  Future<void> stop();
  void dispose();
}

abstract class SpeechRecognizer {
  String acceptWaveform(List<int> bytes);
  String finalResult();
  void cancel() {}
  void dispose();
}

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
  final data = bytes.buffer.asByteData(
    bytes.offsetInBytes,
    bytes.lengthInBytes,
  );
  final samples = Float32List(bytes.length ~/ 2);
  for (var index = 0; index < samples.length; index++) {
    samples[index] = data.getInt16(index * 2, Endian.little) / 32768.0;
  }
  return samples;
}

class SherpaSpeechInputService implements SpeechInputService {
  SherpaSpeechInputService({
    required this.modelDirectory,
    SpeechPermissionFactory? permissionFactory,
    SpeechRecorderFactory? recorderFactory,
    SpeechRecognizerFactory? recognizerFactory,
  })  : _permission = (permissionFactory ?? _defaultPermissionFactory)(),
        _recorder = (recorderFactory ?? _defaultRecorderFactory)(),
        _recognizerFactory = recognizerFactory ?? _defaultRecognizerFactory;

  final String modelDirectory;
  final SpeechPermission _permission;
  final SpeechRecorder _recorder;
  final SpeechRecognizerFactory _recognizerFactory;
  StreamSubscription<List<int>>? _audioSubscription;
  SpeechRecognizer? _recognizer;
  bool _started = false;
  bool _disposed = false;
  String _latestText = '';

  @override
  Future<void> start({required void Function(String text) onPartial}) async {
    if (_disposed || _started) return;
    _latestText = '';
    final permissionGranted = await _permission.request();
    if (_disposed) return;
    if (!permissionGranted) {
      throw StateError('Microphone permission denied');
    }
    try {
      await _ensureRecognizer();
      if (_disposed) return;
      final recognizer = _recognizer!;
      recognizer.cancel();
      final audioStream = await _recorder.startStream();
      if (_disposed) {
        await _recorder.stop().catchError((Object _) => null);
        return;
      }
      _audioSubscription = audioStream.listen((data) {
        if (_disposed) return;
        _latestText = recognizer.acceptWaveform(data);
        onPartial(_latestText);
      });
      _started = true;
    } catch (_) {
      await _cleanupFailedStart();
      rethrow;
    }
  }

  Future<void> _cleanupFailedStart() async {
    _started = false;
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _recorder.stop().catchError((Object _) => null);
    _recognizer?.cancel();
  }

  Future<void> _ensureRecognizer() async {
    if (_recognizer != null) return;
    _recognizer = _recognizerFactory(modelDirectory);
  }

  @override
  Future<String> stop() async {
    if (_disposed) return _latestText;
    _started = false;
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _recorder.stop();
    final finalText = _recognizer?.finalResult() ?? '';
    if (finalText.isNotEmpty) {
      _latestText = finalText;
    }
    return _latestText;
  }

  @override
  Future<void> cancel() async {
    if (_disposed) return;
    _latestText = '';
    _started = false;
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _recorder.stop();
    _recognizer?.cancel();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _started = false;
    unawaited(_audioSubscription?.cancel());
    _audioSubscription = null;
    _recognizer?.dispose();
    _recognizer = null;
    _recorder.dispose();
  }
}

SpeechPermission _defaultPermissionFactory() => _MicrophoneSpeechPermission();

SpeechRecorder _defaultRecorderFactory() => _AudioSpeechRecorder();

SpeechRecognizer _defaultRecognizerFactory(String modelDirectory) =>
    _SherpaSpeechRecognizer(modelDirectory);

class _MicrophoneSpeechPermission implements SpeechPermission {
  @override
  Future<bool> request() async {
    final permission = await Permission.microphone.request();
    return permission.isGranted;
  }
}

class _AudioSpeechRecorder implements SpeechRecorder {
  final AudioRecorder _recorder = AudioRecorder();

  @override
  Future<Stream<List<int>>> startStream() => _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _sampleRate,
          numChannels: 1,
        ),
      );

  @override
  Future<void> stop() => _recorder.stop();

  @override
  void dispose() {
    _recorder.dispose();
  }
}

class _SherpaSpeechRecognizer implements SpeechRecognizer {
  _SherpaSpeechRecognizer(String modelDirectory)
      : _recognizer = _createRecognizer(modelDirectory);

  final sherpa.OnlineRecognizer _recognizer;
  sherpa.OnlineStream? _stream;
  String _latestText = '';

  @override
  String acceptWaveform(List<int> bytes) {
    final stream = _stream ??= _recognizer.createStream();
    final samples = pcm16LittleEndianToFloatSamples(Uint8List.fromList(bytes));
    stream.acceptWaveform(samples: samples, sampleRate: _sampleRate);
    while (_recognizer.isReady(stream)) {
      _recognizer.decode(stream);
    }
    _latestText = _recognizer.getResult(stream).text;
    return _latestText;
  }

  @override
  String finalResult() {
    final stream = _stream;
    if (stream == null) return _latestText;
    stream.inputFinished();
    stream.free();
    _stream = null;
    return _latestText;
  }

  @override
  void cancel() {
    _stream?.free();
    _stream = null;
  }

  @override
  void dispose() {
    cancel();
    _recognizer.free();
  }
}

sherpa.OnlineRecognizer _createRecognizer(String modelDirectory) {
  ensureSherpaOnnxInitialized();
  final model = sherpa.OnlineModelConfig(
    transducer: sherpa.OnlineTransducerModelConfig(
      encoder: '$modelDirectory/encoder.onnx',
      decoder: '$modelDirectory/decoder.onnx',
      joiner: '$modelDirectory/joiner.onnx',
    ),
    tokens: '$modelDirectory/tokens.txt',
    modelType: 'zipformer',
  );
  final config = sherpa.OnlineRecognizerConfig(
    feat: const sherpa.FeatureConfig(sampleRate: _sampleRate, featureDim: 80),
    model: model,
  );
  return sherpa.OnlineRecognizer(config);
}
