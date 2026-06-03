import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../core/theme/theme.dart' as theme;
import '../workbench_messages.dart';
import 'approval_event_card.dart';
import 'assistant_markdown_body.dart';
import 'command_event_card.dart';
import 'diff_event_card.dart';
import 'notice_event_card.dart';
import 'question_event_card.dart';
import 'task_progress_card.dart';
import 'thinking_event_card.dart';
import 'user_message_card.dart';

class WorkbenchMessageCard extends StatelessWidget {
  const WorkbenchMessageCard(
      {super.key,
      required this.message,
      required this.onApproval,
      required this.onSuggestion,
      required this.expandThinking,
      this.expandToolDetails = false});
  final WorkbenchMessage message;
  final ValueChanged<String> onApproval;
  final ValueChanged<String> onSuggestion;
  final bool expandThinking;
  final bool expandToolDetails;
  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final isApproval = message.role == 'approval';
    final isCommand = message.role == 'command';
    final isDiff = message.role == 'diff';
    final isFileChange = message.role == 'file_change';
    final isTool = isCommand || isDiff;
    if (message.role == 'task_progress') {
      return TaskProgressCard(message: message);
    }
    if (isCommand && isSubAgentCommand(message)) {
      return SubAgentCallCard(
          message: message, expandByDefault: expandToolDetails);
    }
    if (isCommand) {
      return CommandEventCard(
          message: message, expandByDefault: expandToolDetails);
    }
    if (isDiff) return DiffEventCard(message: message);
    if (isFileChange) return FileChangeEventCard(message: message);
    if (message.role == 'thinking') {
      return ThinkingEventCard(message: message, expanded: expandThinking);
    }
    if (isApproval) {
      return ApprovalEventCard(message: message, onApproval: onApproval);
    }
    if (message.role == 'question') {
      return QuestionEventCard(message: message, onSuggestion: onSuggestion);
    }
    if (message.role == 'notice') {
      return SystemNoticeEventCard(message: message);
    }
    if (isUser) return UserMessageCard(message: message);
    final color = isApproval
        ? theme.amber
        : isTool
            ? theme.orange
            : theme.green;
    return Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
            widthFactor: 1,
            child: Container(
                padding: EdgeInsets.fromLTRB(16, isApproval ? 12 : 11, 16, 11),
                decoration: BoxDecoration(
                    color: isApproval
                        ? const Color(0xFF101113)
                        : message.role == 'assistant'
                            ? Colors.transparent
                            : const Color(0xFF101113),
                    borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(isApproval ? 14 : 18),
                        topRight: Radius.circular(isApproval ? 14 : 18),
                        bottomLeft: Radius.circular(isApproval ? 14 : 6),
                        bottomRight: Radius.circular(isApproval ? 14 : 18)),
                    border: Border.all(
                        color: isApproval
                            ? Colors.white.withValues(alpha: .08)
                            : message.role == 'assistant'
                                ? Colors.transparent
                                : theme.stroke)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (message.role != 'assistant') ...[
                        Row(children: [
                          Container(
                              width: isApproval ? 24 : 18,
                              height: isApproval ? 24 : 18,
                              alignment: Alignment.center,
                              decoration: isApproval
                                  ? BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      color: theme.amber.withValues(alpha: .10),
                                      border: Border.all(
                                          color: theme.amber
                                              .withValues(alpha: .22)))
                                  : null,
                              child: Icon(
                                  isApproval
                                      ? Icons.shield_outlined
                                      : isTool
                                          ? Icons.build_circle_rounded
                                          : Icons.auto_awesome_rounded,
                                  color: color,
                                  size: isApproval ? 15 : 16)),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(message.title,
                                  style: const TextStyle(
                                      color: theme.text,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700))),
                        ]),
                        const SizedBox(height: 8),
                      ],
                      if (message.attachments.isNotEmpty) ...[
                        MessageAttachmentStrip(
                            attachments: message.attachments, alignEnd: false),
                        if (message.body.trim().isNotEmpty)
                          const SizedBox(height: 8),
                      ],
                      if (message.body.trim().isNotEmpty) ...[
                        if (message.role == 'assistant')
                          AssistantMarkdownBody(markdown: message.body)
                        else
                          Text(message.body,
                              style: TextStyle(
                                  color: theme.muted,
                                  fontSize: 12.5,
                                  height: 1.55,
                                  fontWeight: FontWeight.w400)),
                      ],
                      if (isApproval) ...[
                        const SizedBox(height: 12),
                        if (message.event?.approvalId == null)
                          Text(
                              AppLocalizations.of(context)
                                  .workbenchApprovalMissingId,
                              style: TextStyle(color: theme.red, fontSize: 12))
                        else
                          Row(children: [
                            Expanded(
                                child: ApprovalActionButton(
                                    AppLocalizations.of(context)
                                        .workbenchRejectAction,
                                    color: theme.red,
                                    onTap: () => onApproval('deny'))),
                            const SizedBox(width: 10),
                            Expanded(
                                child: ApprovalActionButton(
                                    AppLocalizations.of(context)
                                        .workbenchApproveAction,
                                    color: theme.purple2,
                                    primary: true,
                                    onTap: () => onApproval('allow'))),
                          ])
                      ]
                    ]))));
  }
}
