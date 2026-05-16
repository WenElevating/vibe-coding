import 'dart:async';

import 'package:lan_ai_cli_control/src/services/speech_input_service.dart';

class FakeSpeechPermission implements SpeechPermission {
  FakeSpeechPermission({this.granted = true});

  bool granted;

  @override
  Future<bool> request() async => granted;
}

class FakeSpeechRecorder implements SpeechRecorder {
  final StreamController<List<int>> controller = StreamController<List<int>>();
  bool started = false;
  bool stopped = false;
  bool disposed = false;
  bool get hasListener => controller.hasListener;
  Object? startError;

  @override
  Future<Stream<List<int>>> startStream() async {
    final error = startError;
    if (error != null) throw error;
    started = true;
    stopped = false;
    return controller.stream;
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }

  @override
  void dispose() {
    disposed = true;
    unawaited(controller.close());
  }
}

class FakeSpeechRecognizer implements SpeechRecognizer {
  final List<String> partials = <String>[];
  bool canceled = false;
  bool disposed = false;

  @override
  String acceptWaveform(List<int> bytes) {
    if (partials.isEmpty) return '';
    return partials.removeAt(0);
  }

  @override
  String finalResult() {
    if (partials.isEmpty) return '';
    return partials.removeAt(0);
  }

  @override
  void cancel() {
    canceled = true;
  }

  @override
  void dispose() {
    disposed = true;
  }
}
