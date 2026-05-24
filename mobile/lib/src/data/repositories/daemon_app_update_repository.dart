import '../../domain/repositories/app_update_repository.dart';
import '../../services/app_update_client.dart';
import '../models/app_update_models.dart';

class DaemonAppUpdateRepository implements AppUpdateRepository {
  DaemonAppUpdateRepository({required this.client});

  final AppUpdateClient client;
  AppUpdateManifest? _cachedManifest;

  @override
  Future<AppUpdateManifest> fetchLatest({String? ifNoneMatch}) async {
    final result = await client.fetchLatest(ifNoneMatch: ifNoneMatch);
    if (result.notModified) {
      final cached = _cachedManifest;
      if (cached != null) return cached;
      throw const AppUpdateNotModifiedWithoutCacheException();
    }

    final manifest = result.manifest ??
        const AppUpdateManifest(
          schemaVersion: 1,
          platform: 'android',
          available: false,
        );
    _cachedManifest = manifest;
    return manifest;
  }
}

class AppUpdateNotModifiedWithoutCacheException implements Exception {
  const AppUpdateNotModifiedWithoutCacheException();

  @override
  String toString() {
    return 'App update manifest returned 304 without a cached manifest.';
  }
}
