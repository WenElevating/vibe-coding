import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/data/repositories/cli_adapter_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/command_catalog_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/adapter_repository.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';

void main() {
  test('adapter probe failure does not set catalog error', () async {
    final delegate = _FakeAdapterRepository()
      ..adapterError = StateError('adapter failed');
    final adapters = CliAdapterRepository(delegate: delegate);
    final catalog = CommandCatalogRepository(delegate: delegate);

    await expectLater(adapters.probe(), throwsA(isA<StateError>()));

    expect(adapters.error, isA<StateError>());
    expect(catalog.error, isNull);
  });

  test('catalog failure does not block loaded adapters', () async {
    final delegate = _FakeAdapterRepository()
      ..extensionError = StateError('extension failed');
    final adapters = CliAdapterRepository(delegate: delegate);
    final catalog = CommandCatalogRepository(delegate: delegate);

    await adapters.probe();
    await expectLater(catalog.load(), throwsA(isA<StateError>()));

    expect(
      adapters.adapters.map((adapter) => adapter.adapter),
      const <String>['codex'],
    );
    expect(adapters.error, isNull);
    expect(catalog.error, isA<StateError>());
  });

  test('bootstrap adapters are available without probing', () {
    final adapters = CliAdapterRepository(delegate: _FakeAdapterRepository());

    adapters.replaceFromBootstrap(const <AdapterStatus>[
      AdapterStatus(adapter: 'codex', available: true, status: 'available'),
    ]);

    expect(adapters.adapters.single.adapter, 'codex');
    expect(adapters.loading, isFalse);
    expect(adapters.error, isNull);
  });

  test('catalog load reuses a successful catalog until forced', () async {
    final delegate = _FakeAdapterRepository();
    final catalog = CommandCatalogRepository(delegate: delegate);

    await catalog.load();
    await catalog.load();

    expect(delegate.shortcutCalls, 1);
    expect(delegate.templateCalls, 1);
    expect(delegate.extensionCalls, 1);

    await catalog.load(force: true);

    expect(delegate.shortcutCalls, 2);
    expect(delegate.templateCalls, 2);
    expect(delegate.extensionCalls, 2);
  });
}

class _FakeAdapterRepository implements AdapterRepository {
  Object? adapterError;
  Object? shortcutError;
  Object? templateError;
  Object? extensionError;
  int shortcutCalls = 0;
  int templateCalls = 0;
  int extensionCalls = 0;

  @override
  Future<List<AdapterStatus>> listAdapters() async {
    final error = adapterError;
    if (error != null) throw error;
    return const <AdapterStatus>[
      AdapterStatus(adapter: 'codex', available: true, status: 'available'),
    ];
  }

  @override
  Future<List<ShortcutCommand>> listShortcuts() async {
    shortcutCalls++;
    final error = shortcutError;
    if (error != null) throw error;
    return const <ShortcutCommand>[
      ShortcutCommand(
        id: 'fix',
        label: 'Fix',
        prompt: 'Fix failing tests',
        tool: 'codex',
      ),
    ];
  }

  @override
  Future<List<CommandTemplate>> listCommandTemplates() async {
    templateCalls++;
    final error = templateError;
    if (error != null) throw error;
    return const <CommandTemplate>[
      CommandTemplate(
        id: 'review',
        label: 'Review',
        prompt: 'Review changes',
        requiresApproval: false,
      ),
    ];
  }

  @override
  Future<List<ExtensionSummary>> listExtensions() async {
    extensionCalls++;
    final error = extensionError;
    if (error != null) throw error;
    return const <ExtensionSummary>[
      ExtensionSummary(
        id: 'github',
        name: 'GitHub',
        version: '1.0.0',
        installed: true,
        status: 'installed',
        description: 'Issue sync',
      ),
    ];
  }
}
