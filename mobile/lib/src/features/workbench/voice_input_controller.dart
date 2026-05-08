import 'dart:async';

import 'package:flutter/foundation.dart';

enum VoiceInputState {
  idle,
  initializing,
  listening,
  stopping,
  cancelling,
  failed
}

abstract class SpeechInputService {
  Future<void> start({required void Function(String text) onPartial});
  Future<String> stop();
  Future<void> cancel();
  void dispose();
}

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

class VoiceInputController extends ChangeNotifier {
  VoiceInputController({
    required SpeechInputService service,
    Duration initializeTimeout = const Duration(seconds: 5),
  })  : _service = service,
        _initializeTimeout = initializeTimeout;

  final SpeechInputService _service;
  final Duration _initializeTimeout;
  VoiceInputState _state = VoiceInputState.idle;
  String _partialText = '';
  String _baseText = '';
  String? _error;

  VoiceInputState get state => _state;
  String get partialText => _partialText;
  String? get error => _error;
  bool get isBusy =>
      _state != VoiceInputState.idle && _state != VoiceInputState.failed;

  Future<void> start({required String currentPrompt}) async {
    if (_state == VoiceInputState.initializing ||
        _state == VoiceInputState.listening ||
        _state == VoiceInputState.stopping ||
        _state == VoiceInputState.cancelling) {
      return;
    }
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
      _error = error.toString();
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
      _error = error.toString();
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

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }
}
