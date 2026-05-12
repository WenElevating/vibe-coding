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

This project intentionally has no third-party package dependencies beyond Flutter SDK packages for now.
