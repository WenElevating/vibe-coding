import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/data/repositories/cli_adapter_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/command_catalog_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/adapter_repository.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/ui/features/adapters/adapters.dart';

void main() {
  group('AdaptersViewModel', () {
    test('reads adapters and extensions from repositories', () async {
      final delegate = _FakeAdapterRepository();
      final adapterRepository = CliAdapterRepository(delegate: delegate);
      final commandCatalogRepository =
          CommandCatalogRepository(delegate: delegate);
      adapterRepository.replaceFromBootstrap(const <AdapterStatus>[
        _codexAdapter,
      ]);
      await commandCatalogRepository.load();

      final viewModel = AdaptersViewModel(
        adapterRepository: adapterRepository,
        commandCatalogRepository: commandCatalogRepository,
      );

      expect(viewModel.adapters, hasLength(1));
      expect(viewModel.adapters.single.adapter, 'codex');
      expect(viewModel.extensions, hasLength(1));
      expect(viewModel.extensions.single.id, 'github');
      expect(viewModel.loading, isFalse);
      expect(viewModel.error, isNull);
    });

    test('notifies when the adapter repository changes', () async {
      final delegate = _FakeAdapterRepository();
      final adapterRepository = CliAdapterRepository(delegate: delegate);
      final commandCatalogRepository =
          CommandCatalogRepository(delegate: delegate);
      await commandCatalogRepository.load();
      final viewModel = AdaptersViewModel(
        adapterRepository: adapterRepository,
        commandCatalogRepository: commandCatalogRepository,
      );
      var notifications = 0;
      viewModel.addListener(() => notifications++);

      adapterRepository.replaceFromBootstrap(const <AdapterStatus>[
        _codexAdapter,
      ]);

      expect(notifications, 1);
      expect(viewModel.adapters.single.adapter, 'codex');
    });

    test('loadCatalog populates extensions from an unloaded repository',
        () async {
      final delegate = _FakeAdapterRepository();
      final adapterRepository = CliAdapterRepository(delegate: delegate);
      final commandCatalogRepository =
          CommandCatalogRepository(delegate: delegate);
      final viewModel = AdaptersViewModel(
        adapterRepository: adapterRepository,
        commandCatalogRepository: commandCatalogRepository,
      );
      var notifications = 0;
      viewModel.addListener(() => notifications++);

      await viewModel.loadCatalog();

      expect(viewModel.extensions.single.id, 'github');
      expect(notifications, greaterThanOrEqualTo(1));
    });
  });
}

const _codexAdapter = AdapterStatus(
  adapter: 'codex',
  available: true,
  status: 'available',
);

const _githubExtension = ExtensionSummary(
  id: 'github',
  name: 'GitHub',
  version: '1.0.0',
  description: 'Issue sync',
  installed: true,
  status: 'installed',
);

class _FakeAdapterRepository implements AdapterRepository {
  @override
  Future<List<AdapterStatus>> listAdapters() async => const <AdapterStatus>[
        _codexAdapter,
      ];

  @override
  Future<List<ShortcutCommand>> listShortcuts() async =>
      const <ShortcutCommand>[];

  @override
  Future<List<CommandTemplate>> listCommandTemplates() async =>
      const <CommandTemplate>[];

  @override
  Future<List<ExtensionSummary>> listExtensions() async =>
      const <ExtensionSummary>[_githubExtension];
}
