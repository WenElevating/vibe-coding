import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/app/app_localization.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/diagnostics_repository.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/ui/core/theme/theme.dart' as theme;
import 'package:lan_ai_cli_control/src/ui/features/diagnostics/diagnostics.dart';

void main() {
  testWidgets('diagnostics page disables duplicate generate while loading',
      (tester) async {
    final completer = Completer<DiagnosticBundleSummary>();
    final repository = _FakeDiagnosticsRepository(completer: completer);
    final viewModel = DiagnosticsViewModel(repository: repository);

    await tester.pumpWidget(_Harness(viewModel: viewModel));
    await tester.tap(find.text('Generate diagnostics bundle'));
    await tester.pump();
    await tester.tap(find.text('Generate diagnostics bundle'));

    expect(repository.exportCalls, 1);

    completer.complete(_bundle(path: r'C:\temp\diagnostics.zip'));
    await tester.pumpAndSettle();
    expect(find.text(r'C:\temp\diagnostics.zip'), findsOneWidget);
  });

  testWidgets('diagnostics page shows export errors and back action',
      (tester) async {
    var backed = false;
    final viewModel = DiagnosticsViewModel(
      repository: _FakeDiagnosticsRepository(
        exportError: StateError('export failed'),
      ),
    );

    await tester.pumpWidget(_Harness(
      viewModel: viewModel,
      onBack: () => backed = true,
    ));
    await tester.tap(find.text('Generate diagnostics bundle'));
    await tester.pumpAndSettle();

    expect(find.textContaining('export failed'), findsOneWidget);

    await tester.tap(find.text('Back'));
    expect(backed, isTrue);
  });

  testWidgets('diagnostics page shows success bundle path', (tester) async {
    final viewModel = DiagnosticsViewModel(
      repository: _FakeDiagnosticsRepository(
        bundle: _bundle(path: r'D:\diag\bundle.zip'),
      ),
    );

    await tester.pumpWidget(_Harness(viewModel: viewModel));
    await tester.tap(find.text('Generate diagnostics bundle'));
    await tester.pumpAndSettle();

    expect(find.text(r'D:\diag\bundle.zip'), findsOneWidget);
  });
}

class _Harness extends StatelessWidget {
  const _Harness({required this.viewModel, this.onBack});

  final DiagnosticsViewModel viewModel;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => MaterialApp(
        locale: const Locale('en', 'US'),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        theme: theme.buildAppTheme(),
        home: Scaffold(
          body: DiagnosticsPage(
            viewModel: viewModel,
            onBack: onBack ?? () {},
          ),
        ),
      );
}

DiagnosticBundleSummary _bundle({required String path}) =>
    DiagnosticBundleSummary(
      bundleId: 'diag_1',
      createdAt: DateTime.utc(2026, 5, 16),
      path: path,
      redacted: true,
      items: const <String>['system', 'logs'],
    );

class _FakeDiagnosticsRepository implements DiagnosticsRepository {
  _FakeDiagnosticsRepository({this.bundle, this.exportError, this.completer});

  final DiagnosticBundleSummary? bundle;
  final Object? exportError;
  Completer<DiagnosticBundleSummary>? completer;
  int exportCalls = 0;

  @override
  Future<DiagnosticBundleSummary> exportDiagnostics() async {
    exportCalls += 1;
    final pendingBundle = completer;
    if (pendingBundle != null) {
      completer = null;
      return pendingBundle.future;
    }
    final error = exportError;
    if (error != null) throw error;
    return bundle!;
  }

  @override
  Future<String> recordException({
    required String message,
    String? stack,
    String? path,
    String? method,
    String? conversationId,
    String? runId,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async =>
      'trace_1';
}
