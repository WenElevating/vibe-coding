import '../../domain/models/attachment_types.dart';

export '../../domain/models/attachment_types.dart';

class AttachmentCapabilities {
  const AttachmentCapabilities({
    this.image = AttachmentHandling.unsupported,
    this.textDocument = AttachmentHandling.textExtract,
    this.pdf = AttachmentHandling.unsupported,
  });

  final AttachmentHandling image;
  final AttachmentHandling textDocument;
  final AttachmentHandling pdf;

  factory AttachmentCapabilities.fromJson(Object? value) {
    final json = _objectMap(value);
    return AttachmentCapabilities(
      image: parseAttachmentHandling(
        json['image'],
        fallback: AttachmentHandling.unsupported,
      ),
      textDocument: parseAttachmentHandling(
        json['textDocument'],
        fallback: AttachmentHandling.textExtract,
      ),
      pdf: parseAttachmentHandling(
        json['pdf'],
        fallback: AttachmentHandling.unsupported,
      ),
    );
  }
}

class CommittedAttachment {
  const CommittedAttachment({
    required this.id,
    required this.name,
    required this.kind,
    required this.mimeType,
    required this.sizeBytes,
    required this.handling,
    this.localPath,
  });

  final String id;
  final String name;
  final AttachmentKind kind;
  final String mimeType;
  final int sizeBytes;
  final AttachmentHandling handling;
  final String? localPath;

  factory CommittedAttachment.fromJson(Map<String, Object?> json) =>
      CommittedAttachment(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        kind: parseAttachmentKind(json['kind']),
        mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
        handling: parseAttachmentHandling(json['handling']),
        localPath: _optionalString(json['localPath']),
      );

  CommittedAttachment copyWith({
    String? localPath,
  }) =>
      CommittedAttachment(
        id: id,
        name: name,
        kind: kind,
        mimeType: mimeType,
        sizeBytes: sizeBytes,
        handling: handling,
        localPath: localPath ?? this.localPath,
      );
}

AttachmentKind parseAttachmentKind(Object? value) => switch (value) {
      'image' => AttachmentKind.image,
      'textDocument' => AttachmentKind.textDocument,
      'pdf' => AttachmentKind.pdf,
      _ => AttachmentKind.unsupported,
    };

AttachmentHandling parseAttachmentHandling(
  Object? value, {
  AttachmentHandling fallback = AttachmentHandling.unsupported,
}) =>
    switch (value) {
      'native' => AttachmentHandling.native,
      'text_extract' => AttachmentHandling.textExtract,
      'staged_path' => AttachmentHandling.stagedPath,
      'unsupported' => AttachmentHandling.unsupported,
      _ => fallback,
    };

Map<String, Object?> _objectMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is! Map) {
    return const <String, Object?>{};
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is String) {
      result[key] = entry.value;
    }
  }
  return result;
}

String? _optionalString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
