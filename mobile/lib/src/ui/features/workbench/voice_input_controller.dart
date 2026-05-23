import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../services/speech_input_contract.dart';
import '../../../services/speech_text_post_processor.dart';

enum VoiceInputState {
  idle,
  initializing,
  listening,
  stopping,
  cancelling,
  failed
}

class VoiceInputController extends ChangeNotifier {
  VoiceInputController({
    required SpeechInputService service,
    Duration initializeTimeout = const Duration(seconds: 5),
    SpeechTextPostProcessor textPostProcessor = const SpeechTextPostProcessor(),
  })  : _service = service,
        _initializeTimeout = initializeTimeout,
        _textPostProcessor = textPostProcessor;

  SpeechInputService _service;
  final Duration _initializeTimeout;
  final SpeechTextPostProcessor _textPostProcessor;
  VoiceInputState _state = VoiceInputState.idle;
  String _partialText = '';
  String _baseText = '';
  TextSelection _baseSelection = const TextSelection.collapsed(offset: 0);
  String? _error;
  bool _receivedPartial = false;

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

  Future<void> start({
    required String currentPrompt,
    TextSelection? currentSelection,
  }) async {
    if (_state == VoiceInputState.initializing ||
        _state == VoiceInputState.listening ||
        _state == VoiceInputState.stopping ||
        _state == VoiceInputState.cancelling) {
      return;
    }
    _baseText = currentPrompt;
    _baseSelection = _normalizedSelection(
        currentSelection ??
            TextSelection.collapsed(offset: currentPrompt.length),
        currentPrompt.length);
    _partialText = '';
    _receivedPartial = false;
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

  Future<void> startValue({required TextEditingValue currentPrompt}) => start(
      currentPrompt: currentPrompt.text,
      currentSelection: currentPrompt.selection);

  Future<String> stop({required String currentPrompt}) async {
    final merged = await stopValue(
        currentPrompt: TextEditingValue(
            text: currentPrompt,
            selection: TextSelection.collapsed(offset: currentPrompt.length)));
    return merged.text;
  }

  Future<TextEditingValue> stopValue(
      {required TextEditingValue currentPrompt}) async {
    if (_state != VoiceInputState.listening) return currentPrompt;
    _setState(VoiceInputState.stopping);
    try {
      final finalText = await _service.stop();
      final processedFinalText = _textPostProcessor.processFinalText(finalText);
      final preview = previewValue();
      final mergeBase = currentPrompt.text == preview.text
          ? _baseValue()
          : _normalizedValue(currentPrompt);
      final merged = processedFinalText.trim().isEmpty || !_receivedPartial
          ? currentPrompt
          : mergeVoiceTextValue(mergeBase, processedFinalText);
      _partialText = '';
      _receivedPartial = false;
      _baseText = merged.text;
      _baseSelection = merged.selection;
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
      _receivedPartial = false;
      _setState(VoiceInputState.idle);
    }
  }

  String restoreBaseText() => _baseText;

  String previewText() => previewValue().text;

  TextEditingValue previewValue() {
    final base = _baseValue();
    if (_partialText.trim().isEmpty) return base;
    return mergeVoiceTextValue(base, _partialText);
  }

  String mergeVoiceText(String currentPrompt, String voiceText) =>
      mergeVoiceTextValue(
              TextEditingValue(
                  text: currentPrompt,
                  selection:
                      TextSelection.collapsed(offset: currentPrompt.length)),
              voiceText)
          .text;

  TextEditingValue mergeVoiceTextValue(
      TextEditingValue currentPrompt, String voiceText) {
    final trimmedVoice = voiceText.trim();
    if (trimmedVoice.isEmpty) return _normalizedValue(currentPrompt);
    final normalized = _normalizedValue(currentPrompt);
    final text = normalized.text;
    final range = _normalizedRange(normalized.selection, text.length);
    final before = text.substring(0, range.start);
    final after = text.substring(range.end);
    if (after.isEmpty) {
      if (before.isEmpty) {
        return TextEditingValue(
            text: trimmedVoice,
            selection: TextSelection.collapsed(offset: trimmedVoice.length));
      }
      final merged = '$before$trimmedVoice';
      return TextEditingValue(
          text: merged,
          selection: TextSelection.collapsed(offset: merged.length));
    }
    final merged = '$before$trimmedVoice$after';
    return TextEditingValue(
        text: merged,
        selection: TextSelection.collapsed(
            offset: before.length + trimmedVoice.length));
  }

  TextEditingValue _baseValue() =>
      TextEditingValue(text: _baseText, selection: _baseSelection);

  void _setPartialText(String text) {
    _partialText = text;
    _receivedPartial = true;
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

class VoiceInputViewModel extends ChangeNotifier {
  VoiceInputViewModel({
    required SpeechInputService service,
    Duration initializeTimeout = const Duration(seconds: 5),
    SpeechTextPostProcessor textPostProcessor = const SpeechTextPostProcessor(),
  }) : _controller = VoiceInputController(
          service: service,
          initializeTimeout: initializeTimeout,
          textPostProcessor: textPostProcessor,
        ) {
    _controller.addListener(notifyListeners);
  }

  final VoiceInputController _controller;

  VoiceInputState get state => _controller.state;
  String? get error => _controller.error;
  bool get isBusy => _controller.isBusy;

  void updateService(SpeechInputService service) {
    _controller.updateService(service);
  }

  Future<void> start({required String currentPrompt}) =>
      _controller.start(currentPrompt: currentPrompt);

  Future<void> startValue({required TextEditingValue currentPrompt}) =>
      _controller.startValue(currentPrompt: currentPrompt);

  Future<String> stop({required String currentPrompt}) =>
      _controller.stop(currentPrompt: currentPrompt);

  Future<TextEditingValue> stopValue(
          {required TextEditingValue currentPrompt}) =>
      _controller.stopValue(currentPrompt: currentPrompt);

  Future<void> cancel() => _controller.cancel();

  String previewText() => _controller.previewText();

  TextEditingValue previewValue() => _controller.previewValue();

  Future<void> cancelIfBusy() async {
    if (!isBusy) return;
    await cancel();
  }

  Future<String?> finishForSend({required String currentPrompt}) async {
    if (!isBusy) return null;
    if (state == VoiceInputState.listening) {
      return stop(currentPrompt: currentPrompt);
    }
    await cancel();
    return null;
  }

  Future<TextEditingValue?> finishForSendValue(
      {required TextEditingValue currentPrompt}) async {
    if (!isBusy) return null;
    if (state == VoiceInputState.listening) {
      return stopValue(currentPrompt: currentPrompt);
    }
    await cancel();
    return null;
  }

  @override
  void dispose() {
    _controller.removeListener(notifyListeners);
    if (isBusy) {
      unawaited(_controller.cancel().whenComplete(_controller.dispose));
    } else {
      _controller.dispose();
    }
    super.dispose();
  }
}

({int start, int end}) _normalizedRange(TextSelection selection, int length) {
  final normalized = _normalizedSelection(selection, length);
  final start =
      normalized.start < normalized.end ? normalized.start : normalized.end;
  final end =
      normalized.start < normalized.end ? normalized.end : normalized.start;
  return (start: start, end: end);
}

TextEditingValue _normalizedValue(TextEditingValue value) => TextEditingValue(
    text: value.text,
    selection: _normalizedSelection(value.selection, value.text.length));

TextSelection _normalizedSelection(TextSelection selection, int length) {
  final safeLength = length < 0 ? 0 : length;
  final start = selection.isValid ? selection.start : safeLength;
  final end = selection.isValid ? selection.end : safeLength;
  return TextSelection(
      baseOffset: _clampOffset(start, safeLength),
      extentOffset: _clampOffset(end, safeLength),
      affinity: selection.affinity,
      isDirectional: selection.isDirectional);
}

int _clampOffset(int value, int max) {
  if (value < 0) return 0;
  if (value > max) return max;
  return value;
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
