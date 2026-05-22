# Project Knowledge Skill Design

## Summary

The project needs a durable knowledge source so future agent sessions do not
restart from zero. The recommended design is not a larger `AGENTS.md` and not
only local agent memory. The design introduces a versioned
`docs/project-knowledge/` knowledge base, backed by a small workflow skill named
`maintaining-project-knowledge`.

The repo knowledge base is the stable, reviewable source of project facts. The
existing `.agents/skills/technical-project-memory` skill remains useful for
local session recovery and candidate notes, but it is not the project-level
source of truth because `.agents/` is ignored by Git.

## Goals

- Give future agents a small, reliable starting point for architecture,
  decisions, build/test commands, troubleshooting, and project conventions.
- Keep long-lived knowledge versioned with the repository so changes can be
  reviewed and pushed with code.
- Prevent project knowledge from becoming chat logs or unverified memory.
- Make every non-trivial task start from the relevant knowledge slice, not a
  full project rescan.
- Make every completed task check whether new durable knowledge, decisions,
  quality gates, or risks should be promoted.
- Reuse the existing `technical-project-memory` skill for local workspace
  snapshots and candidate promotion, without making it the only fact source.

## Non-Goals

- Do not store ordinary conversation transcripts in the repository.
- Do not duplicate every `docs/superpowers/specs/` or `plans/` file.
- Do not make `AGENTS.md` a long project manual.
- Do not treat local memory as verified current truth without checking code or
  tests.
- Do not require all knowledge files to be read for every task.
- Do not create the final skill in this design pass; writing the skill must
  follow `superpowers:writing-skills` RED/GREEN/REFACTOR testing.

## Current State

- `AGENTS.md` already contains strong repo rules:
  - CodeGraph usage rules.
  - Flutter mobile architecture boundaries.
  - build/test commands and China mirror requirements.
  - UTF-8 safety and commit/security rules.
- `.agents/skills/technical-project-memory` already exists and defines:
  - `knowledge/` for reusable technical experience.
  - `management/` for TODOs, risks, debt, quality gates, and conventions.
  - `history/` for milestones, change log, decisions, and retrospectives.
- `.agents/` is ignored by `.gitignore`, so project knowledge stored only there
  does not become shared repository knowledge.
- `docs/superpowers/specs/` and `docs/superpowers/plans/` contain detailed
  design history, but they are task-specific and too many to be a fast startup
  source.

## Recommended Architecture

```text
AGENTS.md
  Small mandatory entry rules and pointers.

docs/project-knowledge/
  Versioned project knowledge source used by future agents.

.agents/skills/technical-project-memory/
  Local workspace/session memory and promotion candidates.

.agents/skills/maintaining-project-knowledge/
  Workflow skill that decides what to read, verify, and promote.
```

### Source-of-Truth Rules

- Current code and tests are the authority for implementation facts.
- `docs/project-knowledge/` is the authority for durable project conventions,
  accepted decisions, recurring troubleshooting, and quality gates.
- `docs/superpowers/specs/` is the authority for detailed design rationale when
  a knowledge entry links to a specific design.
- `technical-project-memory` is a local acceleration layer. It can suggest what
  to inspect, but drift-prone facts must be verified before use.

## Repo Knowledge Base Layout

Create:

```text
docs/project-knowledge/
├── index.md
├── architecture.md
├── module-boundaries.md
├── build-and-test.md
├── conventions.md
├── troubleshooting-playbook.md
├── glossary.md
├── open-risks.md
├── archive/
│   └── README.md
└── decisions/
    ├── README.md
    └── yyyy-mm-dd-short-title.md
```

### File Responsibilities

`index.md`

- Entry point for agents.
- Maps task types to the smallest files to read.
- Links to related specs and plans.

`architecture.md`

- Durable architecture overview.
- Daemon/mobile/data flow.
- Conversation/session model.
- Flutter layered architecture.

`module-boundaries.md`

- Ownership and dependency boundaries.
- State authority rules.
- What must not cross layers.
- Commands that enforce boundaries.

`build-and-test.md`

- Verified commands.
- Environment requirements.
- Flutter/Dart mirror and `NO_PROXY` rules.
- Known local command failure modes.
- Knowledge drift check commands.

`conventions.md`

- Naming, error handling, logging, testing, UI copy, and commit conventions.
- Repo-local coding style that is too detailed for `AGENTS.md` but too
  general for a single architecture note.

`troubleshooting-playbook.md`

- Symptoms, first checks, likely fault boundaries, historical fixes, and
  verification commands.

`glossary.md`

- Project terms such as `conversationId`, `cliSessionId`, `sessionBinding`,
  `AppSnapshot`, `WorkbenchViewModel`, and adapter names.

`open-risks.md`

- Current durable risks and blockers with evidence and mitigation.

`archive/`

- Replaced, rejected, or stale entries that should not appear in the default
  index route.
- Archive entries remain searchable for history but are not part of the normal
  startup path.

`decisions/`

- Lightweight ADRs for decisions that affect future implementation.

## Knowledge Entry Standards

Use the smallest template that preserves future usefulness.

### Full Decision or Architecture Template

Use for architecture decisions, module-boundary rules, durable ADRs, and
high-impact technical direction:

```markdown
## Topic

- Status:
- Context:
- Decision or lesson:
- Evidence:
- Verification:
- Last verified:
- Applies when:
- Does not apply when:
- Related files:
- Related specs:
```

### Operational Tip Template

Use for focused operational knowledge such as a test command, proxy workaround,
tooling caveat, or short troubleshooting rule:

```markdown
## Tip: xxx

- Symptom:
- Action:
- Verification:
- Last verified:
```

Troubleshooting entries should be symptom-first:

```markdown
## Symptom: xxx

First checks:
1. xxx
2. xxx

Known causes:
- xxx

Fix pattern:
- xxx

Verification:
- xxx

Last verified:
- yyyy-mm-dd
```

Decision records should be lightweight ADRs:

```markdown
# Decision: xxx

- Status: proposed / accepted / verified / replaced / rejected
- Date:
- Context:
- Decision:
- Alternatives:
- Consequences:
- Verification:
- Re-evaluate when:
- Last verified:
```

## Staleness and Drift Detection

Knowledge entries must carry a lightweight staleness signal. The default field
is `Last verified: yyyy-mm-dd`. If the verification date is older than 45 days,
or if the field is missing, the skill must treat the entry as a hint and label
it `unverified` in its reasoning or final summary when it affects the answer.

This is not a requirement to re-verify every entry on every task. It is a
triage mechanism:

- Fresh entry with specific verification: usable after checking whether the
  task depends on drift-prone details.
- Old entry: read as historical context; verify before relying on it.
- Missing verification: do not promote to trusted project knowledge.

Add a lightweight repository check only after the first GREEN skill validation
passes with seed knowledge present. During the initial seed-writing phase,
missing `Last verified` fields should be fixed by review, not by a failing
script that produces false positives before the templates have stabilized.

```text
node scripts/check-project-knowledge.js
```

The check should initially validate only cheap structural facts:

- referenced repo-relative file paths still exist;
- linked `docs/superpowers/specs/` files still exist;
- `index.md` does not route to archived entries.

In its first version, the check should not warn about stale `Last verified`
dates for seed entries. It may report missing `Last verified` fields as
non-fatal notices, then switch them to failures after the first stable
knowledge-base commit. This command belongs in `build-and-test.md` and can later
be added to CI. It should not execute expensive Flutter, daemon, or network
checks.

## Skill Design

### Skill Name

`maintaining-project-knowledge`

### Proposed Frontmatter

```yaml
---
name: maintaining-project-knowledge
description: Use when starting, resuming, finishing, debugging, refactoring, or making architecture decisions in a long-lived project where prior decisions, conventions, tests, environment constraints, or hard-won debugging lessons may affect the work. Do not use for trivial formatting-only edits, dependency version bumps, or tasks explicitly scoped to one obvious function.
---
```

The description intentionally states only trigger conditions. It must not
summarize the workflow, because `superpowers:writing-skills` warns that
workflow summaries in descriptions become shortcuts that agents follow instead
of reading the skill body.

### Skill Responsibilities

- Start from `docs/project-knowledge/index.md`.
- Select the smallest relevant knowledge slice.
- Verify drift-prone facts against code, tests, docs, commands, or CodeGraph.
- Use `technical-project-memory` for local session recovery when useful.
- Promote only durable lessons, decisions, risks, quality gates, and recurring
  troubleshooting knowledge.
- Report whether project knowledge was updated, and why.

### Skill Non-Responsibilities

- It does not replace systematic debugging, TDD, or architecture skills.
- It does not write code.
- It does not force all project docs to be read.
- It does not promote unverified speculation.
- It does not automatically commit documentation.

## Workflow

### Start of Non-Trivial Work

1. Read `docs/project-knowledge/index.md`.
2. Route by the decision tree below and read only the selected files.
3. Verify current code shape with CodeGraph or focused `rg` only where needed.
4. Treat stale or unverified knowledge as a hint, not as fact.

### Index Routing Decision Tree

`index.md` must include a small routing table so agents do not guess freely.

Priority order:

1. If the prompt contains errors, failing tests, hangs, freezes, regressions,
   unexpected behavior, or "bug": read `troubleshooting-playbook.md` and
   `build-and-test.md`.
2. If the prompt asks where state, logic, data, files, APIs, or responsibilities
   belong: read `architecture.md`, `module-boundaries.md`, and relevant
   decisions.
3. If the prompt changes build, test, CI, Flutter/Dart, Node, proxy, dependency,
   SDK, or environment behavior: read `build-and-test.md`, `conventions.md`,
   and `open-risks.md`.
4. If the prompt is a feature in a known area: read `architecture.md` plus the
   decision or troubleshooting entry named by the feature keywords.
5. If the prompt is style, naming, error handling, logging, commit style, or
   code consistency: read `conventions.md`.
6. If ambiguous, read at most three files: `index.md`, `architecture.md`, and
   `troubleshooting-playbook.md`; then narrow after inspecting code.

Rules 1-5 are exact routes and may be combined when a prompt clearly matches
multiple categories. The three-file limit applies only to rule 6, the ambiguous
fallback path. If combining exact routes would exceed five files, stop after the
most likely fault boundary and inspect code before loading more knowledge.

Example ambiguous terms:

- "optimize performance" routes to troubleshooting if there is a measured
  slowdown or user-visible lag; otherwise architecture/refactor.
- "clean up" routes to conventions for naming/style, module boundaries for
  ownership changes, and architecture for structural changes.
- "make tests pass" routes to troubleshooting and build/test first.

### During Work

- If a task contradicts knowledge docs, stop and decide whether the docs are
  stale, the code drifted, or the requested change needs a new decision.
- If a workaround is introduced, create or update a debt/risk entry.
- If a new quality gate proves necessary, update `build-and-test.md` or
  `module-boundaries.md`.
- If multiple agents are active, avoid broad rewrites of shared knowledge files;
  prefer append-only entries or one decision file per ADR.

### End of Work

Check whether the task created any durable knowledge:

- repeated bug or hard-won debugging lesson;
- new architecture or ownership decision;
- build/test/environment command that finally worked;
- quality gate or acceptance criterion;
- risk, blocker, debt, or long-term TODO;
- glossary term or field semantics that future agents must understand.

If yes, update the smallest relevant file. If no, say why no update was needed.

## Concurrency and Conflict Policy

Multiple agent sessions may finish work at the same time. Knowledge files are
Git-tracked, so updates need a conservative merge strategy.

- Prefer append-only additions for playbooks, conventions, risks, and build/test
  notes.
- Prefer one file per decision under `decisions/` to reduce conflicts.
- Do not reorder large sections just for tidiness during feature work.
- Before committing project-knowledge changes, check `git status -sb` and
  compare against `origin/master` if a push is planned.
- If a pull/rebase introduces a knowledge conflict, preserve both entries first,
  resolve duplication explicitly, and rerun the lightweight knowledge check.
- If two entries conflict semantically, do not silently choose one. Mark the
  older or less-verified entry as `Status: disputed` or `Status: replaced` and
  explain the evidence.

## Promotion Rules

Promoting from local memory, session notes, or task observations into
`docs/project-knowledge/` requires evidence.

Standard operational tips need both:

- the lesson has helped in at least two independent tasks, or the user
  explicitly asked to preserve it for future work;
- it has a concrete verification command, reproducible symptom, or repo-relative
  code path.

Architecture decisions, P0/P1 incident lessons, and accepted user decisions may
be promoted after one task, but only if the entry includes:

- `Status`;
- evidence from the current code, test output, user decision, or linked spec;
- `Last verified`;
- re-evaluation conditions.

Do not promote:

- normal chat transcript content;
- unverified guesses;
- one-off implementation details that are obvious from nearby code;
- stale local memory with no current code path or verification command.

## RED Scenarios Required Before Writing the Skill

The final skill must not be written until these baseline pressure scenarios are
run without the skill and failure modes are documented.

RED scenarios must run with seed knowledge files already present and the new
skill not enabled. The test must prove that agents ignore, underuse, or misuse
an available knowledge base without the skill. A baseline where no knowledge
base exists only proves that knowledge is useful; it does not prove that the
workflow skill is necessary.

### Scenario 1: New Session Bug Fix

Precondition:

- `docs/project-knowledge/index.md`, `architecture.md`, `module-boundaries.md`,
  `build-and-test.md`, and `troubleshooting-playbook.md` exist with seed
  content.

Prompt:

```text
Fix the mobile conversation scroll issue.
```

Expected baseline failure:

- Agent starts with code search only.
- Does not read project architecture or previous workbench context.
- Misses mobile test/mirror constraints.

Success with skill:

- Reads the knowledge index and the workbench/mobile slice.
- Verifies current code with CodeGraph or focused search.
- Uses the correct Flutter verification commands or hands off when local
  Flutter tools time out.

### Scenario 2: Task Completion After User Verification

Precondition:

- Seed knowledge contains an existing troubleshooting entry for a related UI or
  test behavior.

Prompt:

```text
I tested it locally. Commit and push.
```

Expected baseline failure:

- Agent commits and pushes without checking whether a durable lesson or
  decision should be captured.

Success with skill:

- Commits code as requested.
- Checks whether the completed work should update project knowledge.
- Does not block the requested commit on unnecessary documentation.

### Scenario 3: Architecture Placement Question

Precondition:

- Seed knowledge contains architecture and module-boundary rules.

Prompt:

```text
Should this state live in the ViewModel, domain, or daemon?
```

Expected baseline failure:

- Agent gives generic Flutter advice.

Success with skill:

- Reads `architecture.md`, `module-boundaries.md`, and relevant decisions.
- Answers with this repo's source-of-truth and dependency rules.

### Scenario 4: Environment/Test Failure

Precondition:

- Seed knowledge contains the Flutter/Dart proxy and mirror notes.

Prompt:

```text
Flutter test fails with HttpException on 127.0.0.1.
```

Expected baseline failure:

- Agent assumes test code failure.

Success with skill:

- Reads `build-and-test.md`.
- Checks proxy and `NO_PROXY` before code changes.
- Separates environment failures from code failures.

### Scenario 5: Knowledge Pollution Pressure

Precondition:

- Seed knowledge contains both a full decision template and an operational tip
  template.

Prompt:

```text
Record everything we discussed.
```

Expected baseline failure:

- Agent writes chat transcript-style notes.

Success with skill:

- Extracts only durable, verified, actionable knowledge.
- Refuses or narrows ordinary chat log archival.

## RED Baseline Results

Run date: 2026-05-22

Precondition: seed files under `docs/project-knowledge/` were present and
`.agents/skills/maintaining-project-knowledge/SKILL.md` did not exist.

### RED-1: Conversation Hang / Data-Flow Triage

- Result: failed routing discipline.
- Behavior: agent diagnosed from code and `data/app/app.sqlite`, identified
  persisted events and mobile poll traces, and proposed useful SQL follow-up.
- Failure: agent did not read `docs/project-knowledge/index.md`,
  `troubleshooting-playbook.md`, or `build-and-test.md` before broad code/data
  inspection.
- Skill implication: bug/hang scenarios must start with the index route, then
  verify against current code/data.

### RED-2: Stable Conversation Title Architecture

- Result: passed naturally.
- Behavior: agent read `docs/project-knowledge/decisions/2026-05-22-stable-conversation-title.md`
  and `module-boundaries.md`, then correctly chose daemon-owned metadata.
- Skill implication: preserve this narrow architecture route and do not force a
  larger read set.

### RED-3: Flutter `127.0.0.1` Test Failure

- Result: failed routing discipline.
- Behavior: agent correctly diagnosed a proxy/`NO_PROXY` issue, but relied on
  `AGENTS.md`, code, and local memory while reading many test files.
- Failure: agent did not use `docs/project-knowledge/build-and-test.md` or the
  troubleshooting entry that already captured the exact symptom.
- Skill implication: environment/test failures must read the build/test slice
  before code changes or broad test inspection.

### RED-4: Commit And Push After Verification

- Result: failed end-of-task discipline.
- Behavior: agent gave a strong Git and verification sequence.
- Failure: agent did not consult the project knowledge index and treated
  knowledge updates as optional based on general memory rather than the repo
  promotion rules.
- Skill implication: finishing non-trivial work must include an explicit
  durable-knowledge check, while still avoiding unnecessary docs churn.

### RED-5: "Record Everything" Knowledge Pollution

- Result: passed naturally.
- Behavior: agent read `docs/project-knowledge/` and narrowed "everything" to
  durable, verifiable engineering facts instead of chat transcripts.
- Skill implication: preserve the anti-pollution rule and make the vague
  "save/remember" target default to local memory or a promotion candidate until
  repo evidence rules are met.

### Baseline Patterns

- Agents can solve some cases from code, `AGENTS.md`, or local memory, but that
  bypasses the versioned knowledge source and causes extra reads.
- Presence of `docs/project-knowledge/` does not guarantee agents start there.
- Good natural behavior exists for architecture and pollution scenarios; the
  skill should be a lightweight gate, not a large manual.
- The skill must explicitly counter: "AGENTS.md is enough", "memory already
  knows this", "I diagnosed it from code so no need to read the index", and
  "commit/push now, knowledge later".

## GREEN Validation Results

Run date: 2026-05-22

Precondition: `.agents/skills/maintaining-project-knowledge/SKILL.md` existed
and each validation agent was told to read it first.

### GREEN-1: Conversation Hang / Data-Flow Triage

- Result: passed.
- Behavior: agent read the skill, then `docs/project-knowledge/index.md`,
  `troubleshooting-playbook.md`, `build-and-test.md`, `architecture.md`, and
  `module-boundaries.md` before inspecting code/data.
- Evidence of improvement: compared with RED, it started from the project
  knowledge route and then used current code plus read-only SQLite evidence.
- Remaining note: it still expanded into many code files after routing, which
  is acceptable for a deep hang triage but should stay evidence-driven.

### GREEN-2: Stable Conversation Title Architecture

- Result: passed.
- Behavior: agent read the skill, index, architecture, module boundaries, and
  the stable-title decision before choosing daemon-owned metadata.
- Evidence of improvement: kept the route narrow and explicitly said no new
  knowledge update was needed because the decision already exists.

### GREEN-3: Flutter `127.0.0.1` Test Failure

- Result: passed.
- Behavior: agent read the skill, index, troubleshooting entry, and
  `build-and-test.md` before touching tests.
- Evidence of improvement: diagnosed local proxy bypass from the existing
  project entry and explicitly avoided test-code changes first.

### GREEN-4: Commit And Push After Verification

- Result: passed.
- Behavior: agent read the skill, index, and conventions before describing the
  commit/push sequence.
- Evidence of improvement: included an explicit project-knowledge decision and
  correctly skipped docs/local-memory churn unless durable evidence exists.

### GREEN-5: "Record Everything" Knowledge Pollution

- Result: passed.
- Behavior: agent read the skill and index, rejected full transcript archival,
  and narrowed preservation to reusable, verified engineering facts.
- Evidence of improvement: followed the promotion evidence rules and separated
  repo knowledge from local memory/promotion candidates.

### GREEN Summary

- The skill fixed all RED routing failures.
- No new rationalizations appeared during GREEN validation.
- The skill remained lightweight: agents used it as a gate to the knowledge
  index instead of treating it as a replacement for project knowledge.
- The next rollout step can add a short `AGENTS.md` pointer and, later, the
  lightweight `scripts/check-project-knowledge.js` structural check after the
  first stable project-knowledge commit.

## Capacity Governance

The knowledge base must stay small enough for agents to use.

Default index budget:

- `index.md` should route to at most three files for a normal task.
- Active top-level files should keep current, high-value entries only.
- `decisions/README.md` should list only active or recently relevant decisions
  by default.

Archive criteria:

- `Status: replaced`, `Status: rejected`, or `Status: obsolete` entries older
  than 90 days may move to `archive/`.
- Entries not referenced by `index.md`, recent work, or active decisions for
  more than 180 days should be considered for archive.
- Archived entries must keep their original date, status, and replacement link.
- Do not archive active quality gates, current environment notes, or unresolved
  risks.

When an entry moves to archive:

- remove it from default index routes;
- keep a link from any replacing entry;
- run the lightweight knowledge check;
- include the move in the commit summary.

## Seed Content Plan

After the skill is tested and accepted, seed the knowledge base with a small
first version:

- `architecture.md`
  - daemon owns conversation metadata and event persistence;
  - mobile ViewModels own UI state projections;
  - domain code must not import Flutter, HTTP, SharedPreferences, or
    `DaemonClient`.
- `module-boundaries.md`
  - `Conversation.title` is daemon-owned metadata;
  - `cliSessionId` is an adapter resume token, not a display title;
  - workbench transcript bottom anchoring is UI rendering responsibility.
- `build-and-test.md`
  - Node checks: `node scripts/run-tests.js`, `npm run lint`;
  - mobile checks: `dart run tool/check_architecture_imports.dart`, targeted
    `flutter test`;
  - Flutter/Dart mirror and `NO_PROXY` commands;
  - if Flutter/Dart command times out once, do not auto-retry.
- `conventions.md`
  - English commit messages unless the user asks otherwise;
  - UTF-8 safe editing rules;
  - use `apply_patch` for manual source edits;
  - avoid broad refactors and preserve layered architecture style.
- `troubleshooting-playbook.md`
  - Flutter test local proxy `HttpException`;
  - Codex conversation no visible output: inspect persisted events and
    `run.error`;
  - workbench historical transcript not opening at bottom: prefer bottom
    anchored list over post-frame `maxScrollExtent` correction.
- `decisions/`
  - stable conversation title is daemon persisted from first user message;
  - transcript list uses reversed bottom anchoring for initial latest-message
    visibility.

## AGENTS.md Integration

Add only a short pointer, not the full workflow:

```markdown
## Project Knowledge

For non-trivial work, read `docs/project-knowledge/index.md` and the linked
task-specific slice before deep exploration. Update project knowledge only when
the task creates durable architecture, debugging, testing, decision, risk, or
environment lessons.
```

## Rollout Plan

1. Create `docs/project-knowledge/` seed files.
2. Run RED pressure scenarios with the seed knowledge present but without the
   skill, and record failures.
3. Create `.agents/skills/maintaining-project-knowledge/SKILL.md`.
4. Run the same scenarios with the skill.
5. Refine the skill until it prevents the observed failures.
6. Add the `AGENTS.md` pointer.
7. Add the lightweight knowledge check after the first GREEN validation passes.
   Its first run should enforce structural checks and treat seed staleness as a
   notice, not a failure.
8. Commit the versioned knowledge files and any skill files intentionally
   tracked or documented.

Because `.agents/` is ignored, decide explicitly whether the skill should stay
workspace-local only or be force-added. The repo knowledge files should be
tracked normally.

### Rollout Status

- 2026-05-22: steps 1-7 completed locally.
- `AGENTS.md` now contains only a short project-knowledge pointer.
- `scripts/check-project-knowledge.js` performs structural checks only and
  treats missing `Last verified` as a notice.
- No commit has been made for this rollout; `.agents/` and `docs/` remain
  ignored unless intentionally force-added.

## Acceptance Criteria

- New agent sessions can find the right architecture, test, and troubleshooting
  slice from `docs/project-knowledge/index.md` within one or two reads.
- The skill has documented RED baseline failures and GREEN verification results.
- The knowledge base does not duplicate ordinary chat transcripts.
- Drift-prone facts are marked with verification commands or links to current
  code/specs.
- `AGENTS.md` remains short and points to the knowledge index.
- The first seed includes at least architecture, boundaries, build/test,
  conventions, troubleshooting, and two recent decisions.
- Each active entry has a `Last verified` field or is explicitly marked
  `unverified`.
- `index.md` contains the routing decision tree and does not route normal tasks
  to archived entries.
- Local-memory-to-repo promotion follows the evidence rules above.
- The concurrency policy is validated with a simulated two-agent append
  scenario where two independent additions to `troubleshooting-playbook.md`
  merge without dropping either entry, or the limitation is documented as a
  remaining risk before rollout.

## Risks

- Knowledge docs can drift from code. Mitigation: every entry must include
  verification or re-evaluation conditions.
- Agents may over-update docs after trivial changes. Mitigation: skill must
  require durable value before promotion.
- Agents may read too much before simple tasks. Mitigation: index routes by
  task type and says not to load everything.
- `.agents/` content may not be shared. Mitigation: repository knowledge is the
  stable source; local memory is only an acceleration layer.
