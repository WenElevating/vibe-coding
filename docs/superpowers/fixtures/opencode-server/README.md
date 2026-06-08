# OpenCode Server Smoke Fixtures

These fixtures separate two kinds of evidence:

- `fake_contract`: route, body, and event assumptions exercised by the committed
  fake OpenCode server and daemon integration tests.
- `pass`: assumptions verified against a live `opencode serve` process.

The current implementation is gated by the fake contract for the first
integration path. That does not imply live OpenCode compatibility while the
manifest top-level `status` remains `not_run`.

Live smoke remains required before treating these assumptions as provider
compatibility evidence. Keep live-only gates such as terminal session status
values and history replay as `not_run` or `blocked` until a live run records a
decision.

The smoke runner defaults to non-model-consuming checks. A prompt dispatch check
requires an explicit `--allow-prompt-dispatch` flag.
