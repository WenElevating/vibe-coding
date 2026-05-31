import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../data/models/app_update_models.dart';
import 'background_download_bridge.dart';

typedef AppUpdateStreamOpener = Future<http.StreamedResponse> Function(
  Uri uri, {
  int? rangeStart,
  String? ifRange,
});

typedef AppUpdateDownloadProgressCallback = void Function(
  AppUpdateDownloadProgress progress,
);

typedef BackgroundDownloadHeadersProvider = FutureOr<Map<String, String>>
    Function();

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
    Uri daemonBaseUri, {
    AppUpdateDownloadProgressCallback? onProgress,
  });

  Future<File?> readDownloadedUpdate(AppUpdateManifest manifest);

  Future<AppUpdateInstallSessionRecord?> readInstallSession(
    AppUpdateManifest manifest,
  );

  Future<void> recordInstallSession(AppUpdateManifest manifest, int sessionId);

  Future<void> clearInstallSession(AppUpdateManifest manifest,
      {int? sessionId});

  Future<void> clearAllInstallSessions();

  Future<void> discard(int versionCode);
}

class AppUpdateDownloadProgress {
  const AppUpdateDownloadProgress({
    required this.downloadedBytes,
    required this.totalBytes,
  });

  final int downloadedBytes;
  final int totalBytes;

  double get fraction {
    if (totalBytes <= 0) return 0;
    return (downloadedBytes / totalBytes).clamp(0, 1).toDouble();
  }
}

class AppUpdateDownloadResult {
  const AppUpdateDownloadResult({required this.state, this.file, this.message});

  final AppUpdateDownloadState state;
  final File? file;
  final String? message;
}

class AppUpdateInstallSessionRecord {
  const AppUpdateInstallSessionRecord({
    required this.sessionId,
    required this.file,
  });

  final int sessionId;
  final File file;
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
    BackgroundDownloadBridge? backgroundDownloadBridge,
    BackgroundDownloadHeadersProvider? backgroundDownloadHeadersProvider,
    DateTime Function() now = DateTime.now,
  })  : _cacheDirectory = cacheDirectory,
        _openStream = openStream,
        _availableBytes = availableBytes,
        _backgroundDownloadBridge = backgroundDownloadBridge,
        _backgroundDownloadHeadersProvider = backgroundDownloadHeadersProvider,
        _now = now;

  static const int _storageSafetyMarginBytes = 5 * 1024 * 1024;
  static const String _updateDirectoryName = 'app_updates';

  final Directory _cacheDirectory;
  final AppUpdateStreamOpener _openStream;
  final Future<int> Function() _availableBytes;
  final BackgroundDownloadBridge? _backgroundDownloadBridge;
  final BackgroundDownloadHeadersProvider? _backgroundDownloadHeadersProvider;
  final DateTime Function() _now;
  final Map<String, _ActiveAppUpdateDownload> _downloadsByKey = {};

  @override
  Future<AppUpdateDownloadResult> download(
    AppUpdateManifest manifest,
    Uri daemonBaseUri, {
    AppUpdateDownloadProgressCallback? onProgress,
  }) async {
    final validationError = _validateDownloadableManifest(manifest);
    if (validationError != null) {
      return AppUpdateDownloadResult(
        state: AppUpdateDownloadState.failed,
        message: validationError,
      );
    }
    final versionCode = manifest.versionCode!;
    final downloadKey = _downloadKey(manifest, daemonBaseUri);
    final activeDownload = _downloadsByKey[downloadKey];
    if (activeDownload != null) return activeDownload.future;
    await _awaitActiveDownloadsForVersion(versionCode, exceptKey: downloadKey);
    final pendingDownload = _downloadsByKey[downloadKey];
    if (pendingDownload != null) return pendingDownload.future;

    final download = _downloadWithoutGuard(
      manifest,
      daemonBaseUri,
      onProgress: onProgress,
    );
    _downloadsByKey[downloadKey] = _ActiveAppUpdateDownload(
      versionCode: versionCode,
      future: download,
    );
    return download.whenComplete(() => _downloadsByKey.remove(downloadKey));
  }

  Future<AppUpdateDownloadResult> _downloadWithoutGuard(
    AppUpdateManifest manifest,
    Uri daemonBaseUri, {
    AppUpdateDownloadProgressCallback? onProgress,
  }) async {
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
      _emitProgress(onProgress, resumeLength, manifest.sizeBytes!);

      final apkUri = manifest.resolveApkUri(daemonBaseUri);
      final nativeResult = await _downloadWithNativeBridge(
        manifest: manifest,
        daemonBaseUri: daemonBaseUri,
        apkUri: apkUri,
        paths: paths,
        resumeLength: resumeLength,
        onProgress: onProgress,
      );
      if (nativeResult != null) return nativeResult;

      final responseResult = await _downloadFromDaemon(
        manifest: manifest,
        apkUri: apkUri,
        paths: paths,
        resumeLength: resumeLength,
        onProgress: onProgress,
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

  Future<AppUpdateDownloadResult?> _downloadWithNativeBridge({
    required AppUpdateManifest manifest,
    required Uri daemonBaseUri,
    required Uri apkUri,
    required _AppUpdatePaths paths,
    required int resumeLength,
    AppUpdateDownloadProgressCallback? onProgress,
  }) async {
    final bridge = _backgroundDownloadBridge;
    if (bridge == null || !await bridge.isSupported) return null;
    if (!await bridge.prepareNotifications()) {
      return const AppUpdateDownloadResult(
        state: AppUpdateDownloadState.paused,
        message:
            'Notification permission is required for background update downloads.',
      );
    }
    final downloadId = 'app-update:${manifest.versionCode}';
    final terminal = Completer<BackgroundDownloadSnapshot>();
    late final StreamSubscription<BackgroundDownloadSnapshot> subscription;
    subscription =
        bridge.events.where((event) => event.id == downloadId).listen((event) {
      if (event.status == BackgroundDownloadStatus.downloading ||
          event.status == BackgroundDownloadStatus.completed) {
        _emitProgress(
          onProgress,
          event.downloadedBytes,
          event.totalBytes <= 0 ? manifest.sizeBytes! : event.totalBytes,
        );
      }
      if (!terminal.isCompleted &&
          (event.status == BackgroundDownloadStatus.completed ||
              event.status == BackgroundDownloadStatus.cancelled ||
              event.status == BackgroundDownloadStatus.failed)) {
        terminal.complete(event);
      }
    });
    try {
      final headers = <String, String>{
        ...await (_backgroundDownloadHeadersProvider?.call() ??
            Future<Map<String, String>>.value(const <String, String>{})),
        if (resumeLength > 0) 'range': 'bytes=$resumeLength-',
        if (resumeLength > 0 && manifest.etag != null)
          'if-range': manifest.etag!,
      };
      await bridge.start(BackgroundDownloadRequest(
        id: downloadId,
        kind: BackgroundDownloadKind.appUpdate,
        url: daemonBaseUri.resolveUri(apkUri).toString(),
        destinationPath: paths.part.path,
        headers: headers,
        expectedBytes: manifest.sizeBytes!,
        resumeFromBytes: resumeLength,
        notificationTitle: 'Downloading update',
        notificationBody: manifest.versionName ?? 'Android update',
      ));
      final result = await terminal.future;
      if (result.status == BackgroundDownloadStatus.completed) {
        await _writeMetadata(paths.metadata, manifest, manifest.sizeBytes!);
        return await _verifyAndPromote(paths, manifest);
      }
      if (result.status == BackgroundDownloadStatus.cancelled) {
        return AppUpdateDownloadResult(
          state: AppUpdateDownloadState.paused,
          message: result.message ?? 'Update download was cancelled.',
        );
      }
      if (result.status == BackgroundDownloadStatus.failed) {
        return AppUpdateDownloadResult(
          state: AppUpdateDownloadState.paused,
          message: result.message ?? 'Update download was interrupted.',
        );
      }
      return null;
    } catch (error) {
      return AppUpdateDownloadResult(
        state: AppUpdateDownloadState.paused,
        message: 'Background update download could not start: $error',
      );
    } finally {
      await subscription.cancel();
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
    await _awaitActiveDownloadsForVersion(versionCode);
    final paths = await _pathsFor(versionCode);
    await _deleteIfExists(paths.part);
    await _deleteIfExists(paths.metadata);
    await _deleteIfExists(paths.apk);
  }

  @override
  Future<File?> readDownloadedUpdate(AppUpdateManifest manifest) async {
    if (_validateDownloadableManifest(manifest) != null) return null;
    await _awaitActiveDownloadsForVersion(manifest.versionCode!);
    final paths = await _pathsFor(manifest.versionCode!);
    return _reuseReadyApk(paths, manifest);
  }

  @override
  Future<AppUpdateInstallSessionRecord?> readInstallSession(
    AppUpdateManifest manifest,
  ) async {
    if (_validateDownloadableManifest(manifest) != null) return null;
    final paths = await _pathsFor(manifest.versionCode!);
    final metadata = await _readMetadata(paths.metadata);
    final sessionId = metadata?.installSessionId;
    if (metadata == null ||
        sessionId == null ||
        !_metadataMatches(metadata, manifest)) {
      return null;
    }
    final readyApk = await _reuseReadyApk(paths, manifest);
    if (readyApk == null) return null;
    return AppUpdateInstallSessionRecord(sessionId: sessionId, file: readyApk);
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
    await _awaitActiveDownloadsForVersion(manifest.versionCode!);
    final paths = await _pathsFor(manifest.versionCode!);
    final metadata = await _readMetadata(paths.metadata);
    await _writeMetadata(
      paths.metadata,
      manifest,
      metadata?.downloadedBytes ?? manifest.sizeBytes!,
      installSessionId: sessionId,
    );
  }

  @override
  Future<void> clearInstallSession(
    AppUpdateManifest manifest, {
    int? sessionId,
  }) async {
    if (_validateDownloadableManifest(manifest) != null) return;
    await _awaitActiveDownloadsForVersion(manifest.versionCode!);
    final paths = await _pathsFor(manifest.versionCode!);
    final metadata = await _readMetadata(paths.metadata);
    if (metadata == null ||
        metadata.installSessionId == null ||
        !_metadataMatches(metadata, manifest)) {
      return;
    }
    if (sessionId != null && metadata.installSessionId != sessionId) return;
    await _writeMetadata(paths.metadata, manifest, metadata.downloadedBytes);
  }

  @override
  Future<void> clearAllInstallSessions() async {
    final directory = Directory(
      _joinPath(_cacheDirectory.path, _updateDirectoryName),
    );
    if (!await directory.exists()) return;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final metadata = await _readMetadata(entity);
      if (metadata == null || metadata.installSessionId == null) continue;
      await _writeMetadataRecord(
          entity, _metadataWithoutInstallSession(metadata));
    }
  }

  Future<void> _awaitActiveDownloadsForVersion(
    int versionCode, {
    String? exceptKey,
  }) async {
    final activeDownloads = _downloadsByKey.entries
        .where((entry) =>
            entry.key != exceptKey && entry.value.versionCode == versionCode)
        .map((entry) => entry.value.future)
        .toList(growable: false);
    for (final activeDownload in activeDownloads) {
      try {
        await activeDownload;
      } catch (_) {
        // Waiting here is only a cache mutation barrier. The original download
        // operation owns reporting its failure to the caller.
      }
    }
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
    AppUpdateDownloadProgressCallback? onProgress,
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
        if (statusCode == 206 &&
            !_contentRangeStartsAt(
              response.headers['content-range'],
              currentResumeLength,
            )) {
          await response.stream.drain<void>();
          if (!canRestart) {
            return const AppUpdateDownloadResult(
              state: AppUpdateDownloadState.failed,
              message: 'Update server returned an invalid resume range.',
            );
          }
          await _deleteIfExists(paths.part);
          await _deleteIfExists(paths.metadata);
          currentResumeLength = 0;
          canRestart = false;
          await _writeMetadata(paths.metadata, manifest, 0);
          continue;
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
          totalBytes: manifest.sizeBytes!,
          onProgress: onProgress,
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
    required int totalBytes,
    AppUpdateDownloadProgressCallback? onProgress,
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
        _emitProgress(onProgress, downloadedBytes, totalBytes);
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
    await _writeMetadataRecord(file, metadata);
  }

  Future<void> _writeMetadataRecord(
    File file,
    AppUpdateDownloadMetadata metadata,
  ) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(metadata.toJson()));
  }

  AppUpdateDownloadMetadata _metadataWithoutInstallSession(
    AppUpdateDownloadMetadata metadata,
  ) {
    return AppUpdateDownloadMetadata(
      versionCode: metadata.versionCode,
      versionName: metadata.versionName,
      apkUrl: metadata.apkUrl,
      sha256: metadata.sha256,
      sizeBytes: metadata.sizeBytes,
      etag: metadata.etag,
      downloadedBytes: metadata.downloadedBytes,
      updatedAt: _now().toUtc(),
    );
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
    return Isolate.run(() => _sha256HexForFilePath(file.path));
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

  String _downloadKey(AppUpdateManifest manifest, Uri daemonBaseUri) {
    return [
      manifest.versionCode,
      manifest.versionName,
      manifest.sha256,
      manifest.sizeBytes,
      manifest.etag,
      manifest.apkUrl,
      daemonBaseUri.scheme,
      daemonBaseUri.authority,
    ].join('|');
  }

  String _joinPath(String parent, String child) {
    if (parent.endsWith(Platform.pathSeparator)) return '$parent$child';
    return '$parent${Platform.pathSeparator}$child';
  }

  bool _contentRangeStartsAt(String? contentRange, int start) =>
      contentRange != null && contentRange.startsWith('bytes $start-');

  void _emitProgress(
    AppUpdateDownloadProgressCallback? onProgress,
    int downloadedBytes,
    int totalBytes,
  ) {
    onProgress?.call(
      AppUpdateDownloadProgress(
        downloadedBytes: downloadedBytes,
        totalBytes: totalBytes,
      ),
    );
  }
}

class _ActiveAppUpdateDownload {
  const _ActiveAppUpdateDownload({
    required this.versionCode,
    required this.future,
  });

  final int versionCode;
  final Future<AppUpdateDownloadResult> future;
}

Future<String> _sha256HexForFilePath(String filePath) async {
  final digest = await sha256.bind(File(filePath).openRead()).first;
  return digest.toString();
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
