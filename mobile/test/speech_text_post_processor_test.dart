import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/services/speech_text_post_processor.dart';

void main() {
  const processor = SpeechTextPostProcessor();

  test('adds conservative Chinese punctuation to command text', () {
    final result = processor.processFinalText('帮我看一下这个文件然后提交代码');

    expect(result, '帮我看一下这个文件，然后提交代码。');
  });

  test('uses question mark for question-like Chinese text', () {
    final result = processor.processFinalText('这个能不能先出一个方案');

    expect(result, '这个能不能先出一个方案？');
  });

  test('normalizes common coding domain terms', () {
    final result = processor.processFinalText('codex 帮我运行 flutter test');

    expect(result, 'Codex 帮我运行 Flutter test。');
  });

  test('leaves non-Chinese command text without synthetic punctuation', () {
    final result = processor.processFinalText('git status');

    expect(result, 'Git status');
  });

  test('does not add commas when sentence punctuation already exists', () {
    final result = processor.processFinalText('帮我看一下这个文件，然后提交代码');

    expect(result, '帮我看一下这个文件，然后提交代码。');
  });
}
