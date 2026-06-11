# Slash Command Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an adapter-aware slash command menu above the mobile workbench composer, backed by a daemon command catalog endpoint.

**Architecture:** The daemon owns adapter slash command catalogs and exposes `GET /api/adapters/:adapterId/slash-commands`. Mobile adds a dedicated `SlashCommandCatalogRepository`, injects it through `WorkbenchDependencies`, and keeps composer slash detection, filtering, and insertion in `CodingWorkbenchPage`. `CodingComposer` stays presentational and renders an overlay-style compact command menu above the input.

**Tech Stack:** Node.js daemon HTTP server and CommonJS modules; Flutter/Dart mobile app with ChangeNotifier repositories, widget tests, and existing workbench theme primitives.

---

## Source Spec

Approved design: `docs/superpowers/specs/2026-05-31-slash-command-menu-design.md`

Implementation must preserve these hard requirements:

- Unknown adapter lookup returns `HTTP 200` with `commands: []`.
- Filtering is case-insensitive and uses command text only.
- `/Code-Review` and `/code-review` dedupe to one command key, `code-review`.
- Selecting a command replaces the active slash token at the cursor and adds a trailing space.
- The menu is an overlay above the composer and must not move the composer text field when result count changes.
- The repository uses per-adapter monotonically increasing integer generations for race-safe loads.
- Use a dedicated `SlashCommandCatalogRepository`, not `CommandCatalogRepository`.
- Existing shortcuts and command templates are out of v1.

## File Structure

Daemon:

- Create: `daemon/src/slash-command-catalog.js`
  - Owns static v1 adapter command lists and normalizes endpoint output to `{ command, description }`.
  - Returns empty arrays for unknown adapters.
- Modify: `daemon/src/server.js`
  - Adds `GET /api/adapters/:adapterId/slash-commands`.
- Modify: `daemon/src/main.js`
  - Constructs `SlashCommandCatalog` and passes it into `createServer`.
- Modify: `scripts/run-tests.js`
  - Adds daemon regression coverage for the new endpoint.

Mobile data:

- Modify: `mobile/lib/src/data/models/adapter_models.dart`
  - Adds `SlashCommand` model with `command`, `description`, `matchingKey`, and normalized `fromJson`.
- Modify: `mobile/lib/src/models/protocol.dart`
  - Existing barrel exports `adapter_models.dart`, so no new export is needed after adding the model there.
- Modify: `mobile/lib/src/services/daemon_client.dart`
  - Adds `listSlashCommands(String adapterId)` and list parsing.
- Add: `mobile/lib/src/data/repositories/slash_command_catalog_repository.dart`
  - Dedicated ChangeNotifier repository with per-adapter cache, future reuse, force reload, error preservation, and generation checks.

Mobile dependency wiring:

- Modify: `mobile/lib/src/app/app_dependencies.dart`
  - Constructs and passes `SlashCommandCatalogRepository`.
- Modify: `mobile/lib/src/app/connected_session_scope.dart`
  - Adds repository to connected scope only if needed by tests or future consumers.
- Modify: `mobile/lib/src/ui/features/workbench/workbench_dependencies.dart`
  - Adds required `SlashCommandCatalogRepository`.
- Modify: `mobile/test/widget_test.dart`
  - Updates test `WorkbenchDependencies` construction to include the repository.

Mobile UI:

- Modify: `mobile/lib/src/ui/features/workbench/coding_workbench_page.dart`
  - Owns slash token detection, adapter catalog loading, filtering, insertion, and visible menu state.
- Modify: `mobile/lib/src/ui/features/workbench/coding_composer.dart`
  - Adds compact slash menu rendering above the text field with stable row height.

Tests:

- Modify: `mobile/test/daemon_client_test.dart`
  - Covers client parsing for slash command list errors.
- Add: `mobile/test/slash_command_catalog_repository_test.dart`
  - Covers repository caching, force reload, error preservation, race handling, and dedupe normalization.
- Modify: `mobile/test/widget_test.dart`
  - Adds workbench slash menu widget tests.
- Existing verification:
  - `node scripts/run-tests.js`
  - `cd mobile && flutter test --no-pub test\daemon_client_test.dart -r expanded --plain-name "slash"`
  - `cd mobile && flutter test --no-pub test\slash_command_catalog_repository_test.dart -r expanded`
  - `cd mobile && flutter test --no-pub test\widget_test.dart -r expanded --plain-name "slash command"`
  - `cd mobile && dart analyze lib test`
  - `cd mobile && dart run tool\check_architecture_imports.dart`

---

### Task 1: Daemon Slash Command Catalog

**Files:**
- Create: `daemon/src/slash-command-catalog.js`
- Modify: `daemon/src/server.js`
- Modify: `daemon/src/main.js`
- Modify: `scripts/run-tests.js`

- [ ] **Step 1: Write daemon endpoint regression tests**

Add these tests near the existing API tests in `scripts/run-tests.js`, close to the adapter and command template coverage:

```js
test('slash command catalog returns adapter commands and unknown adapters as empty lists', async () => {
  const app = createApp({
    port: 0,
    devAdapters: true,
    appDbPath: tempConversationDbPath('app-db-slash-commands-')
  });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const port = app.server.address().port;
  try {
    const pairing = await request(port, 'POST', '/api/pairing-code', {});
    const paired = await request(port, 'POST', '/api/pair', {
      code: pairing.body.code,
      label: 'slash-command-test'
    });
    const token = paired.body.token;

    const codex = await request(port, 'GET', '/api/adapters/codex/slash-commands', null, token);
    assert.equal(codex.status, 200);
    assert.equal(codex.body.adapter, 'codex');
    assert.equal(Array.isArray(codex.body.commands), true);
    assert.equal(codex.body.commands.some((item) => item.command === '/model'), true);
    assert.equal(codex.body.commands.every((item) => typeof item.command === 'string' && item.command.startsWith('/')), true);
    assert.equal(codex.body.commands.every((item) => typeof item.description === 'string'), true);
    assert.equal(codex.body.commands.some((item) => Object.prototype.hasOwnProperty.call(item, 'source')), false);

    const claude = await request(port, 'GET', '/api/adapters/claude/slash-commands', null, token);
    assert.equal(claude.status, 200);
    assert.equal(claude.body.adapter, 'claude');
    assert.equal(claude.body.commands.some((item) => item.command === '/compact'), true);

    const opencode = await request(port, 'GET', '/api/adapters/opencode/slash-commands', null, token);
    assert.equal(opencode.status, 200);
    assert.equal(opencode.body.adapter, 'opencode');
    assert.equal(Array.isArray(opencode.body.commands), true);

    const unknown = await request(port, 'GET', '/api/adapters/not-real/slash-commands', null, token);
    assert.equal(unknown.status, 200);
    assert.deepEqual(unknown.body, { adapter: 'not-real', commands: [] });
  } finally {
    await new Promise((resolve) => app.server.close(resolve));
  }
});
```

- [ ] **Step 2: Run daemon test to verify it fails**

Run:

```powershell
node scripts/run-tests.js
```

Expected: FAIL at the new slash command catalog test with a 404 for `/api/adapters/codex/slash-commands` or with "not found".

- [ ] **Step 3: Add daemon catalog module**

Create `daemon/src/slash-command-catalog.js`:

```js
'use strict';

const catalogs = Object.freeze({
  claude: Object.freeze([
    command('/add-dir', 'add additional working directories'),
    command('/agents', 'manage specialized subagents'),
    command('/clear', 'clear conversation history'),
    command('/compact', 'compact conversation with optional instructions'),
    command('/cost', 'show token usage and cost'),
    command('/doctor', 'check Claude Code installation health'),
    command('/help', 'show help and available commands'),
    command('/ide', 'manage IDE integrations'),
    command('/init', 'create a CLAUDE.md project memory file'),
    command('/mcp', 'manage MCP server connections'),
    command('/memory', 'edit memory files'),
    command('/model', 'select model for the current session'),
    command('/permissions', 'review or update permission rules'),
    command('/pr_comments', 'view pull request comments'),
    command('/review', 'request a code review'),
    command('/status', 'show account and system status'),
    command('/terminal-setup', 'install terminal key binding support'),
    command('/vim', 'toggle vim mode')
  ]),
  codex: Object.freeze([
    command('/model', 'choose what model and reasoning effort to use'),
    command('/status', 'show current session configuration and account status'),
    command('/approvals', 'choose approval behavior for commands and edits'),
    command('/diff', 'review current code changes'),
    command('/compact', 'summarize the conversation to free context'),
    command('/new', 'start a new conversation'),
    command('/init', 'create project instructions for Codex'),
    command('/help', 'show help and available commands')
  ]),
  opencode: Object.freeze([
    command('/help', 'show help and available commands'),
    command('/model', 'select model for the current session'),
    command('/new', 'start a new session'),
    command('/share', 'share the current session'),
    command('/status', 'show current session status')
  ])
});

class SlashCommandCatalog {
  list(adapterId) {
    const id = normalizeAdapterId(adapterId);
    return {
      adapter: id,
      commands: Array.from(catalogs[id] || [])
    };
  }
}

function command(commandText, description) {
  return Object.freeze({ command: commandText, description });
}

function normalizeAdapterId(value) {
  return String(value || '').trim().toLowerCase();
}

module.exports = { SlashCommandCatalog };
```

- [ ] **Step 4: Wire the daemon endpoint**

Modify `daemon/src/server.js`:

```js
function createServer({ auth, workspaces, runs, conversations, adapterRegistry, diagnostics, diagnosticBundle, shortcuts, commandTemplates, slashCommandCatalog, gitService, workspaceInspector, runQueue, eventStore, config, version, asrModelAsset, appUpdates }) {
```

Add this route immediately after `/api/adapters`:

```js
      const slashCommands = url.pathname.match(/^\/api\/adapters\/([^/]+)\/slash-commands$/);
      if (method === 'GET' && slashCommands) return json(res, 200, slashCommandCatalog.list(decodeURIComponent(slashCommands[1])));
```

Modify `daemon/src/main.js`:

```js
const { SlashCommandCatalog } = require('./slash-command-catalog');
```

Construct it near `ShortcutStore` and `CommandTemplateStore`:

```js
  const slashCommandCatalog = new SlashCommandCatalog();
```

Pass it to `createServer`:

```js
  const server = createServer({ auth, workspaces, runs, conversations, adapterRegistry, diagnostics, diagnosticBundle, shortcuts, commandTemplates, slashCommandCatalog, gitService, workspaceInspector, runQueue, eventStore, config, version, asrModelAsset, appUpdates });
```

Include it in the object returned from `start` if `main.js` returns runtime components for tests:

```js
  return { server, auth, workspaces, eventStore, conversationEventStore, conversationSqliteStore, appSqliteStore, auditLog, adapterRegistry, shortcuts, commandTemplates, slashCommandCatalog, gitService, workspaceInspector, runQueue, migrationService, diagnostics, diagnosticBundle, runs, conversations, notificationHub, config, version, asrModelAsset, appUpdates, attachmentScratchCleanup };
```

- [ ] **Step 5: Run daemon test to verify it passes**

Run:

```powershell
node scripts/run-tests.js
```

Expected: PASS for the full daemon regression suite, including the new slash command catalog test.

- [ ] **Step 6: Commit daemon catalog**

```powershell
git add daemon/src/slash-command-catalog.js daemon/src/server.js daemon/src/main.js scripts/run-tests.js
git commit -m "Expose adapter slash command catalogs" -m "The mobile composer needs adapter-specific slash commands from the daemon so command inventories do not drift in the app." -m "Constraint: Unknown adapters return HTTP 200 with an empty commands array" -m "Confidence: high" -m "Scope-risk: narrow" -m "Tested: node scripts/run-tests.js"
```

---

### Task 2: Mobile Slash Command Model And Client

**Files:**
- Modify: `mobile/lib/src/data/models/adapter_models.dart`
- Modify: `mobile/lib/src/services/daemon_client.dart`
- Modify: `mobile/test/daemon_client_test.dart`

- [ ] **Step 1: Write failing mobile client tests**

In `mobile/test/daemon_client_test.dart`, add one happy-path test near other `DaemonClient` list endpoint tests:

```dart
test('listSlashCommands parses command catalog', () async {
  final requests = <http.BaseRequest>[];
  final client = DaemonClient(
    baseUri: Uri.parse('http://127.0.0.1:4317'),
    tokenStore: MemoryTokenStore(),
    httpClient: FakeHttpClient((request) {
      requests.add(request);
      return jsonResponse(const <String, Object?>{
        'adapter': 'codex',
        'commands': <Object?>[
          <String, Object?>{
            'command': '/Model',
            'description': 'choose model',
          },
          <String, Object?>{
            'command': 'compact',
            'description': 'compact context',
          },
        ],
      });
    }),
  );

  final commands = await client.listSlashCommands('codex');

  expect(requests.single.url.path, '/api/adapters/codex/slash-commands');
  expect(commands.map((command) => command.command), const <String>[
    '/Model',
    '/compact',
  ]);
  expect(commands.map((command) => command.matchingKey), const <String>[
    'model',
    'compact',
  ]);
  expect(commands.last.description, 'compact context');
});
```

Add a malformed-list case to the existing `list endpoints report typed parse errors for malformed lists` table:

```dart
(
  name: 'listSlashCommands',
  key: 'commands',
  body: const <String, Object?>{'commands': 'bad'},
  call: (client) => client.listSlashCommands('codex'),
),
```

- [ ] **Step 2: Run client tests to verify they fail**

Run:

```powershell
cd mobile
flutter test --no-pub test\daemon_client_test.dart -r expanded --plain-name "listSlashCommands"
```

Expected: FAIL with `The method 'listSlashCommands' isn't defined for the type 'DaemonClient'`.

- [ ] **Step 3: Add `SlashCommand` model**

Modify `mobile/lib/src/data/models/adapter_models.dart`, below `ExtensionSummary`:

```dart
class SlashCommand {
  const SlashCommand({
    required this.command,
    required this.description,
  });

  final String command;
  final String description;

  String get matchingKey => normalizedSlashCommandKey(command);

  factory SlashCommand.fromJson(Map<String, Object?> json) {
    return SlashCommand(
      command: normalizeSlashCommand(json['command'] as String? ?? ''),
      description: json['description'] as String? ?? '',
    );
  }
}

String normalizeSlashCommand(String value) {
  final trimmed = value.trim();
  final withoutLeadingSlash = trimmed.startsWith('/')
      ? trimmed.substring(1).trimLeft()
      : trimmed;
  return '/$withoutLeadingSlash';
}

String normalizedSlashCommandKey(String value) {
  final normalized = normalizeSlashCommand(value);
  return normalized.substring(1).toLowerCase();
}
```

- [ ] **Step 4: Add daemon client method**

Modify `mobile/lib/src/services/daemon_client.dart`, near `listCommandTemplates()`:

```dart
Future<List<SlashCommand>> listSlashCommands(String adapterId) async {
  final encoded = Uri.encodeComponent(adapterId.trim().toLowerCase());
  final response = await _get('/api/adapters/$encoded/slash-commands');
  final items = _readMapList(response, 'commands');
  return items.map(SlashCommand.fromJson).toList();
}
```

- [ ] **Step 5: Run client tests to verify they pass**

Run:

```powershell
cd mobile
flutter test --no-pub test\daemon_client_test.dart -r expanded --plain-name "listSlashCommands"
flutter test --no-pub test\daemon_client_test.dart -r expanded --plain-name "list endpoints report typed parse errors"
```

Expected: PASS for both test selections.

- [ ] **Step 6: Commit mobile client model**

```powershell
git add mobile/lib/src/data/models/adapter_models.dart mobile/lib/src/services/daemon_client.dart mobile/test/daemon_client_test.dart
git commit -m "Parse daemon slash command catalogs" -m "The mobile app needs a typed slash command model before repositories and composer UI can consume adapter command catalogs." -m "Constraint: Matching keys are lowercase command text without the leading slash" -m "Confidence: high" -m "Scope-risk: narrow" -m "Tested: cd mobile && flutter test --no-pub test\\daemon_client_test.dart -r expanded --plain-name \"listSlashCommands\""
```

---

### Task 3: Mobile Slash Command Repository

**Files:**
- Add: `mobile/lib/src/data/repositories/slash_command_catalog_repository.dart`
- Add: `mobile/test/slash_command_catalog_repository_test.dart`

- [ ] **Step 1: Write failing repository tests**

Create `mobile/test/slash_command_catalog_repository_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/data/models/adapter_models.dart';
import 'package:lan_ai_cli_control/src/data/repositories/slash_command_catalog_repository.dart';

void main() {
  test('loads each adapter once and returns cached commands', () async {
    final delegate = _FakeSlashCommandClient()
      ..responses['codex'] = const <SlashCommand>[
        SlashCommand(command: '/model', description: 'choose model'),
      ];
    final repository = SlashCommandCatalogRepository(client: delegate.load);

    final first = await repository.loadForAdapter('codex');
    final second = await repository.loadForAdapter('codex');

    expect(first.single.command, '/model');
    expect(second.single.command, '/model');
    expect(delegate.calls, const <String>['codex']);
    expect(repository.commandsForAdapter('codex').single.matchingKey, 'model');
  });

  test('force reload increments generation and updates cache', () async {
    final delegate = _FakeSlashCommandClient()
      ..responses['codex'] = const <SlashCommand>[
        SlashCommand(command: '/model', description: 'choose model'),
      ];
    final repository = SlashCommandCatalogRepository(client: delegate.load);

    await repository.loadForAdapter('codex');
    delegate.responses['codex'] = const <SlashCommand>[
      SlashCommand(command: '/status', description: 'show status'),
    ];
    await repository.loadForAdapter('codex', force: true);

    expect(
      repository.commandsForAdapter('codex').map((item) => item.command),
      const <String>['/status'],
    );
    expect(delegate.calls, const <String>['codex', 'codex']);
  });

  test('deduplicates commands by normalized key and keeps first item', () async {
    final delegate = _FakeSlashCommandClient()
      ..responses['codex'] = const <SlashCommand>[
        SlashCommand(command: '/Code-Review', description: 'first'),
        SlashCommand(command: '/code-review', description: 'second'),
        SlashCommand(command: 'compact', description: 'compact'),
      ];
    final repository = SlashCommandCatalogRepository(client: delegate.load);

    await repository.loadForAdapter('codex');

    final commands = repository.commandsForAdapter('codex');
    expect(commands.map((item) => item.command), const <String>[
      '/Code-Review',
      '/compact',
    ]);
    expect(commands.first.description, 'first');
  });

  test('late response for older generation does not overwrite newer cache',
      () async {
    final first = Completer<List<SlashCommand>>();
    final second = Completer<List<SlashCommand>>();
    var call = 0;
    final repository = SlashCommandCatalogRepository(
      client: (adapter) {
        call += 1;
        return call == 1 ? first.future : second.future;
      },
    );

    final firstLoad = repository.loadForAdapter('codex', force: true);
    final secondLoad = repository.loadForAdapter('codex', force: true);
    second.complete(const <SlashCommand>[
      SlashCommand(command: '/new', description: 'new result'),
    ]);
    await secondLoad;
    first.complete(const <SlashCommand>[
      SlashCommand(command: '/old', description: 'old result'),
    ]);
    await firstLoad;

    expect(
      repository.commandsForAdapter('codex').map((item) => item.command),
      const <String>['/new'],
    );
  });

  test('load failure records error and preserves existing cache', () async {
    final delegate = _FakeSlashCommandClient()
      ..responses['codex'] = const <SlashCommand>[
        SlashCommand(command: '/model', description: 'choose model'),
      ];
    final repository = SlashCommandCatalogRepository(client: delegate.load);
    await repository.loadForAdapter('codex');

    delegate.error = StateError('network failed');

    await expectLater(
      repository.loadForAdapter('codex', force: true),
      throwsA(isA<StateError>()),
    );
    expect(repository.errorForAdapter('codex'), isA<StateError>());
    expect(repository.commandsForAdapter('codex').single.command, '/model');
  });
}

class _FakeSlashCommandClient {
  final Map<String, List<SlashCommand>> responses =
      <String, List<SlashCommand>>{};
  final List<String> calls = <String>[];
  Object? error;

  Future<List<SlashCommand>> load(String adapter) async {
    calls.add(adapter);
    final currentError = error;
    if (currentError != null) throw currentError;
    return responses[adapter] ?? const <SlashCommand>[];
  }
}
```

- [ ] **Step 2: Run repository tests to verify they fail**

Run:

```powershell
cd mobile
flutter test --no-pub test\slash_command_catalog_repository_test.dart -r expanded
```

Expected: FAIL because `slash_command_catalog_repository.dart` does not exist.

- [ ] **Step 3: Implement repository**

Create `mobile/lib/src/data/repositories/slash_command_catalog_repository.dart`:

```dart
import 'package:flutter/foundation.dart';

import '../models/adapter_models.dart';

typedef SlashCommandLoader = Future<List<SlashCommand>> Function(
  String adapterId,
);

class SlashCommandCatalogRepository extends ChangeNotifier {
  SlashCommandCatalogRepository({required SlashCommandLoader client})
      : _client = client;

  final SlashCommandLoader _client;

  final Map<String, List<SlashCommand>> _commandsByAdapter =
      <String, List<SlashCommand>>{};
  final Map<String, Object?> _errorsByAdapter = <String, Object?>{};
  final Map<String, Future<List<SlashCommand>>> _loadsByAdapter =
      <String, Future<List<SlashCommand>>>{};
  final Map<String, int> _generationsByAdapter = <String, int>{};
  final Set<String> _loadedAdapters = <String>{};
  bool _disposed = false;

  bool get loading => _loadsByAdapter.isNotEmpty;

  List<SlashCommand> commandsForAdapter(String adapterId) {
    final key = _adapterKey(adapterId);
    return List<SlashCommand>.unmodifiable(
      _commandsByAdapter[key] ?? const <SlashCommand>[],
    );
  }

  Object? errorForAdapter(String adapterId) => _errorsByAdapter[_adapterKey(adapterId)];

  bool hasLoadedAdapter(String adapterId) =>
      _loadedAdapters.contains(_adapterKey(adapterId));

  Future<List<SlashCommand>> loadForAdapter(
    String adapterId, {
    bool force = false,
  }) {
    final key = _adapterKey(adapterId);
    if (key.isEmpty) return Future<List<SlashCommand>>.value(const <SlashCommand>[]);
    if (!force && _loadedAdapters.contains(key)) {
      return Future<List<SlashCommand>>.value(commandsForAdapter(key));
    }
    final existing = _loadsByAdapter[key];
    if (!force && existing != null) return existing;
    final generation = (_generationsByAdapter[key] ?? 0) + 1;
    _generationsByAdapter[key] = generation;
    _errorsByAdapter.remove(key);
    final future = _client(key).then((commands) {
      if (_disposed || _generationsByAdapter[key] != generation) {
        return commandsForAdapter(key);
      }
      final normalized = _normalizeCommands(commands);
      _commandsByAdapter[key] = List<SlashCommand>.unmodifiable(normalized);
      _loadedAdapters.add(key);
      return commandsForAdapter(key);
    }).catchError((Object error) {
      if (!_disposed && _generationsByAdapter[key] == generation) {
        _errorsByAdapter[key] = error;
      }
      throw error;
    }).whenComplete(() {
      if (_disposed) return;
      if (_generationsByAdapter[key] == generation) {
        _loadsByAdapter.remove(key);
      }
      _notifyIfActive();
    });
    _loadsByAdapter[key] = future;
    _notifyIfActive();
    return future;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final key in _generationsByAdapter.keys.toList(growable: false)) {
      _generationsByAdapter[key] = (_generationsByAdapter[key] ?? 0) + 1;
    }
    super.dispose();
  }

  List<SlashCommand> _normalizeCommands(List<SlashCommand> commands) {
    final byKey = <String, SlashCommand>{};
    for (final command in commands) {
      final normalized = SlashCommand(
        command: normalizeSlashCommand(command.command),
        description: command.description,
      );
      final key = normalized.matchingKey;
      if (key.isEmpty || byKey.containsKey(key)) continue;
      byKey[key] = normalized;
    }
    final result = byKey.values.toList(growable: false);
    result.sort((a, b) => a.matchingKey.compareTo(b.matchingKey));
    return result;
  }

  String _adapterKey(String value) => value.trim().toLowerCase();

  void _notifyIfActive() {
    if (!_disposed) notifyListeners();
  }
}
```

- [ ] **Step 4: Run repository tests to verify they pass**

Run:

```powershell
cd mobile
flutter test --no-pub test\slash_command_catalog_repository_test.dart -r expanded
```

Expected: PASS.

- [ ] **Step 5: Commit repository**

```powershell
git add mobile/lib/src/data/repositories/slash_command_catalog_repository.dart mobile/test/slash_command_catalog_repository_test.dart
git commit -m "Cache adapter slash command catalogs" -m "Workbench slash commands need a dedicated adapter-scoped repository with race-safe loads and normalized filtering keys." -m "Constraint: Request generations are monotonically increasing integers per adapter" -m "Confidence: high" -m "Scope-risk: narrow" -m "Tested: cd mobile && flutter test --no-pub test\\slash_command_catalog_repository_test.dart -r expanded"
```

---

### Task 4: Dependency Injection Wiring

**Files:**
- Modify: `mobile/lib/src/app/app_dependencies.dart`
- Modify: `mobile/lib/src/app/connected_session_scope.dart`
- Modify: `mobile/lib/src/ui/features/workbench/workbench_dependencies.dart`
- Modify: `mobile/test/app_dependencies_test.dart`
- Modify: `mobile/test/main_route_overlay_test.dart`
- Modify: `mobile/test/widget_test.dart`

- [ ] **Step 1: Write wiring test expectation**

In `mobile/test/app_dependencies_test.dart`, extend the connected dependency test that already verifies repositories are reused. Add this assertion after the local `mainTabs` value is created:

```dart
expect(
  mainTabs.workbenchDependencies.slashCommandCatalogRepository,
  same(mainTabs.connectedData.slashCommandCatalogRepository),
);
```

- [ ] **Step 2: Run app dependency test to verify it fails**

Run:

```powershell
cd mobile
flutter test --no-pub test\app_dependencies_test.dart -r expanded --plain-name "dependencies"
```

Expected: FAIL because `slashCommandCatalogRepository` is not available on dependencies.

- [ ] **Step 3: Wire repository through app dependencies**

Modify imports in `mobile/lib/src/app/app_dependencies.dart`:

```dart
import '../data/repositories/slash_command_catalog_repository.dart';
```

In `ConnectedDataDependencies`, add constructor parameter and field:

```dart
SlashCommandCatalogRepository? slashCommandCatalogRepository,
```

Constructor initializer:

```dart
slashCommandCatalogRepository = slashCommandCatalogRepository ??
    SlashCommandCatalogRepository(client: adapterRepository.listSlashCommands),
```

Field:

```dart
final SlashCommandCatalogRepository slashCommandCatalogRepository;
```

Dispose block:

```dart
try {
  slashCommandCatalogRepository.dispose();
} catch (_) {
  // Cleanup failures must not surface as unhandled async errors.
}
```

In `DataDependencies.forDaemonClient`, create it from the raw daemon adapter repository:

```dart
final slashCommandCatalogRepository = SlashCommandCatalogRepository(
  client: rawAdapterRepository.listSlashCommands,
);
```

Pass it into `ConnectedDataDependencies`:

```dart
slashCommandCatalogRepository: slashCommandCatalogRepository,
```

In `FeatureDependencies.createDefault.createWorkbenchDependencies`, pass:

```dart
slashCommandCatalogRepository: connectedData.slashCommandCatalogRepository,
```

Modify `mobile/lib/src/data/repositories/daemon_adapter_repository.dart` to expose the loader:

```dart
Future<List<SlashCommand>> listSlashCommands(String adapterId) =>
    _client.listSlashCommands(adapterId);
```

This method is intentionally concrete on `DaemonAdapterRepository`; do not add it to `AdapterRepository` because slash commands are not part of the existing global adapter resource contract.

- [ ] **Step 4: Wire through `WorkbenchDependencies`**

Modify `mobile/lib/src/ui/features/workbench/workbench_dependencies.dart`:

```dart
import '../../../data/repositories/slash_command_catalog_repository.dart';
```

Add required constructor parameter:

```dart
required this.slashCommandCatalogRepository,
```

Add field:

```dart
final SlashCommandCatalogRepository slashCommandCatalogRepository;
```

Add to `copyWith`:

```dart
SlashCommandCatalogRepository? slashCommandCatalogRepository,
```

Pass in `copyWith` return:

```dart
slashCommandCatalogRepository:
    slashCommandCatalogRepository ?? this.slashCommandCatalogRepository,
```

- [ ] **Step 5: Fix test constructors**

Every direct `WorkbenchDependencies(...)` in tests must pass a repository. Use this helper shape near existing widget test fakes:

```dart
SlashCommandCatalogRepository _emptySlashCommandCatalogRepository() =>
    SlashCommandCatalogRepository(
      client: (_) async => const <SlashCommand>[],
    );
```

Then add to each test dependency construction:

```dart
slashCommandCatalogRepository: _emptySlashCommandCatalogRepository(),
```

For fakes that need a controllable repository in later tasks, create:

```dart
SlashCommandCatalogRepository _slashCommandCatalogRepository(
  Map<String, List<SlashCommand>> commandsByAdapter,
) =>
    SlashCommandCatalogRepository(
      client: (adapter) async =>
          commandsByAdapter[adapter] ?? const <SlashCommand>[],
    );
```

- [ ] **Step 6: Run wiring and architecture checks**

Run:

```powershell
cd mobile
flutter test --no-pub test\app_dependencies_test.dart -r expanded --plain-name "dependencies"
flutter test --no-pub test\widget_test.dart -r expanded --plain-name "workbench lifecycle"
dart run tool\check_architecture_imports.dart
```

Expected: PASS.

- [ ] **Step 7: Commit DI wiring**

```powershell
git add mobile/lib/src/app/app_dependencies.dart mobile/lib/src/app/connected_session_scope.dart mobile/lib/src/ui/features/workbench/workbench_dependencies.dart mobile/lib/src/data/repositories/daemon_adapter_repository.dart mobile/test/app_dependencies_test.dart mobile/test/main_route_overlay_test.dart mobile/test/widget_test.dart
git commit -m "Inject slash command catalogs into workbench" -m "The workbench owns slash command presentation, so adapter-scoped catalog loading is injected directly through WorkbenchDependencies." -m "Rejected: Prop drilling through MainTabsShellViewModel | composer command state is workbench-local" -m "Confidence: high" -m "Scope-risk: moderate" -m "Tested: cd mobile && dart run tool\\check_architecture_imports.dart"
```

---

### Task 5: Slash Token Filtering And Insertion Logic

**Files:**
- Modify: `mobile/lib/src/ui/features/workbench/coding_workbench_page.dart`
- Add tests in: `mobile/test/widget_test.dart`

- [ ] **Step 1: Write focused widget tests for filtering and insertion**

Add these tests near existing workbench composer tests in `mobile/test/widget_test.dart`:

```dart
testWidgets('slash command menu filters by command text only',
    (WidgetTester tester) async {
  final catalog = _slashCommandCatalogRepository(const <String, List<SlashCommand>>{
    'codex': <SlashCommand>[
      SlashCommand(command: '/compact', description: 'summarize context'),
      SlashCommand(command: '/code-review', description: 'review changes'),
      SlashCommand(command: '/fast', description: 'contains co in description'),
    ],
  });

  await _pumpWorkbenchForSlashCommands(tester, catalog);
  await tester.tap(find.text('Current Project'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).last, '/co');
  await tester.pumpAndSettle();

  expect(find.text('/code-review'), findsOneWidget);
  expect(find.text('/compact'), findsOneWidget);
  expect(find.text('/fast'), findsNothing);
});

testWidgets('slash command menu is case-insensitive and inserts at cursor',
    (WidgetTester tester) async {
  final catalog = _slashCommandCatalogRepository(const <String, List<SlashCommand>>{
    'codex': <SlashCommand>[
      SlashCommand(command: '/compact', description: 'summarize context'),
      SlashCommand(command: '/code-review', description: 'review changes'),
    ],
  });

  await _pumpWorkbenchForSlashCommands(tester, catalog);
  await tester.tap(find.text('Current Project'));
  await tester.pumpAndSettle();
  final input = find.byType(TextField).last;
  await tester.enterText(input, 'please /CO now');
  final field = tester.widget<TextField>(input);
  field.controller!.selection = const TextSelection.collapsed(offset: 10);
  field.controller!.notifyListeners();
  await tester.pumpAndSettle();

  await tester.tap(find.text('/compact'));
  await tester.pumpAndSettle();

  expect(field.controller!.text, 'please /compact  now');
  expect(field.controller!.selection.baseOffset, 'please /compact '.length);
});
```

Add helper:

```dart
Future<void> _pumpWorkbenchForSlashCommands(
  WidgetTester tester,
  SlashCommandCatalogRepository catalog,
) async {
  SharedPreferences.setMockInitialValues(
      <String, Object>{AppLanguage.storageKey: 'en-US'});
  const workspace = WorkspaceSummary(
    id: 'workspace_1',
    name: 'Current Project',
    path: r'D:\AiProject\vibe-coding',
  );
  final client = DaemonClient(
    baseUri: Uri.parse('http://127.0.0.1:4317'),
    tokenStore: MemoryTokenStore(),
  );
  final adapterRepository = CliAdapterRepository(
      delegate: DaemonAdapterRepository(client: client))
    ..replaceFromBootstrap(const <AdapterStatus>[
      AdapterStatus(adapter: 'codex', available: true, status: 'available'),
    ]);
  final conversationRepository =
      CachedConversationRepository(delegate: _UnusedConversationRepository());
  final runRepository =
      CachedRunRepository(delegate: DaemonRunRepository(client: client))
        ..replaceFromBootstrap(
          workspaceId: workspace.id,
          runs: const <RunSummary>[],
          queue: const <QueueItem>[],
        );
  final workspaceRepository = DaemonWorkspaceRepository(client: client)
    ..applyBootstrapCatalog(
      selectedWorkspace: workspace,
      workspaces: const <WorkspaceSummary>[workspace],
    );

  await tester.pumpWidget(MaterialApp(
      supportedLocales: appSupportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
      theme: theme.buildAppTheme(),
      home: Scaffold(
          body: CodingWorkbenchPage(
              onBack: () {},
              onSessionListChanged: (_) {},
              openSessionListRequest: 0,
              streamOutput: false,
              expandThinking: false,
              permissionMode: 'default',
              dependencies: WorkbenchDependencies(
                adapterRepository: adapterRepository,
                asrModelManager:
                    AsrModelManager(client: client.createAsrModelClient()),
                codingPreferencesRepository: _WidgetCodingPreferencesRepository(
                    permissionMode: 'default'),
                conversationRepository: conversationRepository,
                diagnosticsRepository: DaemonDiagnosticsRepository(client: client),
                runRepository: runRepository,
                slashCommandCatalogRepository: catalog,
                speechInputServiceBuilder: (_) =>
                    const DisabledSpeechInputService(),
                workspaceRepository: workspaceRepository,
              )))));
  await tester.pumpAndSettle();
}
```

- [ ] **Step 2: Run widget tests to verify they fail**

Run:

```powershell
cd mobile
flutter test --no-pub test\widget_test.dart -r expanded --plain-name "slash command menu"
```

Expected: FAIL because the menu is not rendered.

- [ ] **Step 3: Add state helpers in `CodingWorkbenchPage`**

In `CodingWorkbenchPageState`, add fields:

```dart
List<SlashCommand> _visibleSlashCommands = const <SlashCommand>[];
_SlashToken? _activeSlashToken;
String? _slashCatalogAdapter;
```

Add helper methods:

```dart
void _handleComposerTextChanged(String value) {
  if (_applyingVoiceText) return;
  _updateSlashCommandMenu(_prompt.value);
}

void _updateSlashCommandMenu(TextEditingValue value) {
  final adapter = _workbenchViewModel.selectedAdapter;
  final token = _activeSlashTokenFor(value);
  if (adapter == null || token == null || _sending || _isRunningCli) {
    _setSlashCommands(const <SlashCommand>[], null);
    return;
  }
  unawaited(_ensureSlashCommandsLoaded(adapter));
  final commands = widget.dependencies.slashCommandCatalogRepository
      .commandsForAdapter(adapter);
  final query = token.query.toLowerCase();
  final prefixMatches = <SlashCommand>[];
  final containsMatches = <SlashCommand>[];
  for (final command in commands) {
    final key = command.matchingKey;
    if (query.isEmpty || key.startsWith(query)) {
      prefixMatches.add(command);
    } else if (key.contains(query)) {
      containsMatches.add(command);
    }
  }
  final visible = <SlashCommand>[...prefixMatches, ...containsMatches];
  _setSlashCommands(visible, token);
}

void _setSlashCommands(List<SlashCommand> commands, _SlashToken? token) {
  setState(() {
    _visibleSlashCommands = List<SlashCommand>.unmodifiable(commands);
    _activeSlashToken = token;
  });
}

Future<void> _ensureSlashCommandsLoaded(String adapter) async {
  final normalized = adapter.trim().toLowerCase();
  if (normalized.isEmpty || _slashCatalogAdapter == normalized) return;
  _slashCatalogAdapter = normalized;
  try {
    await widget.dependencies.slashCommandCatalogRepository
        .loadForAdapter(normalized);
  } catch (_) {
    return;
  }
  if (!mounted || _workbenchViewModel.selectedAdapter != normalized) return;
  _updateSlashCommandMenu(_prompt.value);
}

void _insertSlashCommand(SlashCommand command) {
  final token = _activeSlashToken;
  if (token == null) return;
  final value = _prompt.value;
  final insertText = '${normalizeSlashCommand(command.command)} ';
  final text = value.text.replaceRange(token.start, token.end, insertText);
  final offset = token.start + insertText.length;
  _prompt.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: offset),
  );
  _setSlashCommands(const <SlashCommand>[], null);
}

_SlashToken? _activeSlashTokenFor(TextEditingValue value) {
  final selection = value.selection;
  if (!selection.isValid || !selection.isCollapsed) return null;
  final cursor = selection.baseOffset;
  if (cursor < 0 || cursor > value.text.length) return null;
  final beforeCursor = value.text.substring(0, cursor);
  final slash = beforeCursor.lastIndexOf('/');
  if (slash < 0) return null;
  for (var index = slash; index < beforeCursor.length; index += 1) {
    if (_isSlashTokenBoundary(beforeCursor.codeUnitAt(index))) return null;
  }
  final query = beforeCursor.substring(slash + 1);
  return _SlashToken(start: slash, end: cursor, query: query);
}

bool _isSlashTokenBoundary(int codeUnit) =>
    codeUnit == 0x20 || codeUnit == 0x09 || codeUnit == 0x0A || codeUnit == 0x0D;
```

Add private class near bottom of file:

```dart
class _SlashToken {
  const _SlashToken({
    required this.start,
    required this.end,
    required this.query,
  });

  final int start;
  final int end;
  final String query;
}
```

- [ ] **Step 4: Load catalog when entering conversation**

In `_goToConversation()` or immediately after active conversation route is shown, call:

```dart
final adapter = _workbenchViewModel.selectedAdapter;
if (adapter != null) {
  unawaited(_ensureSlashCommandsLoaded(adapter));
}
```

Also call `_updateSlashCommandMenu(_prompt.value)` after adapter changes or route updates where composer remains visible.

- [ ] **Step 5: Pass menu state into `CodingComposer`**

In the `CodingComposer(...)` construction in `coding_workbench_page.dart`, add:

```dart
slashCommands: _visibleSlashCommands,
onSlashCommandSelected: _insertSlashCommand,
```

- [ ] **Step 6: Run widget tests for filtering and insertion**

Run:

```powershell
cd mobile
flutter test --no-pub test\widget_test.dart -r expanded --plain-name "slash command menu"
```

Expected: Tests still fail until `CodingComposer` renders the menu in Task 6.

- [ ] **Step 7: Commit page state after Task 6 passes**

Do not commit yet if Task 6 has not rendered the menu. Commit page state together with Task 6 UI.

---

### Task 6: Composer Slash Menu UI Overlay

**Files:**
- Modify: `mobile/lib/src/ui/features/workbench/coding_composer.dart`
- Continue tests in: `mobile/test/widget_test.dart`

- [ ] **Step 1: Convert `CodingComposer` to a stateful overlay host**

Change the widget declaration in `mobile/lib/src/ui/features/workbench/coding_composer.dart`:

```dart
class CodingComposer extends StatefulWidget {
  const CodingComposer(
      {super.key,
      required this.controller,
      required this.adapter,
      required this.workspace,
      required this.running,
      required this.canSend,
      required this.sending,
      required this.voiceState,
      required this.voiceEnabled,
      required this.voiceError,
      required this.cliLocked,
      required this.modelLocked,
      this.model,
      this.modelNotice,
      this.draftAttachments = const <DraftAttachment>[],
      this.slashCommands = const <SlashCommand>[],
      this.onSlashCommandSelected,
      this.onAttachmentTap,
      this.onRemoveAttachment,
      required this.onCliTap,
      required this.onModelTap,
      required this.onVoiceStart,
      required this.onVoiceStop,
      required this.onVoiceCancel,
      required this.onTextChanged,
      required this.onSend,
      required this.onCancel});
```

Keep the existing fields and add:

```dart
final List<SlashCommand> slashCommands;
final ValueChanged<SlashCommand>? onSlashCommandSelected;
```

Add the state class:

```dart
class _CodingComposerState extends State<CodingComposer> {
  final _slashMenuController = OverlayPortalController();
  final _slashMenuLink = LayerLink();

  @override
  void initState() {
    super.initState();
    _syncSlashMenuOverlay();
  }

  @override
  void didUpdateWidget(covariant CodingComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slashCommands.isEmpty != widget.slashCommands.isEmpty) {
      _syncSlashMenuOverlay();
    }
  }

  void _syncSlashMenuOverlay() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.slashCommands.isEmpty) {
        _slashMenuController.hide();
      } else {
        _slashMenuController.show();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final attachmentStatus =
        _firstLocalizedAttachmentError(context, widget.draftAttachments);
    return LayoutBuilder(builder: (context, constraints) {
      final overlayWidth = constraints.maxWidth;
      return CompositedTransformTarget(
        link: _slashMenuLink,
        child: OverlayPortal(
          controller: _slashMenuController,
          overlayChildBuilder: (context) => CompositedTransformFollower(
            link: _slashMenuLink,
            showWhenUnlinked: false,
            targetAnchor: Alignment.topLeft,
            followerAnchor: Alignment.bottomLeft,
            offset: const Offset(0, -8),
            child: SizedBox(
              width: overlayWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _SlashCommandMenu(
                  commands: widget.slashCommands,
                  onSelected: widget.onSlashCommandSelected,
                ),
              ),
            ),
          ),
          child: _buildComposerSurface(
            context,
            l10n: l10n,
            attachmentStatus: attachmentStatus,
          ),
        ),
      );
    });
  }
```

Move the current `CodingComposer.build` body into a new private method named `_buildComposerSurface` on `_CodingComposerState`. The method signature is:

```dart
Widget _buildComposerSurface(
  BuildContext context, {
  required AppLocalizations l10n,
  required String? attachmentStatus,
})
```

The moved body starts with the existing `return Container(padding: const EdgeInsets.fromLTRB(12, 8, 12, 4), ...)` and keeps the current child tree unchanged. Inside the moved body, replace field reads such as `controller`, `adapter`, `draftAttachments`, and callbacks with `widget.controller`, `widget.adapter`, `widget.draftAttachments`, and `widget.onSend`. Do not insert the slash menu into this body; the menu is rendered by `OverlayPortal` so it cannot affect the composer `TextField` position.

- [ ] **Step 2: Extend `CodingComposer` API at call sites**

The `CodingComposer` call in `coding_workbench_page.dart` already adds these fields in Task 5:

```dart
slashCommands: _visibleSlashCommands,
onSlashCommandSelected: _insertSlashCommand,
```

Every test-only `CodingComposer` construction can omit both fields because they have defaults.

- [ ] **Step 3: Add menu row widgets**

Add these widgets in `coding_composer.dart` below `CodingComposer`:

```dart
class _SlashCommandMenu extends StatelessWidget {
  const _SlashCommandMenu({
    required this.commands,
    required this.onSelected,
  });

  static const double _rowHeight = 34;
  static const int _maxVisibleRows = 6;

  final List<SlashCommand> commands;
  final ValueChanged<SlashCommand>? onSelected;

  @override
  Widget build(BuildContext context) {
    final visibleCount =
        commands.length > _maxVisibleRows ? _maxVisibleRows : commands.length;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: _rowHeight * visibleCount,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF111214),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: .085)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .26),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemExtent: _rowHeight,
            itemCount: commands.length,
            itemBuilder: (context, index) {
              final command = commands[index];
              return _SlashCommandRow(
                command: command,
                onTap: onSelected == null
                    ? null
                    : () => onSelected?.call(command),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SlashCommandRow extends StatelessWidget {
  const _SlashCommandRow({
    required this.command,
    required this.onTap,
  });

  final SlashCommand command;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            SizedBox(
              width: 116,
              child: Text(
                command.command,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.appTextStyle.copyWith(
                  color: theme.active,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                command.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.appTextStyle.copyWith(
                  color: theme.muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

This overlay follows the composer target and sits directly above it. It may shrink with result count, but because it is in the overlay layer it does not participate in the composer layout.

- [ ] **Step 4: Add stable-offset test**

Add a widget test:

```dart
testWidgets('slash command filtering does not move composer text field',
    (WidgetTester tester) async {
  final catalog = _slashCommandCatalogRepository(const <String, List<SlashCommand>>{
    'codex': <SlashCommand>[
      SlashCommand(command: '/compact', description: 'summarize context'),
      SlashCommand(command: '/code-review', description: 'review changes'),
      SlashCommand(command: '/config', description: 'edit config'),
      SlashCommand(command: '/continue', description: 'continue session'),
      SlashCommand(command: '/context', description: 'show context'),
      SlashCommand(command: '/copy', description: 'copy output'),
    ],
  });

  await _pumpWorkbenchForSlashCommands(tester, catalog);
  await tester.tap(find.text('Current Project'));
  await tester.pumpAndSettle();
  final input = find.byType(TextField).last;
  await tester.enterText(input, '/co');
  await tester.pumpAndSettle();
  final before = tester.getTopLeft(input);

  await tester.enterText(input, '/comp');
  await tester.pumpAndSettle();
  final after = tester.getTopLeft(input);

  expect(after, before);
});
```

- [ ] **Step 5: Run widget tests**

Run:

```powershell
cd mobile
flutter test --no-pub test\widget_test.dart -r expanded --plain-name "slash command"
```

Expected: PASS, including the global-offset assertion for the composer `TextField`.

- [ ] **Step 6: Commit composer UI and page logic**

```powershell
git add mobile/lib/src/ui/features/workbench/coding_workbench_page.dart mobile/lib/src/ui/features/workbench/coding_composer.dart mobile/test/widget_test.dart
git commit -m "Show slash command menu in composer" -m "The workbench composer now filters adapter slash commands from the active cursor token and inserts selected commands without sending." -m "Constraint: Menu result changes must not move the composer text field" -m "Confidence: high" -m "Scope-risk: moderate" -m "Tested: cd mobile && flutter test --no-pub test\\widget_test.dart -r expanded --plain-name \"slash command\""
```

---

### Task 7: Catalog Load Timing And Adapter Switch Coverage

**Files:**
- Modify: `mobile/lib/src/ui/features/workbench/coding_workbench_page.dart`
- Modify: `mobile/test/widget_test.dart`

- [ ] **Step 1: Add tests for load-on-entry and adapter switching**

Use a controllable repository in `widget_test.dart`:

```dart
class _RecordingSlashCommandCatalogRepository
    extends SlashCommandCatalogRepository {
  _RecordingSlashCommandCatalogRepository(
    this.commandsByAdapter,
  ) : super(client: (adapter) async =>
            commandsByAdapter[adapter] ?? const <SlashCommand>[]);

  final Map<String, List<SlashCommand>> commandsByAdapter;
  final List<String> loadCalls = <String>[];

  @override
  Future<List<SlashCommand>> loadForAdapter(
    String adapterId, {
    bool force = false,
  }) {
    loadCalls.add(adapterId.trim().toLowerCase());
    return super.loadForAdapter(adapterId, force: force);
  }
}
```

Add test:

```dart
testWidgets('slash command catalog loads once when entering conversation',
    (WidgetTester tester) async {
  final catalog = _RecordingSlashCommandCatalogRepository(
    const <String, List<SlashCommand>>{
      'codex': <SlashCommand>[
        SlashCommand(command: '/model', description: 'choose model'),
      ],
    },
  );

  await _pumpWorkbenchForSlashCommands(tester, catalog);
  await tester.tap(find.text('Current Project'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).last, '/');
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).last, '/m');
  await tester.pumpAndSettle();

  expect(catalog.loadCalls.where((adapter) => adapter == 'codex'), hasLength(1));
  expect(find.text('/model'), findsOneWidget);
});
```

Add adapter switch test by bootstrapping both adapters and tapping the existing CLI picker:

```dart
testWidgets('slash command catalog loads new adapter after CLI switch',
    (WidgetTester tester) async {
  final catalog = _RecordingSlashCommandCatalogRepository(
    const <String, List<SlashCommand>>{
      'codex': <SlashCommand>[
        SlashCommand(command: '/model', description: 'codex model'),
      ],
      'claude': <SlashCommand>[
        SlashCommand(command: '/compact', description: 'claude compact'),
      ],
    },
  );

  await _pumpWorkbenchForSlashCommands(
    tester,
    catalog,
    adapters: const <AdapterStatus>[
      AdapterStatus(adapter: 'codex', available: true, status: 'available'),
      AdapterStatus(adapter: 'claude', available: true, status: 'available'),
    ],
  );
  await tester.tap(find.text('Current Project'));
  await tester.pumpAndSettle();

  await tester.tap(find.text('codex').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('claude').last);
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).last, '/co');
  await tester.pumpAndSettle();

  expect(catalog.loadCalls, containsAll(<String>['codex', 'claude']));
  expect(find.text('/compact'), findsOneWidget);
  expect(find.text('/model'), findsNothing);
});
```

- [ ] **Step 2: Run tests to verify failures or gaps**

Run:

```powershell
cd mobile
flutter test --no-pub test\widget_test.dart -r expanded --plain-name "slash command catalog"
```

Expected: FAIL if current load timing or adapter switch handling is incomplete.

- [ ] **Step 3: Fix load timing**

In `_goToConversation`, after `_navigatorKey.currentState?.pushNamedAndRemoveUntil(...)`, add:

```dart
_ensureSlashCatalogForSelectedAdapter();
```

Implement:

```dart
void _ensureSlashCatalogForSelectedAdapter() {
  final adapter = _workbenchViewModel.selectedAdapter;
  if (adapter == null || adapter.trim().isEmpty) return;
  unawaited(_ensureSlashCommandsLoaded(adapter));
}
```

In `_syncWorkbenchViewModel`, detect selected adapter changes:

```dart
String? _lastSlashAdapter;

void _syncWorkbenchViewModel() {
  final adapter = _workbenchViewModel.selectedAdapter;
  if (adapter != _lastSlashAdapter) {
    _lastSlashAdapter = adapter;
    _setSlashCommands(const <SlashCommand>[], null);
    _ensureSlashCatalogForSelectedAdapter();
  }
  if (mounted) setState(() {});
}
```

Keep `setState` guarded so this method does not call `setState` twice after disposal.

- [ ] **Step 4: Run adapter timing tests**

Run:

```powershell
cd mobile
flutter test --no-pub test\widget_test.dart -r expanded --plain-name "slash command catalog"
```

Expected: PASS.

- [ ] **Step 5: Commit load timing**

```powershell
git add mobile/lib/src/ui/features/workbench/coding_workbench_page.dart mobile/test/widget_test.dart
git commit -m "Load slash commands for active adapters" -m "The workbench now loads slash command catalogs when a conversation opens and refreshes the visible menu when the selected adapter changes." -m "Constraint: Catalog loads are local to workbench and do not pass through shell view model state" -m "Confidence: high" -m "Scope-risk: narrow" -m "Tested: cd mobile && flutter test --no-pub test\\widget_test.dart -r expanded --plain-name \"slash command catalog\""
```

---

### Task 8: Full Verification And Documentation Check

**Files:**
- Possibly modify: `docs/project-knowledge/decisions/2026-05-31-slash-command-menu.md`
- Possibly modify: `docs/project-knowledge/index.md`

- [ ] **Step 1: Run daemon regression tests**

Run:

```powershell
node scripts/run-tests.js
```

Expected: PASS.

- [ ] **Step 2: Run focused mobile tests**

Run:

```powershell
cd mobile
flutter test --no-pub test\daemon_client_test.dart -r expanded --plain-name "listSlashCommands"
flutter test --no-pub test\slash_command_catalog_repository_test.dart -r expanded
flutter test --no-pub test\widget_test.dart -r expanded --plain-name "slash command"
flutter test --no-pub test\adapter_resource_state_test.dart -r expanded
```

Expected: PASS.

- [ ] **Step 3: Run mobile static checks**

Run:

```powershell
cd mobile
dart analyze lib test
dart run tool\check_architecture_imports.dart
```

Expected: PASS.

- [ ] **Step 4: Run diff checks**

Run:

```powershell
git diff --check
git status -sb
```

Expected: no whitespace errors. `git status -sb` should show only intentional implementation files before the final commit.

- [ ] **Step 5: Decide project knowledge update**

When implementation preserves the exact architecture in the spec and no new durable lesson appears, do not add project knowledge. The spec already captures the durable design.

If implementation changes the architecture materially, create `docs/project-knowledge/decisions/2026-05-31-slash-command-menu.md`:

```markdown
# Decision: Mobile slash commands are daemon-owned adapter catalogs

- Status: accepted
- Date: 2026-05-31
- Last verified: 2026-05-31

## Context

The mobile workbench composer needs slash command discovery for Claude, Codex,
and OpenCode without hardcoding command inventories in Flutter.

## Decision

The daemon owns adapter slash command catalogs. Mobile loads the active
adapter's catalog into a dedicated `SlashCommandCatalogRepository` and renders a
composer-local command menu.

## Alternatives

- Hardcode commands in mobile: rejected because CLI command lists drift.
- Extend `CommandCatalogRepository`: rejected because global templates and
  adapter-native slash commands have different lifecycle semantics.

## Evidence

- Spec: `docs/superpowers/specs/2026-05-31-slash-command-menu-design.md`
- Code paths: `daemon/src/slash-command-catalog.js`,
  `mobile/lib/src/data/repositories/slash_command_catalog_repository.dart`,
  `mobile/lib/src/ui/features/workbench/coding_workbench_page.dart`

## Verification

- `node scripts/run-tests.js`
- `cd mobile && flutter test --no-pub test\slash_command_catalog_repository_test.dart -r expanded`
- `cd mobile && flutter test --no-pub test\widget_test.dart -r expanded --plain-name "slash command"`
- `cd mobile && dart run tool\check_architecture_imports.dart`

## Re-evaluate When

- daemon supports discovered or user-defined slash commands;
- shortcuts/templates join the composer slash menu;
- command descriptions become locale-aware.
```

If adding this decision, also add one bullet under `## Current Accepted Decisions` in `docs/project-knowledge/index.md`:

```markdown
- [Mobile slash commands are daemon-owned adapter catalogs](decisions/2026-05-31-slash-command-menu.md)
```

- [ ] **Step 6: Final commit if knowledge was added**

Only run this if Step 5 created or changed project knowledge:

```powershell
git add -f docs/project-knowledge/index.md docs/project-knowledge/decisions/2026-05-31-slash-command-menu.md
git commit -m "Record slash command catalog ownership" -m "The slash command implementation creates a durable daemon/mobile ownership boundary that future work should preserve." -m "Confidence: high" -m "Scope-risk: narrow" -m "Tested: node scripts/check-project-knowledge.js"
```

- [ ] **Step 7: Final verification summary**

Before reporting done, collect:

```powershell
git log --oneline -5
git status -sb
```

Expected: worktree clean except ignored local artifacts, implementation commits present, branch ahead count matches the number of new commits.
