import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/app/app_localization.dart';
import 'package:lan_ai_cli_control/src/data/repositories/cli_adapter_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/command_catalog_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/adapter_repository.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/ui/core/theme/theme.dart' as theme;
import 'package:lan_ai_cli_control/src/ui/features/adapters/adapters.dart';

void main() {
  testWidgets('adapters page shows empty state and back action',
      (tester) async {
    var backed = false;
    final viewModel = await _viewModel();
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(_Harness(
      viewModel: viewModel,
      onBack: () => backed = true,
    ));

    expect(find.text('daemon returned no adapters'), findsOneWidget);
    expect(find.text('No extension information'), findsOneWidget);

    await tester.tap(find.text('Back'));
    expect(backed, isTrue);
  });

  testWidgets('adapters page shows populated and unavailable states',
      (tester) async {
    final viewModel = await _viewModel(
      adapters: const <AdapterStatus>[
        AdapterStatus(
          adapter: 'codex',
          available: true,
          status: 'available',
          version: '1.0.0',
        ),
        AdapterStatus(
          adapter: 'claude',
          available: false,
          status: 'missing binary',
          error: 'missing binary',
        ),
      ],
      extensions: const <ExtensionSummary>[
        ExtensionSummary(
          id: 'ext_1',
          name: 'GitHub',
          version: '1.0.0',
          description: 'Issue sync',
          installed: false,
          status: 'missing',
        ),
      ],
    );
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(_Harness(
      viewModel: viewModel,
    ));

    expect(find.text('codex'), findsOneWidget);
    expect(find.text('claude'), findsOneWidget);
    expect(find.text('Status OK'), findsOneWidget);
    expect(find.textContaining('missing binary'), findsOneWidget);
    expect(find.textContaining('Status OK\nmissing binary'), findsNothing);
    expect(find.text('GitHub'), findsOneWidget);
    expect(find.text('not installed'), findsOneWidget);
  });
}

class _Harness extends StatelessWidget {
  const _Harness({required this.viewModel, this.onBack});

  final AdaptersViewModel viewModel;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => MaterialApp(
        locale: const Locale('en', 'US'),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        theme: theme.buildAppTheme(),
        home: Scaffold(
          body: AdaptersPage(
            viewModel: viewModel,
            onBack: onBack ?? () {},
          ),
        ),
      );
}

Future<AdaptersViewModel> _viewModel({
  List<AdapterStatus> adapters = const <AdapterStatus>[],
  List<ExtensionSummary> extensions = const <ExtensionSummary>[],
}) async {
  final delegate = _FakeAdapterRepository(
    adapters: adapters,
    extensions: extensions,
  );
  final adapterRepository = CliAdapterRepository(delegate: delegate);
  final commandCatalogRepository = CommandCatalogRepository(delegate: delegate);
  adapterRepository.replaceFromBootstrap(adapters);
  await commandCatalogRepository.load();
  return AdaptersViewModel(
    adapterRepository: adapterRepository,
    commandCatalogRepository: commandCatalogRepository,
  );
}

class _FakeAdapterRepository implements AdapterRepository {
  const _FakeAdapterRepository({
    required this.adapters,
    required this.extensions,
  });

  final List<AdapterStatus> adapters;
  final List<ExtensionSummary> extensions;

  @override
  Future<List<AdapterStatus>> listAdapters() async => adapters;

  @override
  Future<List<ShortcutCommand>> listShortcuts() async =>
      const <ShortcutCommand>[];

  @override
  Future<List<CommandTemplate>> listCommandTemplates() async =>
      const <CommandTemplate>[];

  @override
  Future<List<ExtensionSummary>> listExtensions() async => extensions;
}
