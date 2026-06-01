import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../models/protocol.dart';
import '../../../core/theme/theme.dart' as theme;
import '../workbench_messages.dart';

class UserMessageCard extends StatelessWidget {
  const UserMessageCard({super.key, required this.message});

  final WorkbenchMessage message;

  @override
  Widget build(BuildContext context) {
    final body = message.body.trim();
    final bubbles = <Widget>[];
    if (message.attachments.isNotEmpty) {
      final attachmentStrip = MessageAttachmentStrip(
          attachments: message.attachments, alignEnd: true);
      if (_usesBorderlessImageAttachmentFrame(message.attachments)) {
        bubbles.add(KeyedSubtree(
            key: const Key('workbench-user-attachment-bubble'),
            child: attachmentStrip));
      } else {
        bubbles.add(_UserBubbleFrame(
          key: const Key('workbench-user-attachment-bubble'),
          child: attachmentStrip,
        ));
      }
    }
    if (body.isNotEmpty) {
      if (bubbles.isNotEmpty) bubbles.add(const SizedBox(height: 6));
      bubbles.add(_UserBubbleFrame(
        key: const Key('workbench-user-text-bubble'),
        child: Text(body,
            style: const TextStyle(
                color: Color(0xFFF4F4F4),
                fontSize: 14.5,
                height: 1.45,
                fontWeight: FontWeight.w500)),
      ));
    }
    if (bubbles.isEmpty) return const SizedBox.shrink();
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: bubbles);
  }
}

bool _usesBorderlessImageAttachmentFrame(
        List<CommittedAttachment> attachments) =>
    attachments.isNotEmpty &&
    attachments.every((attachment) => attachment.kind == AttachmentKind.image);

class _UserBubbleFrame extends StatelessWidget {
  const _UserBubbleFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
      alignment: Alignment.centerRight,
      child: FractionallySizedBox(
          widthFactor: .78,
          child: Container(
              padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
              decoration: BoxDecoration(
                  color: const Color(0xFF191A1E),
                  borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(18),
                      topRight: Radius.circular(18),
                      bottomLeft: Radius.circular(18),
                      bottomRight: Radius.circular(6)),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: .085))),
              child: child)));
}

class MessageAttachmentStrip extends StatelessWidget {
  const MessageAttachmentStrip({
    super.key,
    required this.attachments,
    required this.alignEnd,
  });

  final List<CommittedAttachment> attachments;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) => Align(
      alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      child: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: alignEnd ? WrapAlignment.end : WrapAlignment.start,
          children: attachments
              .map((attachment) =>
                  _MessageAttachmentPill(attachment: attachment))
              .toList(growable: false)));
}

class _MessageAttachmentPill extends StatelessWidget {
  const _MessageAttachmentPill({required this.attachment});

  final CommittedAttachment attachment;

  @override
  Widget build(BuildContext context) {
    if (attachment.kind == AttachmentKind.image) {
      return _MessageImageAttachmentPreview(attachment: attachment);
    }
    return Tooltip(
        message: attachment.name,
        child: Container(
            constraints: const BoxConstraints(maxWidth: 180),
            padding: const EdgeInsets.fromLTRB(6, 6, 9, 6),
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .045),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: Colors.white.withValues(alpha: .085))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(7)),
                  child: Icon(_attachmentIcon(attachment.kind),
                      color: theme.muted, size: 17)),
              const SizedBox(width: 8),
              Flexible(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(attachment.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: theme.text,
                            fontSize: 11.5,
                            height: 1.1,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0)),
                    const SizedBox(height: 3),
                    Text(_attachmentSizeLabel(attachment.sizeBytes),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: theme.muted,
                            fontSize: 10.5,
                            height: 1,
                            letterSpacing: 0)),
                  ])),
            ])));
  }
}

class _MessageImageAttachmentPreview extends StatelessWidget {
  const _MessageImageAttachmentPreview({required this.attachment});

  final CommittedAttachment attachment;

  @override
  Widget build(BuildContext context) => Semantics(
      button: true,
      child: Tooltip(
          message: attachment.name,
          child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _showImageAttachmentViewer(context, attachment),
              child: Container(
                  key: const Key('workbench-message-image-preview-shell'),
                  constraints:
                      const BoxConstraints(minWidth: 180, maxWidth: 260),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .045),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: .085))),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                            constraints: const BoxConstraints(maxHeight: 220),
                            width: double.infinity,
                            color: Colors.black.withValues(alpha: .22),
                            child: AspectRatio(
                              aspectRatio: 4 / 3,
                              child: _attachmentPreviewImage(
                                attachment,
                                key: const Key(
                                    'workbench-message-image-preview'),
                                fit: BoxFit.contain,
                                errorIconSize: 22,
                              ),
                            ))),
                    const SizedBox(height: 7),
                    Row(children: [
                      Icon(_attachmentIcon(attachment.kind),
                          color: theme.muted, size: 15),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(attachment.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: theme.text,
                                  fontSize: 11.5,
                                  height: 1.1,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0))),
                      const SizedBox(width: 8),
                      Text(_attachmentSizeLabel(attachment.sizeBytes),
                          style: const TextStyle(
                              color: theme.muted,
                              fontSize: 10.5,
                              height: 1,
                              letterSpacing: 0)),
                    ]),
                  ])))));
}

void _showImageAttachmentViewer(
    BuildContext context, CommittedAttachment attachment) {
  if (_cachedImagePreviewFile(attachment) == null) return;
  showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: const Color(0xF20B0C10),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, animation, secondaryAnimation) =>
          _ImageAttachmentViewer(attachment: attachment),
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(
              opacity: CurvedAnimation(
                  parent: animation, curve: Curves.easeOutCubic),
              child: child));
}

class _ImageAttachmentViewer extends StatelessWidget {
  const _ImageAttachmentViewer({required this.attachment});

  final CommittedAttachment attachment;

  @override
  Widget build(BuildContext context) => Material(
      key: const Key('workbench-message-image-viewer'),
      color: Colors.transparent,
      child: SafeArea(
          child: Stack(children: [
        Positioned.fill(
            child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 52, 12, 18),
                child: InteractiveViewer(
                    minScale: .75,
                    maxScale: 5,
                    boundaryMargin: const EdgeInsets.all(80),
                    child: Center(
                        child: _attachmentPreviewImage(
                      attachment,
                      key: const Key('workbench-message-image-viewer-image'),
                      fit: BoxFit.contain,
                      errorIconSize: 44,
                    ))))),
        Positioned(
            left: 16,
            top: 11,
            right: 64,
            child: Text(attachment.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: theme.text,
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0))),
        Positioned(
            right: 8,
            top: 4,
            child: Container(
                decoration: BoxDecoration(
                    color: const Color(0x1FE6E2D8),
                    borderRadius: BorderRadius.circular(20)),
                child: IconButton(
                    key: const Key('workbench-message-image-viewer-close'),
                    tooltip:
                        MaterialLocalizations.of(context).closeButtonTooltip,
                    icon: const Icon(Icons.close_rounded,
                        color: theme.text, size: 22),
                    onPressed: () => Navigator.of(context).maybePop()))),
      ])));
}

Widget _attachmentPreviewImage(
  CommittedAttachment attachment, {
  required Key key,
  required BoxFit fit,
  required double errorIconSize,
}) {
  Widget errorBuilder(
          BuildContext context, Object error, StackTrace? stackTrace) =>
      Icon(_attachmentIcon(attachment.kind),
          color: theme.muted, size: errorIconSize);

  final localFile = _cachedImagePreviewFile(attachment);
  if (localFile != null) {
    return Image.file(
      localFile,
      key: key,
      fit: fit,
      errorBuilder: errorBuilder,
    );
  }
  return Icon(_attachmentIcon(attachment.kind),
      key: key, color: theme.muted, size: errorIconSize);
}

File? _cachedImagePreviewFile(CommittedAttachment attachment) {
  if (attachment.kind != AttachmentKind.image) return null;
  final localPath = attachment.localPath;
  if (localPath == null) return null;
  final file = File(localPath);
  return file.existsSync() ? file : null;
}

IconData _attachmentIcon(AttachmentKind kind) => switch (kind) {
      AttachmentKind.image => Icons.image_outlined,
      AttachmentKind.pdf => Icons.picture_as_pdf_outlined,
      AttachmentKind.textDocument => Icons.description_outlined,
      AttachmentKind.unsupported => Icons.attach_file_rounded,
    };

String _attachmentSizeLabel(int sizeBytes) {
  if (sizeBytes <= 0) return '0 B';
  const units = <String>['B', 'KB', 'MB', 'GB'];
  var size = sizeBytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  final digits = unit == 0 || size >= 10 ? 0 : 1;
  return '${size.toStringAsFixed(digits)} ${units[unit]}';
}
