import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart' as theme;
import '../workbench_messages.dart';
import 'event_card_frame.dart';

class SystemNoticeEventCard extends StatelessWidget {
  const SystemNoticeEventCard({super.key, required this.message});
  final WorkbenchMessage message;

  @override
  Widget build(BuildContext context) {
    return AgentEventCard(
        icon: message.isError
            ? Icons.error_outline_rounded
            : Icons.info_outline_rounded,
        title: message.title,
        meta: _noticeMeta(message),
        trailing: null,
        accentColor: message.isError ? theme.red : null,
        child: Text(message.body,
            style: TextStyle(
                color: message.isError ? theme.text : theme.muted,
                fontSize: 12.5,
                height: 1.55)));
  }
}

String _noticeMeta(WorkbenchMessage message) {
  if (!message.isError) return 'notice';
  final text = message.body.toLowerCase();
  if (text.contains('claude') &&
      (text.contains('auth') || text.contains('401'))) {
    return 'provider auth';
  }
  if (text.startsWith('run error:')) return 'run failed';
  return 'error';
}
