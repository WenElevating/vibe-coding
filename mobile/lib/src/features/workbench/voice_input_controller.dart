import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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
      _state != VoiceInputState.idle && _state != VoiceInputState.failed;

  void updateService(SpeechInputService service) {
    if (identical(_service, service)) return;
    if (isBusy) {
      throw StateError(
          'Cannot replace voice input service while it is active.');
    }
    _service.dispose();
    _service = service;
    _error = null;
    if (_state == VoiceInputState.failed) _setState(VoiceInputState.idle);
  }

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

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }
}

@visibleForTesting
String friendlyVoiceInputError(Object error) {
  if (error is PlatformException) {
    final details = [
      error.code,
      if (error.message != null) error.message!,
      if (error.details != null) error.details.toString(),
    ].join(' ').toLowerCase();
    if (details.contains('no recording device') ||
        details.contains('no input device') ||
        details.contains('not found') ||
        details.contains('未找到') ||
        details.contains('录音设备') ||
        details.contains('麦克风')) {
      return '未检测到可用麦克风，请连接或启用录音设备后重试。';
    }
    return '语音输入暂时不可用，请检查麦克风权限或设备状态后重试。';
  }
  if (error is StateError && error.message == 'Microphone permission denied') {
    return '麦克风权限未开启，请允许访问麦克风后重试。';
  }
  return '语音输入暂时不可用，请稍后重试。';
}
