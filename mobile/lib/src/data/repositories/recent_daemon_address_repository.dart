import '../../domain/repositories/recent_daemon_address_repository.dart';
import '../../services/recent_daemon_address_store.dart';

class StoreRecentDaemonAddressRepository
    implements RecentDaemonAddressRepository {
  StoreRecentDaemonAddressRepository({required RecentDaemonAddressStore store})
      : _store = store;

  final RecentDaemonAddressStore _store;

  @override
  Future<List<String>> loadRecentAddresses() => _store.load();

  @override
  Future<void> recordSuccessfulAddress(String addressInput) =>
      _store.record(addressInput);
}
