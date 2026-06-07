# OpenCode Server Smoke Fixtures

These fixtures record the local contract observed from `opencode serve`.
The daemon implementation must not rely on an OpenCode route body, event field,
permission reply shape, session reconciliation route, or terminal session status
until this fixture records it as `pass`.

The smoke runner defaults to non-model-consuming checks. A prompt dispatch check
requires an explicit `--allow-prompt-dispatch` flag.
