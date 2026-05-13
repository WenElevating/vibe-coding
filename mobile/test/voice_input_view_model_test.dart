import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/ui/features/workbench/voice_input.dart';

class _FakeSpeechInputService implements SpeechInputService {
  int startCalls = 0;
  int stopCalls = 0;
  int cancelCalls = 0;
  void Function(String text)? onPartial;
  Completer<void>? startCompleter;
  String stopText = 'voice result';

  @override
  Future<void> start({required void Function(String text) onPartial}) async {
    startCalls++;
    this.onPartial = onPartial;
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
  test('exposes controller state and preview text', () async {
    final service = _FakeSpeechInputService();
    final viewModel = VoiceInputViewModel(service: service);
    addTearDown(viewModel.dispose);

    await viewModel.start(currentPrompt: 'typed');
    service.onPartial?.call('partial');

    expect(viewModel.state, VoiceInputState.listening);
    expect(viewModel.previewText(), 'typed\npartial');
  });

  test('finishForSend stops listening input', () async {
    final service = _FakeSpeechInputService()..stopText = 'final';
    final viewModel = VoiceInputViewModel(service: service);
    addTearDown(viewModel.dispose);

    await viewModel.start(currentPrompt: 'typed');
    service.onPartial?.call('partial');
    final merged =
        await viewModel.finishForSend(currentPrompt: 'typed\npartial');

    expect(merged, 'typed\nfinal');
    expect(service.stopCalls, 1);
    expect(viewModel.state, VoiceInputState.idle);
  });

  test('finishForSend cancels non-listening input', () async {
    final service = _FakeSpeechInputService()
      ..startCompleter = Completer<void>();
    final viewModel = VoiceInputViewModel(service: service);
    addTearDown(viewModel.dispose);

    final start = viewModel.start(currentPrompt: 'typed');
    final merged = await viewModel.finishForSend(currentPrompt: 'typed');
    service.startCompleter!.complete();
    await start;

    expect(merged, isNull);
    expect(service.cancelCalls, 1);
    expect(service.stopCalls, 0);
    expect(viewModel.state, VoiceInputState.idle);
  });
}
