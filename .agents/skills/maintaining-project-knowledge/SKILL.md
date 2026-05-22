---
name: maintaining-project-knowledge
description: Use when working in the vibe-coding repository on non-trivial project tasks that may depend on architecture, build/test rules, troubleshooting lessons, decisions, handoff, or knowledge promotion. Do not trigger for single-file formatting changes, dependency version bumps, or tasks explicitly scoped to one small function.
---

# Maintaining Project Knowledge

## Core Rule

Use the versioned project knowledge base first, then verify against current code.
Local memory can suggest where to look, but it is not the project source of
truth.

Project knowledge lives at:

```text
docs/project-knowledge/index.md
```

## When To Use

Use this skill for non-trivial work in `D:\AIProject\vibe-coding`:

- starting or resuming a bug fix, feature, refactor, architecture discussion, or
  debugging session;
- finishing verified work, especially before commit/push or handoff;
- investigating build, test, Flutter/Dart, daemon, proxy, or CLI behavior;
- deciding where state or behavior belongs across daemon/mobile layers;
- the user asks to remember, save, preserve, or "沉淀" reusable project knowledge.

Skip this skill for tiny edits with no durable project implication: pure
formatting, dependency version bumps, or a change explicitly scoped to one small
function where no architecture, build, or troubleshooting knowledge is needed.

## Start Of Work

1. Read `docs/project-knowledge/index.md`.
2. Follow its routing table and load the smallest relevant slice.
3. If an exact route matches multiple categories, combine those exact routes.
   The three-file limit applies only to the ambiguous fallback route.
4. Check `Last verified`. If missing or older than 45 days, treat the entry as a
   hint and verify before relying on it.
5. Inspect current code/tests after the knowledge slice. Code and tests remain
   the implementation authority.

Do not replace this with a broad grep/code scan, `AGENTS.md` only, or local
memory only. Those may be useful, but they are not the project knowledge entry
point.

## Routing Shortcuts

| Task signal | Read first |
| --- | --- |
| bug, hang, regression, failing test | `index.md`, `troubleshooting-playbook.md`, `build-and-test.md` |
| architecture, state ownership, data flow | `index.md`, `architecture.md`, `module-boundaries.md`, relevant `decisions/` |
| Flutter/Dart, proxy, SDK, command failure | `index.md`, `build-and-test.md`, `troubleshooting-playbook.md` |
| naming, commit, UTF-8, UI taste, repo style | `index.md`, `conventions.md` |
| risk, blocker, debt, long-term TODO | `index.md`, `open-risks.md` |

If the task names a known feature, also read the relevant decision or
troubleshooting entry named by the index before expanding to code.

## End Of Work

Before final response on non-trivial work, decide whether the task created
durable knowledge:

- recurring troubleshooting symptom or environment command;
- new architecture, ownership, protocol, or product decision;
- quality gate, accepted verification command, or test caveat;
- risk, blocker, technical debt, or long-term TODO;
- glossary term or field semantics future agents must preserve.

If yes, update the smallest relevant file under `docs/project-knowledge/`. If
no, state briefly that no project-knowledge update was needed. Do not delay a
requested commit/push for unrelated documentation churn.

## Promotion Rules

Repo knowledge requires evidence. Promote only when the content has durable
value and at least one concrete anchor:

- current code path;
- verification command or test result;
- reproducible symptom;
- linked spec/decision;
- explicit user decision.

Operational tips need both:

- the lesson helped in at least two independent tasks, or the user explicitly
  asked to preserve it for future work;
- a verification command, reproducible symptom, or repo-relative code path.

Architecture decisions need:

- accepted status or clear user decision;
- evidence from code, tests, or linked design;
- `Last verified`;
- re-evaluation conditions.

If the user says "remember", "save", "preserve", "记录", "保存", or "沉淀"
without explicitly saying repo/project knowledge, default to local memory or a
promotion candidate. Promote to `docs/project-knowledge/` only when the evidence
rules above are met. If the user explicitly asks for repo/project knowledge but
evidence is incomplete, either narrow the entry or mark it `Status: unverified`
with a concrete verification needed line.

Do not promote chat transcripts, ordinary command logs, private machine noise,
secrets, unverified guesses, or facts that are already obvious from nearby code.

## Templates

Use a lightweight operational tip for commands and troubleshooting facts:

```markdown
## Symptom: xxx

- Symptom:
- Action:
- Verification:
- Last verified: yyyy-mm-dd
```

Use an ADR-style entry for durable decisions:

```markdown
# Decision: xxx

- Status:
- Date:
- Last verified:

## Context
## Decision
## Alternatives
## Evidence
## Verification
## Re-evaluate When
```

Prefer one decision file under `docs/project-knowledge/decisions/` per durable
decision.

## Staleness And Capacity

- Missing or stale `Last verified` means "hint", not "trusted fact".
- Do not re-verify every entry every time; verify only entries that affect the
  task.
- Keep `index.md` small and route to narrow slices.
- Do not route normal tasks to `archive/`.
- Move replaced/rejected entries to `archive/` only when they are no longer
  active and have not been needed recently.

## Concurrent Agents

Knowledge files are shared Git content. Reduce conflicts:

- append playbook/convention/risk entries instead of reordering large sections;
- use one ADR file per decision;
- before committing knowledge changes, inspect `git status -sb`;
- if a pull/rebase creates a knowledge conflict, preserve both independent
  entries first, then deduplicate with evidence.

## Red Flags

Stop and use the project knowledge index when you think:

- "AGENTS.md already has enough."
- "Local memory remembers this."
- "I can diagnose from code first and read docs later."
- "The user asked to commit/push, so knowledge can be skipped."
- "They asked to save everything, so I should store the whole chat."

Correct response:

- read `docs/project-knowledge/index.md`;
- route to the smallest slice;
- verify current code/tests;
- capture only durable, evidenced knowledge.
