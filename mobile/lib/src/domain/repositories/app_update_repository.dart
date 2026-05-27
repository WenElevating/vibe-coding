import '../models/app_update_manifest.dart';

abstract class AppUpdateRepository {
  Future<AppUpdateManifest> fetchLatest({String? ifNoneMatch});
}
