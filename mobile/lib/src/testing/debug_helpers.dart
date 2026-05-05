part of '../app/app.dart';

@visibleForTesting
Widget buildAssistantMarkdownPreview(String markdown) => MaterialApp(
    locale: _zhHansCnLocale,
    supportedLocales: const [_zhHansCnLocale, Locale('en', 'US')],
    localizationsDelegates: _appLocalizationsDelegates,
    theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _bg,
        fontFamily: 'Segoe UI',
        fontFamilyFallback: _appFontFallback,
        textTheme: const TextTheme(bodyMedium: TextStyle(color: _text)),
        useMaterial3: true),
    home: Scaffold(
        body: Padding(
            padding: const EdgeInsets.all(16),
            child: _AssistantMarkdownBody(markdown: markdown))));

@visibleForTesting
String? debugVisibleWorkbenchBodyFromEvent(Map<String, Object?> json,
        {bool streamOutput = false}) =>
    _WorkbenchMessage.fromEvent(AgentEvent.fromJson(json), streamOutput)?.body;

@visibleForTesting
List<String> debugMergeSessionRunIds(
    List<RunSummary> localRuns, List<RunSummary> snapshotRuns) {
  final ids = <String>[];
  final seen = <String>{};
  for (final run in localRuns) {
    if (seen.add(run.id)) ids.add(run.id);
  }
  for (final run in snapshotRuns) {
    if (seen.add(run.id)) ids.add(run.id);
  }
  return ids;
}

@visibleForTesting
List<String> debugMergeSessionIds(
        List<RunSummary> localRuns,
        List<ConversationSummary> snapshotConversations,
        List<RunSummary> snapshotRuns) =>
    _mergeSessionItems(localRuns.map((run) => _SessionItem(run: run)).toList(),
            snapshotConversations, snapshotRuns)
        .map((item) => item.id)
        .toList(growable: false);

@visibleForTesting
String debugConversationPendingStatusText(String status) =>
    _conversationPendingStatusText(status, const <ConversationEvent>[]);

@visibleForTesting
bool debugShouldPollAfterApproval(ConversationSummary conversation) =>
    _shouldPollAfterApproval(conversation);

@visibleForTesting
bool debugHasExplicitWorkspaceSelection({
  required bool workspaceConfirmedForSession,
  required String? activeRunId,
  required bool hasLocalSessions,
}) =>
    _hasExplicitWorkspaceSelectionState(
      workspaceConfirmedForSession: workspaceConfirmedForSession,
      activeRunId: activeRunId,
      hasLocalSessions: hasLocalSessions,
    );

@visibleForTesting
List<String> debugVisibleApprovalIdsForConversation(
    List<Map<String, Object?>> events, ConversationSummary conversation) {
  final state = const ConversationViewState().apply(events
      .map((event) => ConversationEvent.fromJson(event))
      .toList(growable: false));
  return _messagesForConversationSnapshot(state.messages, conversation)
      .where((message) => message.role == 'approval')
      .map((message) => message.approvalId ?? '')
      .toList(growable: false);
}

@visibleForTesting
List<String> debugWorkbenchMessageRolesForConversationEvents(
    List<Map<String, Object?>> events, ConversationSummary? conversation) {
  final state = const ConversationViewState().apply(events
      .map((event) => ConversationEvent.fromJson(event))
      .toList(growable: false));
  return _messagesForConversationSnapshot(state.messages, conversation)
      .where((message) => message.role != 'question_hidden')
      .map(_workbenchMessageFromConversation)
      .map((message) => '${message.role}:${message.body}')
      .toList(growable: false);
}

@visibleForTesting
String? debugEmptyConversationCompletionDiagnostic(
    List<Map<String, Object?>> events, ConversationSummary conversation) {
  final parsed = events
      .map((event) => ConversationEvent.fromJson(event))
      .toList(growable: false);
  final state = const ConversationViewState().apply(parsed);
  return _emptyConversationCompletionDiagnostic(parsed, state.messages,
      conversation.status == 'idle' || conversation.status == 'failed');
}

@visibleForTesting
Widget buildRunningComposerPreview() => MaterialApp(
    locale: _zhHansCnLocale,
    supportedLocales: const [_zhHansCnLocale, Locale('en', 'US')],
    localizationsDelegates: _appLocalizationsDelegates,
    theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'Segoe UI',
        fontFamilyFallback: _appFontFallback,
        useMaterial3: true),
    home: Scaffold(
        backgroundColor: _bg,
        body: _CodingComposer(
            controller: TextEditingController(),
            adapter: 'claude',
            workspace: const WorkspaceSummary(
                id: 'workspace_1', name: 'vibe-coding', path: ''),
            running: true,
            canSend: true,
            sending: false,
            onModelTap: () {},
            onSend: () {},
            onCancel: () {})));

@visibleForTesting
Widget buildNewSessionWorkspacePickerPreview() {
  const workspace = WorkspaceSummary(
      id: 'workspace_1',
      name: 'Current Project',
      path: r'D:\AiProject\vibe-coding');
  return MaterialApp(
      locale: _zhHansCnLocale,
      supportedLocales: const [_zhHansCnLocale, Locale('en', 'US')],
      localizationsDelegates: _appLocalizationsDelegates,
      theme: ThemeData(
          brightness: Brightness.dark,
          fontFamily: 'Segoe UI',
          fontFamilyFallback: _appFontFallback,
          useMaterial3: true),
      home: Scaffold(
          backgroundColor: _bg,
          body: WorkspaceListPage(
              workspaces: const <WorkspaceSummary>[workspace],
              selected: workspace,
              onSelected: (_) {},
              onAddWorkspace: () {})));
}

@visibleForTesting
List<String> debugWorkbenchMessageRolesAfterEvents(
    List<Map<String, Object?>> events) {
  final messages = <_WorkbenchMessage>[];
  final resolvedApprovalIds = <String>{};
  for (final json in events) {
    final event = AgentEvent.fromJson(json);
    if (event.type == 'approval.responded') {
      final approvalId = event.approvalId ?? event.raw['approvalId'] as String?;
      if (approvalId != null && approvalId.isNotEmpty) {
        resolvedApprovalIds.add(approvalId);
        messages.removeWhere((item) =>
            item.role == 'approval' && item.event?.approvalId == approvalId);
      }
      final decision = event.raw['decision'];
      final input = event.raw['input'];
      final command = input is Map<String, Object?> ? input['command'] : null;
      if (decision == 'allow' &&
          command is String &&
          command.trim().isNotEmpty) {
        final duplicateIndex = messages.indexWhere((item) =>
            item.role == 'command' &&
            item.runId == event.runId &&
            debugSameCommandDisplay(item.body.trim(), command.trim()));
        if (duplicateIndex >= 0) {
          final current = messages[duplicateIndex];
          messages[duplicateIndex] = current.copyWith(
              body: debugPreferDetailedCommand(
                  current.body.trim(), command.trim()));
        } else {
          messages.add(_WorkbenchMessage(
              'command', 'cwd resolved · permissions checked', command.trim(),
              event: event, runId: event.runId));
        }
      }
      continue;
    }
    final message = _WorkbenchMessage.fromEvent(event, false);
    if (message == null) continue;
    if (message.role == 'approval') {
      final approvalId = message.event?.approvalId;
      if (approvalId != null && resolvedApprovalIds.contains(approvalId)) {
        continue;
      }
      final key = approvalId ?? message.body.trim();
      final existingIndex = messages.indexWhere((item) {
        if (item.role != 'approval') return false;
        return (item.event?.approvalId ?? item.body.trim()) == key;
      });
      if (existingIndex >= 0) {
        messages[existingIndex] = message;
      } else {
        messages.add(message);
      }
      continue;
    }
    if (message.role == 'command') {
      final duplicateIndex = messages.indexWhere((item) =>
          item.role == 'command' &&
          item.runId == message.runId &&
          debugSameCommandDisplay(item.body.trim(), message.body.trim()));
      if (duplicateIndex >= 0) {
        final current = messages[duplicateIndex];
        messages[duplicateIndex] = current.copyWith(
            body: debugPreferDetailedCommand(
                current.body.trim(), message.body.trim()));
      } else {
        messages.add(message);
      }
      continue;
    }
    if (message.role == 'question') {
      messages.removeWhere((item) =>
          item.role == 'assistant_stream' && item.runId == event.runId);
      if (messages.any(
          (item) => item.role == 'assistant' && item.runId == event.runId)) {
        continue;
      }
      messages.removeWhere(
          (item) => item.role == 'question' && item.runId == event.runId);
      messages.add(message);
      continue;
    }
    if (message.role == 'assistant') {
      messages.removeWhere((item) =>
          item.role == 'assistant_stream' && item.runId == event.runId);
      messages.removeWhere(
          (item) => item.role == 'question' && item.runId == event.runId);
      final sameRunIndex = messages.lastIndexWhere(
          (item) => item.role == 'assistant' && item.runId == event.runId);
      if (sameRunIndex >= 0) {
        messages[sameRunIndex] = message;
      } else {
        messages.add(message);
      }
      continue;
    }
    messages.add(message);
  }
  return messages.map((message) => '${message.role}:${message.body}').toList();
}

@visibleForTesting
bool debugSameCommandDisplay(String current, String incoming) {
  if (current == incoming) return true;
  if (current.isEmpty || incoming.isEmpty) return false;
  final currentHead = current.split(RegExp(r'\s+')).first;
  final incomingHead = incoming.split(RegExp(r'\s+')).first;
  return currentHead == incomingHead &&
      (incoming.startsWith('$current ') || current.startsWith('$incoming '));
}

@visibleForTesting
String debugPreferDetailedCommand(String current, String incoming) =>
    incoming.length > current.length ? incoming : current;

String _conversationPendingStatusText(
    String status, Iterable<ConversationEvent> events) {
  if (status == 'interrupted') return '会话已中断，可继续发送新消息恢复上下文';
  if (status == 'waiting_input') return '等待你回复问题…';
  if (status == 'waiting_approval') return '等待你确认权限请求…';
  final list = events.toList(growable: false);
  if (list.isEmpty) return '正在启动 CLI 会话…';
  for (final event in list.reversed) {
    if (event.type == 'assistant.partial') return '正在生成回复…';
    if (event.type == 'tool.started') {
      return '正在执行 ${event.toolName ?? '工具调用'}…';
    }
    if (event.type == 'tool.output') return '正在接收工具输出…';
    if (event.type == 'diff.summary') return '正在汇总文件变更…';
    if (event.type == 'conversation.started') {
      return 'CLI 会话已启动，正在读取上下文…';
    }
  }
  return '等待下一条事件…';
}

@visibleForTesting
Widget buildCodingSessionListPreview() {
  const current = WorkspaceSummary(
      id: 'workspace_1',
      name: 'Current Project',
      path: r'D:\AiProject\vibe-coding');
  const other = WorkspaceSummary(
      id: 'workspace_2', name: 'Other Project', path: r'D:\AiProject\other');
  return MaterialApp(
      locale: _zhHansCnLocale,
      supportedLocales: const [_zhHansCnLocale, Locale('en', 'US')],
      localizationsDelegates: _appLocalizationsDelegates,
      theme: ThemeData(
          brightness: Brightness.dark,
          fontFamily: 'Segoe UI',
          fontFamilyFallback: _appFontFallback,
          useMaterial3: true),
      home: Scaffold(
          backgroundColor: _bg,
          body: WorkspaceListPage(
              workspaces: const <WorkspaceSummary>[current, other],
              selected: current,
              onSelected: (_) {},
              onAddWorkspace: () {})));
}

@visibleForTesting
Widget buildWorkspaceScopedSessionPreview() {
  const current = WorkspaceSummary(
      id: 'workspace_1',
      name: 'Current Project',
      path: r'D:\AiProject\vibe-coding');
  const other = WorkspaceSummary(
      id: 'workspace_2', name: 'Other Project', path: r'D:\AiProject\other');
  const currentRun = RunSummary(
      id: 'current-1',
      tool: 'claude',
      workspaceId: 'workspace_1',
      status: 'completed');
  const otherRun = RunSummary(
      id: 'other-1',
      tool: 'claude',
      workspaceId: 'workspace_2',
      status: 'completed');
  final data = _previewSnapshot(
      current,
      const <WorkspaceSummary>[current, other],
      const <RunSummary>[currentRun, otherRun]);
  return MaterialApp(
      locale: _zhHansCnLocale,
      supportedLocales: const [_zhHansCnLocale, Locale('en', 'US')],
      localizationsDelegates: _appLocalizationsDelegates,
      theme: ThemeData(
          brightness: Brightness.dark,
          fontFamily: 'Segoe UI',
          fontFamilyFallback: _appFontFallback,
          useMaterial3: true),
      home: Scaffold(
          backgroundColor: _bg,
          body: _CodingSessionListPage(
              data: data,
              items: _mergeSessionItems(
                  const <_SessionItem>[], data.conversations, data.runs),
              currentWorkspace: current,
              onNewSession: () {},
              onSelectItem: (_) {},
              onBackToWorkspaces: () {})));
}

@visibleForTesting
Widget buildMissingWorkspaceFallbackPreview() {
  const current = WorkspaceSummary(
      id: 'workspace_1',
      name: 'Current Project',
      path: r'D:\AiProject\vibe-coding');
  return MaterialApp(
      locale: _zhHansCnLocale,
      supportedLocales: const [_zhHansCnLocale, Locale('en', 'US')],
      localizationsDelegates: _appLocalizationsDelegates,
      theme: ThemeData(
          brightness: Brightness.dark,
          fontFamily: 'Segoe UI',
          fontFamilyFallback: _appFontFallback,
          useMaterial3: true),
      home: Scaffold(
          backgroundColor: _bg,
          body: WorkspaceListPage(
              workspaces: const <WorkspaceSummary>[current],
              selected: current,
              onSelected: (_) {},
              onAddWorkspace: () {})));
}

AppSnapshot _previewSnapshot(WorkspaceSummary current,
        List<WorkspaceSummary> workspaces, List<RunSummary> runs) =>
    AppSnapshot(
        health: DaemonHealth.fromJson(const <String, Object?>{
          'status': 'ok',
          'daemonVersion': 'test',
          'mode': 'test',
          'lanMode': false,
          'bindAddress': '127.0.0.1',
          'port': 4317,
          'security': {'tokenRequired': false}
        }),
        workspaces: workspaces,
        workspace: current,
        overview: ProjectOverview(
            workspaceId: current.id,
            name: current.name,
            path: current.path,
            fileCount: 0,
            codeLineCount: 0,
            symbolCount: 0,
            analysisScore: 0,
            recentFiles: const <RecentFileSummary>[]),
        adapters: const <AdapterStatus>[],
        runs: runs,
        conversations: const <ConversationSummary>[],
        queue: const <QueueItem>[],
        templates: const <CommandTemplate>[],
        gitStatus: GitStatusSummary(
            workspaceId: current.id,
            clean: true,
            files: const <GitStatusFile>[]),
        diffs: const <DiffSummary>[],
        commits: const <GitCommitSummary>[],
        fileTree: FileTreeResponse(
            workspaceId: current.id,
            root: '',
            entries: const <FileTreeEntry>[]),
        diagnostics: CodeDiagnosticsSummary(
            workspaceId: current.id,
            available: true,
            diagnostics: const <CodeDiagnostic>[]),
        extensions: const <ExtensionSummary>[]);

@visibleForTesting
Widget buildCodingWorkbenchEntryPreview() {
  const current = WorkspaceSummary(
      id: 'workspace_1',
      name: 'Current Project',
      path: r'D:\AiProject\vibe-coding');
  final data = AppSnapshot(
      health: DaemonHealth.fromJson(const <String, Object?>{
        'status': 'ok',
        'daemonVersion': 'test',
        'mode': 'test',
        'lanMode': false,
        'bindAddress': '127.0.0.1',
        'port': 4317,
        'security': {'tokenRequired': false}
      }),
      workspaces: const <WorkspaceSummary>[current],
      workspace: current,
      overview: const ProjectOverview(
          workspaceId: 'workspace_1',
          name: 'vibe-coding',
          path: r'D:\AiProject\vibe-coding',
          fileCount: 0,
          codeLineCount: 0,
          symbolCount: 0,
          analysisScore: 0,
          recentFiles: <RecentFileSummary>[]),
      adapters: const <AdapterStatus>[],
      runs: const <RunSummary>[],
      conversations: const <ConversationSummary>[],
      queue: const <QueueItem>[],
      templates: const <CommandTemplate>[],
      gitStatus: const GitStatusSummary(
          workspaceId: 'workspace_1', clean: true, files: <GitStatusFile>[]),
      diffs: const <DiffSummary>[],
      commits: const <GitCommitSummary>[],
      fileTree: const FileTreeResponse(
          workspaceId: 'workspace_1', root: '', entries: <FileTreeEntry>[]),
      diagnostics: const CodeDiagnosticsSummary(
          workspaceId: 'workspace_1',
          available: true,
          diagnostics: <CodeDiagnostic>[]),
      extensions: const <ExtensionSummary>[]);
  return MaterialApp(
      locale: _zhHansCnLocale,
      supportedLocales: const [_zhHansCnLocale, Locale('en', 'US')],
      localizationsDelegates: _appLocalizationsDelegates,
      theme: ThemeData(
          brightness: Brightness.dark,
          fontFamily: 'Segoe UI',
          fontFamilyFallback: _appFontFallback,
          useMaterial3: true),
      home: Scaffold(
          backgroundColor: _bg,
          body: _CodingWorkbenchPage(
              data: data,
              client: DaemonClient(
                  baseUri: Uri.parse('http://127.0.0.1:4317'),
                  tokenStore: MemoryTokenStore()),
              onBack: () {},
              onSessionListChanged: (_) {},
              openSessionListRequest: 0,
              streamOutput: false,
              expandThinking: false,
              permissionMode: 'default')));
}
