import 'package:flutter/material.dart';

import '../../../../models/protocol.dart';
import '../attachments/draft_attachment.dart';
import '../coding_composer.dart';
import '../voice_input.dart';
import '../widgets/workbench_header.dart';

const _codexWorkbenchBackground = Color(0xFF151515);
const _codexWorkbenchHeader = Color(0xF2181818);
const _codexWorkbenchDivider = Color(0xFF2A2A2A);

class WorkbenchConversationRoute extends StatelessWidget {
  const WorkbenchConversationRoute({
    super.key,
    required this.title,
    required this.workspace,
    required this.adapter,
    required this.modelLabel,
    required this.modelNotice,
    required this.running,
    required this.cliLocked,
    required this.modelLocked,
    required this.canSend,
    required this.sending,
    required this.voiceState,
    required this.voiceEnabled,
    required this.draftAttachments,
    required this.slashCommands,
    required this.promptController,
    required this.messageList,
    this.approvalPrompt,
    required this.onBack,
    required this.onSlashCommandSelected,
    required this.onAttachmentTap,
    required this.onRemoveAttachment,
    required this.onCliTap,
    required this.onModelTap,
    required this.onVoiceStart,
    required this.onVoiceStop,
    required this.onVoiceCancel,
    required this.onTextChanged,
    required this.onSend,
    required this.onCancel,
    required this.onWorkspaceTap,
  });

  final String title;
  final WorkspaceSummary workspace;
  final String? adapter;
  final String? modelLabel;
  final String? modelNotice;
  final bool running;
  final bool cliLocked;
  final bool modelLocked;
  final bool canSend;
  final bool sending;
  final VoiceInputState voiceState;
  final bool voiceEnabled;
  final List<DraftAttachment> draftAttachments;
  final List<SlashCommand> slashCommands;
  final TextEditingController promptController;
  final Widget messageList;
  final Widget? approvalPrompt;
  final VoidCallback onBack;
  final ValueChanged<SlashCommand> onSlashCommandSelected;
  final VoidCallback onAttachmentTap;
  final ValueChanged<int> onRemoveAttachment;
  final VoidCallback onCliTap;
  final VoidCallback onModelTap;
  final VoidCallback onVoiceStart;
  final VoidCallback onVoiceStop;
  final VoidCallback onVoiceCancel;
  final ValueChanged<String> onTextChanged;
  final VoidCallback onSend;
  final VoidCallback onCancel;
  final VoidCallback onWorkspaceTap;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _codexWorkbenchBackground,
      child: Column(key: const ValueKey('coding-workbench-detail'), children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 9),
          decoration: const BoxDecoration(
            color: _codexWorkbenchHeader,
            border: Border(
              bottom: BorderSide(color: _codexWorkbenchDivider),
            ),
          ),
          child: WorkbenchHeader(
            title: title,
            workspace: workspace,
            adapter: adapter,
            running: running,
            onBack: onBack,
          ),
        ),
        Expanded(child: messageList),
        approvalPrompt ??
            CodingComposer(
              controller: promptController,
              adapter: adapter,
              model: modelLabel,
              modelNotice: modelNotice,
              workspace: workspace,
              running: running,
              cliLocked: cliLocked,
              modelLocked: modelLocked,
              canSend: canSend,
              sending: sending,
              voiceState: voiceState,
              voiceEnabled: voiceEnabled,
              voiceError: null,
              draftAttachments: draftAttachments,
              slashCommands: slashCommands,
              onSlashCommandSelected: onSlashCommandSelected,
              onAttachmentTap: onAttachmentTap,
              onRemoveAttachment: onRemoveAttachment,
              onCliTap: onCliTap,
              onModelTap: onModelTap,
              onVoiceStart: onVoiceStart,
              onVoiceStop: onVoiceStop,
              onVoiceCancel: onVoiceCancel,
              onTextChanged: onTextChanged,
              onSend: onSend,
              onCancel: onCancel,
            ),
        ComposerWorkspaceCloud(
          workspace: workspace,
          adapter: adapter,
          running: running,
          cliLocked: cliLocked,
          onCliTap: onCliTap,
          onTap: onWorkspaceTap,
        ),
      ]),
    );
  }
}
