import 'dart:io';

const migrationOnlyRoots = <String>[
  'src/features/',
  'src/widgets/',
  'src/theme/',
  'src/state/',
];

const productionTestingRoot = 'src/testing/';

const allowedMigrationDebt = <_AllowedDebt>[];

final importOrExportPattern = RegExp(
  r'''^\s*(import|export)\s+['"]([^'"]+)['"]''',
);

void main(List<String> args) {
  final mobileRoot = _findMobileRoot();
  final libRoot = Directory('${mobileRoot.path}${Platform.pathSeparator}lib');
  final dartFiles = libRoot
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final violations = <String>[];
  final migrationDebt = <String>[];
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

  stdout.writeln('Architecture import check');
  stdout.writeln('Migration-only import/export counts:');
  for (final root in migrationOnlyRoots) {
    stdout.writeln('  $root ${oldPathCounts[root]}');
  }
  if (migrationDebt.isNotEmpty) {
    stdout.writeln('Allowed migration debt:');
    for (final debt in migrationDebt) {
      stdout.writeln('  $debt');
    }
  }

  if (violations.isEmpty) {
    stdout.writeln('No forbidden imports found.');
    return;
  }

  stderr.writeln('Forbidden imports found:');
  for (final violation in violations) {
    stderr.writeln('  $violation');
  }
  exitCode = 1;
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

Directory _findMobileRoot() {
  var directory = Directory.current;
  while (true) {
    final pubspec =
        File('${directory.path}${Platform.pathSeparator}pubspec.yaml');
    final lib = Directory('${directory.path}${Platform.pathSeparator}lib');
    if (pubspec.existsSync() && lib.existsSync()) return directory;
    final parent = directory.parent;
    if (parent.path == directory.path) {
      stderr.writeln(
          'Could not find Flutter mobile root from ${Directory.current.path}.');
      exitCode = 1;
      exit(1);
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
  if (_targetsRoot(normalizedTarget, 'src/services/daemon_client.dart')) {
    return 'domain must not import concrete daemon client';
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
