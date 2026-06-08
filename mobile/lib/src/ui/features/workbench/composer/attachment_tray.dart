import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../../models/protocol.dart';
import '../../../core/theme/theme.dart' as theme;
import '../attachments/draft_attachment.dart';

class WorkbenchAttachmentTray extends StatelessWidget {
  const WorkbenchAttachmentTray({
    super.key,
    required this.attachments,
    required this.onRemove,
  });

  final List<DraftAttachment> attachments;
  final ValueChanged<int>? onRemove;

  @override
  Widget build(BuildContext context) => SizedBox(
      height: 56,
      width: double.infinity,
      child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          itemBuilder: (context, index) => _AttachmentTile(
              attachment: attachments[index],
              onRemove: onRemove == null ? null : () => onRemove?.call(index)),
          separatorBuilder: (context, index) => const SizedBox(width: 8),
          itemCount: attachments.length));
}

class WorkbenchAttachmentStatus extends StatelessWidget {
  const WorkbenchAttachmentStatus(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Row(children: [
        const Icon(Icons.error_outline_rounded, color: theme.red, size: 14),
        const SizedBox(width: 7),
        Expanded(
            child: Text(text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: theme.red,
                    fontSize: 12,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0)))
      ]);
}

String? localizedAttachmentError(
  BuildContext context,
  DraftAttachment attachment,
) {
  final code = attachment.errorCode;
  if (code == null) return null;
  final l10n = AppLocalizations.of(context);
  return switch (code) {
    'attachment_kind_unsupported' => l10n.workbenchAttachmentUnsupported,
    'attachment_too_large' ||
    'attachment_total_too_large' =>
      l10n.workbenchAttachmentTooLarge,
    _ => attachment.errorMessage,
  };
}

String? firstLocalizedAttachmentError(
  BuildContext context,
  List<DraftAttachment> attachments,
) {
  for (final attachment in attachments) {
    final error = localizedAttachmentError(context, attachment);
    if (error != null && error.trim().isNotEmpty) return error;
  }
  return null;
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({required this.attachment, required this.onRemove});

  final DraftAttachment attachment;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final invalid = !attachment.isValid;
    final errorMessage = localizedAttachmentError(context, attachment);
    return Tooltip(
        message: errorMessage ?? attachment.name,
        child: Container(
            width: 154,
            height: 56,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: const Color(0xFF111214),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: invalid
                        ? theme.red.withValues(alpha: .72)
                        : Colors.white.withValues(alpha: .085))),
            child: Row(children: [
              _AttachmentPreview(attachment),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(attachment.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: invalid ? theme.red : theme.text,
                          fontSize: 11.5,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0))),
              const SizedBox(width: 4),
              Tooltip(
                  message:
                      l10n.workbenchAttachmentRemoveTooltip(attachment.name),
                  child: InkWell(
                      onTap: onRemove,
                      borderRadius: BorderRadius.circular(999),
                      child: SizedBox(
                          width: 22,
                          height: 22,
                          child: Icon(Icons.close_rounded,
                              color: invalid ? theme.red : theme.muted,
                              size: 15)))),
            ])));
  }
}

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview(this.attachment);

  final DraftAttachment attachment;

  @override
  Widget build(BuildContext context) => ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
          width: 42,
          height: 42,
          color: Colors.white.withValues(alpha: .045),
          child: _previewChild()));

  Widget _previewChild() {
    if (attachment.kind == AttachmentKind.image) {
      return Image.file(
        File(attachment.localPath),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.image_outlined, color: theme.muted, size: 20),
      );
    }
    final icon = attachment.kind == AttachmentKind.pdf
        ? Icons.picture_as_pdf_outlined
        : Icons.description_outlined;
    return Icon(icon, color: theme.muted, size: 20);
  }
}
