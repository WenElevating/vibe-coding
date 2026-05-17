# Workbench Composer Model Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a refined bottom composer with separate CLI/model chips and safe model discovery/selection for Codex and Claude.

**Architecture:** Extend daemon adapter capabilities with optional model metadata, keeping the protocol additive and safe for mixed old/new clients. Mobile parses those optional fields, stores selected model state in the existing WorkbenchViewModel, and renders a polished composer plus model picker without changing conversation adapter-lock semantics.

**Tech Stack:** Node.js CommonJS daemon, Dart/Flutter mobile UI, existing `scripts/run-tests.js`, Flutter widget/unit tests, Codex config files, Claude/Codex CLI capability probing.

---

## File Structure

- Create: `daemon/src/model-discovery.js` ? config/env/catalog model discovery helpers, guarded by an environment variable and safe file reads.
- Modify: `daemon/src/adapter-registry.js` ? pass discovered model metadata through `listCapabilities()` without making adapters unavailable.
- Modify: `daemon/src/conversation-protocol.js` ? accept optional `model` in conversation creation payload.
- Modify: `daemon/src/conversation-manager.js` ? store `model`, expose it publicly, and pass it to adapter `startConversation()`.
- Modify: `daemon/src/codex-conversation-adapter.js` ? report Codex model support and add `--model` only when supported and requested.
- Modify: `daemon/src/claude-conversation-adapter.js` ? report Claude model support and add `--model` only when supported and requested.
- Modify: `scripts/run-tests.js` ? daemon unit/integration coverage for discovery, compatibility, launch args, and model propagation.
- Modify: `mobile/lib/src/data/models/adapter_models.dart` ? add `AdapterModelOption` and optional model fields with missing-field defaults.
- Modify: `mobile/lib/src/domain/repositories/conversation_repository.dart` ? add optional `model` to `createConversation()`.
- Modify: `mobile/lib/src/data/repositories/daemon_conversation_repository.dart` ? forward optional model to `DaemonClient`.
- Modify: `mobile/lib/src/services/daemon_client.dart` ? serialize optional model in `POST /api/conversations`.
- Modify: `mobile/lib/src/ui/features/workbench/view_models/workbench_view_model.dart` ? track selected model per selected adapter, fallback on refresh, and expose a short model notice.
- Modify: `mobile/lib/src/ui/features/workbench/coding_composer.dart` ? restyle composer and split CLI/model chips.
- Modify: `mobile/lib/src/ui/features/workbench/coding_workbench_page.dart` ? add model picker sheet, pass selected model to create/send, and keep lock behavior.
- Modify: `mobile/test/adapter_model_test.dart` ? protocol parsing and ViewModel state tests.
- Modify: `mobile/test/widget_test.dart` ? composer/model picker rendering coverage.

## Verification Rules

- Run daemon tests with `cmd.exe /c npm test` from `D:\AiProject\vibe-coding`.
- Run Flutter commands with domestic mirrors only:
  `cmd.exe /c "cd /d D:\AiProject\vibe-coding\mobile && set PUB_HOSTED_URL=https://pub.flutter-io.cn&& set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn&& dart run tool\check_architecture_imports.dart && flutter test test\adapter_model_test.dart test\widget_test.dart"`
- If the Flutter/Dart command times out on the first attempt, do not retry. Report the timeout and give the same manual command to the user.

---

### Task 1: Daemon Model Discovery Helpers

**Files:**
- Create: `daemon/src/model-discovery.js`
- Modify: `scripts/run-tests.js`

- [ ] **Step 1: Write failing daemon discovery tests**

Add tests near the adapter/protocol tests in `scripts/run-tests.js` for: Codex user/project override, unsupported TOML ignored, oversize catalog ignored, and Claude env de-duplication.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cmd.exe /c npm test`

Expected: FAIL with `Cannot find module '../daemon/src/model-discovery'` or missing exported functions.

- [ ] **Step 3: Implement discovery helper**

Create `daemon/src/model-discovery.js` with:
- `MODEL_CATALOG_MAX_BYTES = 1024 * 1024`
- `discoverConfiguredModels()`
- `parseTomlScalarConfig()`
- safe config reads that treat unreadable files as absent
- disable switch via `VIBE_DISABLE_MODEL_DISCOVERY`
- source values `codex_config`, `codex_catalog`, `claude_env`, `cli_default`, `unknown`

Implementation rules:
- parse only simple quoted scalar TOML assignments
- ignore multiline strings, inline tables, and unsupported syntax
- ignore unreadable, missing, non-file, or oversize catalog files
- never throw discovery errors to callers

- [ ] **Step 4: Run daemon tests**

Run: `cmd.exe /c npm test`

Expected: PASS for the new discovery tests or only targeted failures from later not-yet-implemented model propagation tests.

- [ ] **Step 5: Commit discovery helper**

```bash
git add daemon/src/model-discovery.js scripts/run-tests.js
git commit -m "Discover configured CLI models defensively" -m "Model selection needs daemon-owned discovery that can fail closed, so this adds guarded config/env/catalog parsing before exposing anything to mobile.

Constraint: Model discovery must not make adapter availability fail
Rejected: Full TOML parser | unnecessary for the required scalar keys
Confidence: medium
Scope-risk: moderate
Tested: npm test
Not-tested: Flutter UI not touched"
```

---

### Task 2: Adapter Capability Model Metadata

**Files:**
- Modify: `daemon/src/adapter-registry.js`
- Modify: `daemon/src/codex-conversation-adapter.js`
- Modify: `daemon/src/claude-conversation-adapter.js`
- Modify: `daemon/src/claude-adapter.js`
- Modify: `scripts/run-tests.js`

- [ ] **Step 1: Write failing capability tests**

Add tests to `scripts/run-tests.js` for:
- `AdapterRegistry.listCapabilities()` merging `models`, `selectedModel`, and `canSelectModel`
- Codex help text enabling `canSelectModel` only when `--model` exists
- Claude help/detection exposing `supportsModelFlag`

- [ ] **Step 2: Run tests to verify they fail**

Run: `cmd.exe /c npm test`

Expected: FAIL because `getModelCapability()` is not used and adapter capabilities do not expose `canSelectModel`.

- [ ] **Step 3: Enrich registry output**

Update `daemon/src/adapter-registry.js` so `enrich()` merges:
- base status
- model capability from `adapter.getModelCapability?.(status)`
- existing `displayName`, `profile`, and `capabilities`

Default model capability when absent:

```js
{ models: [], selectedModel: null, canSelectModel: false }
```

- [ ] **Step 4: Add adapter model support flags**

Codex:
- import `discoverConfiguredModels` from `daemon/src/model-discovery.js`
- store `this.modelCapability`
- in `detectCapabilities()`, set `canSelectModel = /\b--model\b/.test(execHelpText)`
- merge discovery result with `canSelectModel`
- expose `models`, `selectedModel`, and `canSelectModel` on capability
- add `getModelCapability()`

Claude:
- import `discoverConfiguredModels`
- extend detection to expose `supportsModelFlag` from help text when available
- set `this.modelCapability = { ...discoverConfiguredModels(...), canSelectModel: Boolean(detection.supportsModelFlag) }`
- add `getModelCapability()`

- [ ] **Step 5: Run daemon tests**

Run: `cmd.exe /c npm test`

Expected: PASS for model capability tests.

- [ ] **Step 6: Commit capability metadata**

```bash
git add daemon/src/adapter-registry.js daemon/src/codex-conversation-adapter.js daemon/src/claude-conversation-adapter.js daemon/src/claude-adapter.js scripts/run-tests.js
git commit -m "Expose optional adapter model capabilities" -m "The mobile composer needs model metadata, so adapter capabilities now include additive model fields while keeping discovery optional and non-fatal.

Constraint: Old mobile clients must ignore extra fields safely
Rejected: New endpoint first | existing adapters endpoint already refreshes this capability data
Confidence: medium
Scope-risk: moderate
Tested: npm test
Not-tested: Mobile parsing not added yet"
```

---

### Task 3: Conversation Model Propagation

**Files:**
- Modify: `daemon/src/conversation-protocol.js`
- Modify: `daemon/src/conversation-manager.js`
- Modify: `daemon/src/codex-conversation-adapter.js`
- Modify: `daemon/src/claude-conversation-adapter.js`
- Modify: `scripts/run-tests.js`

- [ ] **Step 1: Write failing propagation tests**

Add tests for:
- `normalizeConversationCreate({ model: 'gpt-5.5' })` preserving `model`
- `ConversationManager.ensureStarted()` passing the selected model into adapter `startConversation()`
- Codex/Claude launch args including `--model` only when `canSelectModel` is true

- [ ] **Step 2: Run tests to verify they fail**

Run: `cmd.exe /c npm test`

Expected: FAIL because `model` is not normalized or passed.

- [ ] **Step 3: Normalize and store model**

Update `daemon/src/conversation-protocol.js`:
- add `model: optionalString(payload.model)` to `normalizeConversationCreate()`
- add `optionalString()` helper returning trimmed string or `null`

Update `daemon/src/conversation-manager.js`:
- store `model: input.model` on the internal conversation object
- ensure public conversation serialization keeps `model` if the serializer strips fields
- pass `model: conversation.model` into `adapter.startConversation()`

- [ ] **Step 4: Add model launch args safely**

Codex:
- extend `startConversation({ ..., model, onEvent })`
- keep `model` on `CodexConversationHandle`
- update `buildCodexExecArgs()` and `buildCodexResumeArgs()` to insert `--model <id>` only when `model` is present and `this.adapter.modelCapability?.canSelectModel === true`

Claude:
- extend `startConversation({ ..., model, onEvent })`
- add `--model <id>` to launch args only when `model` is present and `this.modelCapability?.canSelectModel === true`

- [ ] **Step 5: Run daemon tests**

Run: `cmd.exe /c npm test`

Expected: PASS.

- [ ] **Step 6: Commit propagation**

```bash
git add daemon/src/conversation-protocol.js daemon/src/conversation-manager.js daemon/src/codex-conversation-adapter.js daemon/src/claude-conversation-adapter.js scripts/run-tests.js
git commit -m "Carry selected model into CLI conversations" -m "Selected models only matter if they reach the adapter launch path, so conversation creation now carries an optional model without changing existing model-less sends.

Constraint: Model is optional and must not block old clients
Rejected: Send model with every message | model belongs to conversation launch, not turn payload
Confidence: medium
Scope-risk: moderate
Tested: npm test
Not-tested: Mobile request wiring not added yet"
```

---

### Task 4: Mobile Protocol and Repository Wiring

**Files:**
- Modify: `mobile/lib/src/data/models/adapter_models.dart`
- Modify: `mobile/lib/src/domain/repositories/conversation_repository.dart`
- Modify: `mobile/lib/src/data/repositories/daemon_conversation_repository.dart`
- Modify: `mobile/lib/src/services/daemon_client.dart`
- Create: `mobile/test/adapter_model_test.dart`

- [ ] **Step 1: Write failing mobile protocol tests**

Create `mobile/test/adapter_model_test.dart` covering:
- old daemon payload defaults to `models = []`, `selectedModel = null`, `canSelectModel = false`
- new daemon payload parses a selected model row with source `codex_config`

- [ ] **Step 2: Run test to verify it fails**

Run:
`cmd.exe /c "cd /d D:\AiProject\vibe-coding\mobile && set PUB_HOSTED_URL=https://pub.flutter-io.cn&& set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn&& flutter test test\adapter_model_test.dart"`

Expected: FAIL because `models`, `selectedModel`, and `canSelectModel` do not exist.

- [ ] **Step 3: Implement protocol models**

In `mobile/lib/src/data/models/adapter_models.dart`:
- add `AdapterModelOption`
- extend `AdapterStatus` with `models`, `selectedModel`, `canSelectModel`
- parse missing fields safely

- [ ] **Step 4: Forward optional model in repositories**

Update:
- `ConversationRepository.createConversation(..., String? model)`
- `DaemonConversationRepository.createConversation(..., model: model)`
- `DaemonClient.createConversation()` to include `'model': model.trim()` when non-empty

- [ ] **Step 5: Run mobile protocol test**

Run:
`cmd.exe /c "cd /d D:\AiProject\vibe-coding\mobile && set PUB_HOSTED_URL=https://pub.flutter-io.cn&& set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn&& flutter test test\adapter_model_test.dart"`

Expected: PASS. If this first Flutter/Dart attempt times out, stop and report the command to the user.

- [ ] **Step 6: Commit mobile protocol wiring**

```bash
git add mobile/lib/src/data/models/adapter_models.dart mobile/lib/src/domain/repositories/conversation_repository.dart mobile/lib/src/data/repositories/daemon_conversation_repository.dart mobile/lib/src/services/daemon_client.dart mobile/test/adapter_model_test.dart
git commit -m "Parse and send optional adapter models on mobile" -m "The mobile client needs to tolerate old adapter JSON while forwarding selected models for new conversations, so protocol parsing and repository calls now treat model data as optional.

Constraint: Missing fields must remain safe defaults for old daemons
Confidence: high
Scope-risk: moderate
Tested: flutter test test\adapter_model_test.dart
Not-tested: Composer UI not updated yet"
```

---

### Task 5: Workbench ViewModel Model State

**Files:**
- Modify: `mobile/lib/src/ui/features/workbench/view_models/workbench_view_model.dart`
- Modify: `mobile/test/adapter_model_test.dart`

- [ ] **Step 1: Write failing ViewModel tests**

Extend `mobile/test/adapter_model_test.dart` to cover:
- initial `selectedModel` comes from the selected adapter
- `setSelectedModel()` updates the draft state
- snapshot refresh falling back to a new available model sets a short `modelNotice`
- locked conversation state refuses model changes

- [ ] **Step 2: Run test to verify it fails**

Run:
`cmd.exe /c "cd /d D:\AiProject\vibe-coding\mobile && set PUB_HOSTED_URL=https://pub.flutter-io.cn&& set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn&& flutter test test\adapter_model_test.dart"`

Expected: FAIL because ViewModel model state APIs do not exist.

- [ ] **Step 3: Implement model state APIs**

In `WorkbenchViewModel` add:
- `_selectedModel`
- `_modelNotice`
- getters `selectedModel`, `modelNotice`, `selectedAdapterStatus`, `availableModels`
- `setSelectedModel()`
- `clearModelNotice()`
- helpers `_adapterStatusFor()`, `_preferredModelFor()`, `_reconcileSelectedModel()`

Behavior rules:
- use safe defaults when adapter has no models
- keep running conversation selections unchanged
- for a fresh unsent draft whose chosen model disappears, fall back and set a non-blocking notice
- clear the notice on user edit, picker open, or successful send

- [ ] **Step 4: Pass model when creating conversations**

Update `createAndSend()` to accept `String? model` and pass it into the repository call.

- [ ] **Step 5: Run mobile ViewModel tests**

Run:
`cmd.exe /c "cd /d D:\AiProject\vibe-coding\mobile && set PUB_HOSTED_URL=https://pub.flutter-io.cn&& set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn&& flutter test test\adapter_model_test.dart"`

Expected: PASS or a concrete compiler error to fix inside this task.

- [ ] **Step 6: Commit ViewModel state**

```bash
git add mobile/lib/src/ui/features/workbench/view_models/workbench_view_model.dart mobile/test/adapter_model_test.dart
git commit -m "Track selected model in the workbench" -m "Model selection belongs to new conversation draft state, so the existing WorkbenchViewModel now keeps selected model state alongside adapter state and falls back safely on refresh.

Constraint: Conversation-backed histories remain locked
Rejected: Separate model ViewModel | current scope only needs one state owner
Confidence: medium
Scope-risk: moderate
Tested: flutter test test\adapter_model_test.dart
Not-tested: Widget rendering not updated yet"
```

---

### Task 6: Composer and Picker UI

**Files:**
- Modify: `mobile/lib/src/ui/features/workbench/coding_composer.dart`
- Modify: `mobile/lib/src/ui/features/workbench/coding_workbench_page.dart`
- Modify: `mobile/test/widget_test.dart`

- [ ] **Step 1: Write failing widget tests**

Add widget coverage for:
- separate CLI chip and model chip rendering
- model notice rendering
- model picker fallback row when no model list exists
- CLI/model chips disabled while conversation is locked

- [ ] **Step 2: Run widget test to verify it fails**

Run:
`cmd.exe /c "cd /d D:\AiProject\vibe-coding\mobile && set PUB_HOSTED_URL=https://pub.flutter-io.cn&& set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn&& flutter test test\widget_test.dart"`

Expected: FAIL because `CodingComposer` does not accept model/onCliTap yet.

- [ ] **Step 3: Split composer chip API and restyle shell**

In `coding_composer.dart`:
- add `model`, `modelNotice`, `onCliTap`, and `onModelTap`
- keep refined sizing: drag handle, subtle border, smaller 14?16 px icons, <= 32 px actions
- rename the existing adapter chip widget to `_ComposerCliPill`
- create a new `_ComposerModelPill` showing the selected model or `默认模型`
- render the inline notice below the chip row in muted text

- [ ] **Step 4: Add model picker sheet**

In `coding_workbench_page.dart`:
- keep `_showAdapterPicker()` for CLI
- add `_showModelPicker()`
- add `ModelPickerSheet`
- localize known `source` values: `codex_config`, `codex_catalog`, `claude_env`, `cli_default`
- use a neutral fallback for unknown values
- keep lock behavior: no CLI/model switching when `_activeConversationId != null`

- [ ] **Step 5: Wire composer calls**

Pass to `CodingComposer`:
- `model: _workbenchViewModel.selectedModel`
- `modelNotice: _workbenchViewModel.modelNotice`
- `onCliTap: _showAdapterPicker`
- `onModelTap: _showModelPicker`

When creating a conversation, pass model only when `selectedAdapterStatus?.canSelectModel == true`.

- [ ] **Step 6: Run widget tests**

Run:
`cmd.exe /c "cd /d D:\AiProject\vibe-coding\mobile && set PUB_HOSTED_URL=https://pub.flutter-io.cn&& set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn&& flutter test test\widget_test.dart"`

Expected: PASS. If this first Flutter/Dart attempt times out, stop and report the command to the user.

- [ ] **Step 7: Commit UI**

```bash
git add mobile/lib/src/ui/features/workbench/coding_composer.dart mobile/lib/src/ui/features/workbench/coding_workbench_page.dart mobile/test/widget_test.dart
git commit -m "Refine composer with separate model selection" -m "The workbench composer now needs distinct CLI and model controls, so the UI uses a polished bottom panel with separate chips and a dedicated model picker.

Constraint: Existing CLI icons and adapter lock behavior stay unchanged
Rejected: New page for model selection | bottom sheet matches existing picker interaction
Confidence: medium
Scope-risk: moderate
Tested: flutter test test\widget_test.dart
Not-tested: Full Flutter suite not run yet"
```

---

### Task 7: Integration Verification and Cleanup

**Files:**
- Modify: `scripts/run-tests.js`
- Modify: `mobile/test/adapter_model_test.dart`
- Modify: `mobile/test/widget_test.dart`
- Optional Modify: `docs/superpowers/specs/2026-05-17-workbench-composer-model-picker-design.md` only if implementation reveals a necessary design correction.

- [ ] **Step 1: Add daemon integration smoke test**

Add a server-level test in `scripts/run-tests.js` covering:
- `/api/adapters` returning `selectedModel` and `models`
- `POST /api/conversations` accepting `model`
- the selected model reaching adapter `startConversation()`

- [ ] **Step 2: Run daemon full tests**

Run: `cmd.exe /c npm test`

Expected: PASS with all daemon/API tests.

- [ ] **Step 3: Run Flutter architecture and focused tests**

Run:
`cmd.exe /c "cd /d D:\AiProject\vibe-coding\mobile && set PUB_HOSTED_URL=https://pub.flutter-io.cn&& set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn&& dart run tool\check_architecture_imports.dart && flutter test test\adapter_model_test.dart test\widget_test.dart"`

Expected: architecture check passes and focused Flutter tests pass. If this first Flutter/Dart attempt times out, stop and report the command to the user.

- [ ] **Step 4: Run static checks if available**

Run: `cmd.exe /c npm run lint`

Expected: PASS. If lint exposes unrelated failures, do not fix them; report them with exact output.

- [ ] **Step 5: Final review and commit**

Run:
- `git status --short`
- `git diff --stat`

If there are remaining verification-only changes, commit them with a Lore message summarizing the integration verification. If there are no changes left, do not create an empty commit.

---

## Self-Review

- Spec coverage: covered additive protocol compatibility, TOML subset parsing, 1 MB catalog cap, disable switch, probing/cache semantics, source enum, unreadable-file behavior, model refresh fallback, UI restyle, picker behavior, and integration smoke testing.
- Placeholder scan: no forbidden placeholders or vague implementation-only steps remain.
- Type consistency: daemon uses `models`, `selectedModel`, `canSelectModel`, and optional `model`; mobile mirrors the same names through `AdapterStatus`, repository calls, and `WorkbenchViewModel`.
