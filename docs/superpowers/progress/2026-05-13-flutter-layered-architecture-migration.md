# Flutter Layered Architecture Migration Progress

Date: 2026-05-13
Branch: `flutter-layered-architecture-migration`

## Final structure

- App composition lives under `mobile/lib/src/app/`.
- Domain contracts, use cases, failures, and pure models live under `mobile/lib/src/domain/`.
- Data repository implementations live under `mobile/lib/src/data/`.
- UI shared theme and widgets live under `mobile/lib/src/ui/core/`.
- Feature UI, feature ViewModels, and feature-local state live under `mobile/lib/src/ui/features/`.
- Legacy production roots `mobile/lib/src/features`, `mobile/lib/src/widgets`, `mobile/lib/src/theme`, and `mobile/lib/src/state` have zero active imports and their compatibility exports were removed.

## Verification evidence

Commands run from `mobile/`:

- `dart analyze`
- `dart run tool/check_architecture_imports.dart`
- `flutter test -r expanded`

Final architecture guard counts:

- `src/features/ 0`
- `src/widgets/ 0`
- `src/theme/ 0`
- `src/state/ 0`

Full Flutter test result:

- `183` tests passed.
- `1` ASR native recognizer smoke test skipped because `ASR_MODEL_DIR` was not set.

## Additional fixes made during final verification

- `DaemonClient` now retries a transient `http.ClientException` for GET requests, matching the existing retry test and the HTTP client abstraction used by the app.
- `protocol.warning` conversation events are diagnostic-only by default and become visible notices only when `visible: true`, which preserves the empty-completion diagnostic path.

## Remaining architecture debt

The architecture guard reports no forbidden imports and no allowed migration debt.

During final cleanup, `mobile/lib/lan_ai_cli_control.dart` stopped exporting `src/testing/testing.dart`, and `ConnectedAppSession` was made generic so the domain model no longer imports the concrete `DaemonClient`.
