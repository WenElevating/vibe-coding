# Slash Command Menu Design

- Date: 2026-05-31
- Status: approved design
- Scope: mobile workbench composer and daemon command catalog

## Context

The mobile workbench composer should support slash command discovery for the
currently selected CLI. The user types a slash token such as `/` or `/co`, sees a
compact command menu above the composer, and selects a command to insert it at
the current cursor position.

The product is a focused coding control surface, so the menu should feel like a
native command helper rather than a modal command palette. It should match the
existing workbench theme, stay dense, and keep the execution path explicit. The
feature must not change the conversation send protocol.

## Goals

- Show commands for the active CLI adapter only.
- Filter only by command text after `/`.
- Insert the selected command at the current cursor position.
- Fetch command data once when entering a conversation for an adapter.
- Keep the menu visually minimal: command and description only.
- Preserve existing send behavior. Choosing a command does not send.

## Non-Goals

- Do not execute slash commands immediately on selection.
- Do not search descriptions for v1 filtering.
- Do not add command grouping, icons, tags, or source labels in the menu.
- Do not introduce a new dependency injection framework.
- Do not change daemon conversation messages or CLI process protocols.

## Interaction

Slash detection is based on the current cursor position. The workbench finds the
nearest token before the cursor that starts with `/` and has no whitespace
between the slash and the cursor.

Examples:

- `/` shows the current adapter command list.
- `/co` shows commands whose command text starts with or contains `co`, such as
  `/compact` and `/code-review`.
- `please run /co` also shows matching commands because the token before the
  cursor is `/co`.
- `please /co run` does not show the menu when the cursor is after `run`,
  because the active cursor token is no longer the slash token.

Filtering uses only the normalized command text without the leading slash. It
does not search the description. Matching should prefer prefix matches before
contains matches, then sort by command text for stable results.

Normalization is deterministic and happens in mobile filtering:

- trim surrounding whitespace;
- ensure a single leading slash for display and insertion;
- remove the leading slash for matching;
- fold ASCII letters to lowercase for matching and sorting;
- keep punctuation such as `-`, `_`, and `:` unchanged.

Commands whose normalized matching key is identical are treated as the same
command. For example, `/Code-Review` and `/code-review` both normalize to
`code-review`; the first item returned by the daemon wins and later duplicates
are ignored. The daemon should avoid duplicates, but mobile deduplicates so the
menu stays stable if a catalog contains aliases or mixed casing.

When the user selects an item, the active slash token is replaced with the
command text at the cursor location. The inserted command includes a trailing
space, for example `/compact `. Text before and after the token is preserved.
The selection moves to the end of the inserted command.

The menu should be dismissed when:

- no active slash token exists at the cursor;
- the composer is sending or the CLI is running in a state that prevents input;
- the user selects a command;
- the user clears the composer;
- the selected adapter changes and no catalog is available yet.

## Visual Design

The menu is rendered directly above the composer, not as a modal or full command
palette. It uses the current workbench theme colors and typography.

Each row contains:

- command, such as `/model`;
- description, such as `choose what model and reasoning effort to use`.

No extra metadata is shown in v1. This matches the compact terminal-like shape
shown in the reference image: command at the left, description aligned to the
right in the remaining space.

The menu should be positioned as an overlay above the composer rather than a
normal child that changes composer layout height. The composer stays fixed at
the bottom while the menu appears, filters, shrinks, or dismisses.

The menu shows at most six visible rows and becomes scrollable when there are
more commands. When matches shrink from six rows to one row, the menu height may
shrink to the single-row height because the overlay does not move the composer.
This avoids a large blank panel while still meeting the stable-composer goal.
Row height itself is fixed so each result remains easy to scan. Selected or
pressed rows use a quiet background tint or existing stroke color. The command
text uses the existing accent color. The description uses the existing muted or
faint text color.

Empty and loading states are intentionally quiet:

- while loading, do not block typing;
- on load failure, do not show an error banner in the composer;
- if no commands match, hide the menu.

## Data Contract

Add a daemon-side slash command catalog endpoint. Recommended shape:

```http
GET /api/adapters/:adapterId/slash-commands
```

Unknown adapters return HTTP 200 with an empty `commands` array. They do not
return 4xx. This lets mobile treat an unknown or temporarily unsupported adapter
as an empty catalog instead of a request failure.

Response:

```json
{
  "adapter": "codex",
  "commands": [
    {
      "command": "/model",
      "description": "choose what model and reasoning effort to use"
    }
  ]
}
```

`command` is the canonical display and insertion string. It should include one
leading slash. Mobile normalizes defensively if the daemon omits the slash or
uses mixed case.

`description` is a single display string in v1. It is not used for filtering.
The daemon may return English descriptions only. If localized command
descriptions are needed later, add an optional field such as `descriptions` or a
locale-aware endpoint without changing the v1 `description` meaning.

The daemon owns the mapping from adapter to command list. The mobile app should
not hardcode full CLI command inventories. This keeps the mobile UI stable when
Claude, Codex, or OpenCode changes command support.

The daemon may source commands from static adapter profiles in v1. Later it can
extend the same endpoint with discovered CLI commands, user-defined commands, or
workspace commands without changing the mobile composer contract.

## Mobile Architecture

Add a dedicated `SlashCommandCatalogRepository` at the data boundary. Do not
extend `CommandCatalogRepository` for v1. The existing repository owns global
shortcuts, command templates, and extensions; slash commands are adapter-scoped
native composer affordances with different loading and filtering semantics.
Keeping them separate avoids a mixed catalog abstraction before shortcuts and
templates intentionally join the slash menu.

The repository should expose:

- cached commands by adapter;
- load once per adapter unless forced;
- loading and error state that does not interfere with composer input.

Repository loads should be race-safe. Each request is associated with the
adapter id it was started for and a per-adapter generation. The generation is a
monotonically increasing integer stored by adapter id. Every force reload or
new network request increments that adapter's generation before the request is
started. Responses update only that adapter's cache if the response generation
still equals the current generation. The workbench should also compare the
visible adapter id before presenting results. In a fast adapter sequence such as
A to B to A, a late B response must not replace or display commands for A.

Inject the repository through `WorkbenchDependencies`. Do not pass command state
through `MainTabsShellViewModel`.

`CodingWorkbenchPage` owns composer slash state because it already owns the
`TextEditingController`, selected adapter, route state, and send behavior. It
should:

- trigger the adapter command load when entering a conversation;
- trigger a new load when the selected adapter changes and no cache exists;
- derive the active slash token from `TextEditingValue`;
- filter cached commands;
- update the controller value when a command is selected.

`CodingComposer` remains mostly presentational. It receives the visible menu
items and a selection callback, then renders the menu above the text field inside
the existing composer column.

## Daemon Architecture

Add a small adapter command catalog module near existing adapter profile and
command template modules. It should return only command and description for v1.

The endpoint should validate adapter ids and return an empty command list for
known adapters with no commands. Unknown adapters also return an empty command
list so the composer can degrade quietly without showing a daemon error while
the user is typing.

Existing shortcut and command template APIs remain unchanged. They can be
integrated into a broader command menu later, but v1 focuses on native slash
commands because the user explicitly wants filtering and insertion of slash
command text.

## Localization

The visible command names and descriptions should come from the daemon catalog.
No loading text is shown in v1; loading is intentionally silent so typing stays
uninterrupted. No-match filtering hides the menu, so no no-match text is needed
in v1.

If the daemon returns English descriptions only, the mobile app should display
them as-is. The `description` field is a single display string. Localizing
daemon command descriptions can be a later catalog enhancement through an
additive field or locale-aware catalog request.

## Testing

Daemon tests:

- returns slash commands for `codex`, `claude`, and `opencode`;
- returns only command and description fields required by mobile v1;
- returns an empty command list for unknown adapters.

Mobile repository tests:

- loads commands once per adapter;
- reuses cached adapter commands;
- force reload updates commands;
- load failure records error but preserves cached data when available.
- late responses for another adapter do not overwrite the visible adapter menu.
- duplicate commands with different casing are deduplicated by normalized key.

Workbench widget tests:

- typing `/` above the composer shows the current adapter command menu;
- typing `/co` filters by command text and matches `/compact` and
  `/code-review`;
- typing `/CO` produces the same filtered results as `/co`;
- descriptions are not used for filtering;
- selecting a command replaces only the active slash token at the cursor;
- insertion preserves text before and after the cursor;
- command insertion adds a trailing space and places the cursor after it;
- the composer text field global offset is unchanged when filtering from many
  menu results to one result;
- entering a conversation loads commands once for the adapter;
- switching adapter loads the new adapter command catalog;
- failed command loading does not block typing or sending.

Verification commands after implementation:

```powershell
node scripts/run-tests.js
cd mobile
flutter test --no-pub test\widget_test.dart -r expanded --plain-name "slash command"
flutter test --no-pub test\adapter_resource_state_test.dart -r expanded
dart analyze lib test
dart run tool\check_architecture_imports.dart
```

## Implementation Decisions

- Unknown adapter command lookup returns an empty command list.
- No-match filtering hides the menu.
- Filtering is case-insensitive and deduplicates commands by normalized
  lowercase key without the leading slash.
- The menu is an overlay above the composer; it may shrink with result count
  because it does not participate in composer layout.
- Unknown adapter command lookup returns HTTP 200 with an empty `commands`
  array, not 4xx.
- Repository request generations are monotonically increasing integers tracked
  per adapter id.
- Use a dedicated `SlashCommandCatalogRepository` instead of extending
  `CommandCatalogRepository`.
- Existing shortcuts and command templates stay out of v1. They can join the
  menu in a later iteration if they can be represented as slash command text
  without changing the compact command-and-description row shape.
