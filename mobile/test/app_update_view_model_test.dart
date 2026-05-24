import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/data/models/app_update_models.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/app_update_repository.dart';
import 'package:lan_ai_cli_control/src/services/android_package_installer.dart';
import 'package:lan_ai_cli_control/src/services/app_update_download_manager.dart';
import 'package:lan_ai_cli_control/src/ui/features/settings/view_models/app_update_view_model.dart';

void main() {
  test(
    'check reports available update and mandatory min-supported gate',
    () async {
      final installer = _FakeInstaller();
      final viewModel = AppUpdateViewModel(
        installedVersionCode: 3,
        installedVersionName: '1.3.0',
        repository: _FakeRepository(
          _manifest(versionCode: 4, minSupportedVersionCode: 4),
        ),
        installer: installer,
        downloader: _FakeDownloader(),
        daemonBaseUri: Uri.parse('http://127.0.0.1:4317'),
      );
      addTearDown(viewModel.dispose);
      addTearDown(installer.close);

      await viewModel.checkForUpdates();

      expect(viewModel.state.status, AppUpdateStatus.available);
      expect(viewModel.state.mandatory, true);
    },
  );

  test('install permission missing moves to permission state', () async {
    final installer = _FakeInstaller(canInstall: false);
    final readyFile = await _readyApk();
    addTearDown(() => readyFile.parent.delete(recursive: true));
    final viewModel = AppUpdateViewModel(
      installedVersionCode: 1,
      installedVersionName: '1.0.0',
      repository: _FakeRepository(_manifest()),
      installer: installer,
      downloader: _FakeDownloader(
        result: AppUpdateDownloadResult(
          state: AppUpdateDownloadState.readyToInstall,
          file: readyFile,
        ),
      ),
      daemonBaseUri: Uri.parse('http://127.0.0.1:4317'),
    );
    addTearDown(viewModel.dispose);
    addTearDown(installer.close);

    await viewModel.checkForUpdates();
    await viewModel.download();
    await viewModel.install();

    expect(viewModel.state.status, AppUpdateStatus.installPermissionNeeded);
  });

  test('installer success event updates state', () async {
    final installer = _FakeInstaller();
    final readyFile = await _readyApk();
    addTearDown(() => readyFile.parent.delete(recursive: true));
    final viewModel = AppUpdateViewModel(
      installedVersionCode: 1,
      installedVersionName: '1.0.0',
      repository: _FakeRepository(_manifest()),
      installer: installer,
      downloader: _FakeDownloader(
        result: AppUpdateDownloadResult(
          state: AppUpdateDownloadState.readyToInstall,
          file: readyFile,
        ),
      ),
      daemonBaseUri: Uri.parse('http://127.0.0.1:4317'),
    );
    addTearDown(viewModel.dispose);
    addTearDown(installer.close);

    await viewModel.checkForUpdates();
    await viewModel.download();
    await viewModel.install();
    installer.emit(
      const AndroidInstallEvent(
        status: AndroidInstallStatus.success,
        sessionId: 7,
      ),
    );
    await pumpEventQueue();

    expect(viewModel.state.status, AppUpdateStatus.installSucceeded);
    expect(installer.installedPath, readyFile.path);
  });

  test('records update diagnostics and install session metadata', () async {
    final diagnostics = <String>[];
    final diagnosticMetadata = <Map<String, Object?>>[];
    final installer = _FakeInstaller();
    final readyFile = await _readyApk();
    addTearDown(() => readyFile.parent.delete(recursive: true));
    final downloader = _FakeDownloader(
      result: const AppUpdateDownloadResult(
        state: AppUpdateDownloadState.failed,
        message: 'Insufficient storage available for update download.',
      ),
    );
    final viewModel = AppUpdateViewModel(
      installedVersionCode: 1,
      installedVersionName: '1.0.0',
      repository: _FakeRepository(_manifest()),
      installer: installer,
      downloader: downloader,
      daemonBaseUri: Uri.parse('http://127.0.0.1:4317'),
      recordDiagnostic: (event, metadata) {
        diagnostics.add(event);
        diagnosticMetadata.add(metadata);
      },
    );
    addTearDown(viewModel.dispose);
    addTearDown(installer.close);

    await viewModel.checkForUpdates();
    await viewModel.download();
    downloader.result = AppUpdateDownloadResult(
      state: AppUpdateDownloadState.readyToInstall,
      file: readyFile,
    );
    await viewModel.download();
    await viewModel.install();
    await viewModel.discard();

    expect(diagnostics, contains('update.check.started'));
    expect(diagnostics, contains('update.storage.preflight_failed'));
    expect(diagnostics, contains('update.install.committed'));
    expect(diagnostics, contains('update.discard'));
    expect(diagnosticMetadata.last['versionCode'], 2);
    expect(downloader.recordedSessionId, 7);
    expect(viewModel.state.status, AppUpdateStatus.available);
  });

  test('install cancelled remains visible and retryable', () async {
    final installer = _FakeInstaller();
    final readyFile = await _readyApk();
    addTearDown(() => readyFile.parent.delete(recursive: true));
    final viewModel = AppUpdateViewModel(
      installedVersionCode: 1,
      installedVersionName: '1.0.0',
      repository: _FakeRepository(_manifest()),
      installer: installer,
      downloader: _FakeDownloader(
        result: AppUpdateDownloadResult(
          state: AppUpdateDownloadState.readyToInstall,
          file: readyFile,
        ),
      ),
      daemonBaseUri: Uri.parse('http://127.0.0.1:4317'),
    );
    addTearDown(viewModel.dispose);
    addTearDown(installer.close);

    await viewModel.checkForUpdates();
    await viewModel.download();
    await viewModel.install();
    installer.emit(
      const AndroidInstallEvent(
        status: AndroidInstallStatus.cancelled,
        sessionId: 7,
      ),
    );
    await pumpEventQueue();

    expect(viewModel.state.status, AppUpdateStatus.installCancelled);
    expect(viewModel.state.downloadedFile?.path, readyFile.path);
  });

  test(
    'pending user confirmation stays retryable instead of installing',
    () async {
      final installer = _FakeInstaller();
      final readyFile = await _readyApk();
      addTearDown(() => readyFile.parent.delete(recursive: true));
      final viewModel = AppUpdateViewModel(
        installedVersionCode: 1,
        installedVersionName: '1.0.0',
        repository: _FakeRepository(_manifest()),
        installer: installer,
        downloader: _FakeDownloader(
          result: AppUpdateDownloadResult(
            state: AppUpdateDownloadState.readyToInstall,
            file: readyFile,
          ),
        ),
        daemonBaseUri: Uri.parse('http://127.0.0.1:4317'),
      );
      addTearDown(viewModel.dispose);
      addTearDown(installer.close);

      await viewModel.checkForUpdates();
      await viewModel.download();
      await viewModel.install();
      installer.emit(
        const AndroidInstallEvent(
          status: AndroidInstallStatus.pendingUserAction,
          sessionId: 7,
          message: 'Confirm install in Android.',
        ),
      );
      await pumpEventQueue();

      expect(viewModel.state.status, AppUpdateStatus.awaitingUserConfirmation);
      expect(viewModel.state.downloadedFile?.path, readyFile.path);
      expect(viewModel.state.errorMessage, 'Confirm install in Android.');
      expect(installer.installCalls, 1);

      await viewModel.install();

      expect(installer.installCalls, 1);
      expect(viewModel.state.status, AppUpdateStatus.awaitingUserConfirmation);
    },
  );

  test('installing state ignores repeated install taps', () async {
    final installCompleter = Completer<int>();
    final installer = _FakeInstaller(installCompleter: installCompleter);
    final readyFile = await _readyApk();
    addTearDown(() => readyFile.parent.delete(recursive: true));
    final viewModel = AppUpdateViewModel(
      installedVersionCode: 1,
      installedVersionName: '1.0.0',
      repository: _FakeRepository(_manifest()),
      installer: installer,
      downloader: _FakeDownloader(
        result: AppUpdateDownloadResult(
          state: AppUpdateDownloadState.readyToInstall,
          file: readyFile,
        ),
      ),
      daemonBaseUri: Uri.parse('http://127.0.0.1:4317'),
    );
    addTearDown(viewModel.dispose);
    addTearDown(installer.close);

    await viewModel.checkForUpdates();
    await viewModel.download();
    final firstInstall = viewModel.install();
    await pumpEventQueue();

    expect(viewModel.state.status, AppUpdateStatus.installing);
    expect(installer.installCalls, 1);

    await viewModel.install();

    expect(installer.installCalls, 1);
    installCompleter.complete(7);
    await firstInstall;
  });

  test(
    'recovers persisted install session into pending confirmation state',
    () async {
      final installer = _FakeInstaller(
        recoveredEvent: const AndroidInstallEvent(
          status: AndroidInstallStatus.pendingUserAction,
          sessionId: 11,
          message: 'Package installer session is awaiting user confirmation.',
        ),
      );
      final readyFile = await _readyApk();
      addTearDown(() => readyFile.parent.delete(recursive: true));
      final manifest = _manifest(versionCode: 11);
      final downloader = _FakeDownloader(
        installSession: AppUpdateInstallSessionRecord(
          sessionId: 11,
          file: readyFile,
        ),
      );
      final viewModel = AppUpdateViewModel(
        installedVersionCode: 1,
        installedVersionName: '1.0.0',
        repository: _FakeRepository(manifest),
        installer: installer,
        downloader: downloader,
        daemonBaseUri: Uri.parse('http://127.0.0.1:4317'),
      );
      addTearDown(viewModel.dispose);
      addTearDown(installer.close);

      await viewModel.recoverInstallSession();

      expect(downloader.readSessionManifest, manifest);
      expect(installer.recoveredSessionId, 11);
      expect(viewModel.state.status, AppUpdateStatus.awaitingUserConfirmation);
      expect(viewModel.state.downloadedFile?.path, readyFile.path);
      expect(viewModel.state.manifest, manifest);
    },
  );

  test('recovery does not overwrite an active download', () async {
    final downloadCompleter = Completer<AppUpdateDownloadResult>();
    final installer = _FakeInstaller(
      recoveredEvent: const AndroidInstallEvent(
        status: AndroidInstallStatus.pendingUserAction,
        sessionId: 12,
      ),
    );
    final readyFile = await _readyApk();
    addTearDown(() => readyFile.parent.delete(recursive: true));
    final downloader = _FakeDownloader(
      installSession: AppUpdateInstallSessionRecord(
        sessionId: 12,
        file: readyFile,
      ),
      downloadCompleter: downloadCompleter,
    );
    final viewModel = AppUpdateViewModel(
      installedVersionCode: 1,
      installedVersionName: '1.0.0',
      repository: _FakeRepository(_manifest(versionCode: 12)),
      installer: installer,
      downloader: downloader,
      daemonBaseUri: Uri.parse('http://127.0.0.1:4317'),
    );
    addTearDown(viewModel.dispose);
    addTearDown(installer.close);

    await viewModel.checkForUpdates();
    final downloadFuture = viewModel.download();
    await pumpEventQueue();
    expect(viewModel.state.status, AppUpdateStatus.downloading);

    await viewModel.recoverInstallSession();

    expect(viewModel.state.status, AppUpdateStatus.downloading);
    expect(installer.recoveredSessionId, isNull);
    downloadCompleter.complete(
      AppUpdateDownloadResult(
        state: AppUpdateDownloadState.readyToInstall,
        file: readyFile,
      ),
    );
    await downloadFuture;
  });

  test('recovery failure is surfaced as failed state', () async {
    final installer = _FakeInstaller();
    final viewModel = AppUpdateViewModel(
      installedVersionCode: 1,
      installedVersionName: '1.0.0',
      repository: _FakeRepository(
        _manifest(),
        fetchError: StateError('daemon unavailable'),
      ),
      installer: installer,
      downloader: _FakeDownloader(),
      daemonBaseUri: Uri.parse('http://127.0.0.1:4317'),
    );
    addTearDown(viewModel.dispose);
    addTearDown(installer.close);

    await viewModel.recoverInstallSession();

    expect(viewModel.state.status, AppUpdateStatus.failed);
    expect(viewModel.state.errorMessage, contains('daemon unavailable'));
  });

  test('terminal install events clear recorded install session', () async {
    final installer = _FakeInstaller();
    final readyFile = await _readyApk();
    addTearDown(() => readyFile.parent.delete(recursive: true));
    final manifest = _manifest();
    final downloader = _FakeDownloader(
      result: AppUpdateDownloadResult(
        state: AppUpdateDownloadState.readyToInstall,
        file: readyFile,
      ),
    );
    final viewModel = AppUpdateViewModel(
      installedVersionCode: 1,
      installedVersionName: '1.0.0',
      repository: _FakeRepository(manifest),
      installer: installer,
      downloader: downloader,
      daemonBaseUri: Uri.parse('http://127.0.0.1:4317'),
    );
    addTearDown(viewModel.dispose);
    addTearDown(installer.close);

    await viewModel.checkForUpdates();
    await viewModel.download();
    await viewModel.install();
    installer.emit(
      const AndroidInstallEvent(
        status: AndroidInstallStatus.success,
        sessionId: 7,
      ),
    );
    await pumpEventQueue();

    expect(viewModel.state.status, AppUpdateStatus.installSucceeded);
    expect(downloader.clearedSessionManifest, manifest);
  });

  test('install rolls back when installer returns no session id', () async {
    final installer = _FakeInstaller(sessionId: -1);
    final readyFile = await _readyApk();
    addTearDown(() => readyFile.parent.delete(recursive: true));
    final downloader = _FakeDownloader(
      result: AppUpdateDownloadResult(
        state: AppUpdateDownloadState.readyToInstall,
        file: readyFile,
      ),
    );
    final viewModel = AppUpdateViewModel(
      installedVersionCode: 1,
      installedVersionName: '1.0.0',
      repository: _FakeRepository(_manifest()),
      installer: installer,
      downloader: downloader,
      daemonBaseUri: Uri.parse('http://127.0.0.1:4317'),
    );
    addTearDown(viewModel.dispose);
    addTearDown(installer.close);

    await viewModel.checkForUpdates();
    await viewModel.download();
    await viewModel.install();

    expect(viewModel.state.status, AppUpdateStatus.readyToInstall);
    expect(viewModel.state.errorMessage, contains('installer session'));
    expect(downloader.recordedSessionId, isNull);
  });

  test('install returns to download path when cached apk disappeared',
      () async {
    final installer = _FakeInstaller();
    final missingFile = File('${Directory.systemTemp.path}/missing-update.apk');
    if (await missingFile.exists()) await missingFile.delete();
    final viewModel = AppUpdateViewModel(
      installedVersionCode: 1,
      installedVersionName: '1.0.0',
      repository: _FakeRepository(_manifest()),
      installer: installer,
      downloader: _FakeDownloader(
        result: AppUpdateDownloadResult(
          state: AppUpdateDownloadState.readyToInstall,
          file: missingFile,
        ),
      ),
      daemonBaseUri: Uri.parse('http://127.0.0.1:4317'),
    );
    addTearDown(viewModel.dispose);
    addTearDown(installer.close);

    await viewModel.checkForUpdates();
    await viewModel.download();
    await viewModel.install();

    expect(viewModel.state.status, AppUpdateStatus.available);
    expect(viewModel.state.downloadedFile, isNull);
    expect(installer.installedPath, isNull);
  });

  test(
    'mandatory gate keeps diagnostics and daemon switching actions enabled',
    () {
      const state = AppUpdateState(
        status: AppUpdateStatus.available,
        installedVersionName: '1.0.0',
        installedVersionCode: 1,
        mandatory: true,
      );

      expect(state.mandatory, true);
    },
  );
}

AppUpdateManifest _manifest({
  int versionCode = 2,
  int minSupportedVersionCode = 1,
}) {
  return AppUpdateManifest(
    schemaVersion: 1,
    platform: 'android',
    available: true,
    packageName: 'com.example.lan_ai_cli_control',
    versionName: '1.4.0',
    versionCode: versionCode,
    minSupportedVersionCode: minSupportedVersionCode,
    mandatory: false,
    apkUrl: '/api/app-updates/android/apk/$versionCode',
    sha256: 'a' * 64,
    sizeBytes: 10,
    etag: '"etag-$versionCode"',
    publishedAt: DateTime.utc(2026, 5, 24),
  );
}

class _FakeRepository implements AppUpdateRepository {
  _FakeRepository(this.manifest, {this.fetchError});

  final AppUpdateManifest manifest;
  final Object? fetchError;

  @override
  Future<AppUpdateManifest> fetchLatest({String? ifNoneMatch}) async {
    final fetchError = this.fetchError;
    if (fetchError != null) throw fetchError;
    return manifest;
  }
}

Future<File> _readyApk() async {
  final dir = await Directory.systemTemp.createTemp('ready-update-apk-');
  final file = File('${dir.path}${Platform.pathSeparator}ready.apk');
  return file.writeAsBytes(<int>[1, 2, 3]);
}

class _FakeInstaller implements PackageInstallerService {
  _FakeInstaller({
    this.canInstall = true,
    this.sessionId = 7,
    this.recoveredEvent,
    this.installCompleter,
  });

  final bool canInstall;
  final int sessionId;
  final AndroidInstallEvent? recoveredEvent;
  final Completer<int>? installCompleter;
  final _events = StreamController<AndroidInstallEvent>.broadcast();
  String? installedPath;
  int installCalls = 0;
  int? recoveredSessionId;

  void emit(AndroidInstallEvent event) => _events.add(event);

  Future<void> close() => _events.close();

  @override
  Stream<AndroidInstallEvent> get events => _events.stream;

  @override
  Future<int> availableBytes() async => 1000000;

  @override
  Future<bool> canRequestPackageInstalls() async => canInstall;

  @override
  Future<int> installApk(String filePath) async {
    installCalls += 1;
    installedPath = filePath;
    final installCompleter = this.installCompleter;
    if (installCompleter != null) return installCompleter.future;
    return sessionId;
  }

  @override
  Future<void> openInstallPermissionSettings() async {}

  @override
  Future<AndroidInstallEvent?> recoverInstallSession(int sessionId) async {
    recoveredSessionId = sessionId;
    return recoveredEvent;
  }
}

class _FakeDownloader implements AppUpdateDownloader {
  _FakeDownloader({
    this.result = const AppUpdateDownloadResult(
      state: AppUpdateDownloadState.readyToInstall,
    ),
    this.installSession,
    this.downloadCompleter,
  });

  AppUpdateDownloadResult result;
  AppUpdateInstallSessionRecord? installSession;
  Completer<AppUpdateDownloadResult>? downloadCompleter;
  int? discardedVersionCode;
  int? recordedSessionId;
  AppUpdateManifest? recordedManifest;
  AppUpdateManifest? readSessionManifest;
  AppUpdateManifest? clearedSessionManifest;

  @override
  Future<AppUpdateDownloadResult> download(
    AppUpdateManifest manifest,
    Uri daemonBaseUri,
  ) async {
    final downloadCompleter = this.downloadCompleter;
    if (downloadCompleter != null) return downloadCompleter.future;
    return result;
  }

  @override
  Future<void> discard(int versionCode) async {
    discardedVersionCode = versionCode;
  }

  @override
  Future<void> recordInstallSession(
    AppUpdateManifest manifest,
    int sessionId,
  ) async {
    recordedManifest = manifest;
    recordedSessionId = sessionId;
  }

  @override
  Future<void> clearInstallSession(AppUpdateManifest manifest) async {
    clearedSessionManifest = manifest;
  }

  @override
  Future<AppUpdateInstallSessionRecord?> readInstallSession(
    AppUpdateManifest manifest,
  ) async {
    readSessionManifest = manifest;
    return installSession;
  }
}
