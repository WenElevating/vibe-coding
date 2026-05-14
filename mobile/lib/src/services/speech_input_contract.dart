import 'dart:io';

import 'package:flutter/foundation.dart';

abstract class SpeechInputService {
  Future<void> start({required void Function(String text) onPartial});
  Future<String> stop();
  Future<void> cancel();
  void dispose();
}

typedef SpeechInputServiceBuilder = SpeechInputService Function(
    String modelDirectory);

bool get isVoiceInputPlatformSupported =>
    !kIsWeb &&
    (Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isMacOS ||
        Platform.isLinux ||
        Platform.isWindows);

class DisabledSpeechInputService implements SpeechInputService {
  const DisabledSpeechInputService();

  @override
  Future<void> start({required void Function(String text) onPartial}) {
    throw StateError('Voice input is not available on this platform yet.');
  }

  @override
  Future<String> stop() async => '';

  @override
  Future<void> cancel() async {}

  @override
  void dispose() {}
}
