import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../data/models/app_update_models.dart';

typedef AppUpdateStreamOpener = Future<http.StreamedResponse> Function(
  Uri uri, {
  int? rangeStart,
  String? ifRange,
});

enum AppUpdateDownloadState {
  downloading,
  paused,
  verifying,
  readyToInstall,
  failed,
}

abstract class AppUpdateDownloader {
  Future<AppUpdateDownloadResult> download(
    AppUpdateManifest manifest,
    Uri daemonBaseUri,
  );

  Future<void> recordInstallSession(AppUpdateManifest manifest, int sessionId);

  Future<void> discard(int versionCode);
}

class AppUpdateDownloadResult {
  const AppUpdateDownloadResult({required this.state, this.file, this.message});

  final AppUpdateDownloadState state;
  final File? file;
  final String? message;
}

class AppUpdateDownloadException implements Exception {
  const AppUpdateDownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AppUpdateDownloadManager implements AppUpdateDownloader {
  AppUpdateDownloadManager({
    required Directory cacheDirectory,
    required AppUpdateStreamOpener openStream,
    required Future<int> Function() availableBytes,
    DateTime Function() now = DateTime.now,
  })  : _cacheDirectory = cacheDirectory,
        _openStream = openStream,
        _availableBytes = availableBytes,
        _now = now;

  static const int _storageSafetyMarginBytes = 5 * 1024 * 1024;
  static const String _updateDirectoryName = 'app_updates';

  final Directory _cacheDirectory;
  final AppUpdateStreamOpener _openStream;
  final Future<int> Function() _availableBytes;
  final DateTime Function() _now;

  @override
  Future<AppUpdateDownloadResult> download(
    AppUpdateManifest manifest,
    Uri daemonBaseUri,
  ) async {
    final validationError = _validateDownloadableManifest(manifest);
    if (validationError != null) {
      return AppUpdateDownloadResult(
        state: AppUpdateDownloadState.failed,
        message: validationError,
      );
    }

    try {
      await reconcile(manifest);

      final paths = await _pathsFor(manifest.versionCode!);
      final readyApk = await _reuseReadyApk(paths, manifest);
      if (readyApk != null) {
        return AppUpdateDownloadResult(
          state: AppUpdateDownloadState.readyToInstall,
          file: readyApk,
        );
      }

      final resumeLength = await _resumeLength(paths, manifest);
      if (resumeLength == manifest.sizeBytes) {
        return await _verifyAndPromote(paths, manifest);
      }

      final available = await _availableBytes();
      final requiredBytes =
          (manifest.sizeBytes! - resumeLength).clamp(0, manifest.sizeBytes!) +
              _storageSafetyMarginBytes;
      if (available < requiredBytes) {
        return const AppUpdateDownloadResult(
          state: AppUpdateDownloadState.failed,
          message: 'Insufficient storage available for update download.',
        );
      }

      await _writeMetadata(paths.metadata, manifest, resumeLength);

      final apkUri = manifest.resolveApkUri(daemonBaseUri);
      final responseResult = await _downloadFromDaemon(
        manifest: manifest,
        apkUri: apkUri,
        paths: paths,
        resumeLength: resumeLength,
      );
      if (responseResult != null) return responseResult;

      return await _verifyAndPromote(paths, manifest);
    } on AppUpdateDownloadException catch (error) {
      return AppUpdateDownloadResult(
        state: AppUpdateDownloadState.failed,
        message: error.message,
      );
    } on SocketException catch (error) {
      return AppUpdateDownloadResult(
        state: AppUpdateDownloadState.paused,
        message: 'Network disconnected while downloading update: $error',
      );
    } on TimeoutException catch (error) {
      return AppUpdateDownloadResult(
        state: AppUpdateDownloadState.paused,
        message: 'Update download timed out: $error',
      );
    } on FileSystemException catch (error) {
      return AppUpdateDownloadResult(
        state: AppUpdateDownloadState.paused,
        message: 'Update download was interrupted while writing cache: $error',
      );
    } on FormatException catch (error) {
      return AppUpdateDownloadResult(
        state: AppUpdateDownloadState.failed,
        message: error.message,
      );
    }
  }

  Future<void> reconcile(AppUpdateManifest manifest) async {
    final versionCode = manifest.versionCode;
    if (versionCode == null) return;
    final paths = await _pathsFor(versionCode);

    if (await _safeExists(paths.apk) && await _safeExists(paths.part)) {
      await _deleteIfExists(paths.part);
    }

    final metadata = await _readMetadata(paths.metadata);
    if (metadata != null && !_metadataMatches(metadata, manifest)) {
      await _deleteIfExists(paths.part);
      await _deleteIfExists(paths.metadata);
      await _deleteIfExists(paths.apk);
      return;
    }

    if (metadata == null && await _safeExists(paths.part)) {
      await _deleteIfExists(paths.part);
      return;
    }

    if (await _safeExists(paths.part)) {
      try {
        final length = await paths.part.length();
        if (manifest.sizeBytes != null && length > manifest.sizeBytes!) {
          await _deleteIfExists(paths.part);
          await _deleteIfExists(paths.metadata);
        }
      } on FileSystemException {
        return;
      }
    }
  }

  @override
  Future<void> discard(int versionCode) async {
    final paths = await _pathsFor(versionCode);
    await _deleteIfExists(paths.part);
    await _deleteIfExists(paths.metadata);
    await _deleteIfExists(paths.apk);
  }

  @override
  Future<void> recordInstallSession(
    AppUpdateManifest manifest,
    int sessionId,
  ) async {
    final validationError = _validateDownloadableManifest(manifest);
    if (validationError != null) {
      throw AppUpdateDownloadException(validationError);
    }
    final paths = await _pathsFor(manifest.versionCode!);
    final metadata = await _readMetadata(paths.metadata);
    await _writeMetadata(
      paths.metadata,
      manifest,
      metadata?.downloadedBytes ?? manifest.sizeBytes!,
      installSessionId: sessionId,
    );
  }

  static String sha256HexForTest(List<int> bytes) =>
      sha256.convert(bytes).toString();

  Future<File?> _reuseReadyApk(
    _AppUpdatePaths paths,
    AppUpdateManifest manifest,
  ) async {
    try {
      if (!await paths.apk.exists()) return null;
      final verified = await _fileMatchesManifest(paths.apk, manifest);
      if (verified) return paths.apk;
      await _deleteIfExists(paths.apk);
      await _deleteIfExists(paths.metadata);
      return null;
    } on FileSystemException {
      await _deleteIfExists(paths.apk);
      return null;
    }
  }

  Future<AppUpdateDownloadResult?> _downloadFromDaemon({
    required AppUpdateManifest manifest,
    required Uri apkUri,
    required _AppUpdatePaths paths,
    required int resumeLength,
  }) async {
    var currentResumeLength = resumeLength;
    var canRestart = true;

    while (true) {
      final response = await _openStream(
        apkUri,
        rangeStart: currentResumeLength > 0 ? currentResumeLength : null,
        ifRange: currentResumeLength > 0 ? manifest.etag : null,
      );
      final statusCode = response.statusCode;

      if (statusCode == 416 && currentResumeLength > 0 && canRestart) {
        await response.stream.drain<void>();
        await _deleteIfExists(paths.part);
        await _deleteIfExists(paths.metadata);
        final available = await _availableBytes();
        final requiredBytes = manifest.sizeBytes! + _storageSafetyMarginBytes;
        if (available < requiredBytes) {
          return const AppUpdateDownloadResult(
            state: AppUpdateDownloadState.failed,
            message: 'Insufficient storage available for update download.',
          );
        }
        currentResumeLength = 0;
        canRestart = false;
        await _writeMetadata(paths.metadata, manifest, 0);
        continue;
      }

      if (statusCode == 200 || statusCode == 206) {
        if (statusCode == 206 && currentResumeLength <= 0) {
          await response.stream.drain<void>();
          return const AppUpdateDownloadResult(
            state: AppUpdateDownloadState.failed,
            message: 'Update server returned partial content without a resume.',
          );
        }

        final writeMode = statusCode == 206 && currentResumeLength > 0
            ? FileMode.append
            : FileMode.write;
        final initialBytes =
            writeMode == FileMode.append ? currentResumeLength : 0;
        if (writeMode == FileMode.write) {
          await _deleteIfExists(paths.part);
        }
        final downloadedBytes = await _writeStream(
          response.stream,
          paths.part,
          mode: writeMode,
          initialBytes: initialBytes,
        );
        await _writeMetadata(paths.metadata, manifest, downloadedBytes);
        return null;
      }

      if (statusCode >= 500 && statusCode <= 599) {
        await response.stream.drain<void>();
        return AppUpdateDownloadResult(
          state: AppUpdateDownloadState.paused,
          message: 'Update server returned $statusCode; download can retry.',
        );
      }

      final body = await response.stream.transform(utf8.decoder).join();
      return AppUpdateDownloadResult(
        state: AppUpdateDownloadState.failed,
        message: body.isEmpty
            ? 'Update server returned $statusCode.'
            : 'Update server returned $statusCode: $body',
      );
    }
  }

  Future<AppUpdateDownloadResult> _verifyAndPromote(
    _AppUpdatePaths paths,
    AppUpdateManifest manifest,
  ) async {
    if (!await paths.part.exists()) {
      return const AppUpdateDownloadResult(
        state: AppUpdateDownloadState.paused,
        message: 'Downloaded APK file is missing; retry the download.',
      );
    }

    final actualLength = await paths.part.length();
    if (actualLength != manifest.sizeBytes) {
      if (actualLength > manifest.sizeBytes!) {
        await _deleteIfExists(paths.part);
        await _deleteIfExists(paths.metadata);
      }
      return AppUpdateDownloadResult(
        state: AppUpdateDownloadState.paused,
        message:
            'Downloaded APK size mismatch: expected ${manifest.sizeBytes}, got $actualLength; retry the download.',
      );
    }

    final actualSha256 = await _sha256Hex(paths.part);
    if (actualSha256.toLowerCase() != manifest.sha256!.toLowerCase()) {
      await _deleteIfExists(paths.part);
      await _deleteIfExists(paths.metadata);
      return const AppUpdateDownloadResult(
        state: AppUpdateDownloadState.paused,
        message: 'Downloaded APK integrity check failed; retry the download.',
      );
    }

    await _deleteIfExists(paths.apk);
    final apk = await paths.part.rename(paths.apk.path);
    await _writeMetadata(paths.metadata, manifest, manifest.sizeBytes!);
    return AppUpdateDownloadResult(
      state: AppUpdateDownloadState.readyToInstall,
      file: apk,
    );
  }

  Future<int> _writeStream(
    Stream<List<int>> stream,
    File file, {
    required FileMode mode,
    required int initialBytes,
  }) async {
    await file.parent.create(recursive: true);
    final sink = file.openWrite(mode: mode);
    final iterator = StreamIterator<List<int>>(stream);
    var downloadedBytes = initialBytes;
    try {
      while (await iterator.moveNext()) {
        final chunk = iterator.current;
        sink.add(chunk);
        downloadedBytes += chunk.length;
      }
      await sink.flush();
      return downloadedBytes;
    } catch (_) {
      await iterator.cancel();
      rethrow;
    } finally {
      await sink.close();
    }
  }

  Future<int> _resumeLength(
    _AppUpdatePaths paths,
    AppUpdateManifest manifest,
  ) async {
    if (!await paths.part.exists()) return 0;
    final metadata = await _readMetadata(paths.metadata);
    if (metadata == null || !_metadataMatches(metadata, manifest)) {
      await _deleteIfExists(paths.part);
      await _deleteIfExists(paths.metadata);
      return 0;
    }
    final length = await paths.part.length();
    if (length <= 0 || length >= manifest.sizeBytes!) {
      return length == manifest.sizeBytes! ? length : 0;
    }
    return length;
  }

  Future<bool> _fileMatchesManifest(
    File file,
    AppUpdateManifest manifest,
  ) async {
    try {
      if (!await file.exists()) return false;
      if (await file.length() != manifest.sizeBytes) return false;
      final actualSha256 = await _sha256Hex(file);
      return actualSha256.toLowerCase() == manifest.sha256!.toLowerCase();
    } on FileSystemException {
      return false;
    }
  }

  Future<AppUpdateDownloadMetadata?> _readMetadata(File file) async {
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      return AppUpdateDownloadMetadata.fromJson(
        Map<String, Object?>.from(decoded as Map),
      );
    } on Object {
      return null;
    }
  }

  Future<void> _writeMetadata(
    File file,
    AppUpdateManifest manifest,
    int downloadedBytes, {
    int? installSessionId,
  }) async {
    final versionCode = manifest.versionCode;
    final versionName = manifest.versionName;
    final apkUrl = manifest.apkUrl;
    final sha256 = manifest.sha256;
    final sizeBytes = manifest.sizeBytes;
    final etag = manifest.etag;
    if (versionCode == null ||
        versionName == null ||
        apkUrl == null ||
        sha256 == null ||
        sizeBytes == null ||
        etag == null) {
      throw const AppUpdateDownloadException(
        'Android update manifest is missing required download fields.',
      );
    }
    final metadata = AppUpdateDownloadMetadata(
      versionCode: versionCode,
      versionName: versionName,
      apkUrl: apkUrl,
      sha256: sha256,
      sizeBytes: sizeBytes,
      etag: etag,
      downloadedBytes: downloadedBytes,
      updatedAt: _now().toUtc(),
      installSessionId: installSessionId,
    );
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(metadata.toJson()));
  }

  bool _metadataMatches(
    AppUpdateDownloadMetadata metadata,
    AppUpdateManifest manifest,
  ) {
    return metadata.versionCode == manifest.versionCode &&
        metadata.versionName == manifest.versionName &&
        metadata.apkUrl == manifest.apkUrl &&
        metadata.sha256.toLowerCase() == manifest.sha256?.toLowerCase() &&
        metadata.sizeBytes == manifest.sizeBytes &&
        metadata.etag == manifest.etag;
  }

  Future<String> _sha256Hex(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  Future<_AppUpdatePaths> _pathsFor(int versionCode) async {
    final directory = Directory(
      _joinPath(_cacheDirectory.path, _updateDirectoryName),
    );
    await directory.create(recursive: true);
    final base = _joinPath(directory.path, 'app-update-$versionCode');
    return _AppUpdatePaths(
      part: File('$base.apk.part'),
      metadata: File('$base.json'),
      apk: File('$base.apk'),
    );
  }

  Future<void> _deleteIfExists(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException {
      if (await _safeExists(file)) rethrow;
    }
  }

  Future<bool> _safeExists(File file) async {
    try {
      return await file.exists();
    } on FileSystemException {
      return false;
    }
  }

  String? _validateDownloadableManifest(AppUpdateManifest manifest) {
    if (!manifest.available) return 'No Android update is available.';
    if (manifest.versionCode == null ||
        manifest.versionName == null ||
        manifest.apkUrl == null ||
        manifest.sha256 == null ||
        manifest.sizeBytes == null ||
        manifest.etag == null) {
      return 'Android update manifest is missing required download fields.';
    }
    return null;
  }

  String _joinPath(String parent, String child) {
    if (parent.endsWith(Platform.pathSeparator)) return '$parent$child';
    return '$parent${Platform.pathSeparator}$child';
  }
}

class _AppUpdatePaths {
  const _AppUpdatePaths({
    required this.part,
    required this.metadata,
    required this.apk,
  });

  final File part;
  final File metadata;
  final File apk;
}
