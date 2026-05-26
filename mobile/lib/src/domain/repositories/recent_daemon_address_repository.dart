abstract interface class RecentDaemonAddressRepository {
  Future<List<String>> loadRecentAddresses();

  Future<void> recordSuccessfulAddress(String addressInput);
}
