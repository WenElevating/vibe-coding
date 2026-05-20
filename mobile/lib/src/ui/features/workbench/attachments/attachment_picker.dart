import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../../../../domain/models/attachment_types.dart';
import 'draft_attachment.dart';

class WorkbenchAttachmentPicker {
  const WorkbenchAttachmentPicker();

  Future<List<DraftAttachment>> pickAttachments() async {
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      withData: false,
      type: FileType.custom,
      allowedExtensions: const <String>[
        'png',
        'jpg',
        'jpeg',
        'webp',
        'txt',
        'md',
        'markdown',
        'json',
        'log',
        'csv',
        'pdf',
      ],
    );
    if (result == null) return const <DraftAttachment>[];

    final drafts = <DraftAttachment>[];
    for (final file in result.files) {
      final path = file.path;
      if (path == null || path.isEmpty) continue;
      final size = file.size > 0 ? file.size : await File(path).length();
      drafts.add(DraftAttachment(
        localPath: path,
        name: file.name,
        mimeType: mimeTypeForName(file.name),
        kind: attachmentKindForName(file.name),
        sizeBytes: size,
      ));
    }
    return drafts;
  }
}

AttachmentKind attachmentKindForName(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.png') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.webp')) {
    return AttachmentKind.image;
  }
  if (lower.endsWith('.pdf')) return AttachmentKind.pdf;
  if (lower.endsWith('.txt') ||
      lower.endsWith('.md') ||
      lower.endsWith('.markdown') ||
      lower.endsWith('.json') ||
      lower.endsWith('.log') ||
      lower.endsWith('.csv')) {
    return AttachmentKind.textDocument;
  }
  return AttachmentKind.unsupported;
}

String mimeTypeForName(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.json')) return 'application/json';
  if (lower.endsWith('.md') || lower.endsWith('.markdown')) {
    return 'text/markdown';
  }
  if (lower.endsWith('.csv')) return 'text/csv';
  return 'text/plain';
}
