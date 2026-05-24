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

  test('install cancelled returns to ready-to-install for retry', () async {
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

    expect(viewModel.state.status, AppUpdateStatus.readyToInstall);
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
    },
  );

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
  _FakeRepository(this.manifest);

  final AppUpdateManifest manifest;

  @override
  Future<AppUpdateManifest> fetchLatest({String? ifNoneMatch}) async =>
      manifest;
}

Future<File> _readyApk() async {
  final dir = await Directory.systemTemp.createTemp('ready-update-apk-');
  final file = File('${dir.path}${Platform.pathSeparator}ready.apk');
  return file.writeAsBytes(<int>[1, 2, 3]);
}

class _FakeInstaller implements PackageInstallerService {
  _FakeInstaller({this.canInstall = true, this.sessionId = 7});

  final bool canInstall;
  final int sessionId;
  final _events = StreamController<AndroidInstallEvent>.broadcast();
  String? installedPath;

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
    installedPath = filePath;
    return sessionId;
  }

  @override
  Future<void> openInstallPermissionSettings() async {}

  @override
  Future<AndroidInstallEvent?> recoverInstallSession(int sessionId) async =>
      null;
}

class _FakeDownloader implements AppUpdateDownloader {
  _FakeDownloader({
    this.result = const AppUpdateDownloadResult(
      state: AppUpdateDownloadState.readyToInstall,
    ),
  });

  AppUpdateDownloadResult result;
  int? discardedVersionCode;
  int? recordedSessionId;
  AppUpdateManifest? recordedManifest;

  @override
  Future<AppUpdateDownloadResult> download(
    AppUpdateManifest manifest,
    Uri daemonBaseUri,
  ) async {
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
}
