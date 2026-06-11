# Codex Tab Console Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Codex app-server diagnostic tabs with a localized mobile Codex console and same-page read-only thread review.

**Architecture:** Keep Flutter layered architecture intact. Data/repository code owns daemon DTO parsing and route composition, `CodexAppServerViewModel` owns immutable presentation state and commands, and widgets remain lean localized renderers under `ui/features/codex_app_server/`.

**Tech Stack:** Flutter/Dart, generated `AppLocalizations`, existing daemon HTTP routes, existing `CodexAppServerRepository`, existing widget and unit test harnesses.

---

## Spec Source

Implement the approved spec:

```text
docs/superpowers/specs/2026-06-07-codex-tab-console-redesign.md
```

The first implementation is read-only. Do not add archive, fork, rollback, goal edits, config writes, plugin actions, remote-control changes, or raw app-server JSON-RPC access.

## File Structure

- Modify `mobile/lib/src/domain/models/codex_app_server_models.dart`
  - Add immutable domain models for thread goal, turns, items, turn review, and thread review.
- Modify `mobile/lib/src/data/models/codex_app_server_models.dart`
  - Add parser helpers for goal, turns, items, and thread review DTOs.
- Modify `mobile/lib/src/domain/repositories/codex_app_server_repository.dart`
  - Add `loadThreadReview`.
- Modify `mobile/lib/src/data/repositories/codex_app_server_repository.dart`
  - Compose existing daemon routes for readThread, goal, turns, and items.
- Modify `mobile/lib/src/ui/features/codex_app_server/view_models/codex_app_server_view_model.dart`
  - Add page mode, derived status, route/resource counts, selected thread review state, and thread commands.
- Modify `mobile/lib/l10n/app_en.arb`
  - Add all Codex console strings.
- Modify `mobile/lib/l10n/app_zh.arb`
  - Add matching Chinese strings.
- Regenerate `mobile/lib/l10n/app_localizations.dart`, `app_localizations_en.dart`, and `app_localizations_zh.dart`.
- Modify `mobile/lib/src/ui/main_tab_items.dart`
  - Use localized Codex label.
- Replace `mobile/lib/src/ui/features/codex_app_server/views/codex_app_server_page.dart`
  - Remove internal TabBar and route between overview/detail based on ViewModel state.
- Create `mobile/lib/src/ui/features/codex_app_server/widgets/codex_app_server_overview_view.dart`
  - Render header, status metrics, recent sessions, runtime resources, safety boundary, and empty/error states.
- Create `mobile/lib/src/ui/features/codex_app_server/widgets/codex_app_server_thread_detail_view.dart`
  - Render back header, summary, goal fallback, timeline rows, and partial/fatal error states.
- Modify or replace `mobile/lib/src/ui/features/codex_app_server/widgets/codex_app_server_ui.dart`
  - Keep only shared, theme-aligned primitives.
- Delete after replacement if unused:
  - `mobile/lib/src/ui/features/codex_app_server/widgets/codex_app_server_history_view.dart`
  - `mobile/lib/src/ui/features/codex_app_server/widgets/codex_app_server_discovery_view.dart`
  - `mobile/lib/src/ui/features/codex_app_server/widgets/codex_app_server_risk_view.dart`
- Modify `mobile/lib/src/ui/main/connected_main_shell.dart`
  - Reset Codex detail state when the user leaves the Codex bottom tab.
- Modify `mobile/test/codex_app_server_models_test.dart`
  - Cover parsers and repository route composition.
- Modify `mobile/test/codex_app_server_view_model_test.dart`
  - Cover overview state, status/count derivation, thread detail state, partial failures, and widget navigation.

---

### Task 1: Add Thread Review Domain Models And Repository Aggregation

**Files:**
- Modify: `mobile/lib/src/domain/models/codex_app_server_models.dart`
- Modify: `mobile/lib/src/data/models/codex_app_server_models.dart`
- Modify: `mobile/lib/src/domain/repositories/codex_app_server_repository.dart`
- Modify: `mobile/lib/src/data/repositories/codex_app_server_repository.dart`
- Test: `mobile/test/codex_app_server_models_test.dart`

- [ ] **Step 1: Write failing parser and repository tests**

Add these tests to `mobile/test/codex_app_server_models_test.dart` after the existing thread page parser test:

```dart
  test('CodexAppServerThreadReview parses goal turns and items', () {
    final detail = parseCodexAppServerThreadDetail(const {
      'thread': {
        'id': 'thread_1',
        'title': 'Fix auth',
        'workspacePath': 'D:/Repo',
        'archived': false,
        'updatedAt': '2026-06-07T12:00:00.000Z',
      },
    });
    final goal = parseCodexAppServerGoalResponse(const {
      'goal': {
        'id': 'goal_1',
        'objective': 'Ship the auth fix',
        'status': 'active',
        'updatedAt': '2026-06-07T12:01:00.000Z',
      },
    });
    final turns = parseCodexAppServerTurnPage(const {
      'turns': [
        {
          'id': 'turn_1',
          'status': 'completed',
          'createdAt': '2026-06-07T12:02:00.000Z',
          'completedAt': '2026-06-07T12:03:00.000Z',
        }
      ],
    });
    final items = parseCodexAppServerItemPage(const {
      'items': [
        {
          'id': 'item_1',
          'turnId': 'turn_1',
          'type': 'agent_message',
          'status': 'completed',
          'createdAt': '2026-06-07T12:02:10.000Z',
        }
      ],
    });

    final review = CodexAppServerThreadReview(
      detail: detail,
      goal: goal,
      goalUnavailable: false,
      turns: [
        CodexAppServerTurnReview(
          turn: turns.turns.single,
          items: items.items,
          itemsUnavailable: false,
        ),
      ],
      timelineUnavailable: false,
    );

    expect(review.detail.thread.id, 'thread_1');
    expect(review.goal?.objective, 'Ship the auth fix');
    expect(review.turns.single.turn.id, 'turn_1');
    expect(review.turns.single.items.single.type, 'agent_message');
    expect(review.timelineUnavailable, false);
  });
```

Extend the existing `repository maps Codex app-server calls to daemon routes` test with a `loadThreadReview` call and route cases:

```dart
          case '/api/codex-app-server/workspaces/workspace_1/threads/thread_1/goal':
            return const {
              'goal': {'id': 'goal_1', 'objective': 'Ship the auth fix'}
            };
          case '/api/codex-app-server/workspaces/workspace_1/threads/thread_1/turns?limit=20':
            return const {
              'turns': [
                {'id': 'turn_1', 'status': 'completed'}
              ],
            };
          case '/api/codex-app-server/workspaces/workspace_1/threads/thread_1/turns/turn_1/items?limit=20':
            return const {
              'items': [
                {'id': 'item_1', 'turnId': 'turn_1', 'type': 'agent_message'}
              ],
            };
```

Then assert:

```dart
    final review = await repository.loadThreadReview(
      'workspace_1',
      'thread_1',
    );

    expect(review.detail.thread.id, 'thread_1');
    expect(review.goal?.objective, 'Ship the auth fix');
    expect(review.turns.single.items.single.id, 'item_1');
```

- [ ] **Step 2: Run the tests and verify failure**

Run:

```powershell
cd mobile
flutter test --no-pub test\codex_app_server_models_test.dart --plain-name "CodexAppServerThreadReview parses goal turns and items"
```

Expected: fails because `parseCodexAppServerGoalResponse`, `parseCodexAppServerTurnPage`, `parseCodexAppServerItemPage`, `CodexAppServerThreadReview`, and `loadThreadReview` do not exist.

- [ ] **Step 3: Add domain models**

Add these classes to `mobile/lib/src/domain/models/codex_app_server_models.dart` after `CodexAppServerThreadDetail`:

```dart
class CodexAppServerGoalSummary {
  const CodexAppServerGoalSummary({
    required this.id,
    required this.objective,
    required this.status,
    required this.updatedAt,
    required this.raw,
  });

  final String id;
  final String objective;
  final String status;
  final String? updatedAt;
  final Map<String, Object?> raw;
}

class CodexAppServerTurnSummary {
  const CodexAppServerTurnSummary({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.completedAt,
    required this.raw,
  });

  final String id;
  final String status;
  final String? createdAt;
  final String? completedAt;
  final Map<String, Object?> raw;
}

class CodexAppServerItemSummary {
  const CodexAppServerItemSummary({
    required this.id,
    required this.turnId,
    required this.type,
    required this.status,
    required this.createdAt,
    required this.raw,
  });

  final String id;
  final String turnId;
  final String type;
  final String status;
  final String? createdAt;
  final Map<String, Object?> raw;
}

class CodexAppServerTurnPage {
  const CodexAppServerTurnPage({
    required this.turns,
    required this.nextCursor,
    required this.raw,
  });

  final List<CodexAppServerTurnSummary> turns;
  final String? nextCursor;
  final Map<String, Object?> raw;
}

class CodexAppServerItemPage {
  const CodexAppServerItemPage({
    required this.items,
    required this.nextCursor,
    required this.raw,
  });

  final List<CodexAppServerItemSummary> items;
  final String? nextCursor;
  final Map<String, Object?> raw;
}

class CodexAppServerTurnReview {
  const CodexAppServerTurnReview({
    required this.turn,
    required this.items,
    required this.itemsUnavailable,
  });

  final CodexAppServerTurnSummary turn;
  final List<CodexAppServerItemSummary> items;
  final bool itemsUnavailable;
}

class CodexAppServerThreadReview {
  const CodexAppServerThreadReview({
    required this.detail,
    required this.goal,
    required this.goalUnavailable,
    required this.turns,
    required this.timelineUnavailable,
  });

  final CodexAppServerThreadDetail detail;
  final CodexAppServerGoalSummary? goal;
  final bool goalUnavailable;
  final List<CodexAppServerTurnReview> turns;
  final bool timelineUnavailable;
}
```

- [ ] **Step 4: Add parser functions**

Add these functions to `mobile/lib/src/data/models/codex_app_server_models.dart` after `parseCodexAppServerThreadDetail`:

```dart
CodexAppServerGoalSummary? parseCodexAppServerGoalResponse(
  Map<String, Object?> json,
) {
  final goal = json.containsKey('goal') ? json['goal'] : json;
  if (goal == null) return null;
  final map = _mapValue(goal);
  if (map.isEmpty) return null;
  return CodexAppServerGoalSummary(
    id: _stringValue(map['id'] ?? map['goalId']),
    objective: _stringValue(map['objective'] ?? map['goal']),
    status: _stringValue(map['status']),
    updatedAt: _nullableStringValue(map['updatedAt']),
    raw: map,
  );
}

CodexAppServerTurnPage parseCodexAppServerTurnPage(
  Map<String, Object?> json,
) {
  return CodexAppServerTurnPage(
    turns: _objectListValue(json['turns'] ?? json['items'])
        .map(parseCodexAppServerTurnSummary)
        .toList(growable: false),
    nextCursor: _nullableStringValue(json['nextCursor']),
    raw: json,
  );
}

CodexAppServerTurnSummary parseCodexAppServerTurnSummary(
  Map<String, Object?> json,
) {
  return CodexAppServerTurnSummary(
    id: _stringValue(json['id'] ?? json['turnId']),
    status: _stringValue(json['status']),
    createdAt: _nullableStringValue(json['createdAt']),
    completedAt: _nullableStringValue(json['completedAt']),
    raw: json,
  );
}

CodexAppServerItemPage parseCodexAppServerItemPage(
  Map<String, Object?> json,
) {
  return CodexAppServerItemPage(
    items: _objectListValue(json['items'] ?? json['data'])
        .map(parseCodexAppServerItemSummary)
        .toList(growable: false),
    nextCursor: _nullableStringValue(json['nextCursor']),
    raw: json,
  );
}

CodexAppServerItemSummary parseCodexAppServerItemSummary(
  Map<String, Object?> json,
) {
  return CodexAppServerItemSummary(
    id: _stringValue(json['id'] ?? json['itemId']),
    turnId: _stringValue(json['turnId']),
    type: _stringValue(json['type'] ?? json['kind']),
    status: _stringValue(json['status']),
    createdAt: _nullableStringValue(json['createdAt']),
    raw: json,
  );
}
```

- [ ] **Step 5: Extend repository contract**

Add this method to `mobile/lib/src/domain/repositories/codex_app_server_repository.dart`:

```dart
  Future<CodexAppServerThreadReview> loadThreadReview(
    String workspaceId,
    String threadId, {
    int turnLimit = 20,
    int itemLimit = 20,
  });
```

- [ ] **Step 6: Implement repository aggregation**

Add this implementation to `DaemonCodexAppServerRepository` in `mobile/lib/src/data/repositories/codex_app_server_repository.dart`:

```dart
  @override
  Future<CodexAppServerThreadReview> loadThreadReview(
    String workspaceId,
    String threadId, {
    int turnLimit = 20,
    int itemLimit = 20,
  }) async {
    final detail = await readThread(workspaceId, threadId);

    CodexAppServerGoalSummary? goal;
    var goalUnavailable = false;
    try {
      final response = await _getJson(
        '/api/codex-app-server/workspaces/'
        '${Uri.encodeComponent(workspaceId)}/threads/'
        '${Uri.encodeComponent(threadId)}/goal',
      );
      goal = parseCodexAppServerGoalResponse(response);
    } catch (_) {
      goalUnavailable = true;
    }

    var timelineUnavailable = false;
    final turnReviews = <CodexAppServerTurnReview>[];
    try {
      final query = Uri(queryParameters: <String, String>{
        'limit': turnLimit.toString(),
      }).query;
      final response = await _getJson(
        '/api/codex-app-server/workspaces/'
        '${Uri.encodeComponent(workspaceId)}/threads/'
        '${Uri.encodeComponent(threadId)}/turns?$query',
      );
      final turns = parseCodexAppServerTurnPage(response).turns;
      for (final turn in turns) {
        var itemsUnavailable = false;
        var items = const <CodexAppServerItemSummary>[];
        try {
          final itemQuery = Uri(queryParameters: <String, String>{
            'limit': itemLimit.toString(),
          }).query;
          final itemResponse = await _getJson(
            '/api/codex-app-server/workspaces/'
            '${Uri.encodeComponent(workspaceId)}/threads/'
            '${Uri.encodeComponent(threadId)}/turns/'
            '${Uri.encodeComponent(turn.id)}/items?$itemQuery',
          );
          items = parseCodexAppServerItemPage(itemResponse).items;
        } catch (_) {
          itemsUnavailable = true;
          timelineUnavailable = true;
        }
        turnReviews.add(CodexAppServerTurnReview(
          turn: turn,
          items: items,
          itemsUnavailable: itemsUnavailable,
        ));
      }
    } catch (_) {
      timelineUnavailable = true;
    }

    return CodexAppServerThreadReview(
      detail: detail,
      goal: goal,
      goalUnavailable: goalUnavailable,
      turns: List<CodexAppServerTurnReview>.unmodifiable(turnReviews),
      timelineUnavailable: timelineUnavailable,
    );
  }
```

- [ ] **Step 7: Update fake repository in tests**

Add this method to `FakeCodexAppServerRepository` in `mobile/test/codex_app_server_view_model_test.dart`:

```dart
  @override
  Future<CodexAppServerThreadReview> loadThreadReview(
    String workspaceId,
    String threadId, {
    int turnLimit = 20,
    int itemLimit = 20,
  }) async {
    final detail = await readThread(workspaceId, threadId);
    return CodexAppServerThreadReview(
      detail: detail,
      goal: const CodexAppServerGoalSummary(
        id: 'goal_1',
        objective: 'Ship the auth fix',
        status: 'active',
        updatedAt: null,
        raw: {},
      ),
      goalUnavailable: false,
      turns: const <CodexAppServerTurnReview>[
        CodexAppServerTurnReview(
          turn: CodexAppServerTurnSummary(
            id: 'turn_1',
            status: 'completed',
            createdAt: null,
            completedAt: null,
            raw: {},
          ),
          items: <CodexAppServerItemSummary>[
            CodexAppServerItemSummary(
              id: 'item_1',
              turnId: 'turn_1',
              type: 'agent_message',
              status: 'completed',
              createdAt: null,
              raw: {},
            ),
          ],
          itemsUnavailable: false,
        ),
      ],
      timelineUnavailable: false,
    );
  }
```

- [ ] **Step 8: Run tests and verify pass**

Run:

```powershell
cd mobile
flutter test --no-pub test\codex_app_server_models_test.dart
```

Expected: all tests in `codex_app_server_models_test.dart` pass.

- [ ] **Step 9: Commit**

```bash
git add mobile/lib/src/domain/models/codex_app_server_models.dart mobile/lib/src/data/models/codex_app_server_models.dart mobile/lib/src/domain/repositories/codex_app_server_repository.dart mobile/lib/src/data/repositories/codex_app_server_repository.dart mobile/test/codex_app_server_models_test.dart mobile/test/codex_app_server_view_model_test.dart
git commit -m "Add Codex app-server thread review data projection" -m "Constraint: Compose existing daemon routes and keep mobile off raw app-server JSON-RPC." -m "Confidence: high" -m "Scope-risk: narrow" -m "Tested: cd mobile && flutter test --no-pub test\\codex_app_server_models_test.dart"
```

---

### Task 2: Expand Codex ViewModel State And Commands

**Files:**
- Modify: `mobile/lib/src/ui/features/codex_app_server/view_models/codex_app_server_view_model.dart`
- Test: `mobile/test/codex_app_server_view_model_test.dart`

- [ ] **Step 1: Write failing ViewModel tests**

Add these tests before the widget test in `mobile/test/codex_app_server_view_model_test.dart`:

```dart
  test('CodexAppServerViewModel derives overview metrics and ready status',
      () async {
    final viewModel = CodexAppServerViewModel(
      repository: FakeCodexAppServerRepository(
        capabilities: const CodexAppServerCapabilities(
          raw: {},
          routes: [
            {
              'method': 'thread/list',
              'readOnly': true,
              'requiresApproval': false,
              'risk': 'read',
            },
            {
              'method': 'fs/writeFile',
              'readOnly': false,
              'requiresApproval': true,
              'risk': 'write',
            },
            {
              'method': 'command/exec',
              'readOnly': false,
              'requiresApproval': true,
              'risk': 'process',
            },
          ],
          totalMethods: 3,
        ),
        threads: const [
          CodexAppServerThreadSummary(
            id: 'thread_1',
            title: 'Fix auth',
            workspacePath: 'D:/Repo',
            archived: false,
            raw: {},
          ),
        ],
        discovery: const CodexAppServerDiscoverySnapshot(
          models: {
            'providers': [
              {'id': 'openai'}
            ]
          },
          mcpServers: {'servers': []},
          skills: {'skills': []},
          plugins: {'plugins': []},
          apps: {'apps': []},
          config: {'config': <String, Object?>{}},
        ),
      ),
    );
    addTearDown(viewModel.dispose);

    await viewModel.load(workspaceId: 'workspace_1');

    expect(viewModel.state.mode, CodexAppServerPageMode.overview);
    expect(viewModel.state.overviewStatus, CodexAppServerOverviewStatus.ready);
    expect(viewModel.state.threadCount, 1);
    expect(viewModel.state.resourceCount, 2);
    expect(viewModel.state.guardedRouteCount, 2);
    expect(viewModel.state.approvalRequiredRouteCount, 2);
  });

  test('CodexAppServerViewModel opens thread detail and returns to overview',
      () async {
    final viewModel = CodexAppServerViewModel(
      repository: FakeCodexAppServerRepository(
        capabilities: const CodexAppServerCapabilities(
          raw: {},
          routes: [],
          totalMethods: 1,
        ),
        threads: const [
          CodexAppServerThreadSummary(
            id: 'thread_1',
            title: 'Fix auth',
            workspacePath: 'D:/Repo',
            archived: false,
            raw: {},
          ),
        ],
      ),
    );
    addTearDown(viewModel.dispose);

    await viewModel.load(workspaceId: 'workspace_1');
    await viewModel.openThread(workspaceId: 'workspace_1', threadId: 'thread_1');

    expect(viewModel.state.mode, CodexAppServerPageMode.threadDetail);
    expect(viewModel.state.selectedThreadReview?.detail.thread.id, 'thread_1');
    expect(viewModel.state.threadReviewLoading, false);
    expect(viewModel.state.threadReviewError, isNull);

    viewModel.returnToOverview();

    expect(viewModel.state.mode, CodexAppServerPageMode.overview);
    expect(viewModel.state.selectedThreadReview, isNull);
  });
```

Add this failure degradation test:

```dart
  test('CodexAppServerViewModel keeps overview when thread detail fails',
      () async {
    final repository = FakeCodexAppServerRepository(
      capabilities: const CodexAppServerCapabilities(
        raw: {},
        routes: [],
        totalMethods: 1,
      ),
      threads: const [
        CodexAppServerThreadSummary(
          id: 'thread_1',
          title: 'Fix auth',
          workspacePath: 'D:/Repo',
          archived: false,
          raw: {},
        ),
      ],
    )..failReview = true;
    final viewModel = CodexAppServerViewModel(repository: repository);
    addTearDown(viewModel.dispose);

    await viewModel.load(workspaceId: 'workspace_1');
    await viewModel.openThread(workspaceId: 'workspace_1', threadId: 'thread_1');

    expect(viewModel.state.mode, CodexAppServerPageMode.threadDetail);
    expect(viewModel.state.selectedThreadReview, isNull);
    expect(viewModel.state.threadReviewError, isNotNull);
    expect(viewModel.state.threads.single.id, 'thread_1');
  });
```

- [ ] **Step 2: Run ViewModel tests and verify failure**

Run:

```powershell
cd mobile
flutter test --no-pub test\codex_app_server_view_model_test.dart --plain-name "CodexAppServerViewModel derives overview metrics and ready status"
```

Expected: fails because `CodexAppServerPageMode`, `CodexAppServerOverviewStatus`, derived count getters, and `openThread` do not exist.

- [ ] **Step 3: Replace state shape**

Modify `mobile/lib/src/ui/features/codex_app_server/view_models/codex_app_server_view_model.dart` by adding enums above `CodexAppServerState`:

```dart
enum CodexAppServerPageMode { overview, threadDetail }

enum CodexAppServerOverviewStatus { syncing, ready, busy, unavailable }

enum CodexAppServerErrorKind { busy, unauthorized, unavailable, unknown }
```

Extend `CodexAppServerState` constructor and fields:

```dart
    this.mode = CodexAppServerPageMode.overview,
    this.errorKind,
    this.threadReviewLoading = false,
    this.threadReviewError,
    this.selectedThreadId,
    this.selectedThreadReview,
```

Add fields:

```dart
  final CodexAppServerPageMode mode;
  final CodexAppServerErrorKind? errorKind;
  final bool threadReviewLoading;
  final String? threadReviewError;
  final String? selectedThreadId;
  final CodexAppServerThreadReview? selectedThreadReview;
```

Add derived getters in `CodexAppServerState`:

```dart
  CodexAppServerOverviewStatus get overviewStatus {
    if (loading) return CodexAppServerOverviewStatus.syncing;
    if (error != null) {
      if (errorKind == CodexAppServerErrorKind.busy) {
        return CodexAppServerOverviewStatus.busy;
      }
      return CodexAppServerOverviewStatus.unavailable;
    }
    if (capabilities != null) return CodexAppServerOverviewStatus.ready;
    return CodexAppServerOverviewStatus.unavailable;
  }

  int get threadCount => threads.length;

  int get resourceCount {
    final discovery = this.discovery;
    if (discovery == null) return 0;
    return _count(discovery.models['providers']) +
        _count(discovery.mcpServers['servers']) +
        _count(discovery.skills['skills']) +
        _count(discovery.plugins['plugins']) +
        _count(discovery.apps['apps']) +
        (discovery.config.isEmpty ? 0 : 1);
  }

  int get readOnlyRouteCount => _uniqueRouteCount((route) {
        final readOnly = route['readOnly'];
        final requiresApproval = route['requiresApproval'];
        final risk = route['risk']?.toString();
        return readOnly == true ||
            (requiresApproval != true &&
                const {'none', 'read'}.contains(risk));
      });

  int get guardedRouteCount => _uniqueRouteCount((route) {
        final readOnly = route['readOnly'];
        final requiresApproval = route['requiresApproval'];
        final risk = route['risk']?.toString();
        return readOnly != true ||
            requiresApproval == true ||
            !const {'none', 'read'}.contains(risk);
      });

  int get approvalRequiredRouteCount => _uniqueRouteCount((route) {
        return route['requiresApproval'] == true;
      });

  int _uniqueRouteCount(bool Function(Map<String, Object?> route) include) {
    final routes = capabilities?.routes ?? const <Map<String, Object?>>[];
    final methods = <String>{};
    for (final route in routes) {
      if (!include(route)) continue;
      final method = route['method']?.toString();
      if (method != null && method.isNotEmpty) methods.add(method);
    }
    return methods.length;
  }
```

Add helper below the state class:

```dart
int _count(Object? value) => value is List ? value.length : 0;
```

- [ ] **Step 4: Update `copyWith`**

Replace `copyWith` with explicit clear semantics:

```dart
  CodexAppServerState copyWith({
    bool? loading,
    String? error,
    bool clearError = false,
    CodexAppServerErrorKind? errorKind,
    bool clearErrorKind = false,
    String? workspaceId,
    CodexAppServerCapabilities? capabilities,
    CodexAppServerDiscoverySnapshot? discovery,
    List<CodexAppServerThreadSummary>? threads,
    CodexAppServerPageMode? mode,
    bool? threadReviewLoading,
    String? threadReviewError,
    bool clearThreadReviewError = false,
    String? selectedThreadId,
    bool clearSelectedThreadId = false,
    CodexAppServerThreadReview? selectedThreadReview,
    bool clearSelectedThreadReview = false,
  }) {
    return CodexAppServerState(
      loading: loading ?? this.loading,
      error: clearError ? null : error ?? this.error,
      errorKind: clearErrorKind ? null : errorKind ?? this.errorKind,
      workspaceId: workspaceId ?? this.workspaceId,
      capabilities: capabilities ?? this.capabilities,
      discovery: discovery ?? this.discovery,
      threads: threads ?? this.threads,
      mode: mode ?? this.mode,
      threadReviewLoading: threadReviewLoading ?? this.threadReviewLoading,
      threadReviewError: clearThreadReviewError
          ? null
          : threadReviewError ?? this.threadReviewError,
      selectedThreadId:
          clearSelectedThreadId ? null : selectedThreadId ?? this.selectedThreadId,
      selectedThreadReview: clearSelectedThreadReview
          ? null
          : selectedThreadReview ?? this.selectedThreadReview,
    );
  }
```

- [ ] **Step 5: Implement ViewModel commands**

Update `load` catch to classify errors:

```dart
      _state = CodexAppServerState(
        workspaceId: workspaceId,
        error: '$error',
        errorKind: _classifyError(error),
      );
```

Add methods to `CodexAppServerViewModel`:

```dart
  Future<void> openThread({
    required String workspaceId,
    required String threadId,
  }) async {
    final generation = ++_loadGeneration;
    if (_disposed) return;
    _state = _state.copyWith(
      mode: CodexAppServerPageMode.threadDetail,
      selectedThreadId: threadId,
      clearSelectedThreadReview: true,
      threadReviewLoading: true,
      clearThreadReviewError: true,
    );
    _notifyIfAlive();
    try {
      final review = await _repository.loadThreadReview(workspaceId, threadId);
      if (_disposed || generation != _loadGeneration) return;
      _state = _state.copyWith(
        threadReviewLoading: false,
        selectedThreadReview: review,
        clearThreadReviewError: true,
      );
      _notifyIfAlive();
    } catch (error) {
      if (_disposed || generation != _loadGeneration) return;
      _state = _state.copyWith(
        threadReviewLoading: false,
        threadReviewError: '$error',
        clearSelectedThreadReview: true,
      );
      _notifyIfAlive();
    }
  }

  void returnToOverview() {
    _loadGeneration++;
    _state = _state.copyWith(
      mode: CodexAppServerPageMode.overview,
      threadReviewLoading: false,
      clearThreadReviewError: true,
      clearSelectedThreadId: true,
      clearSelectedThreadReview: true,
    );
    _notifyIfAlive();
  }
```

Add classifier below the ViewModel:

```dart
CodexAppServerErrorKind _classifyError(Object error) {
  final message = '$error'.toLowerCase();
  if (message.contains('maximum codex app-server process limit') ||
      message.contains('pool is busy') ||
      message.contains('busy')) {
    return CodexAppServerErrorKind.busy;
  }
  if (message.contains('401') ||
      message.contains('403') ||
      message.contains('unauthorized') ||
      message.contains('forbidden')) {
    return CodexAppServerErrorKind.unauthorized;
  }
  if (message.contains('disabled') ||
      message.contains('unavailable') ||
      message.contains('not configured')) {
    return CodexAppServerErrorKind.unavailable;
  }
  return CodexAppServerErrorKind.unknown;
}
```

- [ ] **Step 6: Update fake repository controls**

In `FakeCodexAppServerRepository`, add:

```dart
  bool failReview = false;
```

Then update its `loadThreadReview` method from Task 1:

```dart
    if (failReview) throw StateError('review failed');
```

- [ ] **Step 7: Run ViewModel tests and verify pass**

Run:

```powershell
cd mobile
flutter test --no-pub test\codex_app_server_view_model_test.dart
```

Expected: ViewModel tests pass. The old widget test still fails until UI tasks replace the three-tab page.

- [ ] **Step 8: Commit**

```bash
git add mobile/lib/src/ui/features/codex_app_server/view_models/codex_app_server_view_model.dart mobile/test/codex_app_server_view_model_test.dart
git commit -m "Model Codex console view state explicitly" -m "Constraint: Keep thread detail feature-local and generation-guarded." -m "Confidence: high" -m "Scope-risk: narrow" -m "Tested: cd mobile && flutter test --no-pub test\\codex_app_server_view_model_test.dart"
```

---

### Task 3: Localize The Codex Console Surface

**Files:**
- Modify: `mobile/lib/l10n/app_en.arb`
- Modify: `mobile/lib/l10n/app_zh.arb`
- Modify generated: `mobile/lib/l10n/app_localizations.dart`
- Modify generated: `mobile/lib/l10n/app_localizations_en.dart`
- Modify generated: `mobile/lib/l10n/app_localizations_zh.dart`
- Modify: `mobile/lib/src/ui/main_tab_items.dart`

- [ ] **Step 1: Add ARB keys**

Add these keys to `mobile/lib/l10n/app_en.arb` near the existing navigation and workbench keys:

```json
  "navCodex": "Codex",
  "codexConsoleTitle": "Codex",
  "codexConsoleSubtitleNoWorkspace": "No workspace selected",
  "codexStatusSyncing": "syncing",
  "codexStatusReady": "ready",
  "codexStatusBusy": "busy",
  "codexStatusUnavailable": "unavailable",
  "codexNoWorkspaceTitle": "Select a workspace",
  "codexNoWorkspaceDetail": "Codex sessions and runtime resources are scoped to the active authorized workspace.",
  "codexStatusThreadsMetric": "Threads",
  "codexStatusResourcesMetric": "Resources",
  "codexStatusGuardedMetric": "Guarded",
  "codexRecentSessionsTitle": "Recent sessions",
  "codexRecentSessionsScoped": "Workspace scoped",
  "codexNoSessionsTitle": "No Codex sessions yet",
  "codexNoSessionsDetail": "App-server thread history will appear here after Codex sessions run in this workspace.",
  "codexRuntimeResourcesTitle": "Runtime resources",
  "codexSafetyBoundaryTitle": "Safety boundary",
  "codexReadOnlyRoutes": "Read-only",
  "codexGuardedRoutes": "Guarded",
  "codexApprovalRequiredRoutes": "Needs approval",
  "codexDaemonEnforced": "Daemon enforced",
  "codexThreadOpen": "Open",
  "codexThreadArchived": "Archived",
  "codexThreadDetailTitleFallback": "Thread detail",
  "codexThreadWorkspaceLabel": "Workspace",
  "codexThreadIdLabel": "Thread ID",
  "codexThreadGoalLabel": "Goal",
  "codexThreadUpdatedLabel": "Updated",
  "codexNotProvided": "Not provided",
  "codexGoalUnavailable": "Goal unavailable",
  "codexTimelineTitle": "Turns and items",
  "codexTimelineEmpty": "No reviewable events yet",
  "codexTimelineError": "Timeline could not be loaded.",
  "codexThreadReviewLoading": "Loading thread...",
  "codexThreadReviewError": "Thread could not be loaded.",
  "codexOverviewLoadFailed": "Codex runtime unavailable.",
  "codexOverviewBusy": "Codex runtime busy.",
  "codexResourceModels": "Models",
  "codexResourceModelsDetail": "Configured model providers",
  "codexResourceMcp": "MCP Servers",
  "codexResourceMcpDetail": "Connected tool servers",
  "codexResourceSkills": "Skills",
  "codexResourceSkillsDetail": "Codex skill entries",
  "codexResourcePlugins": "Plugins",
  "codexResourcePluginsDetail": "Installed plugin surfaces",
  "codexResourceApps": "Apps",
  "codexResourceAppsDetail": "Registered app integrations",
  "codexResourceConfig": "Config",
  "codexResourceConfigDetail": "Resolved app-server config",
  "codexTurnTypeFallback": "Turn",
  "codexItemTypeFallback": "Item"
```

Add matching keys to `mobile/lib/l10n/app_zh.arb`:

```json
  "navCodex": "Codex",
  "codexConsoleTitle": "Codex",
  "codexConsoleSubtitleNoWorkspace": "未选择工作区",
  "codexStatusSyncing": "同步中",
  "codexStatusReady": "就绪",
  "codexStatusBusy": "繁忙",
  "codexStatusUnavailable": "不可用",
  "codexNoWorkspaceTitle": "选择工作区",
  "codexNoWorkspaceDetail": "Codex 会话和运行资源仅显示当前授权工作区内的数据。",
  "codexStatusThreadsMetric": "会话",
  "codexStatusResourcesMetric": "资源",
  "codexStatusGuardedMetric": "守护",
  "codexRecentSessionsTitle": "最近会话",
  "codexRecentSessionsScoped": "当前工作区",
  "codexNoSessionsTitle": "暂无 Codex 会话",
  "codexNoSessionsDetail": "此工作区运行 Codex app-server 会话后，线程历史会显示在这里。",
  "codexRuntimeResourcesTitle": "运行资源",
  "codexSafetyBoundaryTitle": "安全边界",
  "codexReadOnlyRoutes": "只读",
  "codexGuardedRoutes": "守护",
  "codexApprovalRequiredRoutes": "需要批准",
  "codexDaemonEnforced": "由桌面端执行",
  "codexThreadOpen": "打开",
  "codexThreadArchived": "已归档",
  "codexThreadDetailTitleFallback": "线程详情",
  "codexThreadWorkspaceLabel": "工作区",
  "codexThreadIdLabel": "线程 ID",
  "codexThreadGoalLabel": "目标",
  "codexThreadUpdatedLabel": "更新时间",
  "codexNotProvided": "未提供",
  "codexGoalUnavailable": "目标暂不可用",
  "codexTimelineTitle": "轮次和事件",
  "codexTimelineEmpty": "暂无可审阅事件",
  "codexTimelineError": "时间线加载失败。",
  "codexThreadReviewLoading": "正在加载线程...",
  "codexThreadReviewError": "线程加载失败。",
  "codexOverviewLoadFailed": "Codex 运行时不可用。",
  "codexOverviewBusy": "Codex 运行时繁忙。",
  "codexResourceModels": "模型",
  "codexResourceModelsDetail": "已配置的模型提供方",
  "codexResourceMcp": "MCP 服务器",
  "codexResourceMcpDetail": "已连接的工具服务器",
  "codexResourceSkills": "技能",
  "codexResourceSkillsDetail": "Codex 技能条目",
  "codexResourcePlugins": "插件",
  "codexResourcePluginsDetail": "已安装的插件入口",
  "codexResourceApps": "应用",
  "codexResourceAppsDetail": "已注册的应用集成",
  "codexResourceConfig": "配置",
  "codexResourceConfigDetail": "已解析的 app-server 配置",
  "codexTurnTypeFallback": "轮次",
  "codexItemTypeFallback": "事件"
```

- [ ] **Step 2: Generate localization files**

Run:

```powershell
cd mobile
flutter gen-l10n
```

Expected: generated localization files include getters for every `codex...` key and `navCodex`.

- [ ] **Step 3: Localize bottom navigation**

Modify `mobile/lib/src/ui/main_tab_items.dart`:

```dart
List<NavSpec> mainTabItems(AppLocalizations l10n) => [
      NavSpec(Icons.terminal_rounded, l10n.navCoding),
      NavSpec(Icons.api_rounded, l10n.navCodex),
      NavSpec(Icons.settings_rounded, l10n.navSettings),
    ];
```

- [ ] **Step 4: Run localization-aware smoke test**

Run:

```powershell
cd mobile
flutter test --no-pub test\widget_test.dart --plain-name "uses supported locale resolution for Chinese"
```

Expected: PASS. If that exact plain-name does not exist in the current branch, run:

```powershell
cd mobile
flutter test --no-pub test\widget_test.dart --plain-name "settings tab localizes"
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/l10n/app_en.arb mobile/lib/l10n/app_zh.arb mobile/lib/l10n/app_localizations.dart mobile/lib/l10n/app_localizations_en.dart mobile/lib/l10n/app_localizations_zh.dart mobile/lib/src/ui/main_tab_items.dart
git commit -m "Localize the Codex console vocabulary" -m "Constraint: New Codex tab copy must not be hard-coded in widgets." -m "Confidence: high" -m "Scope-risk: narrow" -m "Tested: cd mobile && flutter gen-l10n"
```

---

### Task 4: Build The Localized Codex Overview

**Files:**
- Create: `mobile/lib/src/ui/features/codex_app_server/widgets/codex_app_server_overview_view.dart`
- Modify: `mobile/lib/src/ui/features/codex_app_server/widgets/codex_app_server_ui.dart`
- Modify: `mobile/lib/src/ui/features/codex_app_server/views/codex_app_server_page.dart`
- Test: `mobile/test/codex_app_server_view_model_test.dart`

- [ ] **Step 1: Replace old widget test expectations**

Replace the old widget test named `Codex app-server page renders history and discovery tabs` with:

```dart
  testWidgets('Codex page renders localized overview and opens thread detail',
      (tester) async {
    final viewModel = CodexAppServerViewModel(
      repository: FakeCodexAppServerRepository(
        capabilities: const CodexAppServerCapabilities(
          raw: {},
          routes: [
            {
              'method': 'thread/list',
              'readOnly': true,
              'requiresApproval': false,
              'risk': 'read',
            },
            {
              'method': 'fs/writeFile',
              'readOnly': false,
              'requiresApproval': true,
              'risk': 'write',
            },
          ],
          totalMethods: 2,
        ),
        threads: const [
          CodexAppServerThreadSummary(
            id: 'thread_1',
            title: 'Fix auth',
            workspacePath: 'D:/Repo',
            archived: false,
            raw: {},
          ),
        ],
        discovery: const CodexAppServerDiscoverySnapshot(
          models: {
            'providers': [
              {'id': 'openai'}
            ]
          },
          mcpServers: {'servers': []},
          skills: {'skills': []},
          plugins: {'plugins': []},
          apps: {'apps': []},
          config: {'config': <String, Object?>{}},
        ),
      ),
    );
    addTearDown(viewModel.dispose);

    await viewModel.load(workspaceId: 'workspace_1');
    await tester.pumpWidget(MaterialApp(
      supportedLocales: appSupportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
      home: CodexAppServerPage(
        viewModel: viewModel,
        workspace: const WorkspaceSummary(
          id: 'workspace_1',
          name: 'Repo',
          path: 'D:/Repo',
        ),
      ),
    ));

    expect(find.text('Codex'), findsWidgets);
    expect(find.text('Recent sessions'), findsOneWidget);
    expect(find.text('Runtime resources'), findsOneWidget);
    expect(find.text('Safety boundary'), findsOneWidget);
    expect(find.text('History'), findsNothing);
    expect(find.text('Discovery'), findsNothing);
    expect(find.text('Risk'), findsNothing);
    expect(find.text('Fix auth'), findsOneWidget);

    await tester.tap(find.text('Fix auth'));
    await tester.pumpAndSettle();

    expect(find.text('Thread ID'), findsOneWidget);
    expect(find.text('Ship the auth fix'), findsOneWidget);
  });
```

Add imports if missing:

```dart
import 'package:lan_ai_cli_control/l10n/app_localizations.dart';
import 'package:lan_ai_cli_control/src/app/app_localization.dart';
```

- [ ] **Step 2: Run widget test and verify failure**

Run:

```powershell
cd mobile
flutter test --no-pub test\codex_app_server_view_model_test.dart --plain-name "Codex page renders localized overview and opens thread detail"
```

Expected: fails because overview widgets do not exist and the page still renders internal tabs.

- [ ] **Step 3: Update shared UI primitives**

Modify `mobile/lib/src/ui/features/codex_app_server/widgets/codex_app_server_ui.dart` to remove private Codex color dominance and keep theme-aligned primitives:

```dart
const codexPanel = theme.panel;
const codexPanelHi = theme.panelHi;
const codexLine = theme.stroke;
const codexAccent = theme.purple2;
const codexSuccess = theme.green;
const codexWarning = theme.amber;
```

Keep `CodexSurface`, `CodexSectionHeader`, `CodexStatusPill`, and `CodexEmptyState`, but ensure display text is supplied by callers from `AppLocalizations`.

- [ ] **Step 4: Create overview widget**

Create `mobile/lib/src/ui/features/codex_app_server/widgets/codex_app_server_overview_view.dart` with this structure:

```dart
import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../../domain/models/codex_app_server_models.dart';
import '../../../../models/protocol.dart';
import '../../../core/theme/theme.dart' as theme;
import '../../../core/widgets/widgets.dart';
import '../view_models/codex_app_server_view_model.dart';
import 'codex_app_server_ui.dart';

class CodexAppServerOverviewView extends StatelessWidget {
  const CodexAppServerOverviewView({
    super.key,
    required this.state,
    required this.workspace,
    required this.onThreadTap,
  });

  final CodexAppServerState state;
  final WorkspaceSummary? workspace;
  final ValueChanged<CodexAppServerThreadSummary> onThreadTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final workspace = this.workspace;
    if (workspace == null) {
      return CodexEmptyState(
        icon: Icons.folder_open_rounded,
        title: l10n.codexNoWorkspaceTitle,
        detail: l10n.codexNoWorkspaceDetail,
      );
    }
    return PageScroll(
      children: [
        _StatusPanel(state: state),
        const SizedBox(height: 16),
        _RecentSessionsSection(
          state: state,
          onThreadTap: onThreadTap,
        ),
        const SizedBox(height: 16),
        _RuntimeResourcesSection(discovery: state.discovery),
        const SizedBox(height: 16),
        _SafetyBoundarySection(state: state),
      ],
    );
  }
}
```

Add private section widgets in the same file:

```dart
class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.state});

  final CodexAppServerState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CodexSurface(
      child: Row(
        children: [
          Expanded(
            child: _Metric(
              label: l10n.codexStatusThreadsMetric,
              value: '${state.threadCount}',
              color: theme.green,
            ),
          ),
          const _MetricDivider(),
          Expanded(
            child: _Metric(
              label: l10n.codexStatusResourcesMetric,
              value: '${state.resourceCount}',
              color: theme.purple2,
            ),
          ),
          const _MetricDivider(),
          Expanded(
            child: _Metric(
              label: l10n.codexStatusGuardedMetric,
              value: '${state.guardedRouteCount}',
              color: theme.amber,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentSessionsSection extends StatelessWidget {
  const _RecentSessionsSection({
    required this.state,
    required this.onThreadTap,
  });

  final CodexAppServerState state;
  final ValueChanged<CodexAppServerThreadSummary> onThreadTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (state.threads.isEmpty) {
      return CodexSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.codexNoSessionsTitle,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(l10n.codexNoSessionsDetail,
                style: const TextStyle(color: theme.muted, fontSize: 12)),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CodexSectionHeader(
          label: l10n.codexRecentSessionsTitle,
          trailing: l10n.codexRecentSessionsScoped,
        ),
        CodexSurface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var index = 0; index < state.threads.length; index++) ...[
                _ThreadRow(
                  thread: state.threads[index],
                  onTap: () => onThreadTap(state.threads[index]),
                ),
                if (index != state.threads.length - 1)
                  const Divider(height: 1, color: codexLine),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
```

Add compact resource and safety sections:

```dart
class _RuntimeResourcesSection extends StatelessWidget {
  const _RuntimeResourcesSection({required this.discovery});

  final CodexAppServerDiscoverySnapshot? discovery;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CodexSectionHeader(label: l10n.codexRuntimeResourcesTitle),
        CodexSurface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _ResourceRow(
                icon: Icons.auto_awesome_outlined,
                title: l10n.codexResourceModels,
                detail: l10n.codexResourceModelsDetail,
                count: _count(discovery?.models['providers']),
              ),
              const Divider(height: 1, color: codexLine),
              _ResourceRow(
                icon: Icons.hub_outlined,
                title: l10n.codexResourceMcp,
                detail: l10n.codexResourceMcpDetail,
                count: _count(discovery?.mcpServers['servers']),
              ),
              const Divider(height: 1, color: codexLine),
              _ResourceRow(
                icon: Icons.psychology_outlined,
                title: l10n.codexResourceSkills,
                detail: l10n.codexResourceSkillsDetail,
                count: _count(discovery?.skills['skills']),
              ),
              const Divider(height: 1, color: codexLine),
              _ResourceRow(
                icon: Icons.extension_outlined,
                title: l10n.codexResourcePlugins,
                detail: l10n.codexResourcePluginsDetail,
                count: _count(discovery?.plugins['plugins']),
              ),
              const Divider(height: 1, color: codexLine),
              _ResourceRow(
                icon: Icons.apps_outlined,
                title: l10n.codexResourceApps,
                detail: l10n.codexResourceAppsDetail,
                count: _count(discovery?.apps['apps']),
              ),
              const Divider(height: 1, color: codexLine),
              _ResourceRow(
                icon: Icons.tune_outlined,
                title: l10n.codexResourceConfig,
                detail: l10n.codexResourceConfigDetail,
                count: discovery?.config.isEmpty == false ? 1 : 0,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SafetyBoundarySection extends StatelessWidget {
  const _SafetyBoundarySection({required this.state});

  final CodexAppServerState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CodexSectionHeader(
          label: l10n.codexSafetyBoundaryTitle,
          trailing: l10n.codexDaemonEnforced,
        ),
        CodexSurface(
          child: Row(
            children: [
              Expanded(
                child: _Metric(
                  label: l10n.codexReadOnlyRoutes,
                  value: '${state.readOnlyRouteCount}',
                  color: theme.green,
                ),
              ),
              const _MetricDivider(),
              Expanded(
                child: _Metric(
                  label: l10n.codexGuardedRoutes,
                  value: '${state.guardedRouteCount}',
                  color: theme.amber,
                ),
              ),
              const _MetricDivider(),
              Expanded(
                child: _Metric(
                  label: l10n.codexApprovalRequiredRoutes,
                  value: '${state.approvalRequiredRouteCount}',
                  color: theme.purple2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
```

Add row helpers in the same file:

```dart
class _ThreadRow extends StatelessWidget {
  const _ThreadRow({required this.thread, required this.onTap});

  final CodexAppServerThreadSummary thread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(
              thread.archived
                  ? Icons.inventory_2_outlined
                  : Icons.chat_bubble_outline,
              color: thread.archived ? theme.faint : theme.green,
              size: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _threadTitle(thread),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _threadContext(thread),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: theme.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            CodexStatusPill(
              label:
                  thread.archived ? l10n.codexThreadArchived : l10n.codexThreadOpen,
              color: thread.archived ? theme.faint : theme.green,
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded,
                color: theme.faint, size: 20),
          ],
        ),
      ),
    );
  }
}

class _ResourceRow extends StatelessWidget {
  const _ResourceRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.count,
  });

  final IconData icon;
  final String title;
  final String detail;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: theme.purple2, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: theme.muted, fontSize: 12)),
              ],
            ),
          ),
          Text('$count',
              style: const TextStyle(
                  color: theme.text, fontSize: 13, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: TextStyle(
                color: color, fontSize: 20, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: theme.muted, fontSize: 11)),
      ],
    );
  }
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 38, color: codexLine);
  }
}

int _count(Object? value) => value is List ? value.length : 0;

String _threadTitle(CodexAppServerThreadSummary thread) {
  final title = thread.title.trim();
  if (title.isNotEmpty) return title;
  return _shortId(thread.id);
}

String _threadContext(CodexAppServerThreadSummary thread) {
  final path = thread.workspacePath?.trim();
  if (path != null && path.isNotEmpty) return path;
  return _shortId(thread.id);
}

String _shortId(String value) {
  if (value.length <= 24) return value;
  return '${value.substring(0, 12)}...${value.substring(value.length - 8)}';
}
```

- [ ] **Step 5: Update page to use overview**

In `mobile/lib/src/ui/features/codex_app_server/views/codex_app_server_page.dart`, remove the internal `DefaultTabController`, `_CodexAppServerTabs`, and imports for old tab widgets. Use:

```dart
import '../../../../../l10n/app_localizations.dart';
import '../../../core/theme/theme.dart' as theme;
import '../widgets/codex_app_server_overview_view.dart';
import '../widgets/codex_app_server_thread_detail_view.dart';
```

Inside the `ListenableBuilder`, build:

```dart
        final l10n = AppLocalizations.of(context);
        final state = viewModel.state;
        final workspace = this.workspace;
        final body = state.mode == CodexAppServerPageMode.threadDetail
            ? CodexAppServerThreadDetailView(
                state: state,
                workspace: workspace,
                onBack: viewModel.returnToOverview,
              )
            : CodexAppServerOverviewView(
                state: state,
                workspace: workspace,
                onThreadTap: (thread) {
                  final workspaceId = workspace?.id;
                  if (workspaceId == null || workspaceId.isEmpty) return;
                  viewModel.openThread(
                    workspaceId: workspaceId,
                    threadId: thread.id,
                  );
                },
              );
        return Column(
          children: [
            TopBar(
              title: l10n.codexConsoleTitle,
              subtitle: workspace?.name ?? l10n.codexConsoleSubtitleNoWorkspace,
              statusLabel: _statusLabel(l10n, state.overviewStatus),
              action: state.mode == CodexAppServerPageMode.threadDetail
                  ? l10n.runDetailTabOverview
                  : null,
            ),
            if (state.loading) const LinearProgressIndicator(minHeight: 2),
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: _CodexAppServerError(
                  message: state.errorKind == CodexAppServerErrorKind.busy
                      ? l10n.codexOverviewBusy
                      : l10n.codexOverviewLoadFailed,
                ),
              ),
            Expanded(child: body),
          ],
        );
```

Add helper:

```dart
String _statusLabel(
  AppLocalizations l10n,
  CodexAppServerOverviewStatus status,
) {
  switch (status) {
    case CodexAppServerOverviewStatus.syncing:
      return l10n.codexStatusSyncing;
    case CodexAppServerOverviewStatus.ready:
      return l10n.codexStatusReady;
    case CodexAppServerOverviewStatus.busy:
      return l10n.codexStatusBusy;
    case CodexAppServerOverviewStatus.unavailable:
      return l10n.codexStatusUnavailable;
  }
}
```

Keep `_CodexAppServerError`, but switch colors to `theme.red` and `theme.stroke`.

- [ ] **Step 6: Run the updated widget test**

Run:

```powershell
cd mobile
flutter test --no-pub test\codex_app_server_view_model_test.dart --plain-name "Codex page renders localized overview and opens thread detail"
```

Expected: fails only because `CodexAppServerThreadDetailView` is not implemented yet. If it fails on overview text, fix the l10n keys or overview widget before moving on.

- [ ] **Step 7: Commit**

Commit after Task 5, not here, because this task depends on the thread detail widget for the widget test to pass.

---

### Task 5: Build Same-Page Thread Detail View

**Files:**
- Create: `mobile/lib/src/ui/features/codex_app_server/widgets/codex_app_server_thread_detail_view.dart`
- Modify: `mobile/test/codex_app_server_view_model_test.dart`

- [ ] **Step 1: Add detail return test**

Add to the widget test after the detail assertions:

```dart
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Recent sessions'), findsOneWidget);
    expect(find.text('Thread ID'), findsNothing);
```

- [ ] **Step 2: Create thread detail widget**

Create `mobile/lib/src/ui/features/codex_app_server/widgets/codex_app_server_thread_detail_view.dart`:

```dart
import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../../models/protocol.dart';
import '../../../core/theme/theme.dart' as theme;
import '../../../core/widgets/widgets.dart';
import '../view_models/codex_app_server_view_model.dart';
import 'codex_app_server_ui.dart';

class CodexAppServerThreadDetailView extends StatelessWidget {
  const CodexAppServerThreadDetailView({
    super.key,
    required this.state,
    required this.workspace,
    required this.onBack,
  });

  final CodexAppServerState state;
  final WorkspaceSummary? workspace;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (state.threadReviewLoading) {
      return Center(child: Text(l10n.codexThreadReviewLoading));
    }
    if (state.threadReviewError != null || state.selectedThreadReview == null) {
      return PageScroll(
        children: [
          _DetailHeader(
            title: l10n.codexThreadDetailTitleFallback,
            onBack: onBack,
          ),
          const SizedBox(height: 12),
          CodexSurface(
            child: Text(
              l10n.codexThreadReviewError,
              style: const TextStyle(color: theme.muted, fontSize: 13),
            ),
          ),
        ],
      );
    }
    final review = state.selectedThreadReview!;
    final thread = review.detail.thread;
    final title = thread.title.trim().isEmpty
        ? _shortId(thread.id)
        : thread.title.trim();
    return PageScroll(
      children: [
        _DetailHeader(title: title, onBack: onBack),
        const SizedBox(height: 12),
        _SummaryPanel(
          review: review,
          workspace: workspace,
        ),
        const SizedBox(height: 16),
        _TimelinePanel(review: review),
      ],
    );
  }
}
```

Add detail helpers:

```dart
class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        InkWell(
          onTap: onBack,
          borderRadius: BorderRadius.circular(11),
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.panelHi,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: theme.stroke),
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                color: theme.muted, size: 16),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({required this.review, required this.workspace});

  final CodexAppServerThreadReview review;
  final WorkspaceSummary? workspace;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final thread = review.detail.thread;
    final goal = review.goal?.objective.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CodexSectionHeader(label: l10n.codexThreadDetailTitleFallback),
        CodexSurface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _SummaryRow(
                label: l10n.codexThreadWorkspaceLabel,
                value: workspace?.name ?? thread.workspacePath ?? l10n.codexNotProvided,
              ),
              const Divider(height: 1, color: codexLine),
              _SummaryRow(
                label: l10n.codexThreadIdLabel,
                value: thread.id,
              ),
              const Divider(height: 1, color: codexLine),
              _SummaryRow(
                label: l10n.codexThreadGoalLabel,
                value: review.goalUnavailable
                    ? l10n.codexGoalUnavailable
                    : goal == null || goal.isEmpty
                        ? l10n.codexNotProvided
                        : goal,
              ),
              const Divider(height: 1, color: codexLine),
              _SummaryRow(
                label: l10n.codexThreadUpdatedLabel,
                value: _threadUpdatedAt(thread) ?? l10n.codexNotProvided,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(label,
                style: const TextStyle(color: theme.muted, fontSize: 12)),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
```

Add timeline helpers:

```dart
class _TimelinePanel extends StatelessWidget {
  const _TimelinePanel({required this.review});

  final CodexAppServerThreadReview review;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (review.turns.isEmpty && !review.timelineUnavailable) {
      return CodexSurface(
        child: Text(
          l10n.codexTimelineEmpty,
          style: const TextStyle(color: theme.muted, fontSize: 13),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CodexSectionHeader(label: l10n.codexTimelineTitle),
        if (review.timelineUnavailable)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: CodexSurface(
              child: Text(
                l10n.codexTimelineError,
                style: const TextStyle(color: theme.amber, fontSize: 13),
              ),
            ),
          ),
        CodexSurface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var index = 0; index < review.turns.length; index++) ...[
                _TurnReviewRow(turnReview: review.turns[index]),
                if (index != review.turns.length - 1)
                  const Divider(height: 1, color: codexLine),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _TurnReviewRow extends StatelessWidget {
  const _TurnReviewRow({required this.turnReview});

  final CodexAppServerTurnReview turnReview;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final turn = turnReview.turn;
    final firstItem =
        turnReview.items.isEmpty ? null : turnReview.items.first.type.trim();
    final title = firstItem == null || firstItem.isEmpty
        ? l10n.codexTurnTypeFallback
        : firstItem;
    final status = turn.status.trim().isEmpty ? l10n.codexNotProvided : turn.status;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.format_list_bulleted_rounded,
              color: theme.purple2, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  '${turn.id} · $status · ${turnReview.items.length} ${l10n.codexItemTypeFallback}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: theme.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String? _threadUpdatedAt(CodexAppServerThreadSummary thread) {
  final value = thread.raw['updatedAt']?.toString().trim();
  if (value == null || value.isEmpty) return null;
  return value;
}

String _shortId(String value) {
  if (value.length <= 24) return value;
  return '${value.substring(0, 12)}...${value.substring(value.length - 8)}';
}
```

- [ ] **Step 3: Run widget test and verify pass**

Run:

```powershell
cd mobile
flutter test --no-pub test\codex_app_server_view_model_test.dart --plain-name "Codex page renders localized overview and opens thread detail"
```

Expected: PASS.

- [ ] **Step 4: Commit overview and detail**

```bash
git add mobile/lib/src/ui/features/codex_app_server/views/codex_app_server_page.dart mobile/lib/src/ui/features/codex_app_server/widgets/codex_app_server_ui.dart mobile/lib/src/ui/features/codex_app_server/widgets/codex_app_server_overview_view.dart mobile/lib/src/ui/features/codex_app_server/widgets/codex_app_server_thread_detail_view.dart mobile/test/codex_app_server_view_model_test.dart
git commit -m "Replace Codex diagnostics tabs with a console overview" -m "Constraint: Keep the first Codex console surface read-only and localized." -m "Confidence: medium" -m "Scope-risk: moderate" -m "Tested: cd mobile && flutter test --no-pub test\\codex_app_server_view_model_test.dart --plain-name \"Codex page renders localized overview and opens thread detail\""
```

---

### Task 6: Wire Bottom-Tab Lifecycle And Remove Dead Tab Widgets

**Files:**
- Modify: `mobile/lib/src/ui/main/connected_main_shell.dart`
- Delete if unused:
  - `mobile/lib/src/ui/features/codex_app_server/widgets/codex_app_server_history_view.dart`
  - `mobile/lib/src/ui/features/codex_app_server/widgets/codex_app_server_discovery_view.dart`
  - `mobile/lib/src/ui/features/codex_app_server/widgets/codex_app_server_risk_view.dart`
- Test: `mobile/test/codex_app_server_view_model_test.dart`

- [ ] **Step 1: Add ViewModel reset test**

Add this unit test to `mobile/test/codex_app_server_view_model_test.dart`:

```dart
  test('CodexAppServerViewModel resets detail state for tab exit', () async {
    final viewModel = CodexAppServerViewModel(
      repository: FakeCodexAppServerRepository(
        capabilities: const CodexAppServerCapabilities(
          raw: {},
          routes: [],
          totalMethods: 1,
        ),
        threads: const [
          CodexAppServerThreadSummary(
            id: 'thread_1',
            title: 'Fix auth',
            workspacePath: 'D:/Repo',
            archived: false,
            raw: {},
          ),
        ],
      ),
    );
    addTearDown(viewModel.dispose);

    await viewModel.load(workspaceId: 'workspace_1');
    await viewModel.openThread(workspaceId: 'workspace_1', threadId: 'thread_1');
    viewModel.returnToOverview();

    expect(viewModel.state.mode, CodexAppServerPageMode.overview);
    expect(viewModel.state.selectedThreadReview, isNull);
    expect(viewModel.state.threadReviewLoading, false);
  });
```

This test uses the existing `returnToOverview` method as the tab-exit reset command.

- [ ] **Step 2: Run test and verify pass**

Run:

```powershell
cd mobile
flutter test --no-pub test\codex_app_server_view_model_test.dart --plain-name "CodexAppServerViewModel resets detail state for tab exit"
```

Expected: PASS from Task 2 implementation.

- [ ] **Step 3: Reset detail state when leaving Codex tab**

Modify `mobile/lib/src/ui/main/connected_main_shell.dart`.

Before the `return PopScope` line in `build`, add:

```dart
    void handleBottomNavTap(int index) {
      if (index != MainShellViewModel.codexTabIndex) {
        codexAppServerViewModel.returnToOverview();
      }
      viewModel.selectTab(index);
    }
```

Change `BottomNav` from:

```dart
                onTap: viewModel.selectTab,
```

to:

```dart
                onTap: handleBottomNavTap,
```

- [ ] **Step 4: Delete old tab widgets**

After confirming no imports remain, delete:

```text
mobile/lib/src/ui/features/codex_app_server/widgets/codex_app_server_history_view.dart
mobile/lib/src/ui/features/codex_app_server/widgets/codex_app_server_discovery_view.dart
mobile/lib/src/ui/features/codex_app_server/widgets/codex_app_server_risk_view.dart
```

Run:

```powershell
rg -n "CodexAppServerHistoryView|CodexAppServerDiscoveryView|CodexAppServerRiskView|_CodexAppServerTabs|TabBarView|DefaultTabController" mobile\lib\src\ui\features\codex_app_server mobile\test
```

Expected: no results.

- [ ] **Step 5: Run targeted tests**

Run:

```powershell
cd mobile
flutter test --no-pub test\codex_app_server_view_model_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit lifecycle cleanup**

```bash
git add mobile/lib/src/ui/main/connected_main_shell.dart mobile/lib/src/ui/features/codex_app_server mobile/test/codex_app_server_view_model_test.dart
git commit -m "Reset Codex thread review when leaving the tab" -m "Constraint: Thread detail is feature-local state and must not persist as a global destination." -m "Confidence: high" -m "Scope-risk: narrow" -m "Tested: cd mobile && flutter test --no-pub test\\codex_app_server_view_model_test.dart"
```

---

### Task 7: Final Architecture, Analysis, And Test Verification

**Files:**
- Verify all modified mobile files.
- Optionally update `docs/project-knowledge/` only if implementation uncovers a durable architecture or troubleshooting lesson not already covered by the spec.

- [ ] **Step 1: Run architecture import check**

Run:

```powershell
cd mobile
dart run tool\check_architecture_imports.dart
```

Expected: PASS. Domain files must not import Flutter, data repositories must not import UI, and UI must consume repositories through ViewModels.

- [ ] **Step 2: Run analyzer**

Run:

```powershell
cd mobile
dart analyze
```

Expected: PASS with no new diagnostics.

- [ ] **Step 3: Run targeted Flutter tests**

Run:

```powershell
cd mobile
flutter test --no-pub test\codex_app_server_view_model_test.dart test\codex_app_server_models_test.dart
```

Expected: PASS.

- [ ] **Step 4: Run cross-platform command variant if executing in Linux/macOS**

Run:

```bash
cd mobile
flutter test --no-pub test/codex_app_server_view_model_test.dart test/codex_app_server_models_test.dart
dart run tool/check_architecture_imports.dart
dart analyze
```

Expected: PASS.

- [ ] **Step 5: Handle local command timeout policy**

If the first Flutter or Dart command times out in this Windows/Codex environment, stop retrying automatically and report the exact command to the user. Do not hide the timeout as a passing verification.

- [ ] **Step 6: Inspect final diff for scope**

Run:

```powershell
git status --short
git diff --stat
rg -n "Codex app-server|History|Discovery|Risk|No workspace selected|Open|Archived|Thread ID" mobile\lib\src\ui\features\codex_app_server mobile\lib\src\ui\main_tab_items.dart
```

Expected:

- `git status --short` shows only intentional implementation files before the final commit.
- `git diff --stat` does not include unrelated files.
- `rg` does not show hard-coded user-visible Codex strings in widgets except enum names, class names, and test names.

- [ ] **Step 7: Commit final verification cleanup if needed**

Only make a final commit if Tasks 1-6 left formatting, generated localization, or small cleanup changes unstaged.

```bash
git add mobile
git commit -m "Verify Codex console architecture and localization" -m "Constraint: Keep the Codex console read-only and localized." -m "Confidence: high" -m "Scope-risk: narrow" -m "Tested: cd mobile && dart run tool\\check_architecture_imports.dart" -m "Tested: cd mobile && dart analyze" -m "Tested: cd mobile && flutter test --no-pub test\\codex_app_server_view_model_test.dart test\\codex_app_server_models_test.dart"
```

---

## Self-Review Checklist

- Spec coverage:
  - Single overview replaces internal tabs: Task 4 and Task 6.
  - Same-page thread detail: Task 2 and Task 5.
  - Thread review error aggregation: Task 1 and Task 2.
  - Status chip derivation: Task 2 and Task 4.
  - Guarded count definition: Task 2 and Task 4.
  - Local tab state lifecycle: Task 6.
  - Full i18n: Task 3, Task 4, Task 5, Task 7.
  - Flutter layered architecture: Task 1, Task 2, Task 7.
- Placeholder scan:
  - This plan contains no incomplete markers or unspecified test steps.
- Type consistency:
  - `CodexAppServerThreadReview`, `CodexAppServerTurnReview`, `CodexAppServerOverviewStatus`, and `CodexAppServerPageMode` are introduced before use in UI tasks.
- Scope check:
  - The plan is one mobile-first feature over existing daemon routes. It does not add mutation UX or raw JSON-RPC access.
