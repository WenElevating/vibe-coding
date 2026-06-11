# Flutter 本地语音输入（record + sherpa_onnx + permission_handler）

## 1. 效果

实现：

```text
按住说话
   ↓
实时语音识别
   ↓
文字实时显示
   ↓
松开自动发送
```

支持：

- Android
- iOS
- 离线识别
- 中文
- 流式输出

------

# 2. 添加依赖

## pubspec.yaml

```yaml
dependencies:
  flutter:
    sdk: flutter

  record: ^6.1.1
  sherpa_onnx: ^1.13.0
  permission_handler: ^12.0.1
```

安装：

```bash
flutter pub get
```

------

# 3. Android 配置

## android/app/src/main/AndroidManifest.xml

加入：

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.INTERNET"/>
```

------

# 4. iOS 配置

## ios/Runner/Info.plist

加入：

```xml
<key>NSMicrophoneUsageDescription</key>
<string>需要麦克风权限进行语音输入</string>
```

------

# 5. 下载中文模型

推荐模型：

```text
sherpa-onnx-streaming-zipformer-bilingual-zh-en
```

官方下载：

https://github.com/k2-fsa/sherpa-onnx/releases

下载后解压。

------

# 6. 放置模型

创建：

```text
assets/models/
```

放入：

```text
assets/models/
    encoder.onnx
    decoder.onnx
    joiner.onnx
    tokens.txt
```

------

# 7. 注册 assets

## pubspec.yaml

```yaml
flutter:
  assets:
    - assets/models/
```

------

# 8. 语音服务

## lib/speech_service.dart

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart';

class SpeechService {
  final _recorder = AudioRecorder();

  late final StreamingRecognizer _recognizer;
  late final Stream _stream;

  bool _isListening = false;

  Future<void> init() async {
    final config = StreamingRecognizerConfig(
      featConfig: FeatureExtractorConfig(
        sampleRate: 16000,
        featureDim: 80,
      ),
      modelConfig: StreamingModelConfig(
        encoder: 'assets/models/encoder.onnx',
        decoder: 'assets/models/decoder.onnx',
        joiner: 'assets/models/joiner.onnx',
        tokens: 'assets/models/tokens.txt',
      ),
    );

    _recognizer = StreamingRecognizer(config);
    _stream = _recognizer.createStream();
  }

  Future<void> startListening(
    Function(String text) onText,
  ) async {
    if (_isListening) return;

    _isListening = true;

    await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );

    final audioStream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );

    audioStream.listen((data) {
      if (!_isListening) return;

      final samples = _toFloatSamples(data);

      _stream.acceptWaveform(
        samples: samples,
        sampleRate: 16000,
      );

      while (_recognizer.isReady(_stream)) {
        _recognizer.decode(_stream);
      }

      final text = _recognizer.getResult(_stream).text;

      onText(text);
    });
  }

  Future<void> stopListening() async {
    _isListening = false;
    await _recorder.stop();
  }

  List<double> _toFloatSamples(Uint8List bytes) {
    final samples = <double>[];

    for (int i = 0; i < bytes.length; i += 2) {
      final sample = bytes.buffer.asByteData().getInt16(i, Endian.little);
      samples.add(sample / 32768.0);
    }

    return samples;
  }
}
```

------

# 9. 权限申请

## lib/permission_util.dart

```dart
import 'package:permission_handler/permission_handler.dart';

Future<bool> requestMicPermission() async {
  final status = await Permission.microphone.request();

  return status.isGranted;
}
```

------

# 10. 页面集成

## lib/main.dart

```dart
import 'package:flutter/material.dart';

import 'permission_util.dart';
import 'speech_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: SpeechPage(),
    );
  }
}

class SpeechPage extends StatefulWidget {
  const SpeechPage({super.key});

  @override
  State<SpeechPage> createState() => _SpeechPageState();
}

class _SpeechPageState extends State<SpeechPage> {
  final speech = SpeechService();

  String text = '';

  @override
  void initState() {
    super.initState();

    init();
  }

  Future<void> init() async {
    final ok = await requestMicPermission();

    if (!ok) return;

    await speech.init();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('语音输入'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontSize: 20),
              ),
            ),
            GestureDetector(
              onLongPressStart: (_) async {
                await speech.startListening((t) {
                  setState(() {
                    text = t;
                  });
                });
              },
              onLongPressEnd: (_) async {
                await speech.stopListening();

                print('发送消息: $text');
              },
              child: Container(
                width: double.infinity,
                height: 60,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '按住说话',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                  ),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
```

------

# 11. 运行

```bash
flutter run
```

------

# 12. 现在你已经有：

✅ 本地离线识别
✅ 中文流式 ASR
✅ 实时文字输出
✅ 按住说话
✅ 松开发送

------

# 13. 下一步建议（强烈推荐）

## 增加 VAD

现在只是“按住”。

下一步应该：

```text
静音自动结束
```

推荐：

- silero-vad
- sherpa_onnx 自带 VAD

------

# 14. 推荐优化

## 断句恢复

原始：

```text
你好今天帮我写代码
```

优化：

```text
你好，今天帮我写代码。
```

推荐：

- punctuation model
- LLM 后处理

------

# 15. 生产级架构（推荐）

```text
Flutter UI
   ↓
record PCM
   ↓
VAD
   ↓
sherpa streaming
   ↓
文本增量输出
   ↓
LLM punctuation
   ↓
自动发送
```

------

# 16. 常见坑

## 1. sampleRate 必须一致

必须：

```text
16000
```

------

## 2. PCM 格式

必须：

```text
pcm16bits
```

------

## 3. iOS 不弹权限

检查：

```text
NSMicrophoneUsageDescription
```

------

## 4. Android 没声音

检查：

```xml
RECORD_AUDIO
```

------

# 17. 官方文档

record：

https://docs.flutter.dev/cookbook/audio/record

sherpa_onnx：

https://pub.dev/packages/sherpa_onnx

permission_handler：

https://pub.dev/packages/permission_handler