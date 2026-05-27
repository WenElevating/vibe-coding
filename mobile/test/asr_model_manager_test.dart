import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/services/asr_model_client.dart';
import 'package:lan_ai_cli_control/src/services/asr_model_manager.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('asr-model-manager-test-');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('ready model directory skips download', () async {
    final readyDir = Directory(
        '${tempDir.path}${Platform.pathSeparator}asr_models${Platform.pathSeparator}model-v1')
      ..createSync(recursive: true);
    for (final file in AsrModelManager.requiredFiles) {
      File('${readyDir.path}/$file').writeAsStringSync('ok');
    }
    final client = _FakeAsrModelClient(metadata: _metadata(_zipBytes()));
    final manager = AsrModelManager(
        client: client, supportDirectoryProvider: () async => tempDir);

    final path = await manager.ensureReady();

    expect(path, readyDir.path);
    expect(client.downloadCalls, 0);
    expect(manager.state.status, AsrModelStatus.ready);
  });

  test('existing partial file resumes from its current length', () async {
    final bytes = _zipBytes();
    final metadata = _metadata(bytes);
    final root = Directory('${tempDir.path}/asr_models')..createSync();
    File('${root.path}/model-v1.zip.part')
        .writeAsBytesSync(bytes.sublist(0, 8));
    final client = _FakeAsrModelClient(
        metadata: metadata,
        downloadHandler: (start) => _downloadResponse(
            206,
            bytes.sublist(start ?? 0),
            'bytes ${start ?? 0}-${bytes.length - 1}/${bytes.length}'));
    final manager = AsrModelManager(
        client: client, supportDirectoryProvider: () async => tempDir);

    await manager.ensureReady();

    expect(client.requestedStarts, <int?>[8]);
    expect(manager.state.status, AsrModelStatus.ready);
    expect(File('${root.path}/model-v1/encoder.onnx').existsSync(), true);
  });

  test('mismatched partial response resets and restarts from byte zero',
      () async {
    final bytes = _zipBytes();
    final metadata = _metadata(bytes);
    final root = Directory('${tempDir.path}/asr_models')..createSync();
    File('${root.path}/model-v1.zip.part')
        .writeAsBytesSync(bytes.sublist(0, 8));
    var call = 0;
    final client = _FakeAsrModelClient(
        metadata: metadata,
        downloadHandler: (start) {
          call++;
          if (call == 1) {
            return _downloadResponse(
                206, bytes, 'bytes 0-${bytes.length - 1}/${bytes.length}');
          }
          return _downloadResponse(200, bytes, null);
        });
    final manager = AsrModelManager(
        client: client, supportDirectoryProvider: () async => tempDir);

    await manager.ensureReady();

    expect(client.requestedStarts, <int?>[8, 0]);
    expect(manager.state.status, AsrModelStatus.ready);
  });

  test('SHA-256 mismatch fails and removes corrupted zip', () async {
    final bytes = _zipBytes();
    final client = _FakeAsrModelClient(
        metadata: _metadata(bytes, sha256Value: 'bad'),
        downloadHandler: (_) => _downloadResponse(200, bytes, null));
    final manager = AsrModelManager(
        client: client, supportDirectoryProvider: () async => tempDir);

    await expectLater(manager.ensureReady(), throwsA(isA<StateError>()));

    expect(manager.state.status, AsrModelStatus.failed);
    expect(File('${tempDir.path}/asr_models/model-v1.zip').existsSync(), false);
  });

  test('extraction validates required model files', () async {
    final bytes = _zipBytes(files: const <String, String>{'encoder.onnx': 'x'});
    final client = _FakeAsrModelClient(
        metadata: _metadata(bytes),
        downloadHandler: (_) => _downloadResponse(200, bytes, null));
    final manager = AsrModelManager(
        client: client, supportDirectoryProvider: () async => tempDir);

    await expectLater(manager.ensureReady(), throwsA(isA<StateError>()));

    expect(manager.state.status, AsrModelStatus.failed);
    expect(
        Directory('${tempDir.path}/asr_models/model-v1').existsSync(), false);
  });

  test('extraction rejects archive path traversal entries', () async {
    final bytes = _zipBytes(files: const <String, String>{
      'encoder.onnx': 'encoder',
      'decoder.onnx': 'decoder',
      'joiner.onnx': 'joiner',
      'tokens.txt': 'tokens',
      '../escape.txt': 'escaped',
    });
    final client = _FakeAsrModelClient(
        metadata: _metadata(bytes),
        downloadHandler: (_) => _downloadResponse(200, bytes, null));
    final manager = AsrModelManager(
        client: client, supportDirectoryProvider: () async => tempDir);

    await expectLater(manager.ensureReady(), throwsA(isA<StateError>()));

    expect(manager.state.status, AsrModelStatus.failed);
    expect(File('${tempDir.path}/asr_models/escape.txt').existsSync(), false);
    expect(
        Directory('${tempDir.path}/asr_models/model-v1.staging').existsSync(),
        false);
    expect(
        Directory('${tempDir.path}/asr_models/model-v1.normalized')
            .existsSync(),
        false);
    expect(
        Directory('${tempDir.path}/asr_models/model-v1').existsSync(), false);
  });

  test('extraction rejects unsafe absolute and dot archive paths', () async {
    for (final unsafePath in <String>[
      '/absolute.txt',
      r'C:\Users\Alice\absolute.txt',
      r'nested\..\escape.txt',
      '.',
    ]) {
      final bytes = _zipBytes(files: <String, String>{
        'encoder.onnx': 'encoder',
        'decoder.onnx': 'decoder',
        'joiner.onnx': 'joiner',
        'tokens.txt': 'tokens',
        unsafePath: 'unsafe',
      });
      final client = _FakeAsrModelClient(
          metadata: _metadata(bytes),
          downloadHandler: (_) => _downloadResponse(200, bytes, null));
      final manager = AsrModelManager(
          client: client, supportDirectoryProvider: () async => tempDir);

      await expectLater(manager.ensureReady(), throwsA(isA<StateError>()));

      expect(manager.state.status, AsrModelStatus.failed);
      expect(
          Directory('${tempDir.path}/asr_models/model-v1.staging').existsSync(),
          false);
      expect(
          Directory('${tempDir.path}/asr_models/model-v1.normalized')
              .existsSync(),
          false);
      expect(
          Directory('${tempDir.path}/asr_models/model-v1').existsSync(), false);
    }
  });

  test('extraction rejects archives with too many files', () async {
    final archive = Archive();
    for (final entry in const <String, String>{
      'encoder.onnx': 'encoder',
      'decoder.onnx': 'decoder',
      'joiner.onnx': 'joiner',
      'tokens.txt': 'tokens',
    }.entries) {
      archive.addFile(ArchiveFile.string(entry.key, entry.value));
    }
    for (var index = 0; index < 4093; index++) {
      archive.addFile(ArchiveFile.string('extra-$index.txt', ''));
    }
    final bytes = ZipEncoder().encode(archive);
    final client = _FakeAsrModelClient(
        metadata: _metadata(bytes),
        downloadHandler: (_) => _downloadResponse(200, bytes, null));
    final manager = AsrModelManager(
        client: client, supportDirectoryProvider: () async => tempDir);

    await expectLater(manager.ensureReady(), throwsA(isA<StateError>()));

    expect(manager.state.status, AsrModelStatus.failed);
    expect(
        Directory('${tempDir.path}/asr_models/model-v1.staging').existsSync(),
        false);
    expect(
        Directory('${tempDir.path}/asr_models/model-v1').existsSync(), false);
  });

  test('extraction normalizes nested Sherpa archive file names', () async {
    final bytes = _zipBytes(files: const <String, String>{
      'real-model/encoder-epoch-99-avg-1.int8.onnx': 'encoder',
      'real-model/decoder-epoch-99-avg-1.onnx': 'decoder',
      'real-model/joiner-epoch-99-avg-1.int8.onnx': 'joiner',
      'real-model/tokens.txt': 'tokens',
    });
    final client = _FakeAsrModelClient(
        metadata: _metadata(bytes),
        downloadHandler: (_) => _downloadResponse(200, bytes, null));
    final manager = AsrModelManager(
        client: client, supportDirectoryProvider: () async => tempDir);

    final modelPath = await manager.ensureReady();

    expect(File('$modelPath/encoder.onnx').readAsStringSync(), 'encoder');
    expect(File('$modelPath/decoder.onnx').readAsStringSync(), 'decoder');
    expect(File('$modelPath/joiner.onnx').readAsStringSync(), 'joiner');
    expect(File('$modelPath/tokens.txt').readAsStringSync(), 'tokens');
  });

  test('cancel leaves partial data and does not reach ready', () async {
    final bytes = _zipBytes();
    final releaseStream = Completer<void>();
    final client = _FakeAsrModelClient(
        metadata: _metadata(bytes),
        downloadHandler: (_) => AsrModelDownloadResponse(
            statusCode: 200,
            headers: const <String, String>{},
            stream: (() async* {
              yield bytes.sublist(0, 10);
              await releaseStream.future;
            })()));
    final manager = AsrModelManager(
        client: client, supportDirectoryProvider: () async => tempDir);

    final task = manager.ensureReady();
    final expectedCancellation = expectLater(task, throwsA(anything));
    final part = File(
        '${tempDir.path}${Platform.pathSeparator}asr_models${Platform.pathSeparator}model-v1.zip.part');
    for (var attempt = 0; attempt < 20 && !part.existsSync(); attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    manager.cancel();
    releaseStream.complete();

    await expectedCancellation;
    expect(manager.state.status, AsrModelStatus.cancelled);
    expect(part.existsSync(), true);
  });

  test('concurrent ensureReady calls share the active preparation', () async {
    final bytes = _zipBytes();
    final releaseStream = Completer<void>();
    var activeDownloadStarted = false;
    final client = _FakeAsrModelClient(
        metadata: _metadata(bytes),
        downloadHandler: (_) {
          if (releaseStream.isCompleted) {
            return _downloadResponse(200, bytes, null);
          }
          if (activeDownloadStarted) {
            throw StateError('duplicate ASR model download');
          }
          activeDownloadStarted = true;
          return AsrModelDownloadResponse(
              statusCode: 200,
              headers: const <String, String>{},
              stream: (() async* {
                yield bytes.sublist(0, 10);
                await releaseStream.future;
                yield bytes.sublist(10);
              })());
        });
    final manager = AsrModelManager(
        client: client, supportDirectoryProvider: () async => tempDir);

    final first = manager.ensureReady();
    for (var attempt = 0;
        attempt < 20 && manager.state.status != AsrModelStatus.downloading;
        attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(manager.state.status, AsrModelStatus.downloading);

    final second = manager.ensureReady();
    releaseStream.complete();

    final firstPath = await first;
    final secondPath = await second;

    expect(firstPath, secondPath);
    expect(client.metadataCalls, 1);
    expect(client.downloadCalls, 1);
    expect(manager.state.status, AsrModelStatus.ready);
  });

  test('resume download failure updates state without unhandled async error',
      () async {
    final bytes = _zipBytes();
    final releaseStream = Completer<void>();
    var downloadCalls = 0;
    final client = _FakeAsrModelClient(
        metadata: _metadata(bytes),
        downloadHandler: (_) {
          downloadCalls++;
          if (downloadCalls == 1) {
            return AsrModelDownloadResponse(
                statusCode: 200,
                headers: const <String, String>{},
                stream: (() async* {
                  yield bytes.sublist(0, 10);
                  await releaseStream.future;
                })());
          }
          throw const AsrModelClientException(503, <String, Object?>{
            'error': <String, Object?>{
              'message': 'download unavailable',
              'traceId': 'trace-1',
            },
          });
        });
    final manager = AsrModelManager(
        client: client, supportDirectoryProvider: () async => tempDir);

    final task = manager.ensureReady();
    final expectedPause = expectLater(task, throwsA(anything));
    for (var attempt = 0;
        attempt < 20 && manager.state.status != AsrModelStatus.downloading;
        attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(manager.state.status, AsrModelStatus.downloading);

    manager.pause();
    releaseStream.complete();
    await expectedPause;

    expect(manager.state.status, AsrModelStatus.paused);

    manager.resume();
    for (var attempt = 0;
        attempt < 20 && manager.state.status != AsrModelStatus.failed;
        attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(manager.state.status, AsrModelStatus.failed);
    expect(manager.state.errorMessage, 'download unavailable');
    expect(manager.state.traceId, 'trace-1');
  });

  test('dispose during download suppresses later state notifications',
      () async {
    final bytes = _zipBytes();
    final releaseStream = Completer<void>();
    final client = _FakeAsrModelClient(
        metadata: _metadata(bytes),
        downloadHandler: (_) => AsrModelDownloadResponse(
            statusCode: 200,
            headers: const <String, String>{},
            stream: (() async* {
              yield bytes.sublist(0, 10);
              await releaseStream.future;
              yield bytes.sublist(10);
            })()));
    final manager = AsrModelManager(
        client: client, supportDirectoryProvider: () async => tempDir);

    final task = manager.ensureReady();
    final expectedCancellation = expectLater(task, throwsA(anything));
    for (var attempt = 0;
        attempt < 20 && manager.state.status != AsrModelStatus.downloading;
        attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(manager.state.status, AsrModelStatus.downloading);

    manager.dispose();
    releaseStream.complete();

    await expectedCancellation;
    expect(manager.state.status, AsrModelStatus.downloading);
  });
}

AsrModelMetadata _metadata(List<int> bytes, {String? sha256Value}) =>
    AsrModelMetadata(
      version: 'model-v1',
      fileName: 'model-v1.zip',
      sizeBytes: bytes.length,
      sha256: sha256Value ?? sha256.convert(bytes).toString(),
      downloadPath: '/api/asr-model/download',
    );

List<int> _zipBytes({Map<String, String>? files}) {
  final rawEntries = files ??
      const <String, String>{
        'encoder.onnx': 'encoder',
        'decoder.onnx': 'decoder',
        'joiner.onnx': 'joiner',
        'tokens.txt': 'tokens',
      };
  if (rawEntries.keys.any(_requiresSyntheticArchive)) {
    return _archiveBytes(rawEntries);
  }
  final encoder = ZipFileEncoder();
  final dir = Directory.systemTemp.createTempSync('asr-model-zip-fixture-');
  final zipPath = '${dir.path}/fixture.zip';
  encoder.create(zipPath);
  for (final entry in rawEntries.entries) {
    final file = File('${dir.path}/${entry.key}');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(entry.value);
    encoder.addFileSync(file, entry.key);
  }
  encoder.closeSync();
  final bytes = File(zipPath).readAsBytesSync();
  dir.deleteSync(recursive: true);
  return bytes;
}

bool _requiresSyntheticArchive(String path) =>
    path == '.' ||
    path.startsWith('/') ||
    RegExp(r'^[A-Za-z]:').hasMatch(path) ||
    path.contains('..') ||
    path.contains(r'\');

List<int> _archiveBytes(Map<String, String> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile.string(entry.key, entry.value));
  }
  return ZipEncoder().encode(archive);
}

AsrModelDownloadResponse _downloadResponse(
        int statusCode, List<int> bytes, String? contentRange) =>
    AsrModelDownloadResponse(
        statusCode: statusCode,
        headers: <String, String>{
          if (contentRange != null) 'content-range': contentRange,
        },
        stream: Stream<List<int>>.value(bytes));

class _FakeAsrModelClient extends AsrModelClient {
  _FakeAsrModelClient(
      {required AsrModelMetadata metadata, this.downloadHandler})
      : _metadata = metadata,
        super(
            baseUri: Uri.parse('http://127.0.0.1:4317'),
            tokenProvider: () => null);

  final AsrModelMetadata _metadata;
  final AsrModelDownloadResponse Function(int? start)? downloadHandler;
  final List<int?> requestedStarts = <int?>[];
  int metadataCalls = 0;
  int downloadCalls = 0;

  @override
  Future<AsrModelMetadata> metadata() async {
    metadataCalls++;
    return _metadata;
  }

  @override
  Future<AsrModelDownloadResponse> download({int? start}) async {
    downloadCalls++;
    requestedStarts.add(start ?? 0);
    return downloadHandler?.call(start ?? 0) ??
        _downloadResponse(200, const <int>[], null);
  }
}
