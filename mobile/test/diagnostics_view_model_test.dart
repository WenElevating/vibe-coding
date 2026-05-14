import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/diagnostics_repository.dart';
import 'package:lan_ai_cli_control/src/models/protocol.dart';
import 'package:lan_ai_cli_control/src/ui/features/diagnostics/diagnostics.dart';

void main() {
  group('DiagnosticsViewModel', () {
    test('createBundle exports diagnostics through repository', () async {
      final repository = _FakeDiagnosticsRepository(
        bundle: DiagnosticBundleSummary(
          bundleId: 'diag_1',
          createdAt: DateTime.utc(2026, 5, 14),
          path: r'C:\temp\diag_1.zip',
          redacted: true,
          items: const <String>['system', 'logs'],
        ),
      );
      final viewModel = DiagnosticsViewModel(repository: repository);

      await viewModel.createBundle();

      expect(repository.exportCalls, 1);
      expect(viewModel.bundle?.bundleId, 'diag_1');
      expect(viewModel.bundle?.path, r'C:\temp\diag_1.zip');
      expect(viewModel.error, isNull);
      expect(viewModel.isLoading, isFalse);
    });

    test('createBundle exposes export failure', () async {
      final repository = _FakeDiagnosticsRepository(
        exportError: StateError('export failed'),
      );
      final viewModel = DiagnosticsViewModel(repository: repository);

      await viewModel.createBundle();

      expect(repository.exportCalls, 1);
      expect(viewModel.bundle, isNull);
      expect(viewModel.error, contains('export failed'));
      expect(viewModel.isLoading, isFalse);
    });

    test('duplicate createBundle calls while loading export once', () async {
      final completer = Completer<DiagnosticBundleSummary>();
      final repository = _FakeDiagnosticsRepository(completer: completer);
      final viewModel = DiagnosticsViewModel(repository: repository);

      final firstExport = viewModel.createBundle();
      await pumpEventQueue();

      final secondExport = viewModel.createBundle();

      expect(repository.exportCalls, 1);
      completer.complete(_diagnosticBundle('diag_1'));
      await firstExport;
      await secondExport;

      expect(viewModel.bundle?.bundleId, 'diag_1');
      expect(viewModel.isLoading, isFalse);
    });

    test('stale bundle is cleared when later export fails', () async {
      final repository = _FakeDiagnosticsRepository(
        bundle: _diagnosticBundle('diag_1'),
      );
      final viewModel = DiagnosticsViewModel(repository: repository);

      await viewModel.createBundle();
      expect(viewModel.bundle?.bundleId, 'diag_1');

      repository.bundle = null;
      repository.exportError = StateError('export failed');

      await viewModel.createBundle();

      expect(repository.exportCalls, 2);
      expect(viewModel.bundle, isNull);
      expect(viewModel.error, contains('export failed'));
      expect(viewModel.isLoading, isFalse);
    });

    test('disposing while export is in flight ignores completion', () async {
      final completer = Completer<DiagnosticBundleSummary>();
      final repository = _FakeDiagnosticsRepository(completer: completer);
      final viewModel = DiagnosticsViewModel(repository: repository);

      final export = viewModel.createBundle();
      await pumpEventQueue();

      viewModel.dispose();
      completer.complete(_diagnosticBundle('diag_1'));

      await expectLater(export, completes);
      expect(repository.exportCalls, 1);
    });
  });
}

DiagnosticBundleSummary _diagnosticBundle(String bundleId) {
  return DiagnosticBundleSummary(
    bundleId: bundleId,
    createdAt: DateTime.utc(2026, 5, 14),
    path: r'C:\temp\diag.zip',
    redacted: true,
    items: const <String>['system', 'logs'],
  );
}

class _FakeDiagnosticsRepository implements DiagnosticsRepository {
  _FakeDiagnosticsRepository({this.bundle, this.exportError, this.completer});

  DiagnosticBundleSummary? bundle;
  Object? exportError;
  Completer<DiagnosticBundleSummary>? completer;
  int exportCalls = 0;
  int recordExceptionCalls = 0;

  @override
  Future<DiagnosticBundleSummary> exportDiagnostics() async {
    exportCalls += 1;
    final delayedBundle = completer;
    if (delayedBundle != null) {
      completer = null;
      return delayedBundle.future;
    }
    final error = exportError;
    if (error != null) {
      throw error;
    }
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
  }) async {
    recordExceptionCalls += 1;
    return 'trace_1';
  }
}
