export '../../domain/models/app_update_manifest.dart';

class AppUpdateDownloadMetadata {
  const AppUpdateDownloadMetadata({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    required this.sha256,
    required this.sizeBytes,
    required this.etag,
    required this.downloadedBytes,
    required this.updatedAt,
    this.installSessionId,
  });

  final int versionCode;
  final String versionName;
  final String apkUrl;
  final String sha256;
  final int sizeBytes;
  final String etag;
  final int downloadedBytes;
  final DateTime updatedAt;
  final int? installSessionId;

  Map<String, Object?> toJson() => <String, Object?>{
    'versionCode': versionCode,
    'versionName': versionName,
    'apkUrl': apkUrl,
    'sha256': sha256,
    'sizeBytes': sizeBytes,
    'etag': etag,
    'downloadedBytes': downloadedBytes,
    'updatedAt': updatedAt.toIso8601String(),
    if (installSessionId != null) 'installSessionId': installSessionId,
  };

  factory AppUpdateDownloadMetadata.fromJson(Map<String, Object?> json) {
    return AppUpdateDownloadMetadata(
      versionCode: _requiredPositiveInt(json, 'versionCode'),
      versionName: _requiredString(json, 'versionName'),
      apkUrl: _requiredString(json, 'apkUrl'),
      sha256: _requiredSha256(json, 'sha256'),
      sizeBytes: _requiredPositiveInt(json, 'sizeBytes'),
      etag: _requiredString(json, 'etag'),
      downloadedBytes: _requiredNonNegativeInt(json, 'downloadedBytes'),
      updatedAt: DateTime.parse(_requiredString(json, 'updatedAt')),
      installSessionId: json['installSessionId'] as int?,
    );
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
