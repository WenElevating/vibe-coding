import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/ui/features/workbench/voice_input.dart';

class _FakeSpeechInputService implements SpeechInputService {
  int startCalls = 0;
  int stopCalls = 0;
  int cancelCalls = 0;
  void Function(String text)? onPartial;
  Completer<void>? startCompleter;
  Object? startError;
  String stopText = 'voice result';

  @override
  Future<void> start({required void Function(String text) onPartial}) async {
    startCalls++;
    this.onPartial = onPartial;
    final error = startError;
    if (error != null) throw error;
    final completer = startCompleter;
    if (completer != null) await completer.future;
  }

  @override
  Future<String> stop() async {
    stopCalls++;
    return stopText;
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
  }

  @override
  void dispose() {}
}

void main() {
  test('stop appends voice text at end with newline', () async {
    final service = _FakeSpeechInputService();
    final controller = VoiceInputController(service: service);

    await controller.start(currentPrompt: 'typed context');
    service.onPartial?.call('partial');

    expect(controller.previewText(), 'typed context\npartial');

    final merged = await controller.stop(currentPrompt: 'typed context');

    expect(merged, 'typed context\nvoice result');
    expect(service.startCalls, 1);
    expect(service.stopCalls, 1);
    expect(controller.state, VoiceInputState.idle);
  });

  test('stop keeps visible partial when final text is empty', () async {
    final service = _FakeSpeechInputService()..stopText = '';
    final controller = VoiceInputController(service: service);

    await controller.start(currentPrompt: 'typed context');
    service.onPartial?.call('partial');
    final preview = controller.previewText();

    final merged = await controller.stop(currentPrompt: preview);

    expect(merged, 'typed context\npartial');
    expect(controller.state, VoiceInputState.idle);
  });

  test('stop replaces visible partial with final text', () async {
    final service = _FakeSpeechInputService()..stopText = 'final';
    final controller = VoiceInputController(service: service);

    await controller.start(currentPrompt: 'typed context');
    service.onPartial?.call('partial');

    final merged =
        await controller.stop(currentPrompt: controller.previewText());

    expect(merged, 'typed context\nfinal');
  });

  test(
      'second voice session with no new speech does not append previous result',
      () async {
    final service = _FakeSpeechInputService();
    final controller = VoiceInputController(service: service);

    await controller.start(currentPrompt: '');
    service.onPartial?.call('voice result');
    var merged = await controller.stop(currentPrompt: '');
    expect(merged, 'voice result');

    await controller.start(currentPrompt: merged);
    merged = await controller.stop(currentPrompt: merged);

    expect(merged, 'voice result');
  });

  test('cancel discards uncommitted partial text', () async {
    final service = _FakeSpeechInputService();
    final controller = VoiceInputController(service: service);

    await controller.start(currentPrompt: 'typed');
    service.onPartial?.call('partial');
    await controller.cancel();

    expect(service.cancelCalls, 1);
    expect(controller.state, VoiceInputState.idle);
    expect(controller.partialText, isEmpty);
    expect(controller.restoreBaseText(), 'typed');
  });

  test('duplicate start while initializing is ignored', () async {
    final service = _FakeSpeechInputService()
      ..startCompleter = Completer<void>();
    final controller = VoiceInputController(service: service);

    final first = controller.start(currentPrompt: '');
    final second = controller.start(currentPrompt: '');

    expect(service.startCalls, 1);
    service.startCompleter!.complete();
    await Future.wait<void>([first, second]);

    expect(controller.state, VoiceInputState.listening);
  });

  test('initialize timeout returns failed state and cancels service', () async {
    final service = _FakeSpeechInputService()
      ..startCompleter = Completer<void>();
    final controller = VoiceInputController(
        service: service, initializeTimeout: const Duration(milliseconds: 1));

    await controller.start(currentPrompt: '');

    expect(controller.state, VoiceInputState.failed);
    expect(controller.error, 'Voice input unavailable');
    expect(service.cancelCalls, 1);
  });

  test('missing recording device is reported as a friendly message', () async {
    final service = _FakeSpeechInputService()
      ..startError = PlatformException(code: 'Record', message: '未找到任何录音设备');
    final controller = VoiceInputController(service: service);

    await controller.start(currentPrompt: '');

    expect(controller.state, VoiceInputState.failed);
    expect(controller.error, '未检测到可用麦克风，请连接或启用录音设备后重试。');
    expect(controller.error, isNot(contains('PlatformException')));
  });

  test('microphone permission denial is reported as a friendly message',
      () async {
    final service = _FakeSpeechInputService()
      ..startError = StateError('Microphone permission denied');
    final controller = VoiceInputController(service: service);

    await controller.start(currentPrompt: '');

    expect(controller.state, VoiceInputState.failed);
    expect(controller.error, '麦克风权限未开启，请允许访问麦克风后重试。');
  });
}
