# Workbench Composer and Model Picker Design

## Context

The mobile workbench composer currently exposes CLI selection through a compact chip row, while model selection is visually coupled to CLI selection and is not backed by an explicit model capability contract. The requested direction is to match the refined bottom-sheet style shown in the reference screenshots: a dark rounded composer, subtle borders, small drag handle, precise spacing, and separate CLI/model chips. CLI icons should keep their existing brand/color treatment.

Codex documentation confirms that Codex configuration is stored at user-level `~/.codex/config.toml` and project-level `.codex/config.toml`, and that configuration can set the default `model`, `model_provider`, and optional `model_catalog_json`. The implementation should use this as the authoritative source for Codex model discovery unless a stable CLI model-list command is later introduced.

## Goals

- Restyle the workbench composer to a more polished floating dark panel that matches the current app theme.
- Keep existing colored CLI icons unchanged and remove unnecessary visual chrome around them.
- Support model selection for both Codex and Claude where reliable model information exists.
- Avoid pretending that a CLI supports runtime model switching when the local CLI cannot be verified to accept a model argument.
- Keep conversation-backed histories locked to their original CLI/session semantics.

## Non-Goals

- Do not infer model lists from natural language output.
- Do not add new dependencies for TOML parsing or UI rendering unless an existing repo dependency already covers the need.
- Do not redesign the entire workbench screen.
- Do not change completed or active conversation adapter-lock behavior.
- Do not implement workspace-scoped ViewModel splitting as part of this work.

## Recommended Approach

Use a hybrid model discovery strategy:

1. Read configured/default models from local configuration and process environment.
2. Read catalog-backed model options when `model_catalog_json` exists and is parseable.
3. Verify whether a CLI supports explicit model selection before passing a chosen model to the process.
4. If runtime model switching cannot be verified, expose the model as informational/default-only rather than a fake selectable list.

This keeps the UI useful immediately while avoiding brittle CLI probing.

## Composer UI

The composer should become a bottom floating panel with these properties:

- Outer shell: dark translucent surface, large rounded top/overall corners, subtle border, and small upward shadow.
- Drag handle: centered short rounded bar at the top of the panel, matching the reference bottom-sheet language.
- Text field: calm placeholder, restrained text size, no heavy outline, supports the existing multi-line behavior.
- Chip row: left-aligned CLI chip and model chip, right-aligned action icons.
- CLI chip: existing colored CLI icon plus adapter label; no extra icon border.
- Model chip: compact sparkle/model glyph plus selected model label; opens the model picker.
- Action buttons: smaller, finer icon buttons than the previous oversized treatment.

The composer remains state-driven: running/sending/voice states should update enabled states and hint text without introducing separate page-level empty states.

## Picker UI

### CLI Picker

The CLI picker keeps the current bottom-sheet behavior but adopts the refined reference style:

- Header with icon, title, and a short lock/status subtitle.
- Rows use brand-colored CLI icons and concise version/status text.
- Selected row uses a subtle check indicator.
- Running or conversation-bound sessions show a clear disabled state instead of allowing mutation.

### Model Picker

The model picker mirrors the CLI picker but lists models for the selected adapter:

- Header title uses localized strings, not hard-coded mixed-language labels.
- Subtitle shows current CLI and source, such as `当前 CLI: codex` or `来自 Codex 配置`, via localization.
- Rows show model name, optional source/description, and a selected check.
- If only one model exists, show one selectable/current row and explanatory secondary text.
- If no model is known, show `默认模型` as an informational row and keep sending available.

## Model Capability Contract

Expose model capability data from the daemon to mobile either by extending `/api/adapters` or adding a small adjacent endpoint. Extending `/api/adapters` is preferred because the mobile workbench already refreshes adapter capabilities.

Suggested shape:

```json
{
  "adapter": "codex",
  "available": true,
  "version": "codex-cli 0.130.0",
  "models": [
    {
      "id": "gpt-5.5",
      "label": "gpt-5.5",
      "source": "codex_config",
      "selected": true
    }
  ],
  "selectedModel": "gpt-5.5",
  "canSelectModel": true
}
```

Fields:

- `models`: Can be empty when discovery fails.
- `selectedModel`: Current configured/default model when known.
- `canSelectModel`: True only when the daemon can safely pass a selected model to the CLI process.
- `source`: Diagnostic/display source only; business logic should use normalized fields. Known values are `codex_config`, `codex_catalog`, `claude_env`, `cli_default`, and `unknown`. The list is additive; mobile should localize known values and display a neutral fallback for unknown values.
- `protocolVersion`: Optional future-proof additive field if a breaking contract ever becomes necessary; this rollout does not require one.

## Compatibility Strategy

The protocol change is additive and must be backward compatible by default.

- New mobile + old daemon: missing `models`, `selectedModel`, or `canSelectModel` fields are treated as `models = []`, `selectedModel = null`, and `canSelectModel = false`.
- Old mobile + new daemon: extra fields are ignored by the older JSON parser and must not break parsing.
- The mobile protocol layer must tolerate absent fields without surfacing an error.
- If the daemon ever needs a breaking shape, introduce an explicit versioned endpoint or `protocolVersion` gate rather than changing the additive contract in place.

## Codex Model Discovery

Codex model discovery should use official configuration locations:

1. User config: `~/.codex/config.toml`.
2. Project config: `.codex/config.toml` under the workspace/repo when trusted and present.
3. Project config overrides user config for scalar keys such as `model` and `model_provider`.
4. `model_catalog_json` can add model candidates if the referenced JSON file exists and is parseable.
5. The configured `model` should be first and selected when present.

Parsing rules:

- Only parse the small TOML subset needed for this feature: top-level simple scalar assignments and the specific nested `model_providers` / `shell_environment_policy.set` values already used by the app.
- Skip unfamiliar TOML constructs instead of trying to fully interpret them.
- Never crash on comments, inline tables, multi-line strings, or malformed syntax; ignore what cannot be safely read.
- If `model_catalog_json` points to a missing file, a directory, an unreadable file, or a file larger than the configured safe size limit, ignore it and continue with the remaining sources.
- Default catalog size cap is 1 MB, held as an internal daemon constant so it can be adjusted without changing the protocol.

No new TOML dependency should be added unless the repo already contains one that fits this use case.

## Claude Model Discovery

Claude model discovery should read stable local sources first and treat any environment-based defaults as best effort:

1. Process environment values such as `ANTHROPIC_DEFAULT_OPUS_MODEL`, `ANTHROPIC_DEFAULT_SONNET_MODEL`, and `ANTHROPIC_DEFAULT_HAIKU_MODEL` when they exist.
2. Repo Codex shell policy values under `.codex/config.toml` when they set Claude environment variables for launched commands.
3. De-duplicate values while preserving priority order.
4. If all three default tiers point to the same model, show one model row.

These environment variable names are treated as implementation-specific discovery hints, not a public stable contract. If none are present, show `默认模型` rather than inventing a model ID.

Before passing a selected model to Claude, detect support from `claude --help` or existing capability detection. Probe once during daemon adapter capability detection and cache the result with the detected CLI command path and version. Re-probe when the adapter is explicitly refreshed and the command path or version changes. If explicit model selection is not supported by the installed CLI, set `canSelectModel` to false and present the discovered model as the default/informational model.

## Sending Behavior

- New conversations may choose adapter and model before the first send.
- Active or resumed conversation-backed histories keep their original adapter/session lock.
- If `canSelectModel` is true and a selected model exists, pass the model through the conversation creation/start path to the adapter.
- If `canSelectModel` is false, do not pass a model argument; only display the default model source.
- If a refresh removes the currently selected model from the available list, keep the current value for an already-running conversation, but for a brand-new unsent draft fall back to the first available model or `selectedModel = null`. Show a short non-blocking note near the model chip in secondary text color; it should disappear on the next user edit, picker open, or successful send and must not require confirmation.
- Missing model data must not block sending.

## Error Handling

- Malformed config files should not break adapter availability; return model discovery warnings only in diagnostics/debug data.
- Missing or unreadable config/catalog files should be ignored with an optional warning. Permission errors are treated the same as absent files.
- CLI help probing failures should set `canSelectModel` to false rather than marking the adapter unavailable.
- Mobile should render empty/unknown model lists gracefully.
- Missing protocol fields must be treated as safe defaults, not as parse failures.

## Security Considerations

- Only read the specific config and catalog file paths needed for discovery.
- Resolve `model_catalog_json` to a real file before reading; reject directories and unreadable paths.
- Apply the 1 MB default size cap to catalog JSON files before parsing to avoid memory spikes.
- Do not send raw config contents or arbitrary file contents to the mobile client.

## Testing Strategy

Daemon tests:

- Codex scalar config discovery from user and project config, with project override.
- Codex catalog discovery when `model_catalog_json` points to a JSON file.
- Codex config parsing ignores comments, multiline strings, and unsupported TOML syntax safely.
- Claude env/config discovery and de-duplication.
- CLI model capability probing failure does not make the adapter unavailable.
- Conversation launch includes a model only when `canSelectModel` is true.

Mobile tests:

- Adapter model fields parse from protocol JSON with missing-field defaults.
- Composer renders separate CLI and model chips.
- Model picker shows selected model and fallback default row.
- Running/conversation-bound state keeps adapter/model mutation disabled.
- Refreshing adapter data with a missing selected model preserves running sessions and falls back safely for new drafts.

Integration smoke test:

- Daemon returns capability JSON, mobile parses it, the picker renders discovered models, and a selected model is forwarded back into the conversation start payload.

Manual/visual verification:

- Confirm composer density and dark theme alignment against the provided screenshots.
- Confirm CLI icons retain their original brand colors.
- Confirm no extra icon borders appear in the selector rows.

## Rollout Plan

1. Add daemon model discovery helpers and tests.
2. Extend adapter capability JSON and mobile protocol models.
3. Add selected model state to the workbench ViewModel and conversation creation path.
4. Restyle the composer and split CLI/model chips.
5. Add the model picker bottom sheet.
6. Gate the UI behind a local feature flag so the new chip can be disabled quickly if needed.
7. Gate daemon model discovery behind an environment variable or startup option so discovery can be disabled without reverting the build.
8. Run daemon tests and focused Flutter tests/analyze with the configured domestic Flutter mirrors.

## Rollback Plan

- If daemon discovery causes performance issues or crashes, disable it through the daemon startup option/environment variable and return an empty `models` array with `canSelectModel = false` while leaving adapter availability intact.
- If the UI regresses, disable the model-chip feature flag and keep the existing CLI chip behavior.
- If Claude discovery proves unstable on a given installation, treat it as informational only and keep sending model-less for that adapter.

## Risks

- Codex and Claude may change config/help output formats; keep parsing narrow and defensive.
- Claude may not support stable runtime model switching on every installed version; do not expose fake selection when unsupported.
- Reading user-level config can contain unrelated/private settings; only parse required keys and never send raw config content to mobile.
- Model catalog formats may vary; accept common simple arrays/maps and ignore unknown shapes.
