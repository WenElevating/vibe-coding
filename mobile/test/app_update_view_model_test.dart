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
        repository: _FakeRepository(_manifest(minSupportedVersionCode: 4)),
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
    final viewModel = AppUpdateViewModel(
      installedVersionCode: 1,
      installedVersionName: '1.0.0',
      repository: _FakeRepository(_manifest()),
      installer: installer,
      downloader: _FakeDownloader(
        result: AppUpdateDownloadResult(
          state: AppUpdateDownloadState.readyToInstall,
          file: File('ready.apk'),
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
    final viewModel = AppUpdateViewModel(
      installedVersionCode: 1,
      installedVersionName: '1.0.0',
      repository: _FakeRepository(_manifest()),
      installer: installer,
      downloader: _FakeDownloader(
        result: AppUpdateDownloadResult(
          state: AppUpdateDownloadState.readyToInstall,
          file: File('ready.apk'),
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
    expect(installer.installedPath, 'ready.apk');
  });
}

AppUpdateManifest _manifest({int minSupportedVersionCode = 1}) {
  return AppUpdateManifest(
    schemaVersion: 1,
    platform: 'android',
    available: true,
    packageName: 'com.example.lan_ai_cli_control',
    versionName: '1.4.0',
    versionCode: 2,
    minSupportedVersionCode: minSupportedVersionCode,
    mandatory: false,
    apkUrl: '/api/app-updates/android/apk/2',
    sha256: 'a' * 64,
    sizeBytes: 10,
    etag: '"etag"',
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

class _FakeInstaller implements PackageInstallerService {
  _FakeInstaller({this.canInstall = true});

  final bool canInstall;
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
    return 7;
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

  final AppUpdateDownloadResult result;
  int? discardedVersionCode;

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
}
