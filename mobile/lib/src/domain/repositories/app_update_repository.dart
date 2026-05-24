import '../../data/models/app_update_models.dart';

abstract class AppUpdateRepository {
  Future<AppUpdateManifest> fetchLatest({String? ifNoneMatch});
}
