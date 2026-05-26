# Connection History and Update Prompt Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add address-only recent daemon history to the connection gate and foreground in-app update prompts after connection/resume.

**Architecture:** Keep persistence behind repository/service boundaries, keep connection and update decisions in ViewModels, and keep widgets limited to focus, keyboard, dropdown, dialog, and rendering behavior. `DaemonConnectionViewModel` will depend on `RecentDaemonAddressRepository`; `AppUpdateViewModel` will own silent-check concurrency and prompt suppression.

**Tech Stack:** Flutter, Dart `ChangeNotifier`, SharedPreferences, existing `AppUpdateWorkflow`, existing Flutter widget tests.

---

## File Structure

- Create `mobile/lib/src/domain/repositories/recent_daemon_address_repository.dart`
  - Domain interface for address-only history.
- Create `mobile/lib/src/services/recent_daemon_address_store.dart`
  - SharedPreferences-backed local store with trim, case-insensitive dedupe, ordering, and limit logic.
- Create `mobile/lib/src/data/repositories/recent_daemon_address_repository.dart`
  - Data-layer repository implementation wrapping the service store.
- Modify `mobile/lib/src/app/app_dependencies.dart`
  - Wire the recent-address repository into `DataDependencies` and `FeatureDependencies`.
- Modify `mobile/lib/src/ui/features/connection/view_models/daemon_connection_view_model.dart`
  - Add recent address state, selection command, history record/refresh, and no-op diagnostic recorder.
- Modify `mobile/lib/src/ui/features/connection/view_models/daemon_connection_controller.dart`
  - Pass recent-address repository and diagnostic recorder through the convenience controller.
- Modify `mobile/lib/src/ui/mobile_connection_page.dart`
  - Remove the fake header control, add address dropdown, focus handling, keyboard dismissal, max height, and semantics.
- Modify `mobile/lib/src/ui/features/settings/view_models/app_update_view_model.dart`
  - Add silent-check trigger enum, in-flight guard, session-scoped optional prompt suppression, diagnostics, and non-disruptive silent failures.
- Modify `mobile/lib/src/ui/features/settings/widgets/app_update_panel.dart`
  - Add `onPostpone` callback and skip automatic prompt when state says prompt is suppressed.
- Modify `mobile/lib/src/ui/main_tabs_page.dart`
  - Trigger silent update checks after connected update ViewModel creation and app resume.
- Test `mobile/test/recent_daemon_address_repository_test.dart`
  - New repository/store behavior tests.
- Test `mobile/test/daemon_connection_controller_test.dart`
  - ViewModel history, diagnostics, and selection behavior.
- Test `mobile/test/widget_test.dart`
  - Connection page dropdown and MainTabs lifecycle update checks.
- Test `mobile/test/app_update_view_model_test.dart`
  - Silent checks, in-flight guard, prompt suppression, and diagnostics.
- Test `mobile/test/app_update_panel_test.dart`
  - Prompt suppression and postpone callback.
- Optionally update `mobile/test/app_dependencies_test.dart`
  - Assert default dependency graph exposes the recent-address repository if this test already checks data wiring.

## Task 1: Recent Address Repository Boundary

**Files:**
- Create: `mobile/lib/src/domain/repositories/recent_daemon_address_repository.dart`
- Create: `mobile/lib/src/services/recent_daemon_address_store.dart`
- Create: `mobile/lib/src/data/repositories/recent_daemon_address_repository.dart`
- Create: `mobile/test/recent_daemon_address_repository_test.dart`
- Modify: `mobile/lib/src/app/app_dependencies.dart`

- [ ] **Step 1: Write repository behavior tests**

Create `mobile/test/recent_daemon_address_repository_test.dart`:

```dart
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
```

- [ ] **Step 2: Run the new test and verify it fails**

Run from `mobile/` with mirrors:

```powershell
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test --no-pub test\recent_daemon_address_repository_test.dart -r expanded
```

Expected: fails because `recent_daemon_address_repository.dart` and `recent_daemon_address_store.dart` do not exist.

- [ ] **Step 3: Add the domain interface**

Create `mobile/lib/src/domain/repositories/recent_daemon_address_repository.dart`:

```dart
abstract interface class RecentDaemonAddressRepository {
  Future<List<String>> loadRecentAddresses();

  Future<void> recordSuccessfulAddress(String addressInput);
}
```

- [ ] **Step 4: Add the SharedPreferences store**

Create `mobile/lib/src/services/recent_daemon_address_store.dart`:

```dart
import 'package:shared_preferences/shared_preferences.dart';

class RecentDaemonAddressStore {
  static const storageKey = 'daemonConnection.recentAddresses';
  static const maxRecentAddresses = 8;

  Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return List<String>.unmodifiable(
      _sanitize(prefs.getStringList(storageKey) ?? const <String>[]),
    );
  }

  Future<void> record(String addressInput) async {
    final trimmed = addressInput.trim();
    if (trimmed.isEmpty) return;
    final current = await load();
    final normalized = _dedupeKey(trimmed);
    final next = <String>[
      trimmed,
      for (final address in current)
        if (_dedupeKey(address) != normalized) address,
    ].take(maxRecentAddresses).toList(growable: false);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(storageKey, next);
  }

  List<String> _sanitize(List<String> values) {
    final result = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) continue;
      final key = _dedupeKey(trimmed);
      if (seen.add(key)) {
        result.add(trimmed);
      }
      if (result.length == maxRecentAddresses) break;
    }
    return result;
  }

  String _dedupeKey(String value) => value.trim().toLowerCase();
}
```

- [ ] **Step 5: Add the data repository implementation**

Create `mobile/lib/src/data/repositories/recent_daemon_address_repository.dart`:

```dart
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
```

- [ ] **Step 6: Wire the repository into data dependencies**

Modify `mobile/lib/src/app/app_dependencies.dart`:

```dart
import '../data/repositories/recent_daemon_address_repository.dart';
import '../domain/repositories/recent_daemon_address_repository.dart';
import '../services/recent_daemon_address_store.dart';
```

Update `DataDependencies`:

```dart
class DataDependencies {
  DataDependencies({
    required this.connectionConfigRepository,
    required this.recentAddressRepository,
    NotificationClientFactory? createNotificationClient,
  }) : createNotificationClient =
            createNotificationClient ?? _createDefaultNotificationClient;

  factory DataDependencies.createDefault() {
    final connectionConfigStore = DaemonConnectionConfigStore();
    final recentAddressStore = RecentDaemonAddressStore();
    return DataDependencies(
      connectionConfigRepository:
          StoreDaemonConnectionConfigRepository(store: connectionConfigStore),
      recentAddressRepository:
          StoreRecentDaemonAddressRepository(store: recentAddressStore),
    );
  }

  final DaemonConnectionConfigRepository connectionConfigRepository;
  final RecentDaemonAddressRepository recentAddressRepository;
  final NotificationClientFactory createNotificationClient;
```

The next task will pass this repository into the connection ViewModel factory.

- [ ] **Step 7: Run repository tests and format**

Run:

```powershell
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
dart format lib\src\domain\repositories\recent_daemon_address_repository.dart lib\src\services\recent_daemon_address_store.dart lib\src\data\repositories\recent_daemon_address_repository.dart test\recent_daemon_address_repository_test.dart
flutter test --no-pub test\recent_daemon_address_repository_test.dart -r expanded
```

Expected: all tests in `recent_daemon_address_repository_test.dart` pass.

- [ ] **Step 8: Commit Task 1**

```powershell
git add mobile\lib\src\domain\repositories\recent_daemon_address_repository.dart mobile\lib\src\services\recent_daemon_address_store.dart mobile\lib\src\data\repositories\recent_daemon_address_repository.dart mobile\lib\src\app\app_dependencies.dart mobile\test\recent_daemon_address_repository_test.dart
git commit -m "Add recent daemon address repository"
```

## Task 2: Connection ViewModel History State

**Files:**
- Modify: `mobile/lib/src/ui/features/connection/view_models/daemon_connection_view_model.dart`
- Modify: `mobile/lib/src/ui/features/connection/view_models/daemon_connection_controller.dart`
- Modify: `mobile/lib/src/app/app_dependencies.dart`
- Modify: `mobile/test/daemon_connection_controller_test.dart`

- [ ] **Step 1: Add failing ViewModel tests**

Append these tests to `mobile/test/daemon_connection_controller_test.dart` before the closing `}` of `main()`:

```dart
  test('loads recent addresses without blocking stored config', () async {
    final store = DaemonConnectionConfigStore();
    await store.save(const DaemonConnectionConfig(
      addressInput: '192.168.1.23:4317',
      proxyMode: DaemonProxyMode.system,
      manualProxyInput: '',
    ));
    final recentRepository = _FakeRecentAddressRepository(
      addresses: const <String>['192.168.1.22:4317'],
    );
    final controller = DaemonConnectionController(
      store: store,
      tokenStore: MemoryTokenStore(),
      recentAddressRepository: recentRepository,
      snapshotLoader: (_) async => throw StateError('not used'),
      healthProbe: (_) async => throw StateError('not used'),
    );

    await controller.load();

    expect(controller.addressInput, '192.168.1.23:4317');
    expect(controller.recentAddresses, <String>['192.168.1.22:4317']);
  });

  test('recent address load failure falls back to empty history', () async {
    final diagnostics = <String>[];
    final controller = DaemonConnectionController(
      store: DaemonConnectionConfigStore(),
      tokenStore: MemoryTokenStore(),
      recentAddressRepository: _FakeRecentAddressRepository(
        loadError: StateError('corrupt history'),
      ),
      recordDiagnostic: (event, metadata) => diagnostics.add(event),
      snapshotLoader: (_) async => throw StateError('not used'),
      healthProbe: (_) async => throw StateError('not used'),
    );

    await controller.load();

    expect(controller.status, DaemonConnectionStatus.idle);
    expect(controller.recentAddresses, isEmpty);
    expect(
      diagnostics,
      contains('connection.recent_addresses.load_failed'),
    );
  });

  test('selecting recent address only fills input', () async {
    final controller = DaemonConnectionController(
      store: DaemonConnectionConfigStore(),
      tokenStore: MemoryTokenStore(),
      recentAddressRepository: _FakeRecentAddressRepository(),
      snapshotLoader: (_) async => _snapshot(),
      healthProbe: (_) async => _health(),
    );
    await controller.load();
    controller.setProxyMode(DaemonProxyMode.manual);
    controller.setManualProxyInput('http://proxy.local:8080');

    controller.selectRecentAddress('192.168.1.50:4317');

    expect(controller.addressInput, '192.168.1.50:4317');
    expect(controller.proxyMode, DaemonProxyMode.manual);
    expect(controller.manualProxyInput, 'http://proxy.local:8080');
    expect(controller.status, DaemonConnectionStatus.idle);
  });

  test('successful connection records and refreshes recent address', () async {
    final recentRepository = _FakeRecentAddressRepository();
    final controller = DaemonConnectionController(
      store: DaemonConnectionConfigStore(),
      tokenStore: MemoryTokenStore(),
      recentAddressRepository: recentRepository,
      snapshotLoader: (_) async => _snapshot(),
      healthProbe: (_) async => _health(),
    );
    await controller.load();
    controller.setAddressInput('192.168.1.23');

    await controller.connect();

    expect(recentRepository.recordedAddresses, <String>['192.168.1.23']);
    expect(controller.recentAddresses, <String>['192.168.1.23']);
    expect(controller.status, DaemonConnectionStatus.connected);
  });

  test('recent address record failure does not block connection', () async {
    final diagnostics = <String>[];
    final controller = DaemonConnectionController(
      store: DaemonConnectionConfigStore(),
      tokenStore: MemoryTokenStore(),
      recentAddressRepository: _FakeRecentAddressRepository(
        recordError: StateError('write failed'),
      ),
      recordDiagnostic: (event, metadata) => diagnostics.add(event),
      snapshotLoader: (_) async => _snapshot(),
      healthProbe: (_) async => _health(),
    );
    await controller.load();
    controller.setAddressInput('192.168.1.24');

    await controller.connect();

    expect(controller.status, DaemonConnectionStatus.connected);
    expect(
      diagnostics,
      contains('connection.recent_addresses.record_failed'),
    );
  });
```

Add this fake below `_CloseTrackingDaemonClient`:

```dart
class _FakeRecentAddressRepository implements RecentDaemonAddressRepository {
  _FakeRecentAddressRepository({
    List<String> addresses = const <String>[],
    this.loadError,
    this.recordError,
  }) : addresses = List<String>.from(addresses);

  final List<String> addresses;
  final Object? loadError;
  final Object? recordError;
  final recordedAddresses = <String>[];

  @override
  Future<List<String>> loadRecentAddresses() async {
    final error = loadError;
    if (error != null) throw error;
    return List<String>.unmodifiable(addresses);
  }

  @override
  Future<void> recordSuccessfulAddress(String addressInput) async {
    final error = recordError;
    if (error != null) throw error;
    recordedAddresses.add(addressInput);
    addresses
      ..removeWhere(
        (address) => address.toLowerCase() == addressInput.toLowerCase(),
      )
      ..insert(0, addressInput);
  }
}
```

Add the import:

```dart
import 'package:lan_ai_cli_control/src/domain/repositories/recent_daemon_address_repository.dart';
```

- [ ] **Step 2: Run the controller tests and verify they fail**

Run:

```powershell
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test --no-pub test\daemon_connection_controller_test.dart -r expanded
```

Expected: fails because `DaemonConnectionController` has no `recentAddressRepository`, `recordDiagnostic`, `recentAddresses`, or `selectRecentAddress`.

- [ ] **Step 3: Update `DaemonConnectionViewModel` constructor and state**

Modify `mobile/lib/src/ui/features/connection/view_models/daemon_connection_view_model.dart` imports:

```dart
import '../../../../domain/repositories/recent_daemon_address_repository.dart';
```

Add diagnostic typedefs above the class:

```dart
typedef DiagnosticRecorder = void Function(
  String event,
  Map<String, Object?> metadata,
);

void noopDiagnosticRecorder(String event, Map<String, Object?> metadata) {}
```

Update constructor and fields:

```dart
  DaemonConnectionViewModel({
    required DaemonConnectionConfigRepository configRepository,
    required RecentDaemonAddressRepository recentAddressRepository,
    required ConnectToDaemonUseCase<DaemonClient> connectToDaemon,
    Duration connectionTimeout = const Duration(seconds: 30),
    DiagnosticRecorder recordDiagnostic = noopDiagnosticRecorder,
  })  : _configRepository = configRepository,
        _recentAddressRepository = recentAddressRepository,
        _connectToDaemon = connectToDaemon,
        _connectionTimeout = connectionTimeout,
        _recordDiagnostic = recordDiagnostic;

  final RecentDaemonAddressRepository _recentAddressRepository;
  final DiagnosticRecorder _recordDiagnostic;
```

Add state and getter:

```dart
  List<String> _recentAddresses = const <String>[];

  List<String> get recentAddresses => _recentAddresses;
```

- [ ] **Step 4: Implement load, selection, and record refresh**

Replace `load()` with:

```dart
  Future<void> load() async {
    final config = await _configRepository.load();
    final recentAddresses = await _loadRecentAddressesOrEmpty();
    _addressInput = config.addressInput;
    _proxyMode = config.proxyMode;
    _manualProxyInput = config.manualProxyInput;
    _recentAddresses = recentAddresses;
    _status = DaemonConnectionStatus.idle;
    notifyListeners();
  }
```

Add command:

```dart
  void selectRecentAddress(String address) {
    _addressInput = address;
    _clearTransientErrors();
    notifyListeners();
  }
```

After successful connection state is set in `connect()`, add:

```dart
      _client = session.client;
      _initialData = session.initialData;
      _connectedConfig = session.connectedConfig;
      _status = DaemonConnectionStatus.connected;
      notifyListeners();
      await _recordSuccessfulRecentAddress(session.connectedConfig.addressInput);
```

Add helpers before `_clearTransientErrors()`:

```dart
  Future<List<String>> _loadRecentAddressesOrEmpty() async {
    try {
      return List<String>.unmodifiable(
        await _recentAddressRepository.loadRecentAddresses(),
      );
    } catch (error) {
      _recordDiagnostic('connection.recent_addresses.load_failed', {
        'errorSummary': ExceptionRedactor.redactText(error.toString()),
      });
      return const <String>[];
    }
  }

  Future<void> _recordSuccessfulRecentAddress(String addressInput) async {
    try {
      await _recentAddressRepository.recordSuccessfulAddress(addressInput);
      _recentAddresses = List<String>.unmodifiable(
        await _recentAddressRepository.loadRecentAddresses(),
      );
      notifyListeners();
    } catch (error) {
      _recordDiagnostic('connection.recent_addresses.record_failed', {
        'errorSummary': ExceptionRedactor.redactText(error.toString()),
      });
    }
  }
```

- [ ] **Step 5: Update controller and default app dependencies**

Modify `mobile/lib/src/ui/features/connection/view_models/daemon_connection_controller.dart` imports:

```dart
import '../../../../data/repositories/recent_daemon_address_repository.dart';
import '../../../../domain/repositories/recent_daemon_address_repository.dart';
import '../../../../services/recent_daemon_address_store.dart';
```

Update constructor:

```dart
    RecentDaemonAddressRepository? recentAddressRepository,
    DiagnosticRecorder recordDiagnostic = noopDiagnosticRecorder,
```

Pass into `_fromRepo`:

```dart
          recentAddressRepository: recentAddressRepository ??
              StoreRecentDaemonAddressRepository(
                store: RecentDaemonAddressStore(),
              ),
          recordDiagnostic: recordDiagnostic,
```

Update `_fromRepo`:

```dart
    required RecentDaemonAddressRepository recentAddressRepository,
    DiagnosticRecorder recordDiagnostic = noopDiagnosticRecorder,
```

Pass into `super`:

```dart
          recentAddressRepository: recentAddressRepository,
          recordDiagnostic: recordDiagnostic,
```

Modify `mobile/lib/src/app/app_dependencies.dart` `FeatureDependencies.createDefault`:

```dart
        createDaemonConnectionViewModel: () => DaemonConnectionViewModel(
          configRepository: data.connectionConfigRepository,
          recentAddressRepository: data.recentAddressRepository,
          connectToDaemon: domain.connectionWorkflow,
        ),
```

- [ ] **Step 6: Run controller tests and format**

Run:

```powershell
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
dart format lib\src\ui\features\connection\view_models\daemon_connection_view_model.dart lib\src\ui\features\connection\view_models\daemon_connection_controller.dart lib\src\app\app_dependencies.dart test\daemon_connection_controller_test.dart
flutter test --no-pub test\daemon_connection_controller_test.dart -r expanded
```

Expected: all controller tests pass.

- [ ] **Step 7: Commit Task 2**

```powershell
git add mobile\lib\src\ui\features\connection\view_models\daemon_connection_view_model.dart mobile\lib\src\ui\features\connection\view_models\daemon_connection_controller.dart mobile\lib\src\app\app_dependencies.dart mobile\test\daemon_connection_controller_test.dart
git commit -m "Track recent daemon addresses in connection state"
```

## Task 3: Remove Unused Connection Header Control

**Files:**
- Modify: `mobile/lib/src/ui/mobile_connection_page.dart`
- Modify: `mobile/test/widget_test.dart`

- [ ] **Step 1: Add a failing header cleanup assertion**

Add to `app starts on editable connection page without bottom nav` in `mobile/test/widget_test.dart`:

```dart
    expect(find.byType(IconButton), findsNothing);
    expect(find.byType(PopupMenuButton<dynamic>), findsNothing);
```

This protects the header from replacing the fake control with another unusable action.

- [ ] **Step 2: Run the targeted widget test and verify it fails or inspect**

Run:

```powershell
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test --no-pub test\widget_test.dart -r expanded --plain-name "app starts on editable connection page without bottom nav"
```

Expected: the test may pass already because the current fake control is a `Container`, not an `IconButton`. If it passes, continue with implementation and rely on the visual removal plus snapshot assertions in the next step.

- [ ] **Step 3: Remove the decorative pill**

In `mobile/lib/src/ui/mobile_connection_page.dart`, replace `_ConnectionHeader.build` with:

```dart
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              color: theme.faint,
              fontSize: 12.5,
              height: 1.35,
              letterSpacing: .1,
            ),
          ),
        ],
      );
```

Delete the unused `_TinySignalDot` class.

- [ ] **Step 4: Run the targeted test**

Run:

```powershell
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
dart format lib\src\ui\mobile_connection_page.dart test\widget_test.dart
flutter test --no-pub test\widget_test.dart -r expanded --plain-name "app starts on editable connection page without bottom nav"
```

Expected: targeted widget test passes.

- [ ] **Step 5: Commit Task 3**

```powershell
git add mobile\lib\src\ui\mobile_connection_page.dart mobile\test\widget_test.dart
git commit -m "Remove unused connection header control"
```

## Task 4: Address Input Recent Dropdown

**Files:**
- Modify: `mobile/lib/src/ui/mobile_connection_page.dart`
- Modify: `mobile/test/widget_test.dart`

- [ ] **Step 1: Add widget tests for recent-address dropdown**

Add tests after the existing connection page tests in `mobile/test/widget_test.dart`:

```dart
  testWidgets('connection address field shows recent addresses on focus',
      (WidgetTester tester) async {
    final controller = DaemonConnectionController(
      store: DaemonConnectionConfigStore(),
      tokenStore: MemoryTokenStore(),
      recentAddressRepository: _WidgetRecentAddressRepository(
        addresses: const <String>[
          '192.168.1.20:4317',
          'http://desk.local:4317',
        ],
      ),
      snapshotLoader: (_) async => throw StateError('not used'),
      healthProbe: (_) async => throw StateError('not used'),
    );
    await controller.load();

    await tester.pumpWidget(_connectionPage(controller));

    await tester.tap(find.byType(TextField).first);
    await tester.pump();

    expect(find.text('192.168.1.20:4317'), findsOneWidget);
    expect(find.text('http://desk.local:4317'), findsOneWidget);
  });

  testWidgets('connection recent addresses filter and fill without connecting',
      (WidgetTester tester) async {
    final controller = DaemonConnectionController(
      store: DaemonConnectionConfigStore(),
      tokenStore: MemoryTokenStore(),
      recentAddressRepository: _WidgetRecentAddressRepository(
        addresses: const <String>[
          '192.168.1.20:4317',
          '10.0.0.5:4317',
        ],
      ),
      snapshotLoader: (_) async => throw StateError('not used'),
      healthProbe: (_) async => throw StateError('not used'),
    );
    await controller.load();

    await tester.pumpWidget(_connectionPage(controller));
    await tester.tap(find.byType(TextField).first);
    await tester.enterText(find.byType(TextField).first, '10.');
    await tester.pump();

    expect(find.text('10.0.0.5:4317'), findsOneWidget);
    expect(find.text('192.168.1.20:4317'), findsNothing);

    await tester.tap(find.text('10.0.0.5:4317'));
    await tester.pump();

    expect(controller.addressInput, '10.0.0.5:4317');
    expect(controller.status, DaemonConnectionStatus.idle);
    expect(find.text('10.0.0.5:4317'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus, isNotNull);
  });

  testWidgets('connection recent dropdown clamps long history',
      (WidgetTester tester) async {
    final controller = DaemonConnectionController(
      store: DaemonConnectionConfigStore(),
      tokenStore: MemoryTokenStore(),
      recentAddressRepository: _WidgetRecentAddressRepository(
        addresses: List<String>.generate(
          8,
          (index) => '192.168.1.${index + 1}:4317',
        ),
      ),
      snapshotLoader: (_) async => throw StateError('not used'),
      healthProbe: (_) async => throw StateError('not used'),
    );
    await controller.load();

    await tester.pumpWidget(_connectionPage(controller));
    await tester.tap(find.byType(TextField).first);
    await tester.pump();

    final dropdown = tester.widget<SizedBox>(
      find.byKey(const ValueKey('connection-recent-address-dropdown')),
    );
    expect(dropdown.height, lessThanOrEqualTo(184));
  });
```

Add helper near other test helpers:

```dart
Widget _connectionPage(DaemonConnectionController controller) {
  return MaterialApp(
    supportedLocales: appSupportedLocales,
    localizationsDelegates: appLocalizationsDelegates,
    localeResolutionCallback: (locale, supportedLocales) =>
        resolveSupportedLocale(locale, supportedLocales),
    theme: theme.buildAppTheme(),
    home: MobileConnectionPage(controller: controller),
  );
}

class _WidgetRecentAddressRepository implements RecentDaemonAddressRepository {
  _WidgetRecentAddressRepository({required this.addresses});

  final List<String> addresses;

  @override
  Future<List<String>> loadRecentAddresses() async =>
      List<String>.unmodifiable(addresses);

  @override
  Future<void> recordSuccessfulAddress(String addressInput) async {}
}
```

Add import:

```dart
import 'package:lan_ai_cli_control/src/domain/repositories/recent_daemon_address_repository.dart';
```

- [ ] **Step 2: Run dropdown tests and verify they fail**

Run:

```powershell
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test --no-pub test\widget_test.dart -r expanded --plain-name "connection recent"
```

Expected: fails because no dropdown exists.

- [ ] **Step 3: Add focus state to `MobileConnectionPage`**

Modify `_MobileConnectionPageState` fields:

```dart
  late final FocusNode _addressFocusNode;
  bool _recentDropdownOpen = false;
```

In `initState()`:

```dart
    _addressFocusNode = FocusNode();
    _addressFocusNode.addListener(_handleAddressFocusChanged);
```

In `dispose()` before controller disposal:

```dart
    _addressFocusNode.removeListener(_handleAddressFocusChanged);
    _addressFocusNode.dispose();
```

Add methods:

```dart
  void _handleAddressFocusChanged() {
    if (!mounted) return;
    setState(() => _recentDropdownOpen = _addressFocusNode.hasFocus);
  }

  List<String> _filteredRecentAddresses(DaemonConnectionViewModel controller) {
    if (!_recentDropdownOpen || controller.recentAddresses.isEmpty) {
      return const <String>[];
    }
    final query = _addressController.text.trim().toLowerCase();
    if (query.isEmpty) return controller.recentAddresses;
    return controller.recentAddresses
        .where((address) => address.toLowerCase().contains(query))
        .toList(growable: false);
  }

  void _selectRecentAddress(String address) {
    widget.controller.selectRecentAddress(address);
    _addressController.selection = TextSelection.collapsed(
      offset: _addressController.text.length,
    );
    _addressFocusNode.requestFocus();
    setState(() => _recentDropdownOpen = false);
  }

  void _closeRecentDropdown() {
    if (!_recentDropdownOpen) return;
    setState(() => _recentDropdownOpen = false);
  }
```

- [ ] **Step 4: Render dropdown and handle back/Escape**

Wrap the returned `Scaffold` in `PopScope`:

```dart
        return PopScope(
          canPop: !_recentDropdownOpen,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) _closeRecentDropdown();
          },
          child: Scaffold(
            body: MobileUiFrame(
```

Add `Shortcuts` and `Actions` inside `MobileUiFrame` or around the `ListView`:

```dart
            child: Shortcuts(
              shortcuts: const <ShortcutActivator, Intent>{
                SingleActivator(LogicalKeyboardKey.escape):
                    DismissIntent(),
              },
              child: Actions(
                actions: <Type, Action<Intent>>{
                  DismissIntent: CallbackAction<DismissIntent>(
                    onInvoke: (intent) {
                      _closeRecentDropdown();
                      return null;
                    },
                  ),
                },
                child: ListView(
```

Add import:

```dart
import 'package:flutter/services.dart';
```

Replace the address section child with:

```dart
                  child: Column(
                    children: [
                      _ConnectionTextField(
                        controller: _addressController,
                        focusNode: _addressFocusNode,
                        enabled: !controller.isBusy,
                        hintText: '127.0.0.1:4317',
                        onChanged: controller.setAddressInput,
                      ),
                      _RecentAddressDropdown(
                        addresses: _filteredRecentAddresses(controller),
                        enabled: !controller.isBusy,
                        onSelected: _selectRecentAddress,
                      ),
                    ],
                  ),
```

Update `_ConnectionTextField` to accept `FocusNode? focusNode` and pass it into `TextField`.

- [ ] **Step 5: Add the dropdown widget**

Add below `_ConnectionTextField`:

```dart
class _RecentAddressDropdown extends StatelessWidget {
  const _RecentAddressDropdown({
    required this.addresses,
    required this.enabled,
    required this.onSelected,
  });

  static const double _rowHeight = 42;
  static const double _maxHeight = _rowHeight * 4;

  final List<String> addresses;
  final bool enabled;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (addresses.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SizedBox(
        key: const ValueKey('connection-recent-address-dropdown'),
        height: addresses.length > 4 ? _maxHeight : addresses.length * _rowHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF0B0D10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: .07)),
          ),
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemExtent: _rowHeight,
            itemCount: addresses.length,
            itemBuilder: (context, index) {
              final address = addresses[index];
              return Semantics(
                label: address,
                button: true,
                child: InkWell(
                  onTap: enabled ? () => onSelected(address) : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.history_rounded,
                          color: theme.faint,
                          size: 15,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            address,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: theme.muted,
                              fontSize: 12.5,
                              fontFamily: 'Consolas',
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Run dropdown tests and format**

Run:

```powershell
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
dart format lib\src\ui\mobile_connection_page.dart test\widget_test.dart
flutter test --no-pub test\widget_test.dart -r expanded --plain-name "connection recent"
```

Expected: dropdown tests pass.

- [ ] **Step 7: Commit Task 4**

```powershell
git add mobile\lib\src\ui\mobile_connection_page.dart mobile\test\widget_test.dart
git commit -m "Show recent daemon addresses from input"
```

## Task 5: App Update Silent Check State and Diagnostics

**Files:**
- Modify: `mobile/lib/src/ui/features/settings/view_models/app_update_view_model.dart`
- Modify: `mobile/test/app_update_view_model_test.dart`

- [ ] **Step 1: Add failing AppUpdateViewModel tests**

Append tests before the final `mandatory gate` test in `mobile/test/app_update_view_model_test.dart`:

```dart
  test('silent update check records diagnostics without checking UI state',
      () async {
    final diagnostics = <String>[];
    final metadata = <Map<String, Object?>>[];
    final repository = _FakeRepository(_manifest(versionCode: 3));
    final installer = _FakeInstaller();
    final viewModel = AppUpdateViewModel(
      installedVersionCode: 1,
      installedVersionName: '1.0.0',
      workflow: _workflow(repository: repository, installer: installer),
      daemonBaseUri: Uri.parse('http://127.0.0.1:4317'),
      recordDiagnostic: (event, data) {
        diagnostics.add(event);
        metadata.add(data);
      },
    );
    addTearDown(viewModel.dispose);
    addTearDown(installer.close);

    await viewModel.checkForUpdates(
      trigger: AppUpdateCheckTrigger.connectedShellCreated,
    );

    expect(viewModel.state.status, AppUpdateStatus.available);
    expect(viewModel.state.promptSuppressed, false);
    expect(diagnostics, contains('update.silent_check.started'));
    expect(diagnostics, contains('update.silent_check.completed'));
    expect(metadata.last['remoteVersionCode'], 3);
  });

  test('silent update check failure keeps previous state', () async {
    final diagnostics = <String>[];
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
      recordDiagnostic: (event, data) => diagnostics.add(event),
    );
    addTearDown(viewModel.dispose);
    addTearDown(installer.close);

    await viewModel.checkForUpdates(
      trigger: AppUpdateCheckTrigger.appResumed,
    );

    expect(viewModel.state.status, AppUpdateStatus.idle);
    expect(diagnostics, contains('update.silent_check.failed'));
  });

  test('rapid silent checks do not start concurrent manifest requests',
      () async {
    final diagnostics = <String>[];
    final fetchCompleter = Completer<AppUpdateManifest>();
    final repository = _FakeRepository(_manifest())
      ..fetchCompleter = fetchCompleter;
    final installer = _FakeInstaller();
    final viewModel = AppUpdateViewModel(
      installedVersionCode: 1,
      installedVersionName: '1.0.0',
      workflow: _workflow(repository: repository, installer: installer),
      daemonBaseUri: Uri.parse('http://127.0.0.1:4317'),
      recordDiagnostic: (event, data) => diagnostics.add(event),
    );
    addTearDown(viewModel.dispose);
    addTearDown(installer.close);

    final first = viewModel.checkForUpdates(
      trigger: AppUpdateCheckTrigger.appResumed,
    );
    await pumpEventQueue();
    final second = viewModel.checkForUpdates(
      trigger: AppUpdateCheckTrigger.appResumed,
    );
    await pumpEventQueue();

    expect(repository.fetchCalls, 1);
    expect(diagnostics, contains('update.silent_check.skipped'));

    fetchCompleter.complete(_manifest());
    await Future.wait(<Future<void>>[first, second]);
  });

  test('postponed optional update suppresses prompt after silent check',
      () async {
    final diagnostics = <String>[];
    final repository = _FakeRepository(_manifest(versionCode: 5));
    final installer = _FakeInstaller();
    final viewModel = AppUpdateViewModel(
      installedVersionCode: 1,
      installedVersionName: '1.0.0',
      workflow: _workflow(repository: repository, installer: installer),
      daemonBaseUri: Uri.parse('http://127.0.0.1:4317'),
      recordDiagnostic: (event, data) => diagnostics.add(event),
    );
    addTearDown(viewModel.dispose);
    addTearDown(installer.close);

    await viewModel.checkForUpdates();
    viewModel.postponeCurrentUpdatePrompt();
    await viewModel.checkForUpdates(
      trigger: AppUpdateCheckTrigger.appResumed,
    );

    expect(viewModel.state.status, AppUpdateStatus.available);
    expect(viewModel.state.promptSuppressed, true);
    expect(diagnostics, contains('update.prompt.postponed'));
    expect(diagnostics, contains('update.prompt.suppressed'));
    expect(diagnostics, isNot(contains('update.silent_check.skipped')));
  });
```

- [ ] **Step 2: Run AppUpdateViewModel tests and verify failures**

Run:

```powershell
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test --no-pub test\app_update_view_model_test.dart -r expanded --plain-name "silent update"
```

Expected: fails because trigger enum, `promptSuppressed`, and `postponeCurrentUpdatePrompt` do not exist.

- [ ] **Step 3: Add trigger enum and prompt state**

In `app_update_view_model.dart`, add after `AppUpdateStatus`:

```dart
enum AppUpdateCheckTrigger {
  manual,
  connectedShellCreated,
  appResumed,
}

extension AppUpdateCheckTriggerDiagnostics on AppUpdateCheckTrigger {
  bool get isSilent => this != AppUpdateCheckTrigger.manual;

  String get diagnosticName => switch (this) {
        AppUpdateCheckTrigger.manual => 'manual',
        AppUpdateCheckTrigger.connectedShellCreated => 'connectedShellCreated',
        AppUpdateCheckTrigger.appResumed => 'appResumed',
      };
}
```

Add `promptSuppressed` to `AppUpdateState`:

```dart
    this.promptSuppressed = false,
```

```dart
  final bool promptSuppressed;
```

Add to `copyWith`:

```dart
    bool? promptSuppressed,
```

```dart
      promptSuppressed: promptSuppressed ?? this.promptSuppressed,
```

Add fields to `AppUpdateViewModel`:

```dart
  bool _checkInFlight = false;
  final Set<int> _postponedOptionalVersionCodes = <int>{};
```

- [ ] **Step 4: Replace `checkForUpdates` with trigger-aware implementation**

Replace `checkForUpdates()`:

```dart
  Future<void> checkForUpdates({
    AppUpdateCheckTrigger trigger = AppUpdateCheckTrigger.manual,
  }) async {
    final silent = trigger.isSilent;
    if (_checkInFlight) {
      _recordSilentCheckSkipped(trigger, 'checkInFlight');
      return;
    }
    if (_recoveringInstallSession || _isActiveOperation(state.status)) {
      _recordSilentCheckSkipped(trigger, 'activeOperation');
      return;
    }
    _checkInFlight = true;
    if (silent) {
      _recordDiagnostic('update.silent_check.started', {
        'trigger': trigger.diagnosticName,
      });
    } else {
      _recordDiagnostic('update.check.started', const <String, Object?>{});
      _set(state.copyWith(
        status: AppUpdateStatus.checking,
        promptSuppressed: false,
      ));
    }
    try {
      final manifest = await workflow.fetchLatest();
      if (!manifest.available || !manifest.isNewerThan(installedVersionCode)) {
        _set(
          state.copyWith(
            status: AppUpdateStatus.upToDate,
            manifest: manifest,
            mandatory: false,
            promptSuppressed: false,
          ),
        );
        _recordSilentCheckCompleted(trigger, manifest, false);
        return;
      }
      final mandatory = manifest.isMandatoryFor(installedVersionCode);
      final promptSuppressed = !mandatory &&
          _postponedOptionalVersionCodes.contains(manifest.versionCode);
      _set(
        state.copyWith(
          status: AppUpdateStatus.available,
          manifest: manifest,
          mandatory: mandatory,
          promptSuppressed: promptSuppressed,
        ),
      );
      _recordSilentCheckCompleted(trigger, manifest, mandatory);
      if (silent && promptSuppressed) {
        _recordDiagnostic('update.prompt.suppressed', {
          'versionCode': manifest.versionCode,
          'reason': 'postponedVersion',
        });
      }
    } catch (error) {
      if (silent) {
        _recordDiagnostic('update.silent_check.failed', {
          'trigger': trigger.diagnosticName,
          'errorSummary': '$error',
        });
        return;
      }
      _set(
        state.copyWith(status: AppUpdateStatus.failed, errorMessage: '$error'),
      );
    } finally {
      _checkInFlight = false;
    }
  }
```

Add helpers:

```dart
  void postponeCurrentUpdatePrompt() {
    final manifest = state.manifest;
    if (manifest == null || state.mandatory) return;
    _postponedOptionalVersionCodes.add(manifest.versionCode);
    _recordDiagnostic('update.prompt.postponed', {
      'versionCode': manifest.versionCode,
    });
    _set(state.copyWith(promptSuppressed: true));
  }

  void _recordSilentCheckSkipped(
    AppUpdateCheckTrigger trigger,
    String reason,
  ) {
    if (!trigger.isSilent) return;
    _recordDiagnostic('update.silent_check.skipped', {
      'trigger': trigger.diagnosticName,
      'reason': reason,
    });
  }

  void _recordSilentCheckCompleted(
    AppUpdateCheckTrigger trigger,
    AppUpdateManifest manifest,
    bool mandatory,
  ) {
    if (!trigger.isSilent) return;
    _recordDiagnostic('update.silent_check.completed', {
      'trigger': trigger.diagnosticName,
      'status': state.status.name,
      'remoteVersionCode': manifest.versionCode,
      'mandatory': mandatory,
    });
  }
```

- [ ] **Step 5: Run AppUpdateViewModel tests**

Run:

```powershell
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
dart format lib\src\ui\features\settings\view_models\app_update_view_model.dart test\app_update_view_model_test.dart
flutter test --no-pub test\app_update_view_model_test.dart -r expanded
```

Expected: all AppUpdateViewModel tests pass.

- [ ] **Step 6: Commit Task 5**

```powershell
git add mobile\lib\src\ui\features\settings\view_models\app_update_view_model.dart mobile\test\app_update_view_model_test.dart
git commit -m "Add silent app update checks"
```

## Task 6: Update Prompt Suppression and Shell Triggers

**Files:**
- Modify: `mobile/lib/src/ui/features/settings/widgets/app_update_panel.dart`
- Modify: `mobile/lib/src/ui/main_tabs_page.dart`
- Modify: `mobile/test/app_update_panel_test.dart`
- Modify: `mobile/test/widget_test.dart`

- [ ] **Step 1: Add panel prompt suppression tests**

Add to `mobile/test/app_update_panel_test.dart`:

```dart
  testWidgets('available update can suppress automatic prompt', (
    tester,
  ) async {
    var downloads = 0;
    const state = AppUpdateState(
      status: AppUpdateStatus.available,
      installedVersionName: '1.3.0',
      installedVersionCode: 1,
      manifest: availableManifest,
      promptSuppressed: true,
    );

    await pumpPanel(
      tester,
      state: state,
      onDownload: () => downloads++,
    );
    await tester.pump();

    expect(find.widgetWithText(TextButton, 'Download update'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Download'), findsOneWidget);
    expect(downloads, 0);
  });

  testWidgets('later action records postponed update', (tester) async {
    var postponeCalls = 0;
    const state = AppUpdateState(
      status: AppUpdateStatus.available,
      installedVersionName: '1.3.0',
      installedVersionCode: 1,
      manifest: availableManifest,
    );

    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
          body: AppUpdatePanel(
            state: state,
            onCheck: () {},
            onDownload: () {},
            onInstall: () {},
            onDiscard: () {},
            onPostpone: () => postponeCalls++,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(TextButton, 'Later'));
    await tester.pumpAndSettle();

    expect(postponeCalls, 1);
  });
```

- [ ] **Step 2: Update `AppUpdatePanel` callback contract**

Modify constructor and fields:

```dart
    required this.onPostpone,
```

```dart
  final VoidCallback onPostpone;
```

Update all call sites in `main_tabs_page.dart` to pass:

```dart
        onPostpone: viewModel.postponeCurrentUpdatePrompt,
```

For the null update panel:

```dart
        onPostpone: () {},
```

Update `_showUpdatePromptIfNeeded()`:

```dart
    if (!_shouldPromptForAvailableUpdate(state)) return;
```

Update `_shouldPromptForAvailableUpdate`:

```dart
bool _shouldPromptForAvailableUpdate(AppUpdateState state) {
  return !state.promptSuppressed &&
      state.status == AppUpdateStatus.available &&
      _hasNewerManifest(state);
}
```

Update the Later action:

```dart
              onPressed: () {
                widget.onPostpone();
                Navigator.of(context).pop();
              },
```

- [ ] **Step 3: Run panel tests**

Run:

```powershell
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
dart format lib\src\ui\features\settings\widgets\app_update_panel.dart test\app_update_panel_test.dart
flutter test --no-pub test\app_update_panel_test.dart -r expanded
```

Expected: all panel tests pass.

- [ ] **Step 4: Add shell lifecycle silent-check test**

Modify the existing `app update recovery runs on create and resume` test in `mobile/test/widget_test.dart`:

Change repository setup to a named fake:

```dart
    final repository = _WidgetAppUpdateRepository(manifest);
```

Pass it into `AppUpdateWorkflow`:

```dart
        repository: repository,
```

After initial pump assertions, add:

```dart
    expect(repository.fetchCalls, 1);
```

After resume assertions, add:

```dart
    expect(repository.fetchCalls, 2);
```

If recovery and check race in the test, use a helper:

```dart
    Future<void> pumpUntilFetchCalls(int expected) async {
      for (var attempt = 0;
          attempt < 20 && repository.fetchCalls < expected;
          attempt += 1) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
```

Call `await pumpUntilFetchCalls(1)` after create and `await pumpUntilFetchCalls(2)` after resume.

- [ ] **Step 5: Add shell silent-check orchestration**

Modify the settings import in `mobile/lib/src/ui/main_tabs_page.dart` to include `AppUpdateCheckTrigger`.

Replace `_recoverAppUpdateInstallSession()` with:

```dart
  void _handleAppUpdateForeground(AppUpdateCheckTrigger trigger) {
    if (!(widget.forceAndroidForTesting ?? Platform.isAndroid)) return;
    final viewModel = _appUpdateViewModel;
    if (viewModel == null) return;
    unawaited(_recoverThenCheckForUpdates(viewModel, trigger));
  }

  Future<void> _recoverThenCheckForUpdates(
    AppUpdateViewModel viewModel,
    AppUpdateCheckTrigger trigger,
  ) async {
    viewModel.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    if (!mounted || viewModel != _appUpdateViewModel) return;
    await viewModel.checkForUpdates(trigger: trigger);
  }
```

Update call after creating the ViewModel:

```dart
      _handleAppUpdateForeground(AppUpdateCheckTrigger.connectedShellCreated);
```

Update lifecycle resume:

```dart
      _handleAppUpdateForeground(AppUpdateCheckTrigger.appResumed);
```

- [ ] **Step 6: Run shell lifecycle test**

Run:

```powershell
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
dart format lib\src\ui\main_tabs_page.dart test\widget_test.dart
flutter test --no-pub test\widget_test.dart -r expanded --plain-name "app update recovery runs on create and resume"
```

Expected: the lifecycle test passes and verifies fetch calls.

- [ ] **Step 7: Commit Task 6**

```powershell
git add mobile\lib\src\ui\features\settings\widgets\app_update_panel.dart mobile\lib\src\ui\main_tabs_page.dart mobile\test\app_update_panel_test.dart mobile\test\widget_test.dart
git commit -m "Prompt for updates after foreground checks"
```

## Task 7: Final Architecture and Focused Verification

**Files:**
- Verify all changed Flutter files.

- [ ] **Step 1: Run architecture import check**

Run:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
dart run tool\check_architecture_imports.dart
```

Expected: no forbidden imports.

- [ ] **Step 2: Run Dart analyzer**

Run:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
dart analyze lib test
```

Expected: no issues found.

- [ ] **Step 3: Run focused Flutter tests**

Run:

```powershell
cd mobile
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter test --no-pub test\recent_daemon_address_repository_test.dart test\daemon_connection_config_store_test.dart test\daemon_connection_controller_test.dart test\app_update_view_model_test.dart test\app_update_panel_test.dart test\widget_test.dart -r expanded
```

Expected: all focused tests pass.

- [ ] **Step 4: Run Git whitespace check**

Run:

```powershell
git diff --check
```

Expected: no whitespace errors.

- [ ] **Step 5: Commit verification-only fixes if needed**

If formatting or analyzer fixes were needed, commit them:

```powershell
git add mobile
git commit -m "Stabilize connection history update prompt tests"
```

If no fixes were needed, do not create an empty commit.

## Plan Self-Review

Spec coverage:

- Address-only recent history: Tasks 1, 2, and 4.
- No header button: Task 3.
- Input dropdown, empty input, filtering, keyboard, max height, semantics: Task 4.
- Repository boundary instead of `DaemonConnectionConfigStore` growth: Task 1.
- ViewModel state and diagnostics: Task 2.
- Foreground update checks after create/resume: Tasks 5 and 6.
- Silent-check concurrency and diagnostics: Task 5.
- Prompt suppression and postpone event: Tasks 5 and 6.
- Tests alongside phases: each task has targeted tests before implementation.
- Architecture verification: Task 7.

Red-flag scan:

- No unfinished-marker text or unspecified test requirements are intentionally
  present.
- Every task has concrete files, commands, and expected outcomes.

Type consistency:

- `RecentDaemonAddressRepository.loadRecentAddresses()` and `recordSuccessfulAddress()` signatures match the spec.
- `DiagnosticRecorder` is non-null and defaults to `noopDiagnosticRecorder`.
- `AppUpdateCheckTrigger` names match diagnostic trigger strings.
- `AppUpdateState.promptSuppressed` is used by `AppUpdatePanel`.
