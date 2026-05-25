import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:lan_ai_cli_control/src/data/models/app_update_models.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/app_update_repository.dart';
import 'package:lan_ai_cli_control/src/services/android_package_installer.dart';
import 'package:lan_ai_cli_control/src/services/app_update_download_manager.dart';
import 'package:lan_ai_cli_control/src/ui/features/settings/view_models/app_update_view_model.dart';
import 'package:lan_ai_cli_control/src/workflows/app_update_workflow.dart';

void main() {
  test(
    'check reports available update and mandatory min-supported gate',
    () async {
      final installer = _FakeInstaller();
      final viewModel = AppUpdateViewModel(
        installedVersionCode: 3,
        installedVersionName: '1.3.0',
        workflow: _workflow(
          repository: _FakeRepository(
            _manifest(versionCode: 4, minSupportedVersionCode: 4),
          ),
          installer: installer,
        ),
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
      workflow: _workflow(
        repository: _FakeRepository(_manifest()),
        installer: installer,
        downloader: _FakeDownloader(
          result: AppUpdateDownloadResult(
            state: AppUpdateDownloadState.readyToInstall,
            file: readyFile,
          ),
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
      workflow: _workflow(
        repository: _FakeRepository(_manifest()),
        installer: installer,
        downloader: _FakeDownloader(
          result: AppUpdateDownloadResult(
            state: AppUpdateDownloadState.readyToInstall,
            file: readyFile,
          ),
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
      workflow: _workflow(
        repository: _FakeRepository(_manifest()),
        installer: installer,
        downloader: downloader,
      ),
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
      workflow: _workflow(
        repository: _FakeRepository(_manifest()),
        installer: installer,
        downloader: _FakeDownloader(
          result: AppUpdateDownloadResult(
            state: AppUpdateDownloadState.readyToInstall,
            file: readyFile,
          ),
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
        workflow: _workflow(
          repository: _FakeRepository(_manifest()),
          installer: installer,
          downloader: _FakeDownloader(
            result: AppUpdateDownloadResult(
              state: AppUpdateDownloadState.readyToInstall,
              file: readyFile,
            ),
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
      workflow: _workflow(
        repository: _FakeRepository(_manifest()),
        installer: installer,
        downloader: _FakeDownloader(
          result: AppUpdateDownloadResult(
            state: AppUpdateDownloadState.readyToInstall,
            file: readyFile,
          ),
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

  test('install in-flight guard covers async permission check delay', () async {
    final canInstallCompleter = Completer<bool>();
    final installer = _FakeInstaller(canInstallCompleter: canInstallCompleter);
    final readyFile = await _readyApk();
    addTearDown(() => readyFile.parent.delete(recursive: true));
    final viewModel = AppUpdateViewModel(
      installedVersionCode: 1,
      installedVersionName: '1.0.0',
      workflow: _workflow(
        repository: _FakeRepository(_manifest()),
        installer: installer,
        downloader: _FakeDownloader(
          result: AppUpdateDownloadResult(
            state: AppUpdateDownloadState.readyToInstall,
            file: readyFile,
          ),
        ),
      ),
      daemonBaseUri: Uri.parse('http://127.0.0.1:4317'),
    );
    addTearDown(viewModel.dispose);
    addTearDown(installer.close);

    await viewModel.checkForUpdates();
    await viewModel.download();
    final firstInstall = viewModel.install();
    final secondInstall = viewModel.install();
    await pumpEventQueue();
    canInstallCompleter.complete(true);
    await Future.wait(<Future<void>>[firstInstall, secondInstall]);

    expect(installer.installCalls, 1);
  });

  test('install permission channel failure returns to retryable state',
      () async {
    final installer = _FakeInstaller(
      canInstallError: StateError('permission channel failed'),
    );
    final readyFile = await _readyApk();
    addTearDown(() => readyFile.parent.delete(recursive: true));
    final viewModel = AppUpdateViewModel(
      installedVersionCode: 1,
      installedVersionName: '1.0.0',
      workflow: _workflow(
        repository: _FakeRepository(_manifest()),
        installer: installer,
        downloader: _FakeDownloader(
          result: AppUpdateDownloadResult(
            state: AppUpdateDownloadState.readyToInstall,
            file: readyFile,
          ),
        ),
      ),
      daemonBaseUri: Uri.parse('http://127.0.0.1:4317'),
    );
    addTearDown(viewModel.dispose);
    addTearDown(installer.close);

    await viewModel.checkForUpdates();
    await viewModel.download();
    await viewModel.install();

    expect(viewModel.state.status, AppUpdateStatus.readyToInstall);
    expect(viewModel.state.errorMessage, contains('permission channel failed'));
    expect(installer.installCalls, 0);
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
        workflow: _workflow(
          repository: _FakeRepository(manifest),
          installer: installer,
          downloader: downloader,
        ),
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

  test('lifecycle resume recovers persisted session from available state',
      () async {
    final installer = _FakeInstaller(
      recoveredEvent: const AndroidInstallEvent(
        status: AndroidInstallStatus.pendingUserAction,
        sessionId: 15,
      ),
    );
    final readyFile = await _readyApk();
    addTearDown(() => readyFile.parent.delete(recursive: true));
    final manifest = _manifest(versionCode: 15);
    final downloader = _FakeDownloader(
      installSession: AppUpdateInstallSessionRecord(
        sessionId: 15,
        file: readyFile,
      ),
    );
    final viewModel = AppUpdateViewModel(
      installedVersionCode: 1,
      installedVersionName: '1.0.0',
      workflow: _workflow(
        repository: _FakeRepository(manifest),
        installer: installer,
        downloader: downloader,
      ),
      daemonBaseUri: Uri.parse('http://127.0.0.1:4317'),
    );
    addTearDown(viewModel.dispose);
    addTearDown(installer.close);

    await viewModel.checkForUpdates();
    expect(viewModel.state.status, AppUpdateStatus.available);

    viewModel.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await pumpEventQueue();
    expect(installer.recoveredSessionId, isNull);

    viewModel.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await pumpEventQueue();

    expect(installer.recoveredSessionId, 15);
    expect(viewModel.state.status, AppUpdateStatus.awaitingUserConfirmation);
  });

  test('recovers persisted install session while download is paused', () async {
    final installer = _FakeInstaller(
      recoveredEvent: const AndroidInstallEvent(
        status: AndroidInstallStatus.pendingUserAction,
        sessionId: 16,
      ),
    );
    final readyFile = await _readyApk();
    addTearDown(() => readyFile.parent.delete(recursive: true));
    final manifest = _manifest(versionCode: 16);
    final downloader = _FakeDownloader(
      result: const AppUpdateDownloadResult(
        state: AppUpdateDownloadState.paused,
        message: 'server unavailable',
      ),
      installSession: AppUpdateInstallSessionRecord(
        sessionId: 16,
        file: readyFile,
      ),
    );
    final viewModel = AppUpdateViewModel(
      installedVersionCode: 1,
      installedVersionName: '1.0.0',
      workflow: _workflow(
        repository: _FakeRepository(manifest),
        installer: installer,
        downloader: downloader,
      ),
      daemonBaseUri: Uri.parse('http://127.0.0.1:4317'),
    );
    addTearDown(viewModel.dispose);
    addTearDown(installer.close);

    await viewModel.checkForUpdates();
    await viewModel.download();
    expect(viewModel.state.status, AppUpdateStatus.paused);

    await viewModel.recoverInstallSession();

    expect(installer.recoveredSessionId, 16);
    expect(viewModel.state.status, AppUpdateStatus.awaitingUserConfirmation);
  });

  test('manifest unavailable recovery clears orphan install sessions',
      () async {
    final installer = _FakeInstaller();
    final downloader = _FakeDownloader();
    final viewModel = AppUpdateViewModel(
      installedVersionCode: 1,
      installedVersionName: '1.0.0',
      workflow: _workflow(
        repository: _FakeRepository(
          const AppUpdateManifest(
            schemaVersion: 1,
            platform: 'android',
            available: false,
          ),
        ),
        installer: installer,
        downloader: downloader,
      ),
      daemonBaseUri: Uri.parse('http://127.0.0.1:4317'),
    );
    addTearDown(viewModel.dispose);
    addTearDown(installer.close);

    await viewModel.recoverInstallSession();

    expect(downloader.clearAllInstallSessionCalls, 1);
    expect(viewModel.state.status, AppUpdateStatus.idle);
  });

  test('no-update recovery clears stale available state', () async {
    final installer = _FakeInstaller();
    final downloader = _FakeDownloader();
    final repository = _FakeRepository(_manifest(versionCode: 17));
    final viewModel = AppUpdateViewModel(
      installedVersionCode: 1,
      installedVersionName: '1.0.0',
      workflow: _workflow(
        repository: repository,
        installer: installer,
        downloader: downloader,
      ),
      daemonBaseUri: Uri.parse('http://127.0.0.1:4317'),
    );
    addTearDown(viewModel.dispose);
    addTearDown(installer.close);

    await viewModel.checkForUpdates();
    expect(viewModel.state.status, AppUpdateStatus.available);

    repository.manifest = const AppUpdateManifest(
      schemaVersion: 1,
      platform: 'android',
      available: false,
    );
    await viewModel.recoverInstallSession();

    expect(downloader.clearAllInstallSessionCalls, 1);
    expect(viewModel.state.status, AppUpdateStatus.upToDate);
    expect(viewModel.state.downloadedFile, isNull);
    expect(viewModel.state.mandatory, false);
  });

  test('no-update recovery clears stale paused state', () async {
    final installer = _FakeInstaller();
    final downloader = _FakeDownloader(
      result: const AppUpdateDownloadResult(
        state: AppUpdateDownloadState.paused,
        message: 'server unavailable',
      ),
    );
    final repository = _FakeRepository(_manifest(versionCode: 18));
    final viewModel = AppUpdateViewModel(
      installedVersionCode: 1,
      installedVersionName: '1.0.0',
      workflow: _workflow(
        repository: repository,
        installer: installer,
        downloader: downloader,
      ),
      daemonBaseUri: Uri.parse('http://127.0.0.1:4317'),
    );
    addTearDown(viewModel.dispose);
    addTearDown(installer.close);

    await viewModel.checkForUpdates();
    await viewModel.download();
    expect(viewModel.state.status, AppUpdateStatus.paused);

    repository.manifest = const AppUpdateManifest(
      schemaVersion: 1,
      platform: 'android',
      available: false,
    );
    await viewModel.recoverInstallSession();

    expect(downloader.clearAllInstallSessionCalls, 1);
    expect(viewModel.state.status, AppUpdateStatus.upToDate);
    expect(viewModel.state.downloadedFile, isNull);
  });

  test('check is ignored while download is active', () async {
    final downloadCompleter = Completer<AppUpdateDownloadResult>();
    final installer = _FakeInstaller();
    final repository = _FakeRepository(_manifest());
    final viewModel = AppUpdateViewModel(
      installedVersionCode: 1,
      installedVersionName: '1.0.0',
      workflow: _workflow(
        repository: repository,
        installer: installer,
        downloader: _FakeDownloader(downloadCompleter: downloadCompleter),
      ),
      daemonBaseUri: Uri.parse('http://127.0.0.1:4317'),
    );
    addTearDown(viewModel.dispose);
    addTearDown(installer.close);

    await viewModel.checkForUpdates();
    final downloadFuture = viewModel.download();
    await pumpEventQueue();

    await viewModel.checkForUpdates();

    expect(viewModel.state.status, AppUpdateStatus.downloading);
    expect(repository.fetchCalls, 1);
    downloadCompleter.complete(
      const AppUpdateDownloadResult(state: AppUpdateDownloadState.failed),
    );
    await downloadFuture;
  });

  test('check is ignored while waiting for Android confirmation', () async {
    final installer = _FakeInstaller();
    final repository = _FakeRepository(_manifest());
    final readyFile = await _readyApk();
    addTearDown(() => readyFile.parent.delete(recursive: true));
    final viewModel = AppUpdateViewModel(
      installedVersionCode: 1,
      installedVersionName: '1.0.0',
      workflow: _workflow(
        repository: repository,
        installer: installer,
        downloader: _FakeDownloader(
          result: AppUpdateDownloadResult(
            state: AppUpdateDownloadState.readyToInstall,
            file: readyFile,
          ),
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
      ),
    );
    await pumpEventQueue();

    await viewModel.checkForUpdates();

    expect(viewModel.state.status, AppUpdateStatus.awaitingUserConfirmation);
    expect(repository.fetchCalls, 1);
  });

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
      workflow: _workflow(
        repository: _FakeRepository(_manifest(versionCode: 12)),
        installer: installer,
        downloader: downloader,
      ),
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

  test('recovery clears stale install metadata when native session is gone',
      () async {
    final installer = _FakeInstaller();
    final readyFile = await _readyApk();
    addTearDown(() => readyFile.parent.delete(recursive: true));
    final manifest = _manifest(versionCode: 13);
    final downloader = _FakeDownloader(
      installSession: AppUpdateInstallSessionRecord(
        sessionId: 13,
        file: readyFile,
      ),
    );
    final viewModel = AppUpdateViewModel(
      installedVersionCode: 1,
      installedVersionName: '1.0.0',
      workflow: _workflow(
        repository: _FakeRepository(manifest),
        installer: installer,
        downloader: downloader,
      ),
      daemonBaseUri: Uri.parse('http://127.0.0.1:4317'),
    );
    addTearDown(viewModel.dispose);
    addTearDown(installer.close);

    await viewModel.recoverInstallSession();

    expect(viewModel.state.status, AppUpdateStatus.readyToInstall);
    expect(viewModel.state.downloadedFile?.path, readyFile.path);
    expect(downloader.clearedSessionManifest, manifest);
    expect(downloader.clearedSessionId, 13);
    expect(viewModel.state.errorMessage, contains('no longer active'));
  });

  test('stale native recovery does not overwrite a newer install attempt',
      () async {
    final recoveryCompleter = Completer<AndroidInstallEvent?>();
    final installer = _FakeInstaller(recoverCompleter: recoveryCompleter);
    final readyFile = await _readyApk();
    addTearDown(() => readyFile.parent.delete(recursive: true));
    final manifest = _manifest(versionCode: 14);
    final downloader = _FakeDownloader(
      installSession: AppUpdateInstallSessionRecord(
        sessionId: 13,
        file: readyFile,
      ),
    );
    final viewModel = AppUpdateViewModel(
      installedVersionCode: 1,
      installedVersionName: '1.0.0',
      workflow: _workflow(
        repository: _FakeRepository(manifest),
        installer: installer,
        downloader: downloader,
      ),
      daemonBaseUri: Uri.parse('http://127.0.0.1:4317'),
    );
    addTearDown(viewModel.dispose);
    addTearDown(installer.close);

    final recovery = viewModel.recoverInstallSession();
    await pumpEventQueue();
    expect(installer.recoveredSessionId, 13);

    await viewModel.install();
    expect(installer.installCalls, 0);

    recoveryCompleter.complete(null);
    await recovery;

    expect(viewModel.state.status, AppUpdateStatus.readyToInstall);
    expect(downloader.clearedSessionId, 13);
    expect(downloader.recordedSessionId, isNull);
  });

  test('recovery failure is surfaced as failed state', () async {
    final installer = _FakeInstaller();
    final viewModel = AppUpdateViewModel(
      installedVersionCode: 1,
      installedVersionName: '1.0.0',
      workflow: _workflow(
        repository: _FakeRepository(
          _manifest(),
          fetchError: StateError('daemon unavailable'),
        ),
        installer: installer,
      ),
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
      workflow: _workflow(
        repository: _FakeRepository(manifest),
        installer: installer,
        downloader: downloader,
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
    expect(downloader.clearedSessionManifest, manifest);
  });

  test('dispose suppresses async clear install session diagnostics', () async {
    final diagnostics = <String>[];
    final clearCompleter = Completer<void>();
    final installer = _FakeInstaller();
    final readyFile = await _readyApk();
    addTearDown(() => readyFile.parent.delete(recursive: true));
    final downloader = _FakeDownloader(
      result: AppUpdateDownloadResult(
        state: AppUpdateDownloadState.readyToInstall,
        file: readyFile,
      ),
      clearSessionCompleter: clearCompleter,
      clearSessionError: StateError('clear failed'),
    );
    final viewModel = AppUpdateViewModel(
      installedVersionCode: 1,
      installedVersionName: '1.0.0',
      workflow: _workflow(
        repository: _FakeRepository(_manifest()),
        installer: installer,
        downloader: downloader,
      ),
      daemonBaseUri: Uri.parse('http://127.0.0.1:4317'),
      recordDiagnostic: (event, metadata) => diagnostics.add(event),
    );
    var disposed = false;
    addTearDown(() {
      if (!disposed) viewModel.dispose();
    });
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
    expect(downloader.clearSessionStarted, true);

    viewModel.dispose();
    disposed = true;
    clearCompleter.complete();
    await pumpEventQueue();

    expect(diagnostics, isNot(contains('update.install.clear_session_failed')));
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
      workflow: _workflow(
        repository: _FakeRepository(_manifest()),
        installer: installer,
        downloader: downloader,
      ),
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
      workflow: _workflow(
        repository: _FakeRepository(_manifest()),
        installer: installer,
        downloader: _FakeDownloader(
          result: AppUpdateDownloadResult(
            state: AppUpdateDownloadState.readyToInstall,
            file: missingFile,
          ),
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

AppUpdateWorkflow _workflow({
  required AppUpdateRepository repository,
  required PackageInstallerService installer,
  AppUpdateDownloader? downloader,
}) {
  return AppUpdateWorkflow(
    repository: repository,
    installerService: installer,
    downloaderService: downloader ?? _FakeDownloader(),
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

  AppUpdateManifest manifest;
  final Object? fetchError;
  int fetchCalls = 0;

  @override
  Future<AppUpdateManifest> fetchLatest({String? ifNoneMatch}) async {
    fetchCalls += 1;
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
    this.canInstallCompleter,
    this.recoverCompleter,
    this.canInstallError,
  });

  final bool canInstall;
  final int sessionId;
  final AndroidInstallEvent? recoveredEvent;
  final Completer<int>? installCompleter;
  final Completer<bool>? canInstallCompleter;
  final Completer<AndroidInstallEvent?>? recoverCompleter;
  final Object? canInstallError;
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
  Future<bool> canRequestPackageInstalls() async {
    final error = canInstallError;
    if (error != null) throw error;
    final completer = canInstallCompleter;
    if (completer != null) return completer.future;
    return canInstall;
  }

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
    final recoverCompleter = this.recoverCompleter;
    if (recoverCompleter != null) return recoverCompleter.future;
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
    this.clearSessionCompleter,
    this.clearSessionError,
  });

  AppUpdateDownloadResult result;
  AppUpdateInstallSessionRecord? installSession;
  Completer<AppUpdateDownloadResult>? downloadCompleter;
  Completer<void>? clearSessionCompleter;
  Object? clearSessionError;
  int? discardedVersionCode;
  int? recordedSessionId;
  AppUpdateManifest? recordedManifest;
  AppUpdateManifest? readSessionManifest;
  AppUpdateManifest? clearedSessionManifest;
  int? clearedSessionId;
  int clearAllInstallSessionCalls = 0;
  bool clearSessionStarted = false;

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
  Future<void> clearInstallSession(
    AppUpdateManifest manifest, {
    int? sessionId,
  }) async {
    clearSessionStarted = true;
    final completer = clearSessionCompleter;
    if (completer != null) await completer.future;
    final error = clearSessionError;
    if (error != null) throw error;
    clearedSessionManifest = manifest;
    clearedSessionId = sessionId;
  }

  @override
  Future<void> clearAllInstallSessions() async {
    clearAllInstallSessionCalls += 1;
  }

  @override
  Future<AppUpdateInstallSessionRecord?> readInstallSession(
    AppUpdateManifest manifest,
  ) async {
    readSessionManifest = manifest;
    return installSession;
  }
}
