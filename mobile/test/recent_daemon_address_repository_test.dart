import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/data/repositories/recent_daemon_address_repository.dart';
import 'package:lan_ai_cli_control/src/services/recent_daemon_address_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  StoreRecentDaemonAddressRepository repository() {
    return StoreRecentDaemonAddressRepository(
      store: RecentDaemonAddressStore(),
    );
  }

  test('loads empty history when no addresses are stored', () async {
    expect(await repository().loadRecentAddresses(), isEmpty);
  });

  test('records successful addresses most recent first', () async {
    final repo = repository();

    await repo.recordSuccessfulAddress('192.168.1.10:4317');
    await repo.recordSuccessfulAddress('192.168.1.11:4317');

    expect(await repo.loadRecentAddresses(), <String>[
      '192.168.1.11:4317',
      '192.168.1.10:4317',
    ]);
  });

  test('trims and ignores empty addresses', () async {
    final repo = repository();

    await repo.recordSuccessfulAddress('  http://192.168.1.10:4317  ');
    await repo.recordSuccessfulAddress('   ');

    expect(await repo.loadRecentAddresses(), <String>[
      'http://192.168.1.10:4317',
    ]);
  });

  test('deduplicates case-only variants and preserves newest spelling',
      () async {
    final repo = repository();

    await repo.recordSuccessfulAddress('HTTP://192.168.1.10:4317');
    await repo.recordSuccessfulAddress('http://192.168.1.10:4317');

    expect(await repo.loadRecentAddresses(), <String>[
      'http://192.168.1.10:4317',
    ]);
  });

  test('keeps compact host and explicit URL as distinct entries', () async {
    final repo = repository();

    await repo.recordSuccessfulAddress('192.168.1.10');
    await repo.recordSuccessfulAddress('http://192.168.1.10:4317');

    expect(await repo.loadRecentAddresses(), <String>[
      'http://192.168.1.10:4317',
      '192.168.1.10',
    ]);
  });

  test('limits history to eight and removes oldest entries silently', () async {
    final repo = repository();

    for (var index = 1; index <= 10; index += 1) {
      await repo.recordSuccessfulAddress('192.168.1.$index:4317');
    }

    expect(await repo.loadRecentAddresses(), <String>[
      '192.168.1.10:4317',
      '192.168.1.9:4317',
      '192.168.1.8:4317',
      '192.168.1.7:4317',
      '192.168.1.6:4317',
      '192.168.1.5:4317',
      '192.168.1.4:4317',
      '192.168.1.3:4317',
    ]);
  });
}
