import 'dart:io';

import '../data/models/app_update_models.dart';
import '../domain/repositories/app_update_repository.dart';
import '../services/android_package_installer.dart' as installer;
import '../services/app_update_download_manager.dart' as downloader;

export '../services/android_package_installer.dart'
    show AndroidInstallEvent, AndroidInstallStatus;
export '../services/app_update_download_manager.dart'
    show
        AppUpdateDownloadResult,
        AppUpdateDownloadState,
        AppUpdateInstallSessionRecord;

enum AppUpdateInstallStartState {
  missingFile,
  permissionNeeded,
  invalidSession,
  committed,
}

class AppUpdateInstallStartResult {
  const AppUpdateInstallStartResult({
    required this.state,
    this.sessionId,
    this.message,
  });

  final AppUpdateInstallStartState state;
  final int? sessionId;
  final String? message;
}

enum AppUpdateRecoveryState {
  noUpdate,
  noSession,
  staleSession,
  installerEvent,
}

class AppUpdateRecoveryResult {
  const AppUpdateRecoveryResult({
    required this.state,
    this.manifest,
    this.file,
    this.event,
    this.message,
  });

  final AppUpdateRecoveryState state;
  final AppUpdateManifest? manifest;
  final File? file;
  final installer.AndroidInstallEvent? event;
  final String? message;
}

class AppUpdateWorkflow {
  AppUpdateWorkflow({
    required AppUpdateRepository repository,
    required installer.PackageInstallerService installerService,
    required downloader.AppUpdateDownloader downloaderService,
  })  : _repository = repository,
        _installer = installerService,
        _downloader = downloaderService;

  final AppUpdateRepository _repository;
  final installer.PackageInstallerService _installer;
  final downloader.AppUpdateDownloader _downloader;

  Stream<installer.AndroidInstallEvent> get installEvents => _installer.events;

  Future<AppUpdateManifest> fetchLatest({String? ifNoneMatch}) {
    return _repository.fetchLatest(ifNoneMatch: ifNoneMatch);
  }

  Future<downloader.AppUpdateDownloadResult> download(
    AppUpdateManifest manifest,
    Uri daemonBaseUri,
  ) {
    return _downloader.download(manifest, daemonBaseUri);
  }

  Future<void> clearInstallSession(
    AppUpdateManifest manifest, {
    int? sessionId,
  }) {
    return _downloader.clearInstallSession(manifest, sessionId: sessionId);
  }

  Future<void> discard(int versionCode) {
    return _downloader.discard(versionCode);
  }

  Future<AppUpdateInstallStartResult> startInstall({
    required AppUpdateManifest? manifest,
    required File file,
  }) async {
    if (!await _downloadedFileExists(file)) {
      return const AppUpdateInstallStartResult(
        state: AppUpdateInstallStartState.missingFile,
        message:
            'Downloaded APK is no longer available. Download the update again.',
      );
    }
    if (!await _installer.canRequestPackageInstalls()) {
      return const AppUpdateInstallStartResult(
        state: AppUpdateInstallStartState.permissionNeeded,
      );
    }
    final sessionId = await _installer.installApk(file.path);
    if (sessionId < 0) {
      return const AppUpdateInstallStartResult(
        state: AppUpdateInstallStartState.invalidSession,
        message: 'Android installer did not return a valid installer session.',
      );
    }
    if (manifest != null) {
      await _downloader.recordInstallSession(manifest, sessionId);
    }
    return AppUpdateInstallStartResult(
      state: AppUpdateInstallStartState.committed,
      sessionId: sessionId,
    );
  }

  Future<AppUpdateRecoveryResult> recoverInstall({
    required int installedVersionCode,
  }) async {
    final manifest = await _repository.fetchLatest();
    if (!manifest.available || !manifest.isNewerThan(installedVersionCode)) {
      return const AppUpdateRecoveryResult(
          state: AppUpdateRecoveryState.noUpdate);
    }
    final session = await _downloader.readInstallSession(manifest);
    if (session == null) {
      return AppUpdateRecoveryResult(
        state: AppUpdateRecoveryState.noSession,
        manifest: manifest,
      );
    }
    final event = await _installer.recoverInstallSession(session.sessionId);
    if (event == null) {
      await _downloader.clearInstallSession(
        manifest,
        sessionId: session.sessionId,
      );
      return AppUpdateRecoveryResult(
        state: AppUpdateRecoveryState.staleSession,
        manifest: manifest,
        file: session.file,
        message:
            'Android installer session is no longer active. Try installing the downloaded APK again.',
      );
    }
    return AppUpdateRecoveryResult(
      state: AppUpdateRecoveryState.installerEvent,
      manifest: manifest,
      file: session.file,
      event: event,
    );
  }

  Future<bool> _downloadedFileExists(File file) async {
    try {
      return await file.exists();
    } on FileSystemException {
      return false;
    }
  }

  Future<void> openInstallPermissionSettings() {
    return _installer.openInstallPermissionSettings();
  }
}
