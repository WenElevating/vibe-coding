import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/data/models/app_update_models.dart';

void main() {
  test('parses available manifest and mandatory min-supported semantics', () {
    final manifest = AppUpdateManifest.fromJson(const <String, Object?>{
      'schemaVersion': 1,
      'platform': 'android',
      'packageName': 'com.example.lan_ai_cli_control',
      'versionName': '1.7.0',
      'versionCode': 5,
      'minSupportedVersionCode': 4,
      'mandatory': false,
      'apkUrl': '/api/app-updates/android/apk/5',
      'sha256':
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'sizeBytes': 20,
      'etag': '"android-apk-5-aaaa"',
      'releaseNotes': 'Compatibility update.',
      'publishedAt': '2026-05-24T10:00:00.000Z',
    });

    expect(manifest.available, true);
    expect(manifest.isNewerThan(4), true);
    expect(manifest.isMandatoryFor(3), true);
    expect(manifest.isMandatoryFor(4), false);
  });

  test('parses unavailable manifest using schema envelope', () {
    final manifest = AppUpdateManifest.fromJson(const <String, Object?>{
      'schemaVersion': 1,
      'platform': 'android',
      'available': false,
    });

    expect(manifest.available, false);
    expect(manifest.versionCode, isNull);
  });

  test('rejects unsupported schema and cross-origin apk url', () {
    expect(
      () => AppUpdateManifest.fromJson(const <String, Object?>{
        'schemaVersion': 2,
        'platform': 'android',
        'available': false,
      }),
      throwsFormatException,
    );

    final manifest = AppUpdateManifest.fromJson(const <String, Object?>{
      'schemaVersion': 1,
      'platform': 'android',
      'packageName': 'com.example.lan_ai_cli_control',
      'versionName': '1.4.0',
      'versionCode': 2,
      'minSupportedVersionCode': 1,
      'mandatory': false,
      'apkUrl': 'https://evil.example/app.apk',
      'sha256':
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      'sizeBytes': 10,
      'etag': '"etag"',
      'publishedAt': '2026-05-24T10:00:00.000Z',
    });

    expect(
      () => manifest.resolveApkUri(Uri.parse('http://127.0.0.1:4317')),
      throwsFormatException,
    );
  });
}
