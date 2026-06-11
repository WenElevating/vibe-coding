# Coding CLI Preload Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Start CLI adapter loading after connection, but gate the Coding tab until adapter readiness is known.

**Architecture:** `MainTabsPage` owns adapter preload state and wraps the Coding tab with loading/error gates. `AdapterRegistry` shares concurrent capability probes with a single in-flight promise so background preload and tab entry do not duplicate CLI probing.

**Tech Stack:** Flutter/Dart widgets and tests, Node.js CommonJS daemon tests.

---

### Task 1: Mobile Adapter Preload Gate

**Files:**
- Modify: `mobile/lib/src/ui/main_tabs_page.dart`
- Test: `mobile/test/widget_test.dart`

- [ ] Add explicit adapter load state to `MainTabsPage` with `idle`, `loading`, `loaded`, and `failed`.
- [ ] Start `_ensureCodingAdaptersLoaded()` from `initState()` with `unawaited` background execution.
- [ ] Reuse one `_adapterLoadFuture` while loading so Coding entry joins the background preload.
- [ ] Render a Coding loading gate while adapters are not loaded.
- [ ] Render a retry gate when loading fails.
- [ ] Update the existing adapter-refresh widget test to expect preload on connection.
- [ ] Add a pending-preload widget test that enters Coding and verifies the loading gate hides workspace/history/new-session UI.

### Task 2: Backend Adapter Single-Flight

**Files:**
- Modify: `daemon/src/adapter-registry.js`
- Test: `scripts/run-tests.js`

- [ ] Add `_capabilitiesLoad` to `AdapterRegistry`.
- [ ] Return the same promise for concurrent `listCapabilities()` calls.
- [ ] Clear `_capabilitiesLoad` after success or failure so later retries can run.
- [ ] Add a daemon regression test that two concurrent `listCapabilities()` calls trigger each adapter once.

### Task 3: Verification

**Files:**
- Validate: `mobile/test/widget_test.dart`
- Validate: `scripts/run-tests.js`

- [ ] Run focused Flutter widget tests for adapter preload behavior.
- [ ] Run daemon regression tests with `npm test`.
- [ ] Fix only failures caused by this change.

## Self-Review

- Spec coverage: background preload, Coding gate, retry error path, and backend single-flight are covered.
- Placeholder scan: no TBD/TODO placeholder remains.
- Type consistency: planned Dart state names map to `MainTabsPage`; backend state maps to `AdapterRegistry`.
