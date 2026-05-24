import '../../domain/repositories/app_update_repository.dart';
import '../../services/app_update_client.dart';
import '../models/app_update_models.dart';

class DaemonAppUpdateRepository implements AppUpdateRepository {
  DaemonAppUpdateRepository({required this.client});

  final AppUpdateClient client;

  @override
  Future<AppUpdateManifest> fetchLatest({String? ifNoneMatch}) async {
    final result = await client.fetchLatest(ifNoneMatch: ifNoneMatch);
    return result.manifest ??
        const AppUpdateManifest(
          schemaVersion: 1,
          platform: 'android',
          available: false,
        );
  }
}
