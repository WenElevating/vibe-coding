import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart' as theme;
import '../conversation_reducer.dart';
import '../workbench_messages.dart';
import 'event_card_frame.dart';
import 'patch_transcript_panel.dart';

class DiffEventCard extends StatelessWidget {
  const DiffEventCard({super.key, required this.message});
  final WorkbenchMessage message;

  @override
  Widget build(BuildContext context) => AgentEventCard(
      icon: Icons.call_split_rounded,
      title: 'Changed files',
      meta: 'diff summary',
      trailing: null,
      child: EventCodeLine(text: message.body, ok: true));
}

class FileChangeEventCard extends StatelessWidget {
  const FileChangeEventCard({super.key, required this.message});
  final WorkbenchMessage message;

  @override
  Widget build(BuildContext context) {
    final changes = message.fileChanges;
    final visibleChanges = changes.take(2).toList(growable: false);
    final title = changes.length == 1
        ? _fileChangeTitle(changes.single)
        : 'Edited ${changes.length} files';
    return AgentEventCard(
        icon: Icons.edit_note_rounded,
        title: title,
        meta: 'workspace change',
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
                                child: Text('+${changes.length - 2} more files',
                                    style: const TextStyle(
                                        color: theme.faint,
                                        fontSize: 11,
                                        fontFamily: 'Consolas')))
                          ]
                        : const <Widget>[])
                    .toList(growable: false)));
  }

  static String _fileChangeTitle(ConversationFileChange change) {
    final kind = change.kind.toLowerCase();
    final verb = switch (kind) {
      'add' || 'added' => 'Added',
      'delete' || 'deleted' || 'remove' || 'removed' => 'Deleted',
      _ => 'Edited',
    };
    return '$verb ${shortPathName(change.path)}';
  }
}
