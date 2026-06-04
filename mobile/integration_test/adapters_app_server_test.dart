import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lan_ai_cli_control/src/app/app_localization.dart';
import 'package:lan_ai_cli_control/src/data/repositories/cli_adapter_repository.dart';
import 'package:lan_ai_cli_control/src/data/repositories/command_catalog_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/adapter_repository.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/services/daemon_client.dart';
import 'package:lan_ai_cli_control/src/ui/core/theme/theme.dart' as theme;
import 'package:lan_ai_cli_control/src/ui/features/adapters/adapters.dart';
import 'package:lan_ai_cli_control/src/ui/features/workspace_picker/sheets/adapter_picker_sheet.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('adapters page renders default codex app-server listing',
      (tester) async {
    final delegate = _FakeAdapterRepository(
      adapters: <AdapterStatus>[
        AdapterStatus.fromJson(const <String, Object?>{
          'adapter': 'codex',
          'available': true,
          'status': 'available',
          'version': '0.136.0',
        }),
        AdapterStatus.fromJson(const <String, Object?>{
          'adapter': 'codex-app-server',
          'available': true,
          'status': 'available',
          'selectable': true,
          'transportHealthy': true,
          'unavailableReason': null,
          'capabilities': <String, Object?>{
            'waitingApproval': true,
            'resume': true,
            'approval': <String, Object?>{
              'mobileCallbacks': true,
              'scopes': <Object?>['once'],
              'supportsCancel': true,
              'denyBehaviors': <Object?>['interrupt'],
            },
          },
          'effectiveCapabilities': <String, Object?>{
            'mobileApprovalCallbacks': true,
          },
        }),
      ],
    );
    final adapterRepository = CliAdapterRepository(delegate: delegate);
    final commandCatalogRepository =
        CommandCatalogRepository(delegate: delegate);
    adapterRepository.replaceFromBootstrap(await delegate.listAdapters());
    await commandCatalogRepository.load();
    final viewModel = AdaptersViewModel(
      adapterRepository: adapterRepository,
      commandCatalogRepository: commandCatalogRepository,
    );
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(_Harness(viewModel: viewModel));
    await tester.pumpAndSettle();

    expect(find.text('codex'), findsOneWidget);
    expect(find.text('codex-app-server'), findsOneWidget);
    expect(find.text('Status OK'), findsNWidgets(2));
  });

  testWidgets('adapter picker selects codex app-server by adapter id',
      (tester) async {
    String? selected = 'codex';

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en', 'US'),
      supportedLocales: appSupportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
      theme: theme.buildAppTheme(),
      home: Scaffold(
        body: AdapterPickerSheet(
          adapters: <AdapterStatus>[
            AdapterStatus.fromJson(const <String, Object?>{
              'adapter': 'codex',
              'available': true,
              'status': 'available',
            }),
            AdapterStatus.fromJson(const <String, Object?>{
              'adapter': 'codex-app-server',
              'available': true,
              'status': 'available',
              'selectable': true,
            }),
          ],
          selected: selected,
          onSelected: (value) => selected = value,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('adapter-picker-sheet')), findsOneWidget);
    await tester.tap(find.text('codex-app-server'));
    await tester.pumpAndSettle();

    expect(selected, 'codex-app-server');
  });

  testWidgets('conversation create sends app-server id and preserves fallback',
      (tester) async {
    late Map<String, Object?> requestBody;
    final client = DaemonClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenStore: MemoryTokenStore(),
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/conversations');
        requestBody = jsonDecode(request.body) as Map<String, Object?>;
        return http.Response(
          jsonEncode(const <String, Object?>{
            'conversation': <String, Object?>{
              'id': 'conv_app_server',
              'workspaceId': 'workspace_1',
              'adapter': 'codex-app-server',
              'requestedAdapter': 'codex-app-server',
              'effectiveAdapter': 'codex',
              'status': 'idle',
              'capabilities': <String, Object?>{
                'waitingApproval': false,
                'resume': true,
              },
              'effectiveCapabilities': <String, Object?>{
                'mobileApprovalCallbacks': false,
              },
              'fallbackNotice': <String, Object?>{
                'noticeKind': 'adapter_fallback',
                'requestedAdapter': 'codex-app-server',
                'effectiveAdapter': 'codex',
                'reason': 'probe_not_run',
              },
              'createdAt': '2026-06-03T00:00:00.000Z',
              'updatedAt': '2026-06-03T00:00:01.000Z',
            },
          }),
          200,
        );
      }),
    );
    addTearDown(client.close);

    final conversation = await client.createConversation(
      workspaceId: 'workspace_1',
      adapter: 'codex-app-server',
      permissionMode: 'auto',
      model: ' gpt-5.4 ',
    );

    expect(requestBody, const <String, Object?>{
      'workspaceId': 'workspace_1',
      'adapter': 'codex-app-server',
      'permissionMode': 'auto',
      'model': 'gpt-5.4',
    });
    expect(conversation.adapter, 'codex-app-server');
    expect(conversation.requestedAdapter, 'codex-app-server');
    expect(conversation.effectiveAdapter, 'codex');
    expect(
        conversation.effectiveCapabilities['mobileApprovalCallbacks'], isFalse);
    expect(conversation.fallbackNotice['reason'], 'probe_not_run');
    expect(conversation.capabilities.resume, isTrue);
  });
}

class _Harness extends StatelessWidget {
  const _Harness({required this.viewModel});

  final AdaptersViewModel viewModel;

  @override
  Widget build(BuildContext context) => MaterialApp(
        locale: const Locale('en', 'US'),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        theme: theme.buildAppTheme(),
        home: Scaffold(
          body: AdaptersPage(
            viewModel: viewModel,
            onBack: () {},
          ),
        ),
      );
}

class _FakeAdapterRepository implements AdapterRepository {
  const _FakeAdapterRepository({
    required this.adapters,
  });

  final List<AdapterStatus> adapters;

  @override
  Future<List<AdapterStatus>> listAdapters() async => adapters;

  @override
  Future<List<ShortcutCommand>> listShortcuts() async =>
      const <ShortcutCommand>[];

  @override
  Future<List<CommandTemplate>> listCommandTemplates() async =>
      const <CommandTemplate>[];

  @override
  Future<List<ExtensionSummary>> listExtensions() async =>
      const <ExtensionSummary>[];
}
