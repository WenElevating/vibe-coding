import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../core/theme/theme.dart' as theme;
import '../conversation_reducer.dart';
import '../workbench_messages.dart';
import 'event_card_frame.dart';
import 'patch_transcript_panel.dart';

class DiffEventCard extends StatelessWidget {
  const DiffEventCard({super.key, required this.message});
  final WorkbenchMessage message;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AgentEventCard(
      icon: Icons.call_split_rounded,
      title: l10n.workbenchDiffEventTitle,
      meta: l10n.workbenchDiffEventMeta,
      trailing: null,
      child: EventCodeLine(text: message.body, ok: true));
  }
}

class FileChangeEventCard extends StatelessWidget {
  const FileChangeEventCard({super.key, required this.message});
  final WorkbenchMessage message;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final changes = message.fileChanges;
    final visibleChanges = changes.take(2).toList(growable: false);
    final title = changes.length == 1
        ? _fileChangeTitle(l10n, changes.single)
        : l10n.workbenchFileChangeMultiTitle(changes.length);
    return AgentEventCard(
        icon: Icons.edit_note_rounded,
        title: title,
        meta: l10n.workbenchFileChangeMeta,
        trailing: null,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: changes.isEmpty
                ? <Widget>[FileChangeFallback(text: message.body)]
                : visibleChanges
                    .map<Widget>((change) => Padding(
                        padding: EdgeInsets.only(
                            bottom: change == visibleChanges.last ? 0 : 10),
                        child: PatchTranscriptFile(change: change)))
                    .followedBy(changes.length > 2
                        ? <Widget>[
                            Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Text(
                                    l10n.workbenchFileChangeMoreFiles(
                                        changes.length - 2),
                                    style: const TextStyle(
                                        color: theme.faint,
                                        fontSize: 11,
                                        fontFamily: 'Consolas')))
                          ]
                        : const <Widget>[])
                    .toList(growable: false)));
  }

  static String _fileChangeTitle(
      AppLocalizations l10n, ConversationFileChange change) {
    final kind = change.kind.toLowerCase();
    final path = shortPathName(change.path);
    return switch (kind) {
      'add' || 'added' => l10n.workbenchFileChangeAddedTitle(path),
      'delete' || 'deleted' || 'remove' || 'removed' =>
        l10n.workbenchFileChangeDeletedTitle(path),
      _ => l10n.workbenchFileChangeEditedTitle(path),
    };
  }
}
