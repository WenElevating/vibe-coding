import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'asr_model_client.dart';

enum AsrModelStatus {
  idle,
  checking,
  downloading,
  paused,
  verifying,
  extracting,
  ready,
  failed,
  cancelled,
}

class AsrModelState {
  const AsrModelState({
    required this.status,
    this.version,
    this.modelDirectory,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.speedBytesPerSecond = 0,
    this.errorMessage,
    this.traceId,
  });

  const AsrModelState.idle() : this(status: AsrModelStatus.idle);

  final AsrModelStatus status;
  final String? version;
  final String? modelDirectory;
  final int downloadedBytes;
  final int totalBytes;
  final double speedBytesPerSecond;
  final String? errorMessage;
  final String? traceId;

  double get progress =>
      totalBytes <= 0 ? 0 : (downloadedBytes / totalBytes).clamp(0, 1);

  AsrModelState copyWith({
    AsrModelStatus? status,
    String? version,
    String? modelDirectory,
    int? downloadedBytes,
    int? totalBytes,
    double? speedBytesPerSecond,
    String? errorMessage,
    String? traceId,
    bool clearError = false,
  }) =>
      AsrModelState(
        status: status ?? this.status,
        version: version ?? this.version,
        modelDirectory: modelDirectory ?? this.modelDirectory,
        downloadedBytes: downloadedBytes ?? this.downloadedBytes,
        totalBytes: totalBytes ?? this.totalBytes,
        speedBytesPerSecond: speedBytesPerSecond ?? this.speedBytesPerSecond,
        errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
        traceId: clearError ? null : traceId ?? this.traceId,
      );
}

class AsrModelManager extends ChangeNotifier {
  AsrModelManager({
    required AsrModelClient client,
    Future<Directory> Function()? supportDirectoryProvider,
    DateTime Function()? now,
  })  : _client = client,
        _supportDirectoryProvider =
            supportDirectoryProvider ?? getApplicationSupportDirectory,
        _now = now ?? DateTime.now;

  static const requiredFiles = <String>[
    'encoder.onnx',
    'decoder.onnx',
    'joiner.onnx',
    'tokens.txt',
  ];

  static const maxAsrArchiveFiles = 4096;
  static const maxAsrArchiveUncompressedBytes = 2 * 1024 * 1024 * 1024;

  final AsrModelClient _client;
  final Future<Directory> Function() _supportDirectoryProvider;
  final DateTime Function() _now;
  AsrModelState _state = const AsrModelState.idle();
  Future<String>? _activePreparation;
  bool _cancelRequested = false;
  bool _pauseRequested = false;
  bool _disposed = false;

  AsrModelState get state => _state;

  Future<String> ensureReady() {
    final activePreparation = _activePreparation;
    if (activePreparation != null) return activePreparation;

    final completer = Completer<String>();
    final future = completer.future;
    _activePreparation = future;
    unawaited(_runActivePreparation(completer, future));
    return future;
  }

  Future<void> _runActivePreparation(
      Completer<String> completer, Future<String> future) async {
    try {
      final path = await _ensureReadyInternal();
      if (identical(_activePreparation, future)) {
        _activePreparation = null;
      }
      if (!completer.isCompleted) completer.complete(path);
    } catch (error, stackTrace) {
      if (identical(_activePreparation, future)) {
        _activePreparation = null;
      }
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
    }
  }

  Future<String> _ensureReadyInternal() async {
    _cancelRequested = false;
    _pauseRequested = false;
    _emit(const AsrModelState(status: AsrModelStatus.checking));
    try {
      final metadata = await _client.metadata();
      final paths = await _paths(metadata.version);
      if (await _isReady(paths.modelDirectory)) {
        _emit(AsrModelState(
            status: AsrModelStatus.ready,
            version: metadata.version,
            modelDirectory: paths.modelDirectory.path,
            totalBytes: metadata.sizeBytes,
            downloadedBytes: metadata.sizeBytes));
        return paths.modelDirectory.path;
      }
      final zip = await _download(metadata, paths);
      _throwIfStopped();
      _emit(_state.copyWith(status: AsrModelStatus.verifying));
      await _verifyZip(zip, metadata);
      _throwIfStopped();
      _emit(_state.copyWith(status: AsrModelStatus.extracting));
      await _extract(zip, paths);
      _emit(_state.copyWith(
          status: AsrModelStatus.ready,
          modelDirectory: paths.modelDirectory.path,
          downloadedBytes: metadata.sizeBytes,
          totalBytes: metadata.sizeBytes));
      return paths.modelDirectory.path;
    } on _PreparationStopped catch (stopped) {
      _emit(_state.copyWith(status: stopped.status));
      rethrow;
    } on AsrModelClientException catch (error) {
      _emit(_state.copyWith(
          status: AsrModelStatus.failed,
          errorMessage: error.message,
          traceId: error.traceId));
      rethrow;
    } catch (error) {
      _emit(_state.copyWith(
          status: AsrModelStatus.failed, errorMessage: error.toString()));
      rethrow;
    }
  }

  void pause() {
    if (_state.status != AsrModelStatus.downloading) return;
    _pauseRequested = true;
  }

  void resume() {
    if (_state.status != AsrModelStatus.paused) return;
    unawaited(ensureReady().catchError((Object _) {
      return '';
    }));
  }

  void cancel() {
    _cancelRequested = true;
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelRequested = true;
    super.dispose();
  }

  Future<File> _download(
      AsrModelMetadata metadata, _AsrModelPaths paths) async {
    await paths.root.create(recursive: true);
    var start = await paths.part.exists() ? await paths.part.length() : 0;
    if (start > metadata.sizeBytes) {
      await paths.part.delete();
      start = 0;
    }
    while (true) {
      _throwIfStopped();
      final response = await _client.download(start: start);
      if (response.statusCode == 416) {
        await paths.part.delete().catchError((_) => paths.part);
        start = 0;
        continue;
      }
      final append = response.statusCode == 206 &&
          _contentRangeStartsAt(response.headers['content-range'], start);
      if (start > 0 && !append) {
        await paths.part.delete().catchError((_) => paths.part);
        start = 0;
        continue;
      }
      await paths.part.create(recursive: true);
      final sink =
          paths.part.openWrite(mode: append ? FileMode.append : FileMode.write);
      var downloaded = start;
      var lastBytes = downloaded;
      var lastTime = _now();
      _emit(AsrModelState(
          status: AsrModelStatus.downloading,
          version: metadata.version,
          downloadedBytes: downloaded,
          totalBytes: metadata.sizeBytes));
      try {
        await for (final chunk in response.stream) {
          _throwIfStopped();
          if (_pauseRequested) {
            throw const _PreparationStopped(AsrModelStatus.paused);
          }
          sink.add(chunk);
          downloaded += chunk.length;
          final now = _now();
          final elapsedMs = now.difference(lastTime).inMilliseconds;
          if (elapsedMs >= 250) {
            final speed = (downloaded - lastBytes) / (elapsedMs / 1000);
            lastBytes = downloaded;
            lastTime = now;
            _emit(_state.copyWith(
                downloadedBytes: downloaded,
                totalBytes: metadata.sizeBytes,
                speedBytesPerSecond: speed));
          }
        }
      } finally {
        await sink.close();
      }
      if (await paths.part.length() >= metadata.sizeBytes) break;
      start = await paths.part.length();
    }
    if (await paths.zip.exists()) await paths.zip.delete();
    return paths.part.rename(paths.zip.path);
  }

  Future<void> _verifyZip(File zip, AsrModelMetadata metadata) async {
    final size = await zip.length();
    if (size != metadata.sizeBytes) {
      await zip.delete().catchError((_) => zip);
      throw StateError('ASR model ZIP size mismatch');
    }
    final digest = await sha256.bind(zip.openRead()).first;
    if (digest.toString().toLowerCase() != metadata.sha256.toLowerCase()) {
      await zip.delete().catchError((_) => zip);
      throw StateError('ASR model ZIP checksum mismatch');
    }
  }

  Future<void> _extract(File zip, _AsrModelPaths paths) async {
    if (await paths.staging.exists()) {
      await paths.staging.delete(recursive: true);
    }
    if (await paths.normalized.exists()) {
      await paths.normalized.delete(recursive: true);
    }
    await paths.staging.create(recursive: true);
    try {
      final input = InputFileStream(zip.path);
      try {
        await _safeExtractArchiveToDisk(
            ZipDecoder().decodeStream(input), paths.staging);
      } finally {
        await input.close();
      }
      final resolvedFiles = await _resolveRequiredModelFiles(paths.staging);
      if (resolvedFiles == null) {
        await paths.staging
            .delete(recursive: true)
            .catchError((_) => paths.staging);
        throw StateError('ASR model archive is missing required files');
      }
      await paths.normalized.create(recursive: true);
      for (final entry in resolvedFiles.entries) {
        await entry.value.copy(
            '${paths.normalized.path}${Platform.pathSeparator}${entry.key}');
      }
      if (await paths.modelDirectory.exists()) {
        await paths.modelDirectory.delete(recursive: true);
      }
      await paths.normalized.rename(paths.modelDirectory.path);
      await paths.staging
          .delete(recursive: true)
          .catchError((_) => paths.staging);
    } catch (_) {
      await paths.staging
          .delete(recursive: true)
          .catchError((_) => paths.staging);
      await paths.normalized
          .delete(recursive: true)
          .catchError((_) => paths.normalized);
      rethrow;
    }
  }

  Future<void> _safeExtractArchiveToDisk(
      Archive archive, Directory staging) async {
    final canonicalStaging = await staging.resolveSymbolicLinks();
    var entryCount = 0;
    var fileCount = 0;
    var uncompressedBytes = 0;
    for (final file in archive) {
      entryCount++;
      if (entryCount > maxAsrArchiveFiles) {
        throw StateError('ASR model archive contains too many entries');
      }
      final relativePath = _validateArchiveEntryName(file.name);
      if (file.isSymbolicLink) {
        throw StateError('ASR model archive contains a symbolic link');
      }
      if (!file.isFile) {
        await Directory(_joinPath(staging.path, relativePath))
            .create(recursive: true);
        continue;
      }
      fileCount++;
      if (fileCount > maxAsrArchiveFiles) {
        throw StateError('ASR model archive contains too many files');
      }
      uncompressedBytes += file.size;
      if (uncompressedBytes > maxAsrArchiveUncompressedBytes) {
        throw StateError('ASR model archive is too large');
      }

      final destination = File(_joinPath(staging.path, relativePath));
      await destination.parent.create(recursive: true);
      final canonicalParent = await destination.parent.resolveSymbolicLinks();
      if (!_isWithinDirectory(canonicalParent, canonicalStaging)) {
        throw StateError('ASR model archive entry escapes staging directory');
      }
      final output = OutputFileStream(destination.path);
      try {
        file.writeContent(output);
      } finally {
        await output.close();
      }
    }
  }

  String _validateArchiveEntryName(String name) {
    final normalized = name.replaceAll('\\', '/');
    final drivePattern = RegExp(r'^[A-Za-z]:');
    if (normalized.startsWith('/') ||
        normalized.startsWith('\\') ||
        drivePattern.hasMatch(normalized)) {
      throw StateError('ASR model archive contains an absolute path');
    }
    final parts = normalized.split('/').where((part) => part.isNotEmpty);
    if (parts.isEmpty || parts.any((part) => part == '.' || part == '..')) {
      throw StateError('ASR model archive contains an unsafe path');
    }
    return parts.join(Platform.pathSeparator);
  }

  String _joinPath(String parent, String child) =>
      '$parent${Platform.pathSeparator}$child';

  bool _isWithinDirectory(String child, String parent) {
    final normalizedChild = _normalizeDirectoryPath(child);
    final normalizedParent = _normalizeDirectoryPath(parent);
    return normalizedChild == normalizedParent ||
        normalizedChild
            .startsWith('$normalizedParent${Platform.pathSeparator}');
  }

  String _normalizeDirectoryPath(String path) {
    var normalized = Directory(path).absolute.path;
    if (Platform.isWindows) normalized = normalized.toLowerCase();
    while (normalized.endsWith(Platform.pathSeparator)) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  Future<_AsrModelPaths> _paths(String version) async {
    final support = await _supportDirectoryProvider();
    final root =
        Directory('${support.path}${Platform.pathSeparator}asr_models');
    return _AsrModelPaths(
      root: root,
      modelDirectory:
          Directory('${root.path}${Platform.pathSeparator}$version'),
      part: File('${root.path}${Platform.pathSeparator}$version.zip.part'),
      zip: File('${root.path}${Platform.pathSeparator}$version.zip'),
      staging:
          Directory('${root.path}${Platform.pathSeparator}$version.staging'),
      normalized:
          Directory('${root.path}${Platform.pathSeparator}$version.normalized'),
    );
  }

  Future<bool> _isReady(Directory directory) async {
    for (final file in requiredFiles) {
      if (!await File('${directory.path}${Platform.pathSeparator}$file')
          .exists()) {
        return false;
      }
    }
    return true;
  }

  Future<Map<String, File>?> _resolveRequiredModelFiles(
      Directory directory) async {
    final resolved = <String, File>{};
    await for (final entity in directory.list(recursive: true)) {
      if (entity is! File) continue;
      final name = _fileName(entity.path).toLowerCase();
      final logicalName = _logicalModelFileName(name);
      if (logicalName == null || resolved.containsKey(logicalName)) continue;
      resolved[logicalName] = entity;
    }
    for (final file in requiredFiles) {
      if (!resolved.containsKey(file)) return null;
    }
    return resolved;
  }

  String? _logicalModelFileName(String name) {
    if (name == 'tokens.txt') return 'tokens.txt';
    if (name == 'encoder.onnx' || _isModelCandidate(name, 'encoder')) {
      return 'encoder.onnx';
    }
    if (name == 'decoder.onnx' || _isModelCandidate(name, 'decoder')) {
      return 'decoder.onnx';
    }
    if (name == 'joiner.onnx' || _isModelCandidate(name, 'joiner')) {
      return 'joiner.onnx';
    }
    return null;
  }

  bool _isModelCandidate(String name, String prefix) =>
      name.startsWith('$prefix-') && name.endsWith('.onnx');

  String _fileName(String path) {
    final slash = path.lastIndexOf('/');
    final backslash = path.lastIndexOf('\\');
    final index = slash > backslash ? slash : backslash;
    return index < 0 ? path : path.substring(index + 1);
  }

  bool _contentRangeStartsAt(String? contentRange, int start) =>
      contentRange != null && contentRange.startsWith('bytes $start-');

  void _throwIfStopped() {
    if (_disposed || _cancelRequested) {
      throw const _PreparationStopped(AsrModelStatus.cancelled);
    }
    if (_pauseRequested) {
      throw const _PreparationStopped(AsrModelStatus.paused);
    }
  }

  void _emit(AsrModelState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }
}

class _AsrModelPaths {
  const _AsrModelPaths({
    required this.root,
    required this.modelDirectory,
    required this.part,
    required this.zip,
    required this.staging,
    required this.normalized,
  });

  final Directory root;
  final Directory modelDirectory;
  final File part;
  final File zip;
  final Directory staging;
  final Directory normalized;
}

class _PreparationStopped implements Exception {
  const _PreparationStopped(this.status);

  final AsrModelStatus status;
}
