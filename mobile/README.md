# LAN AI CLI Control Mobile

Flutter shell for the LAN AI CLI Control client library.

## Run

```powershell
flutter pub get
flutter run -d chrome
```

## Architecture Checks

```powershell
dart run tool/check_architecture_imports.dart
```

The architecture check rejects forbidden layer imports and prints migration-only
import/export counts for old production roots.

Runtime and development packages are declared in `pubspec.yaml`. Keep new
dependencies intentional and prefer existing app, data, domain, workflow, and
UI boundaries before adding packages or new infrastructure.
