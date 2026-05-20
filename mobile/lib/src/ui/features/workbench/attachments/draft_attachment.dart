import '../../../../domain/models/attachment_types.dart';

class DraftAttachment {
  const DraftAttachment({
    required this.localPath,
    required this.name,
    required this.mimeType,
    required this.kind,
    required this.sizeBytes,
    this.errorCode,
    this.errorMessage,
  });

  final String localPath;
  final String name;
  final String mimeType;
  final AttachmentKind kind;
  final int sizeBytes;
  final String? errorCode;
  final String? errorMessage;

  bool get isValid => errorCode == null;

  DraftAttachment copyWith({
    String? errorCode,
    String? errorMessage,
  }) =>
      DraftAttachment(
        localPath: localPath,
        name: name,
        mimeType: mimeType,
        kind: kind,
        sizeBytes: sizeBytes,
        errorCode: errorCode,
        errorMessage: errorMessage,
      );
}
