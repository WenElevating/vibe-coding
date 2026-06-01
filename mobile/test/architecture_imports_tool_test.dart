import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/check_architecture_imports.dart' as checker;

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('architecture-imports-test-');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('domain importing workflows is reported as forbidden', () async {
    File('${tempDir.path}${Platform.pathSeparator}pubspec.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync('name: architecture_imports_fixture\n');

    final repository = File(
      '${tempDir.path}${Platform.pathSeparator}'
      'lib${Platform.pathSeparator}'
      'src${Platform.pathSeparator}'
      'domain${Platform.pathSeparator}'
      'repositories${Platform.pathSeparator}'
      'bad_repository.dart',
    )..createSync(recursive: true);

    repository.writeAsStringSync('''
import '../../workflows/workspace/create_workspace_workflow.dart';

class BadRepository {}
''');

    final output = StringBuffer();

    final exitCode = await checker.checkArchitectureImports(
      root: tempDir,
      err: output,
    );

    expect(exitCode, isNonZero);
    expect(output.toString(), contains('domain'));
    expect(output.toString(), contains('workflows'));
  });

  test('domain importing data is reported as forbidden', () async {
    File('${tempDir.path}${Platform.pathSeparator}pubspec.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync('name: architecture_imports_fixture\n');

    final repository = File(
      '${tempDir.path}${Platform.pathSeparator}'
      'lib${Platform.pathSeparator}'
      'src${Platform.pathSeparator}'
      'domain${Platform.pathSeparator}'
      'repositories${Platform.pathSeparator}'
      'bad_repository.dart',
    )..createSync(recursive: true);

    repository.writeAsStringSync('''
import '../../data/models/app_update_models.dart';

class BadRepository {}
''');

    final output = StringBuffer();

    final exitCode = await checker.checkArchitectureImports(
      root: tempDir,
      err: output,
    );

    expect(exitCode, isNonZero);
    expect(output.toString(), contains('domain'));
    expect(output.toString(), contains('data'));
  });

  test('domain importing shell is reported as forbidden', () async {
    File('${tempDir.path}${Platform.pathSeparator}pubspec.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync('name: architecture_imports_fixture\n');

    final model = File(
      '${tempDir.path}${Platform.pathSeparator}'
      'lib${Platform.pathSeparator}'
      'src${Platform.pathSeparator}'
      'domain${Platform.pathSeparator}'
      'models${Platform.pathSeparator}'
      'bad_model.dart',
    )..createSync(recursive: true);

    model.writeAsStringSync('''
import '../../shell/app_snapshot.dart';

class BadModel {}
''');

    final output = StringBuffer();

    final exitCode = await checker.checkArchitectureImports(
      root: tempDir,
      err: output,
    );

    expect(exitCode, isNonZero);
    expect(output.toString(), contains('domain'));
    expect(output.toString(), contains('shell'));
  });

  test('production code cannot import src testing helpers', () async {
    File('${tempDir.path}${Platform.pathSeparator}pubspec.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync('name: architecture_imports_fixture\n');

    final file = File(
      '${tempDir.path}${Platform.pathSeparator}'
      'lib${Platform.pathSeparator}'
      'src${Platform.pathSeparator}'
      'ui${Platform.pathSeparator}'
      'bad.dart',
    )..createSync(recursive: true);

    file.writeAsStringSync("import '../testing/testing.dart';\n");

    final output = StringBuffer();
    final exitCode = await checker.checkArchitectureImports(
      root: tempDir,
      err: output,
    );

    expect(exitCode, isNonZero);
    expect(output.toString(), contains('testing'));
  });

  test('domain cannot import services or ui', () async {
    File('${tempDir.path}${Platform.pathSeparator}pubspec.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync('name: architecture_imports_fixture\n');

    final file = File(
      '${tempDir.path}${Platform.pathSeparator}'
      'lib${Platform.pathSeparator}'
      'src${Platform.pathSeparator}'
      'domain${Platform.pathSeparator}'
      'models${Platform.pathSeparator}'
      'bad.dart',
    )..createSync(recursive: true);

    file.writeAsStringSync('''
import '../../services/daemon_client.dart';
import '../../ui/main_page.dart';
''');

    final output = StringBuffer();
    final exitCode = await checker.checkArchitectureImports(
      root: tempDir,
      err: output,
    );

    expect(exitCode, isNonZero);
    expect(output.toString(), contains('services'));
    expect(output.toString(), contains('UI'));
  });

  test('ui daemon client imports are blocked outside allowlisted files',
      () async {
    File('${tempDir.path}${Platform.pathSeparator}pubspec.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync('name: architecture_imports_fixture\n');

    final view = File(
      '${tempDir.path}${Platform.pathSeparator}'
      'lib${Platform.pathSeparator}'
      'src${Platform.pathSeparator}'
      'ui${Platform.pathSeparator}'
      'features${Platform.pathSeparator}'
      'workbench${Platform.pathSeparator}'
      'bad_view.dart',
    )..createSync(recursive: true);

    view.writeAsStringSync('''
import '../../../services/daemon_client.dart';

class BadView {}
''');

    final output = StringBuffer();

    final exitCode = await checker.checkArchitectureImports(
      root: tempDir,
      err: output,
    );

    expect(exitCode, isNonZero);
    expect(output.toString(), contains('UI imports concrete DaemonClient'));
  });

  test('ui daemon client imports remain allowed for connection boundary',
      () async {
    File('${tempDir.path}${Platform.pathSeparator}pubspec.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync('name: architecture_imports_fixture\n');

    final viewModel = File(
      '${tempDir.path}${Platform.pathSeparator}'
      'lib${Platform.pathSeparator}'
      'src${Platform.pathSeparator}'
      'ui${Platform.pathSeparator}'
      'features${Platform.pathSeparator}'
      'connection${Platform.pathSeparator}'
      'view_models${Platform.pathSeparator}'
      'daemon_connection_view_model.dart',
    )..createSync(recursive: true);

    viewModel.writeAsStringSync('''
import '../../../../services/daemon_client.dart';

class DaemonConnectionViewModel {}
''');

    final output = StringBuffer();
    final errors = StringBuffer();

    final exitCode = await checker.checkArchitectureImports(
      root: tempDir,
      out: output,
      err: errors,
    );

    expect(exitCode, 0);
    expect(output.toString(), contains('Allowed UI DaemonClient'));
    expect(errors.toString(), isEmpty);
  });

  test('windows style paths are normalized before rule matching', () async {
    File('${tempDir.path}${Platform.pathSeparator}pubspec.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync('name: architecture_imports_fixture\n');

    final file = File(
      '${tempDir.path}${Platform.pathSeparator}'
      'lib${Platform.pathSeparator}'
      'src${Platform.pathSeparator}'
      'domain${Platform.pathSeparator}'
      'models${Platform.pathSeparator}'
      'windows_bad.dart',
    )..createSync(recursive: true);

    file.writeAsStringSync("import '../../shell/app_snapshot.dart';\n");

    final output = StringBuffer();
    final exitCode = await checker.checkArchitectureImports(
      root: tempDir,
      err: output,
    );

    expect(exitCode, isNonZero);
    expect(output.toString().replaceAll('\\', '/'), contains('domain/models'));
  });

  test('feature barrel exporting missing file is reported as forbidden',
      () async {
    File('${tempDir.path}${Platform.pathSeparator}pubspec.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync('name: architecture_imports_fixture\n');

    final barrel = File(
      '${tempDir.path}${Platform.pathSeparator}'
      'lib${Platform.pathSeparator}'
      'src${Platform.pathSeparator}'
      'ui${Platform.pathSeparator}'
      'features${Platform.pathSeparator}'
      'workbench${Platform.pathSeparator}'
      'workbench.dart',
    )..createSync(recursive: true);

    barrel.writeAsStringSync("export 'missing.dart';\n");

    final output = StringBuffer();
    final exitCode = await checker.checkArchitectureImports(
      root: tempDir,
      err: output,
    );

    expect(exitCode, isNonZero);
    expect(output.toString(), contains('barrel export target is missing'));
    expect(output.toString(), contains('workbench.dart'));
  });

  test('feature barrel exporting file without public declaration is reported',
      () async {
    File('${tempDir.path}${Platform.pathSeparator}pubspec.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync('name: architecture_imports_fixture\n');

    final featureDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}'
      'lib${Platform.pathSeparator}'
      'src${Platform.pathSeparator}'
      'ui${Platform.pathSeparator}'
      'features${Platform.pathSeparator}'
      'workbench',
    )..createSync(recursive: true);

    File('${featureDir.path}${Platform.pathSeparator}workbench.dart')
        .writeAsStringSync("export 'empty.dart';\n");
    File('${featureDir.path}${Platform.pathSeparator}empty.dart')
        .writeAsStringSync('class _PrivateOnly {}\n');

    final output = StringBuffer();
    final exitCode = await checker.checkArchitectureImports(
      root: tempDir,
      err: output,
    );

    expect(exitCode, isNonZero);
    expect(output.toString(),
        contains('barrel export target has no public declaration'));
    expect(output.toString(), contains('empty.dart'));
  });
}
