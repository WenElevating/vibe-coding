import 'package:flutter/foundation.dart';

import 'workbench_messages.dart';

sealed class WorkbenchTranscriptDisplayItem {
  const WorkbenchTranscriptDisplayItem();
}

class WorkbenchMessageDisplayItem extends WorkbenchTranscriptDisplayItem {
  const WorkbenchMessageDisplayItem(this.message);

  final WorkbenchMessage message;
}

class SingleCommandDisplayItem extends WorkbenchTranscriptDisplayItem {
  const SingleCommandDisplayItem(this.message);

  final WorkbenchMessage message;
}

class CommandRunGroupDisplayItem extends WorkbenchTranscriptDisplayItem {
  const CommandRunGroupDisplayItem(this.messages);

  final List<WorkbenchMessage> messages;
}

List<WorkbenchTranscriptDisplayItem> projectWorkbenchTranscriptDisplayItems(
    List<WorkbenchMessage> messages) {
  final items = <WorkbenchTranscriptDisplayItem>[];
  final pendingCommands = <WorkbenchMessage>[];

  void flushCommands() {
    if (pendingCommands.isEmpty) return;
    if (pendingCommands.length == 1) {
      items.add(SingleCommandDisplayItem(pendingCommands.single));
    } else {
      items.add(CommandRunGroupDisplayItem(List<WorkbenchMessage>.unmodifiable(
          List<WorkbenchMessage>.from(pendingCommands))));
    }
    pendingCommands.clear();
  }

  for (final message in messages) {
    if (_isGroupableCommand(message)) {
      pendingCommands.add(message);
      continue;
    }
    flushCommands();
    items.add(WorkbenchMessageDisplayItem(message));
  }
  flushCommands();
  return List<WorkbenchTranscriptDisplayItem>.unmodifiable(items);
}

bool _isGroupableCommand(WorkbenchMessage message) =>
    message.role == 'command' && !isSubAgentWorkbenchCommand(message);

bool isSubAgentWorkbenchCommand(WorkbenchMessage message) {
  if (message.role != 'command') return false;
  final tool = _normalizeToolIdentity(_rawToolName(message));
  final title = _normalizeToolIdentity(commandDisplayTitle(message));
  return tool == 'agent' || tool == 'subagent' || title == 'agent';
}

String commandDisplayTitle(WorkbenchMessage message) {
  final firstLine = message.body
      .split('\n')
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => message.title);
  return firstLine;
}

String commandOutputText(WorkbenchMessage message) {
  final output = message.event?.raw['output'];
  if (output is String && output.trim().isNotEmpty) return output.trim();
  return '';
}

int? commandExitCode(WorkbenchMessage message) {
  for (final key in const <String>[
    'exitCode',
    'exit_code',
    'code',
    'statusCode',
    'status'
  ]) {
    final value = message.event?.raw[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }
  }
  if (message.completed && !message.isError) return 0;
  return null;
}

String commandStatusLabel(WorkbenchMessage message) {
  if (message.isError) return '错误';
  if (message.completed) return '退出码 ${commandExitCode(message) ?? 0}';
  return '运行中';
}

@visibleForTesting
List<String> debugWorkbenchTranscriptDisplayItemRoles(
        List<WorkbenchTranscriptDisplayItem> items) =>
    items
        .map((item) => switch (item) {
              WorkbenchMessageDisplayItem(:final message) =>
                'message:${message.role}',
              SingleCommandDisplayItem(:final message) =>
                'single_command:${commandDisplayTitle(message)}',
              CommandRunGroupDisplayItem(:final messages) =>
                'command_group:${messages.length}',
            })
        .toList();

String _rawToolName(WorkbenchMessage message) {
  final direct = message.event?.raw['toolName'] ?? message.event?.raw['name'];
  if (direct is String && direct.trim().isNotEmpty) return direct.trim();
  final name = message.event?.name;
  if (name != null && name.trim().isNotEmpty) return name.trim();
  return message.title;
}

String _normalizeToolIdentity(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '').trim();
