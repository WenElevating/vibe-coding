# Mobile Review Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the reviewed mobile security, stability, architecture, rendering performance, and coverage issues in small test-first phases.

**Architecture:** Preserve the current Flutter layered architecture while repairing dependency direction: app/shell compose, workflows coordinate, data repositories map services/protocol data into domain contracts, UI consumes ViewModels/domain contracts, and domain remains pure. Phase 0 adds test seams first so later phases can write failing tests before behavior changes.

**Tech Stack:** Flutter/Dart, `flutter_test`, `http`, `archive`, existing repository/ViewModel patterns, `tool/check_architecture_imports.dart`.

---

## File Responsibility Map

- `mobile/lib/src/services/daemon_client.dart`: daemon HTTP lifecycle, timeout handling, exception reporting, parsing, and client closure.
- `mobile/lib/src/services/exception_redactor.dart`: new focused helper for irreversible client-side diagnostics redaction.
- `mobile/lib/src/services/asr_model_client.dart`: ASR model download request/cancellation behavior.
- `mobile/lib/src/services/asr_model_manager.dart`: safe archive validation/extraction and ASR model staging/promote flow.
- `mobile/lib/src/services/speech_input_service.dart`: speech recorder/recognizer lifecycle and injectable seams.
- `mobile/lib/src/domain/repositories/workspace_repository.dart`: domain-owned workspace repository and workspace creation contract.
- `mobile/lib/src/domain/models/daemon_initial_data.dart`: domain-owned initial data model.
- `mobile/lib/src/domain/models/dashboard_state.dart`: domain projection boundary for dashboard state.
- `mobile/lib/src/app/app_dependencies.dart`: composition root for connected dependencies and feature factories.
- `mobile/lib/src/ui/main_tabs_page.dart`: UI page consuming prebuilt page/feature dependencies without assembling data repositories.
- `mobile/lib/src/ui/features/connection/view_models/daemon_connection_view_model.dart`: connection state over workflow/domain abstractions.
- `mobile/lib/src/ui/features/workbench/coding_workbench_page.dart`: lazy conversation rendering and lifecycle guard.
- `mobile/lib/src/ui/features/workbench/workbench_event_cards.dart`: markdown/code/log rendering performance.
- `mobile/tool/check_architecture_imports.dart`: architecture boundary checker.
- `mobile/test/*`: focused tests for each phase.
- `docs/adr/`: durable record for protocol DTOs intentionally left after Phase 2.

## Phase 0 Verification Baseline

- [ ] **Step 1: Record baseline status**

Run:

```powershell
git status --short
```

Expected: note any existing changes before implementation. Do not overwrite unrelated work.

- [ ] **Step 2: Run current focused baseline tests**

Run:

```powershell
cd mobile
flutter test test\daemon_client_test.dart test\asr_model_client_test.dart test\asr_model_manager_test.dart test\speech_input_service_test.dart test\voice_input_controller_test.dart test\daemon_connection_workflow_test.dart test\daemon_connection_controller_test.dart -r expanded
```

Expected: PASS or record pre-existing failures before adding seams.

---

### Task 1: Test Seam Infrastructure

**Phase:** 0

**Owner:** implementation engineer/agent

**Files:**
- Modify: `mobile/lib/src/services/speech_input_service.dart`
- Modify: `mobile/lib/src/services/asr_model_client.dart`
- Modify: `mobile/lib/src/services/daemon_client.dart`
- Create: `mobile/test/support/fake_http.dart`
- Create: `mobile/test/support/fake_speech.dart`
- Test: `mobile/test/speech_input_service_test.dart`
- Test: `mobile/test/asr_model_client_test.dart`

- [ ] **Step 1: Add fake HTTP helpers for tests**

Create `mobile/test/support/fake_http.dart` with reusable `http.BaseClient` helpers:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class FakeHttpClient extends http.BaseClient {
  FakeHttpClient(this.handler);

  final FutureOr<http.StreamedResponse> Function(http.BaseRequest request)
      handler;

  final requests = <http.BaseRequest>[];
  var closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (closed) {
      throw StateError('FakeHttpClient is closed.');
    }
    requests.add(request);
    return handler(request);
  }

  @override
  void close() {
    closed = true;
    super.close();
  }
}

http.StreamedResponse jsonResponse(
  Object body, {
  int statusCode = 200,
  Map<String, String>? headers,
}) {
  final bytes = utf8.encode(jsonEncode(body));
  return http.StreamedResponse(
    Stream<List<int>>.value(bytes),
    statusCode,
    headers: {'content-type': 'application/json', ...?headers},
  );
}

http.StreamedResponse textResponse(
  String body, {
  int statusCode = 200,
  Map<String, String>? headers,
}) {
  return http.StreamedResponse(
    Stream<List<int>>.value(utf8.encode(body)),
    statusCode,
    headers: headers ?? const {},
  );
}
```

- [ ] **Step 2: Add fake speech helpers for tests**

Create `mobile/test/support/fake_speech.dart` with controllable fakes that mirror the seams added in Step 3:

```dart
import 'dart:async';

class FakeSpeechPermission {
  FakeSpeechPermission({this.granted = true});

  bool granted;

  Future<bool> request() async => granted;
}

class FakeSpeechRecorder {
  final controller = StreamController<List<int>>();
  var started = false;
  var stopped = false;
  var disposed = false;
  Object? startError;

  Stream<List<int>> startStream() {
    if (startError != null) throw startError!;
    started = true;
    return controller.stream;
  }

  Future<void> stop() async {
    stopped = true;
    await controller.close();
  }

  Future<void> dispose() async {
    disposed = true;
    if (!controller.isClosed) await controller.close();
  }
}

class FakeSpeechRecognizer {
  final partials = <String>[];
  var disposed = false;

  void acceptWaveform(List<int> bytes) {
    partials.add('partial ${bytes.length}');
  }

  String finalResult() => partials.join(' ');

  void dispose() {
    disposed = true;
  }
}
```

- [ ] **Step 3: Add injectable seams with production defaults**

Modify `SherpaSpeechInputService` constructor so production behavior remains unchanged while tests can inject permission, recorder, and recognizer factories. Use existing concrete implementations as defaults. Keep public `SpeechInputService` contract unchanged.

Implementation shape:

```dart
typedef SpeechPermissionRequest = Future<bool> Function();
typedef SpeechStreamFactory = Future<Stream<List<int>>> Function();
typedef SpeechRecognizerFactory = Object Function(String modelDirectory);
```

If concrete sherpa types make the exact typedef above awkward, keep the same idea but place the adapter types inside `speech_input_service.dart` and expose only the minimal methods used by `SherpaSpeechInputService`.

- [ ] **Step 4: Verify seam introduction does not change behavior**

Run:

```powershell
cd mobile
flutter test test\speech_input_service_test.dart test\asr_model_client_test.dart -r expanded
```

Expected: PASS. No new behavior assertions yet; this task only prepares seams.

- [ ] **Step 5: Rollback boundary**

If tests fail because seams changed production construction, revert only `speech_input_service.dart`, `asr_model_client.dart`, `daemon_client.dart`, and `mobile/test/support/*` from this task before starting Phase 1.

---

### Task 2: Architecture Guard Fixture Harness

**Phase:** 0

**Owner:** implementation engineer/agent

**Files:**
- Modify: `mobile/tool/check_architecture_imports.dart`
- Create: `mobile/test/architecture_imports_tool_test.dart`

- [ ] **Step 1: Make architecture checker callable from tests**

Refactor `mobile/tool/check_architecture_imports.dart` so its rule evaluation can run against an injected root directory while preserving CLI behavior.

Implementation shape:

```dart
Future<int> checkArchitectureImports({
  required Directory root,
  StringSink? out,
  StringSink? err,
}) async {
  // Move existing scan logic here.
  // Return 0 for pass and non-zero for violations.
}

Future<void> main(List<String> args) async {
  final exitCode = await checkArchitectureImports(
    root: Directory.current,
    out: stdout,
    err: stderr,
  );
  if (exitCode != 0) exit(exitCode);
}
```

- [ ] **Step 2: Add fixture test for one known violation**

Create `mobile/test/architecture_imports_tool_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/check_architecture_imports.dart' as checker;

void main() {
  test('domain cannot import workflows', () async {
    final temp = await Directory.systemTemp.createTemp('arch_check_');
    addTearDown(() async => temp.delete(recursive: true));

    final file = File(
      '${temp.path}/lib/src/domain/repositories/bad_repository.dart',
    );
    await file.create(recursive: true);
    await file.writeAsString(
      "import '../../workflows/workspace/create_workspace_workflow.dart';\n",
    );

    final output = StringBuffer();
    final exitCode = await checker.checkArchitectureImports(
      root: temp,
      err: output,
    );

    expect(exitCode, isNonZero);
    expect(output.toString(), contains('domain'));
    expect(output.toString(), contains('workflows'));
  });
}
```

- [ ] **Step 3: Run test and verify it passes with current rule**

Run:

```powershell
cd mobile
flutter test test\architecture_imports_tool_test.dart -r expanded
```

Expected: PASS.

- [ ] **Step 4: Verify CLI still works**

Run:

```powershell
cd mobile
dart run tool\check_architecture_imports.dart
```

Expected: PASS or same pre-existing architecture result as before refactor. No new violations should be introduced by making the checker testable.

---

### Task 3: Exception Redaction

**Phase:** 1

**Owner:** implementation engineer/agent

**Files:**
- Create: `mobile/lib/src/services/exception_redactor.dart`
- Modify: `mobile/lib/src/services/daemon_client.dart`
- Create: `mobile/test/exception_redactor_test.dart`
- Modify: `mobile/test/daemon_client_test.dart`

- [ ] **Step 1: Write redactor tests first**

Create `mobile/test/exception_redactor_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/services/exception_redactor.dart';

void main() {
  test('redacts bearer tokens and secret-like key values', () {
    final redacted = redactExceptionText(
      'Authorization: Bearer abc.def.ghi api_key=sk-live password: hunter2',
    );

    expect(redacted, isNot(contains('abc.def.ghi')));
    expect(redacted, isNot(contains('sk-live')));
    expect(redacted, isNot(contains('hunter2')));
    expect(redacted, contains('[REDACTED]'));
  });

  test('does not redact arbitrary UUIDs or hashes without secret-like keys', () {
    const uuid = '123e4567-e89b-12d3-a456-426614174000';
    const hash = '0123456789abcdef0123456789abcdef';

    final redacted = redactExceptionText('id=$uuid hash=$hash');

    expect(redacted, contains(uuid));
    expect(redacted, contains(hash));
  });

  test('strips URL query strings and redacts absolute paths', () {
    final redacted = redactExceptionText(
      r'C:\Users\W2830\secret\file.txt failed at '
      'https://example.test/path?token=abc&x=1',
    );

    expect(redacted, isNot(contains('W2830')));
    expect(redacted, isNot(contains('token=abc')));
    expect(redacted, contains('file.txt'));
    expect(redacted, contains('?<redacted>'));
  });

  test('caps exception payload sizes with centralized constants', () {
    final text = 'a' * (maxExceptionMessageChars + 100);
    final redacted = redactExceptionText(text, maxChars: maxExceptionMessageChars);

    expect(redacted.length, lessThanOrEqualTo(maxExceptionMessageChars));
    expect(redacted, endsWith('[truncated]'));
  });
}
```

- [ ] **Step 2: Run redactor tests and verify they fail**

Run:

```powershell
cd mobile
flutter test test\exception_redactor_test.dart -r expanded
```

Expected: FAIL because `exception_redactor.dart` does not exist.

- [ ] **Step 3: Implement redactor helper**

Create `mobile/lib/src/services/exception_redactor.dart`:

```dart
const maxExceptionMessageChars = 4096;
const maxExceptionStackChars = 16384;
const maxExceptionMetadataChars = 8192;
const maxExceptionMetadataEntries = 32;

final _bearerPattern = RegExp(
  r'(?i)(authorization\s*:\s*)?bearer\s+[^\s,;]+',
);
final _secretKeyPattern = RegExp(
  r'(?i)\b(api_key|apikey|access_token|refresh_token|password|secret|token)\b\s*[:=]\s*[^\s,;&]+',
);
final _urlQueryPattern = RegExp(r'(https?://[^\s?]+)\?[^\s]+');
final _windowsPathPattern = RegExp(
  r'\b[A-Za-z]:\\(?:[^\\\s]+\\)*([^\\\s]+)',
);
final _posixUserPathPattern = RegExp(r'/(Users|home)/[^/\s]+/(?:[^/\s]+/)*([^/\s]+)');

String redactExceptionText(String value, {int maxChars = maxExceptionMessageChars}) {
  var redacted = value
      .replaceAllMapped(_bearerPattern, (_) => 'Bearer [REDACTED]')
      .replaceAllMapped(_secretKeyPattern, (match) => '${match.group(1)}=[REDACTED]')
      .replaceAllMapped(_urlQueryPattern, (match) => '${match.group(1)}?<redacted>')
      .replaceAllMapped(_windowsPathPattern, (match) => r'<user-path>\' '${match.group(1)}')
      .replaceAllMapped(_posixUserPathPattern, (match) => '/<user-path>/${match.group(2)}');

  if (redacted.length > maxChars) {
    redacted = '${redacted.substring(0, maxChars - '[truncated]'.length)}[truncated]';
  }
  return redacted;
}

Map<String, Object?> redactExceptionMetadata(Map<String, Object?> metadata) {
  final redacted = <String, Object?>{};
  for (final entry in metadata.entries.take(maxExceptionMetadataEntries)) {
    final value = entry.value;
    redacted[entry.key] = value is String
        ? redactExceptionText(value, maxChars: maxExceptionMetadataChars)
        : value;
  }
  return redacted;
}
```

- [ ] **Step 4: Wire redaction into daemon exception upload**

In `mobile/lib/src/services/daemon_client.dart`, import `exception_redactor.dart` and apply it where exception `message`, `stack`, `path`, and metadata are serialized for `/api/exceptions`.

Implementation intent:

```dart
final redactedMessage = redactExceptionText(message);
final redactedStack = stack == null
    ? null
    : redactExceptionText(stack, maxChars: maxExceptionStackChars);
final redactedMetadata = redactExceptionMetadata(metadata ?? const {});
```

- [ ] **Step 5: Run focused tests**

Run:

```powershell
cd mobile
flutter test test\exception_redactor_test.dart test\daemon_client_test.dart -r expanded
```

Expected: PASS.

---

### Task 4: DaemonClient Lifecycle and Timeouts

**Phase:** 1

**Owner:** implementation engineer/agent

**Files:**
- Modify: `mobile/lib/src/services/daemon_client.dart`
- Modify: `mobile/lib/src/services/asr_model_client.dart`
- Modify: `mobile/lib/src/ui/features/connection/view_models/daemon_connection_view_model.dart`
- Modify: `mobile/lib/src/workflows/connection/daemon_connection_workflow.dart`
- Modify: `mobile/test/daemon_client_test.dart`
- Modify: `mobile/test/asr_model_client_test.dart`
- Modify: `mobile/test/daemon_connection_controller_test.dart`

- [ ] **Step 1: Inventory DaemonClient owners**

Run:

```powershell
rg -n "DaemonClient\(|DaemonClient\?|final DaemonClient|DaemonClient client|createAsrModelClient|forDaemonClient" mobile/lib mobile/test
```

Expected: produce a list of current owners/callers. Add the list to the implementation notes section at the bottom of this plan while executing, marking each as `migrated now` or `follow-up`.

- [ ] **Step 2: Add close idempotency test**

In `mobile/test/daemon_client_test.dart`, add:

```dart
test('close closes the underlying http client once and is idempotent', () {
  final httpClient = FakeHttpClient((request) => jsonResponse({}));
  final client = DaemonClient(baseUri: Uri.parse('http://127.0.0.1:3000'), httpClient: httpClient);

  client.close();
  client.close();

  expect(httpClient.closed, isTrue);
});
```

- [ ] **Step 3: Run close test and verify it fails**

Run:

```powershell
cd mobile
flutter test test\daemon_client_test.dart -r expanded --name "close closes"
```

Expected: FAIL because `DaemonClient.close()` is not implemented.

- [ ] **Step 4: Implement idempotent close and timeout constants**

In `daemon_client.dart`, add centralized constants and `close()`:

```dart
const daemonRequestTimeout = Duration(seconds: 10);
const asrDownloadInactivityTimeout = Duration(seconds: 30);

class DaemonClient {
  var _closed = false;

  void close() {
    if (_closed) return;
    _closed = true;
    _httpClient.close();
  }
}
```

Wrap outgoing requests through a helper:

```dart
Future<T> _withTimeout<T>(Future<T> future) =>
    future.timeout(daemonRequestTimeout);
```

Apply the helper to daemon HTTP request paths without changing endpoint payload behavior.

- [ ] **Step 5: Add stale connection test**

In `daemon_connection_controller_test.dart`, add a fake connect use case that completes after the ViewModel timeout. Assert the late client is closed or discarded and not exposed as connected state.

Test shape:

```dart
test('connection timeout closes abandoned late client', () async {
  final abandoned = FakeClosableDaemonClient();
  final completer = Completer<ConnectedAppSession<DaemonClient>>();
  final viewModel = DaemonConnectionViewModel(
    configRepository: fakeConfigRepository,
    connectToDaemon: FakeConnectUseCase(completer.future),
  );

  unawaited(viewModel.connect());
  await viewModel.debugCompleteConnectionTimeoutForTest();
  completer.complete(ConnectedAppSession(client: abandoned, initialData: fakeInitialData));
  await pumpEventQueue();

  expect(abandoned.closed, isTrue);
  expect(viewModel.client, isNull);
});
```

If the exact test seams do not exist, add a narrowly scoped `@visibleForTesting` timeout hook rather than sleeping in tests.

- [ ] **Step 6: Implement stale client cleanup**

When a connection attempt is superseded or times out, close any late client before dropping it. Keep successful current-attempt behavior unchanged.

- [ ] **Step 7: Run focused lifecycle tests**

Run:

```powershell
cd mobile
flutter test test\daemon_client_test.dart test\daemon_connection_controller_test.dart test\daemon_connection_workflow_test.dart -r expanded
```

Expected: PASS.

---

### Task 5: Safe ASR Archive Extraction

**Phase:** 1

**Owner:** implementation engineer/agent

**Files:**
- Modify: `mobile/lib/src/services/asr_model_manager.dart`
- Modify: `mobile/test/asr_model_manager_test.dart`

- [ ] **Step 1: Add malicious archive tests first**

In `mobile/test/asr_model_manager_test.dart`, add tests that create in-memory ZIP archives with path traversal and oversized content.

Test helper shape:

```dart
List<int> zipWithFile(String name, List<int> bytes) {
  final archive = Archive()..addFile(ArchiveFile(name, bytes.length, bytes));
  return ZipEncoder().encode(archive)!;
}
```

Add assertions:

```dart
test('rejects archive entries that escape staging directory', () async {
  final zip = zipWithFile('../escape.txt', utf8.encode('bad'));

  expect(
    () => manager.debugExtractArchiveForTest(zip),
    throwsA(isA<AsrModelException>()),
  );
});
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```powershell
cd mobile
flutter test test\asr_model_manager_test.dart -r expanded --name "archive"
```

Expected: FAIL because safe validation helper is not implemented.

- [ ] **Step 3: Implement safe extraction**

Replace the current direct archive extraction call, expected to look like `extractArchiveToDisk(ZipDecoder().decodeStream(input), paths.staging.path)`, with a private helper that validates before writing:

```dart
static const maxAsrArchiveFiles = 4096;
static const maxAsrArchiveUncompressedBytes = 2 * 1024 * 1024 * 1024;

Future<void> _extractArchiveSafely(Archive archive, Directory staging) async {
  var fileCount = 0;
  var totalBytes = 0;
  final stagingRoot = staging.resolveSymbolicLinksSync();

  for (final entry in archive.files) {
    if (!entry.isFile) continue;
    fileCount += 1;
    totalBytes += entry.size;
    if (fileCount > maxAsrArchiveFiles ||
        totalBytes > maxAsrArchiveUncompressedBytes) {
      throw AsrModelException('ASR model archive is too large.');
    }
    final name = entry.name.replaceAll('\\', '/');
    if (name.startsWith('/') || name.split('/').contains('..')) {
      throw AsrModelException('ASR model archive contains unsafe path.');
    }
    final target = File('${staging.path}/$name');
    await target.parent.create(recursive: true);
    final parent = target.parent.resolveSymbolicLinksSync();
    if (!parent.startsWith(stagingRoot)) {
      throw AsrModelException('ASR model archive escapes staging directory.');
    }
    await target.writeAsBytes(entry.content as List<int>, flush: true);
  }
}
```

Adjust exact content access to match `archive` package APIs used in the current project.

- [ ] **Step 4: Run ASR manager tests**

Run:

```powershell
cd mobile
flutter test test\asr_model_manager_test.dart -r expanded
```

Expected: PASS.

---

### Task 6: Speech Start Failure Cleanup

**Phase:** 1

**Owner:** implementation engineer/agent

**Files:**
- Modify: `mobile/lib/src/services/speech_input_service.dart`
- Modify: `mobile/test/speech_input_service_test.dart`
- Modify: `mobile/test/voice_input_controller_test.dart`

- [ ] **Step 1: Add failing lifecycle tests**

In `speech_input_service_test.dart`, add tests for start setup failure and cleanup:

```dart
test('start cleans up when recorder start fails', () async {
  final recorder = FakeSpeechRecorder()..startError = StateError('boom');
  final recognizer = FakeSpeechRecognizer();
  final service = SherpaSpeechInputService.forTest(
    permission: FakeSpeechPermission(granted: true),
    recorder: recorder,
    recognizer: recognizer,
  );

  await expectLater(service.start(), throwsStateError);

  expect(recorder.disposed || recorder.stopped, isTrue);
  expect(recognizer.disposed, isTrue);
});
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```powershell
cd mobile
flutter test test\speech_input_service_test.dart -r expanded --name "start cleans up"
```

Expected: FAIL because setup failure cleanup is not implemented.

- [ ] **Step 3: Implement cleanup semantics**

In `SpeechInputService.start()`, set `_started = true` only after stream subscription and recognizer setup succeed. Wrap setup in `try/catch`:

```dart
try {
  final stream = await _recorder.startStream();
  _subscription = stream.listen(_handleAudioBytes);
  _started = true;
} catch (_) {
  await cancel();
  rethrow;
}
```

- [ ] **Step 4: Run voice tests**

Run:

```powershell
cd mobile
flutter test test\speech_input_service_test.dart test\voice_input_controller_test.dart -r expanded
```

Expected: PASS.

---

### Task 7: Domain Boundary Repair

**Phase:** 2

**Owner:** implementation engineer/agent

**Files:**
- Modify: `mobile/lib/src/domain/repositories/workspace_repository.dart`
- Modify: `mobile/lib/src/workflows/workspace/create_workspace_workflow.dart`
- Modify: `mobile/lib/src/domain/models/daemon_initial_data.dart`
- Modify: `mobile/lib/src/shell/app_snapshot.dart`
- Modify: `mobile/test/create_workspace_workflow_test.dart`
- Modify: `mobile/test/app_snapshot_bootstrap_test.dart`
- Modify: `mobile/test/architecture_imports_tool_test.dart`

- [ ] **Step 1: Add architecture tests for workflow and shell imports**

Extend `architecture_imports_tool_test.dart` with fixtures proving `domain` cannot import `workflows` or `shell`.

```dart
test('domain cannot import shell', () async {
  final temp = await Directory.systemTemp.createTemp('arch_check_');
  addTearDown(() async => temp.delete(recursive: true));
  final file = File('${temp.path}/lib/src/domain/models/bad.dart');
  await file.create(recursive: true);
  await file.writeAsString("import '../../shell/app_snapshot.dart';\n");

  final output = StringBuffer();
  final exitCode = await checker.checkArchitectureImports(root: temp, err: output);

  expect(exitCode, isNonZero);
  expect(output.toString(), contains('shell'));
});
```

- [ ] **Step 2: Move workspace creation contract into domain**

In `workspace_repository.dart`, define the creation method/contract without importing workflow code:

```dart
abstract interface class WorkspaceCreationClient {
  Future<WorkspaceSummary> createWorkspace({
    required String path,
    required String name,
  });
}

abstract interface class WorkspaceRepository implements WorkspaceCreationClient {
  Future<List<WorkspaceSummary>> listWorkspaces();
}
```

Update `create_workspace_workflow.dart` to import the domain contract and remove the workflow-owned interface.

- [ ] **Step 3: Replace DaemonInitialData shell alias**

Change `daemon_initial_data.dart` to a domain-owned value. Include only fields actually consumed as initial app/domain data.

Implementation shape:

```dart
import '../../models/protocol.dart';

class DaemonInitialData {
  const DaemonInitialData({
    required this.health,
    required this.workspaces,
    required this.adapters,
  });

  final DaemonHealth health;
  final List<WorkspaceSummary> workspaces;
  final List<AdapterStatus> adapters;
}
```

If protocol DTOs remain temporarily, record that in the ADR created in Task 8.

- [ ] **Step 4: Add mapping at shell/app boundary**

In `app_snapshot.dart`, add a mapping extension or method:

```dart
extension AppSnapshotDaemonInitialData on AppSnapshot {
  DaemonInitialData toDaemonInitialData() => DaemonInitialData(
        health: health,
        workspaces: workspaces,
        adapters: adapters,
      );
}
```

- [ ] **Step 5: Run architecture and workflow tests**

Run:

```powershell
cd mobile
flutter test test\architecture_imports_tool_test.dart test\create_workspace_workflow_test.dart test\app_snapshot_bootstrap_test.dart -r expanded
dart run tool\check_architecture_imports.dart
```

Expected: PASS.

---

### Task 8: Protocol DTO Inventory ADR

**Phase:** 2

**Owner:** implementation engineer/agent

**Files:**
- Create: `docs/adr/2026-05-16-mobile-protocol-dto-boundary.md`
- Modify: `mobile/lib/src/domain/models/dashboard_state.dart`
- Modify: `mobile/test/protocol_compatibility_test.dart`

- [ ] **Step 1: Create ADR for remaining protocol DTOs**

Create `docs/adr/2026-05-16-mobile-protocol-dto-boundary.md`:

```markdown
# Mobile Protocol DTO Boundary

Date: 2026-05-16

## Status

Accepted for the mobile review remediation.

## Context

The mobile domain layer still references protocol DTOs in selected contracts while the app migrates toward domain-owned models.

## Decision

Protocol DTOs may remain temporarily only when replacing them would require a broad model migration unrelated to the current remediation. New domain behavior should use domain-owned projections.

## Current Temporary DTO Uses

- `DashboardState`: temporary protocol-backed projection until dashboard domain models are introduced.
- Repository contracts returning daemon protocol summaries: temporary compatibility surface while data repositories are migrated incrementally.

## Follow-Up

Replace temporary DTO uses with domain-owned models in a dedicated model migration after this remediation.
```

- [ ] **Step 2: Mark intentional temporary DTOs in code**

In `dashboard_state.dart`, add a short doc comment to the class explaining it is a temporary protocol-backed domain projection tracked by the ADR. Do not add broad inline comments elsewhere.

- [ ] **Step 3: Run protocol compatibility tests**

Run:

```powershell
cd mobile
flutter test test\protocol_compatibility_test.dart -r expanded
```

Expected: PASS.

---

### Task 9: UI Composition Boundary

**Phase:** 2

**Owner:** implementation engineer/agent

**Files:**
- Modify: `mobile/lib/src/app/app_dependencies.dart`
- Modify: `mobile/lib/src/ui/main_tabs_page.dart`
- Modify: `mobile/lib/src/ui/features/connection/view_models/daemon_connection_view_model.dart`
- Modify: `mobile/test/main_tabs_view_model_test.dart`
- Modify: `mobile/test/daemon_connection_controller_test.dart`
- Modify: `mobile/test/architecture_imports_tool_test.dart`

- [ ] **Step 1: Add architecture test for UI infrastructure leakage**

Add fixture tests asserting `ui` cannot import `services/daemon_client.dart` except allowlisted files. Include the current allowlist in the test name.

- [ ] **Step 2: Move connected dependency creation into AppDependencies**

In `app_dependencies.dart`, create a grouped page dependency factory:

```dart
class MainTabsDependencies {
  MainTabsDependencies({
    required this.connectedData,
    required this.workbenchDependencies,
  });

  final ConnectedDataDependencies connectedData;
  final WorkbenchDependencies workbenchDependencies;
}

MainTabsDependencies createMainTabsDependencies(DaemonClient client) {
  final connectedData = data.forDaemonClient(client);
  return MainTabsDependencies(
    connectedData: connectedData,
    workbenchDependencies: features.createWorkbenchDependencies(client),
  );
}
```

- [ ] **Step 3: Update MainTabsPage to consume grouped dependencies**

Change `MainTabsPage` so it receives `MainTabsDependencies` or a factory from `AppDependencies`, but does not call `data.forDaemonClient` directly. Prefer the `AppDependencies` factory as specified.

- [ ] **Step 4: Remove concrete data repository import from connection ViewModel**

Introduce or reuse a domain-facing config repository interface. Update `DaemonConnectionViewModel` constructor to depend on the abstraction while `AppDependencies` supplies the concrete implementation.

- [ ] **Step 5: Run focused architecture and connection tests**

Run:

```powershell
cd mobile
flutter test test\architecture_imports_tool_test.dart test\main_tabs_view_model_test.dart test\daemon_connection_controller_test.dart -r expanded
dart run tool\check_architecture_imports.dart
```

Expected: PASS.

---

### Task 10: Lazy Workbench Conversation Rendering

**Phase:** 3

**Owner:** implementation engineer/agent

**Files:**
- Modify: `mobile/lib/src/ui/features/workbench/coding_workbench_page.dart`
- Modify: `mobile/test/widget_test.dart`
- Modify: `mobile/test/coding_workbench_controller_test.dart`

- [ ] **Step 1: Add lazy rendering test first**

Add a widget test that builds a conversation with 500 synthetic messages and asserts an off-screen sentinel message is not found before scrolling.

Test shape:

```dart
testWidgets('workbench conversation lazily builds large message lists', (tester) async {
  final messages = List.generate(500, (index) => fakeConversationMessage(index));
  await tester.pumpWidget(buildWorkbenchWithMessages(messages));

  expect(find.text('message 0'), findsOneWidget);
  expect(find.text('message 499'), findsNothing);
});
```

Use existing test builders from `widget_test.dart` or `coding_workbench_controller_test.dart`; do not create a second app bootstrap helper if one already exists.

- [ ] **Step 2: Run test and verify failure**

Run:

```powershell
cd mobile
flutter test test\widget_test.dart -r expanded --name "lazily builds"
```

Expected: FAIL while the page still builds messages with an eager `ListView` children list.

- [ ] **Step 3: Replace eager list with lazy builder**

In `coding_workbench_page.dart`, replace message rendering from eager children to `ListView.builder` or `SliverList`.

Implementation shape:

```dart
ListView.builder(
  controller: _scrollController,
  itemCount: _messages.length,
  itemBuilder: (context, index) {
    final message = _messages[index];
    return KeyedSubtree(
      key: ValueKey(message.id ?? 'message-$index'),
      child: _buildMessageCard(message),
    );
  },
)
```

- [ ] **Step 4: Add mounted guard to post-frame scroll**

In `_scrollToBottom`, add:

```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  if (!mounted) return;
  if (!_scrollController.hasClients) return;
  // existing scroll logic
});
```

- [ ] **Step 5: Run focused workbench tests**

Run:

```powershell
cd mobile
flutter test test\widget_test.dart test\coding_workbench_controller_test.dart -r expanded --name "workbench|conversation|lazily builds"
```

Expected: PASS. If the `--name` pattern selects zero tests, rerun both files without `--name` and record that in final evidence.

---

### Task 11: Markdown and Large Output Rendering

**Phase:** 3

**Owner:** implementation engineer/agent

**Files:**
- Modify: `mobile/lib/src/ui/features/workbench/workbench_event_cards.dart`
- Modify: `mobile/lib/src/ui/features/workbench/conversation_reducer.dart`
- Modify: `mobile/test/conversation_reducer_test.dart`
- Modify: `mobile/test/widget_test.dart`

- [ ] **Step 1: Add markdown normalization regression test**

In `conversation_reducer_test.dart`, add a test that a 5,001-character assistant markdown message is normalized once into projection state or remains stable across unrelated reductions.

If normalization remains inside `AssistantMarkdownBody`, add a widget test around that widget and expose a test-only normalization counter.

- [ ] **Step 2: Implement preferred normalization location**

Prefer moving normalization into message projection/reducer output:

```dart
class WorkbenchMessageProjection {
  const WorkbenchMessageProjection({
    required this.rawMarkdown,
    required this.normalizedMarkdown,
  });

  final String rawMarkdown;
  final String normalizedMarkdown;
}
```

If that causes broad constructor churn, implement keyed memoization inside `AssistantMarkdownBody`:

```dart
class AssistantMarkdownBody extends StatefulWidget {
  const AssistantMarkdownBody({super.key, required this.markdown});

  final String markdown;

  @override
  State<AssistantMarkdownBody> createState() => _AssistantMarkdownBodyState();
}

class _AssistantMarkdownBodyState extends State<AssistantMarkdownBody> {
  String? _raw;
  String? _normalized;

  String get normalized {
    if (_raw != widget.markdown) {
      _raw = widget.markdown;
      _normalized = normalizeAssistantMarkdown(widget.markdown);
    }
    return _normalized!;
  }
}
```

- [ ] **Step 3: Add large output rendering test**

In `widget_test.dart`, add a test for a code/log block over 200 lines or 20,000 characters. Assert the initial render shows capped content and a clear affordance such as `Show more` or `Open full output`.

- [ ] **Step 4: Implement capped/chunked large output**

In `workbench_event_cards.dart`, define constants:

```dart
const largeOutputLineThreshold = 200;
const largeOutputCharThreshold = 20000;
const initialLargeOutputLines = 120;
```

Render normal content through the existing path. For large content, render the first chunk in a constrained container and provide an expansion/open-full-output action.

- [ ] **Step 5: Run rendering tests**

Run:

```powershell
cd mobile
flutter test test\conversation_reducer_test.dart test\widget_test.dart -r expanded --name "markdown|large output|workbench"
```

Expected: PASS or rerun full files if name filtering selects zero tests.

---

### Task 12: Architecture Guard Coverage Closeout

**Phase:** 4

**Owner:** implementation engineer/agent

**Files:**
- Modify: `mobile/test/architecture_imports_tool_test.dart`
- Modify: `mobile/tool/check_architecture_imports.dart`

- [ ] **Step 1: Add remaining fixture tests**

Extend `architecture_imports_tool_test.dart` with cases for:

```dart
test('production code cannot import src testing helpers', () async {
  final temp = await Directory.systemTemp.createTemp('arch_check_');
  addTearDown(() async => temp.delete(recursive: true));
  final file = File('${temp.path}/lib/src/ui/bad.dart');
  await file.create(recursive: true);
  await file.writeAsString("import '../testing/testing.dart';\n");

  final output = StringBuffer();
  final exitCode = await checker.checkArchitectureImports(root: temp, err: output);

  expect(exitCode, isNonZero);
  expect(output.toString(), contains('testing'));
});

test('domain cannot import services or ui', () async {
  final temp = await Directory.systemTemp.createTemp('arch_check_');
  addTearDown(() async => temp.delete(recursive: true));
  final file = File('${temp.path}/lib/src/domain/models/bad.dart');
  await file.create(recursive: true);
  await file.writeAsString("import '../../services/daemon_client.dart';\n");

  final output = StringBuffer();
  final exitCode = await checker.checkArchitectureImports(root: temp, err: output);

  expect(exitCode, isNonZero);
  expect(output.toString(), contains('services'));
});

test('ui daemon client imports require explicit allowlist', () async {
  final temp = await Directory.systemTemp.createTemp('arch_check_');
  addTearDown(() async => temp.delete(recursive: true));
  final file = File('${temp.path}/lib/src/ui/features/example/bad_page.dart');
  await file.create(recursive: true);
  await file.writeAsString("import '../../../services/daemon_client.dart';\n");

  final output = StringBuffer();
  final exitCode = await checker.checkArchitectureImports(root: temp, err: output);

  expect(exitCode, isNonZero);
  expect(output.toString(), contains('DaemonClient'));
});

test('windows style paths are normalized before rule matching', () async {
  final temp = await Directory.systemTemp.createTemp('arch_check_');
  addTearDown(() async => temp.delete(recursive: true));
  final file = File('${temp.path}/lib/src/domain/models/windows_bad.dart');
  await file.create(recursive: true);
  await file.writeAsString("import '../../shell/app_snapshot.dart';\n");

  final output = StringBuffer();
  final exitCode = await checker.checkArchitectureImports(root: temp, err: output);

  expect(exitCode, isNonZero);
  expect(output.toString().replaceAll('\\', '/'), contains('domain/models'));
});
```

- [ ] **Step 2: Update checker messages if needed**

If tests fail because messages are too vague, update `check_architecture_imports.dart` to include layer names and offending import path in each violation.

- [ ] **Step 3: Run architecture tests and checker**

Run:

```powershell
cd mobile
flutter test test\architecture_imports_tool_test.dart -r expanded
dart run tool\check_architecture_imports.dart
```

Expected: PASS.

---

### Task 13: Daemon Parsing Coverage Closeout

**Phase:** 4

**Owner:** implementation engineer/agent

**Files:**
- Modify: `mobile/lib/src/services/daemon_client.dart`
- Modify: `mobile/test/daemon_client_test.dart`

- [ ] **Step 1: Add table-driven parsing tests**

In `daemon_client_test.dart`, add success and malformed response cases for `listAdapters`, `listShortcuts`, `listCommandTemplates`, `listQueue`, `gitDiff`, `listRuns`, `fetchEvents`, and conversation APIs.

Test shape:

```dart
test('listRuns reports typed parse error for malformed runs payload', () async {
  final client = DaemonClient(
    baseUri: Uri.parse('http://127.0.0.1:3000'),
    httpClient: FakeHttpClient((request) => jsonResponse({'runs': 'bad'})),
  );

  await expectLater(
    client.listRuns(),
    throwsA(isA<DaemonClientException>()
        .having((error) => error.message, 'message', contains('runs'))),
  );
});
```

- [ ] **Step 2: Replace raw casts with typed parse helpers where tests fail**

Add small private helpers in `daemon_client.dart`:

```dart
List<Object?> _readList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is List) return value;
  throw DaemonClientException('Expected "$key" to be a list.');
}
```

Use helpers only where tests demonstrate raw cast failure risk.

- [ ] **Step 3: Run daemon client tests**

Run:

```powershell
cd mobile
flutter test test\daemon_client_test.dart -r expanded
```

Expected: PASS.

---

### Task 14: Page State Widget Coverage

**Phase:** 4

**Owner:** implementation engineer/agent

**Files:**
- Modify: `mobile/test/widget_test.dart`
- Create or modify: `mobile/test/adapters_page_test.dart`
- Create or modify: `mobile/test/runs_queue_pages_test.dart`
- Modify: `mobile/test/run_detail_page_test.dart`

- [ ] **Step 1: Add AdaptersPage widget tests**

Cover populated, empty, unavailable, and back action states. Use existing app/theme wrappers from `widget_test.dart`.

- [ ] **Step 2: Add RunsPage and QueuePage widget tests**

Cover empty states, populated rows, and detail/navigation callbacks.

- [ ] **Step 3: Add DiagnosticsPage state tests**

Cover loading, error, success bundle path, disabled loading action, and back action using a fake or seeded `DiagnosticsViewModel`.

- [ ] **Step 4: Run page tests**

Run:

```powershell
cd mobile
flutter test test\adapters_page_test.dart test\runs_queue_pages_test.dart test\run_detail_page_test.dart test\widget_test.dart -r expanded
```

Expected: PASS.

---

### Task 15: Notifier Coverage and Final Verification

**Phase:** 4

**Owner:** implementation engineer/agent

**Files:**
- Create or modify: `mobile/test/adapters_view_model_test.dart`
- Modify: `mobile/test/main_tabs_view_model_test.dart`
- Modify: `mobile/test/coding_workbench_controller_test.dart`

- [ ] **Step 1: Add notifier tests**

Add tests for `AdaptersViewModel` and `SessionListViewModel` update behavior, listener notification counts, and immutable exposed state.

Test shape:

```dart
test('notifies once when adapter state changes', () {
  final viewModel = AdaptersViewModel(repository: FakeAdapterRepository());
  var notifications = 0;
  viewModel.addListener(() => notifications++);

  viewModel.replaceAdapters([fakeAdapterStatus]);

  expect(notifications, 1);
  expect(() => viewModel.adapters.add(fakeAdapterStatus), throwsUnsupportedError);
});
```

- [ ] **Step 2: Verify no unresolved DaemonClient close owners remain undocumented**

Run:

```powershell
rg -n "DaemonClient\(|DaemonClient\?|final DaemonClient|DaemonClient client|forDaemonClient" mobile/lib
```

Expected: every owner is either migrated to close clients in this remediation or listed in the execution notes/follow-up issue.

- [ ] **Step 3: Run final mobile verification**

Run:

```powershell
cd mobile
dart run tool\check_architecture_imports.dart
flutter analyze
flutter test
```

Expected: all commands PASS. If any command times out, rerun the relevant narrower target and record the timeout as a verification gap.

- [ ] **Step 4: Final rollback boundary**

If final verification fails due to one phase, revert that phase's commits or file group rather than mixing fixes across unrelated phases. Keep independently verified earlier phases intact.

## Execution Notes To Fill While Implementing

### DaemonClient Owner Inventory

Record the `rg` output from Task 4 here during implementation. For each owner, mark `migrated now` or `follow-up`.

### Protocol DTO Leftovers

Record all protocol DTOs intentionally left after Phase 2 here and mirror durable leftovers in `docs/adr/2026-05-16-mobile-protocol-dto-boundary.md`.

### Verification Evidence

Record each phase's focused commands and final verification output here before completion.
