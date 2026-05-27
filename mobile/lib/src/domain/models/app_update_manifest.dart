class AppUpdateManifest {
  const AppUpdateManifest({
    required this.schemaVersion,
    required this.platform,
    required this.available,
    this.packageName,
    this.versionName,
    this.versionCode,
    this.minSupportedVersionCode,
    this.mandatory = false,
    this.apkUrl,
    this.sha256,
    this.sizeBytes,
    this.etag,
    this.releaseNotes,
    this.publishedAt,
    this.fileName,
  });

  final int schemaVersion;
  final String platform;
  final bool available;
  final String? packageName;
  final String? versionName;
  final int? versionCode;
  final int? minSupportedVersionCode;
  final bool mandatory;
  final String? apkUrl;
  final String? sha256;
  final int? sizeBytes;
  final String? etag;
  final String? releaseNotes;
  final DateTime? publishedAt;
  final String? fileName;

  factory AppUpdateManifest.fromJson(Map<String, Object?> json) {
    final schemaVersion = json['schemaVersion'];
    if (schemaVersion != 1) {
      throw FormatException(
        'Unsupported update manifest schemaVersion: $schemaVersion',
      );
    }
    final platform = json['platform'];
    if (platform != 'android') {
      throw FormatException('Unsupported update manifest platform: $platform');
    }
    final available = json['available'] as bool? ?? true;
    if (!available) {
      return const AppUpdateManifest(
        schemaVersion: 1,
        platform: 'android',
        available: false,
      );
    }

    final publishedAt = json['publishedAt'] as String?;
    return AppUpdateManifest(
      schemaVersion: 1,
      platform: 'android',
      available: true,
      packageName: _requiredString(json, 'packageName'),
      versionName: _requiredString(json, 'versionName'),
      versionCode: _requiredPositiveInt(json, 'versionCode'),
      minSupportedVersionCode: _requiredNonNegativeInt(
        json,
        'minSupportedVersionCode',
      ),
      mandatory: json['mandatory'] as bool? ?? false,
      apkUrl: _requiredString(json, 'apkUrl'),
      sha256: _requiredSha256(json, 'sha256'),
      sizeBytes: _requiredPositiveInt(json, 'sizeBytes'),
      etag: _requiredString(json, 'etag'),
      releaseNotes: json['releaseNotes'] as String?,
      publishedAt: publishedAt == null ? null : DateTime.tryParse(publishedAt),
      fileName: json['fileName'] as String?,
    );
  }

  bool isNewerThan(int installedVersionCode) =>
      available && versionCode != null && versionCode! > installedVersionCode;

  bool isMandatoryFor(int installedVersionCode) =>
      available &&
      (mandatory ||
          (minSupportedVersionCode != null &&
              installedVersionCode < minSupportedVersionCode!));

  Uri resolveApkUri(Uri daemonBaseUri) {
    final value = apkUrl;
    if (value == null || value.isEmpty) {
      throw const FormatException('Update manifest apkUrl is missing.');
    }
    final resolved = daemonBaseUri.resolve(value);
    if (resolved.scheme != daemonBaseUri.scheme ||
        resolved.authority != daemonBaseUri.authority) {
      throw FormatException('Update manifest apkUrl is cross-origin: $value');
    }
    return resolved;
  }
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Update manifest $key is required.');
}

int _requiredPositiveInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int && value > 0) return value;
  throw FormatException('Update manifest $key must be a positive integer.');
}

int _requiredNonNegativeInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int && value >= 0) return value;
  throw FormatException('Update manifest $key must be a non-negative integer.');
}

String _requiredSha256(Map<String, Object?> json, String key) {
  final value = _requiredString(json, key);
  if (RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(value)) return value;
  throw FormatException(
    'Update manifest $key must be a 64-character hex hash.',
  );
}
