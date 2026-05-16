import 'dart:io';

const migrationOnlyRoots = <String>[
  'src/features/',
  'src/widgets/',
  'src/theme/',
  'src/state/',
];

const productionTestingRoot = 'src/testing/';

const allowedUiDaemonClientBoundaryImports = <String>{
  'lib/src/ui/main_tabs_page.dart',
  'lib/src/ui/features/connection/view_models/daemon_connection_view_model.dart',
  'lib/src/ui/features/connection/view_models/daemon_connection_controller.dart',
};

const allowedMigrationDebt = <_AllowedDebt>[];

final importOrExportPattern = RegExp(
  r'''^\s*(import|export)\s+['"]([^'"]+)['"]''',
);

Future<void> main(List<String> args) async {
  final exitCode = await checkArchitectureImports(
    root: Directory.current,
    out: stdout,
    err: stderr,
  );
  if (exitCode != 0) exit(exitCode);
}

Future<int> checkArchitectureImports({
  required Directory root,
  StringSink? out,
  StringSink? err,
}) async {
  out ??= stdout;
  err ??= stderr;

  final mobileRoot = _findMobileRoot(root, err);
  if (mobileRoot == null) return 1;
  final libRoot = Directory('${mobileRoot.path}${Platform.pathSeparator}lib');
  final dartFiles = libRoot
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final violations = <String>[];
  final migrationDebt = <String>[];
  final allowedUiDaemonClientImports = <String>[];
  final forbiddenUiDaemonClientImports = <String>[];
  final oldPathCounts = <String, int>{
    for (final root in migrationOnlyRoots) root: 0,
  };

  for (final file in dartFiles) {
    final relativeFile = _relativeToMobile(mobileRoot, file);
    final source = file.readAsLinesSync();
    for (var lineIndex = 0; lineIndex < source.length; lineIndex++) {
      final line = source[lineIndex];
      final match = importOrExportPattern.firstMatch(line);
      if (match == null) continue;

      final uri = match.group(2)!;
      final normalizedTarget = _normalizeTarget(relativeFile, uri);
      for (final root in migrationOnlyRoots) {
        if (_targetsRoot(normalizedTarget, root)) {
          oldPathCounts[root] = oldPathCounts[root]! + 1;
        }
      }

      final lineNumber = lineIndex + 1;
      _checkDomainRule(
        relativeFile: relativeFile,
        uri: uri,
        normalizedTarget: normalizedTarget,
        lineNumber: lineNumber,
        violations: violations,
        migrationDebt: migrationDebt,
      );
      _checkUiCoreRule(
        relativeFile: relativeFile,
        uri: uri,
        normalizedTarget: normalizedTarget,
        lineNumber: lineNumber,
        violations: violations,
        migrationDebt: migrationDebt,
      );
      _checkServicesRule(
        relativeFile: relativeFile,
        uri: uri,
        normalizedTarget: normalizedTarget,
        lineNumber: lineNumber,
        violations: violations,
        migrationDebt: migrationDebt,
      );
      _checkUiDaemonClientRule(
        relativeFile: relativeFile,
        uri: uri,
        normalizedTarget: normalizedTarget,
        lineNumber: lineNumber,
        allowedUiDaemonClientImports: allowedUiDaemonClientImports,
        forbiddenUiDaemonClientImports: forbiddenUiDaemonClientImports,
      );
      _checkTestingRule(
        relativeFile: relativeFile,
        uri: uri,
        normalizedTarget: normalizedTarget,
        lineNumber: lineNumber,
        violations: violations,
        migrationDebt: migrationDebt,
      );
    }
  }

  out.writeln('Architecture import check');
  out.writeln('Migration-only import/export counts:');
  for (final root in migrationOnlyRoots) {
    out.writeln('  $root ${oldPathCounts[root]}');
  }
  if (migrationDebt.isNotEmpty) {
    out.writeln('Allowed migration debt:');
    for (final debt in migrationDebt) {
      out.writeln('  $debt');
    }
  }
  out.writeln('Allowed UI DaemonClient boundary imports:');
  if (allowedUiDaemonClientImports.isEmpty) {
    out.writeln('  none');
  } else {
    for (final debt in allowedUiDaemonClientImports) {
      out.writeln('  $debt');
    }
  }
  out.writeln('Forbidden UI DaemonClient imports:');
  if (forbiddenUiDaemonClientImports.isEmpty) {
    out.writeln('  none');
  } else {
    for (final debt in forbiddenUiDaemonClientImports) {
      out.writeln('  $debt');
    }
  }
  violations.addAll(forbiddenUiDaemonClientImports);

  if (violations.isEmpty) {
    out.writeln('No forbidden imports found.');
    return 0;
  }

  err.writeln('Forbidden imports found:');
  for (final violation in violations) {
    err.writeln('  $violation');
  }
  return 1;
}

final class _AllowedDebt {
  const _AllowedDebt({
    required this.relativeFile,
    required this.uri,
    required this.rule,
  });

  final String relativeFile;
  final String uri;
  final String rule;
}

Directory? _findMobileRoot(Directory root, StringSink err) {
  var directory = root.absolute;
  while (true) {
    final pubspec =
        File('${directory.path}${Platform.pathSeparator}pubspec.yaml');
    final lib = Directory('${directory.path}${Platform.pathSeparator}lib');
    if (pubspec.existsSync() && lib.existsSync()) return directory;
    final parent = directory.parent;
    if (parent.path == directory.path) {
      err.writeln('Could not find Flutter mobile root from ${root.path}.');
      return null;
    }
    directory = parent;
  }
}

String _relativeToMobile(Directory mobileRoot, File file) {
  final rootPath = _withTrailingSeparator(mobileRoot.absolute.path);
  final filePath = file.absolute.path;
  if (!filePath.startsWith(rootPath)) {
    return filePath.replaceAll('\\', '/');
  }
  return filePath.substring(rootPath.length).replaceAll('\\', '/');
}

String _withTrailingSeparator(String path) {
  if (path.endsWith(Platform.pathSeparator)) return path;
  return '$path${Platform.pathSeparator}';
}

String _normalizeTarget(String relativeFile, String uri) {
  if (uri.startsWith('package:lan_ai_cli_control/')) {
    final packagePath = uri.substring('package:lan_ai_cli_control/'.length);
    return packagePath.replaceAll('\\', '/');
  }
  if (uri.startsWith('package:') || uri.startsWith('dart:')) return uri;
  if (!uri.endsWith('.dart')) return uri;

  final fileDirectory = relativeFile.contains('/')
      ? relativeFile.substring(0, relativeFile.lastIndexOf('/'))
      : '';
  final segments = <String>[];
  for (final segment in '$fileDirectory/$uri'.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (segments.isNotEmpty) segments.removeLast();
      continue;
    }
    segments.add(segment);
  }
  return segments.join('/');
}

bool _targetsRoot(String normalizedTarget, String root) {
  final libRoot = 'lib/$root';
  return normalizedTarget.startsWith(libRoot) ||
      normalizedTarget.startsWith(root);
}

void _checkDomainRule({
  required String relativeFile,
  required String uri,
  required String normalizedTarget,
  required int lineNumber,
  required List<String> violations,
  required List<String> migrationDebt,
}) {
  if (!relativeFile.startsWith('lib/src/domain/')) return;
  final rule = _domainRule(uri, normalizedTarget);
  if (rule == null) return;
  _recordFinding(
    relativeFile: relativeFile,
    uri: uri,
    lineNumber: lineNumber,
    rule: rule,
    violations: violations,
    migrationDebt: migrationDebt,
  );
}

void _checkUiCoreRule({
  required String relativeFile,
  required String uri,
  required String normalizedTarget,
  required int lineNumber,
  required List<String> violations,
  required List<String> migrationDebt,
}) {
  if (!relativeFile.startsWith('lib/src/ui/core/')) return;
  final forbidden = _targetsRoot(normalizedTarget, 'src/ui/features/') ||
      _targetsRoot(normalizedTarget, 'src/features/');
  if (!forbidden) return;
  _recordFinding(
    relativeFile: relativeFile,
    uri: uri,
    lineNumber: lineNumber,
    rule: 'ui/core must not import feature code',
    violations: violations,
    migrationDebt: migrationDebt,
  );
}

void _checkServicesRule({
  required String relativeFile,
  required String uri,
  required String normalizedTarget,
  required int lineNumber,
  required List<String> violations,
  required List<String> migrationDebt,
}) {
  if (!relativeFile.startsWith('lib/src/services/')) return;
  if (!_targetsRoot(normalizedTarget, 'src/ui/')) return;
  _recordFinding(
    relativeFile: relativeFile,
    uri: uri,
    lineNumber: lineNumber,
    rule: 'services must not import UI',
    violations: violations,
    migrationDebt: migrationDebt,
  );
}

void _checkUiDaemonClientRule({
  required String relativeFile,
  required String uri,
  required String normalizedTarget,
  required int lineNumber,
  required List<String> allowedUiDaemonClientImports,
  required List<String> forbiddenUiDaemonClientImports,
}) {
  if (!relativeFile.startsWith('lib/src/ui/')) return;
  if (!_targetsRoot(normalizedTarget, 'src/services/daemon_client.dart')) {
    return;
  }
  final finding =
      '$relativeFile:$lineNumber UI imports concrete DaemonClient ($uri)';
  if (allowedUiDaemonClientBoundaryImports.contains(relativeFile)) {
    allowedUiDaemonClientImports.add(finding);
  } else {
    forbiddenUiDaemonClientImports.add(finding);
  }
}

void _checkTestingRule({
  required String relativeFile,
  required String uri,
  required String normalizedTarget,
  required int lineNumber,
  required List<String> violations,
  required List<String> migrationDebt,
}) {
  if (relativeFile.startsWith('lib/src/testing/')) return;
  if (!_targetsRoot(normalizedTarget, productionTestingRoot)) return;
  _recordFinding(
    relativeFile: relativeFile,
    uri: uri,
    lineNumber: lineNumber,
    rule: 'production code must not import src/testing',
    violations: violations,
    migrationDebt: migrationDebt,
  );
}

String? _domainRule(String uri, String normalizedTarget) {
  if (uri.startsWith('package:flutter/')) {
    return 'domain must not import Flutter';
  }
  if (uri.startsWith('package:http/')) return 'domain must not import HTTP';
  if (uri.startsWith('package:shared_preferences/')) {
    return 'domain must not import SharedPreferences';
  }
  if (_targetsRoot(normalizedTarget, 'src/ui/')) {
    return 'domain must not import UI';
  }
  if (_targetsRoot(normalizedTarget, 'src/services/')) {
    return 'domain must not import services';
  }
  if (_targetsRoot(normalizedTarget, 'src/workflows/')) {
    return 'domain must not import workflows';
  }
  if (_targetsRoot(normalizedTarget, 'src/shell/')) {
    return 'domain must not import shell';
  }
  return null;
}

void _recordFinding({
  required String relativeFile,
  required String uri,
  required int lineNumber,
  required String rule,
  required List<String> violations,
  required List<String> migrationDebt,
}) {
  final finding = '$relativeFile:$lineNumber $rule ($uri)';
  final allowed = allowedMigrationDebt.any(
    (debt) =>
        debt.relativeFile == relativeFile &&
        debt.uri == uri &&
        debt.rule == rule,
  );
  if (allowed) {
    migrationDebt.add(finding);
  } else {
    violations.add(finding);
  }
}
