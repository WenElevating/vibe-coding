# Codex App-Server Protocol Fixtures

These fixtures are generated from the local Codex app-server protocol and are
used by daemon tests to keep the `codex-app-server` adapter aligned with the
official JSON-RPC API surface.

## Source

- Generated on: 2026-06-04
- Generator version: `codex-cli 0.137.0`
- Command:

```powershell
codex app-server generate-json-schema --experimental --out daemon\test\fixtures\codex-app-server\schema
```

`--experimental` is intentional. The capability matrix records stability for
each method instead of hiding experimental protocol members.

## Refresh Rules

1. Run `codex --version` and record the version in this file when refreshing.
2. Regenerate the schema with `--experimental`.
3. Run `node scripts\run-tests.js`.
4. If official methods were added, update
   `daemon/src/codex-app-server/capability-matrix.js` with safe default rows.
5. Do not mark a method active while its risk is `unknown`.
