import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/lan_ai_cli_control.dart';
import 'package:lan_ai_cli_control/l10n/app_localizations.dart';
import 'package:lan_ai_cli_control/src/app/app_localization.dart';
import 'package:lan_ai_cli_control/src/app/language_controller.dart';
import 'package:lan_ai_cli_control/src/app/language_mode.dart';
import 'package:lan_ai_cli_control/src/app/language_scope.dart';
import 'package:lan_ai_cli_control/src/app/app_dependencies.dart';
import 'package:lan_ai_cli_control/src/data/models/app_update_models.dart';
import 'package:lan_ai_cli_control/src/domain/models/connected_app_session.dart';
import 'package:lan_ai_cli_control/src/domain/models/daemon_initial_data.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/app_update_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/conversation_repository.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/recent_daemon_address_repository.dart';
import 'package:lan_ai_cli_control/src/domain/use_cases/connect_to_daemon_use_case.dart';
import 'package:lan_ai_cli_control/src/domain/repositories/workspace_repository.dart';
import 'package:lan_ai_cli_control/src/services/android_package_installer.dart';
import 'package:lan_ai_cli_control/src/services/app_update_download_manager.dart';
import 'package:lan_ai_cli_control/src/ui/features/sessions/sessions.dart'
    hide mergeSessionItems;
import 'package:lan_ai_cli_control/src/ui/features/settings/settings_page.dart'
    as settings_feature;
import 'package:lan_ai_cli_control/src/ui/features/settings/view_models/app_update_view_model.dart';
import 'package:lan_ai_cli_control/src/workflows/app_update_workflow.dart';
import 'package:lan_ai_cli_control/src/testing/testing.dart';
import 'package:lan_ai_cli_control/src/ui/features/workspace_picker/workspace_picker_sheet.dart';
import 'package:lan_ai_cli_control/src/domain/models/daemon_connection_config.dart';
import 'package:lan_ai_cli_control/src/services/daemon_connection_config_store.dart';
import 'package:lan_ai_cli_control/src/shell/app_snapshot.dart';
import 'package:lan_ai_cli_control/src/ui/features/connection/view_models/daemon_connection_controller.dart';
import 'package:lan_ai_cli_control/src/ui/features/connection/view_models/daemon_connection_view_model.dart';
import 'package:lan_ai_cli_control/src/ui/core/theme/theme.dart' as theme;
import 'package:lan_ai_cli_control/src/ui/core/widgets/widgets.dart';
import 'package:lan_ai_cli_control/src/ui/features/workbench/attachments/draft_attachment.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _noopString(String _) {}

class _LocalizedSettingsLabelApp extends StatefulWidget {
  const _LocalizedSettingsLabelApp();

  @override
  State<_LocalizedSettingsLabelApp> createState() =>
      _LocalizedSettingsLabelAppState();
}

class _LocalizedSettingsLabelAppState
    extends State<_LocalizedSettingsLabelApp> {
  late final LanguageController _languageController;

  @override
  void initState() {
    super.initState();
    _languageController = LanguageController()..load();
  }

  @override
  void dispose() {
    _languageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _languageController,
      builder: (context, _) => LanguageScope(
          controller: _languageController,
          child: MaterialApp(
              locale: _languageController.locale,
              supportedLocales: appSupportedLocales,
              localizationsDelegates: appLocalizationsDelegates,
              localeResolutionCallback: (locale, supportedLocales) =>
                  resolveSupportedLocale(locale, supportedLocales),
              home: Builder(
                  builder: (context) =>
                      Text(AppLocalizations.of(context).navSettings)))));
}

class _LocalizedSettingsPageApp extends StatefulWidget {
  const _LocalizedSettingsPageApp();

  @override
  State<_LocalizedSettingsPageApp> createState() =>
      _LocalizedSettingsPageAppState();
}

class _LocalizedSettingsPageAppState extends State<_LocalizedSettingsPageApp> {
  late final LanguageController _languageController;

  @override
  void initState() {
    super.initState();
    _languageController = LanguageController()..load();
  }

  @override
  void dispose() {
    _languageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _languageController,
      builder: (context, _) => LanguageScope(
          controller: _languageController,
          child: MaterialApp(
              locale: _languageController.locale,
              supportedLocales: appSupportedLocales,
              localizationsDelegates: appLocalizationsDelegates,
              localeResolutionCallback: (locale, supportedLocales) =>
                  resolveSupportedLocale(locale, supportedLocales),
              home: Scaffold(
                  body: settings_feature.SettingsPage(
                      open: (_) {},
                      data: _testSnapshot(),
                      connectionConfig: const DaemonConnectionConfig(
                          addressInput: '192.168.1.20:4317',
                          proxyMode: DaemonProxyMode.manual,
                          manualProxyInput: 'http://proxy.local:8080'),
                      streamOutput: false,
                      expandThinking: false,
                      permissionMode: 'default',
                      onPermissionModeChanged: (_) {},
                      onStreamOutputChanged: (_) {},
                      onExpandThinkingChanged: (_) {})))));
}

class _LocalizedHomePageApp extends StatefulWidget {
  const _LocalizedHomePageApp({this.snapshot});

  final AppSnapshot? snapshot;

  @override
  State<_LocalizedHomePageApp> createState() => _LocalizedHomePageAppState();
}

class _LocalizedHomePageAppState extends State<_LocalizedHomePageApp> {
  late final LanguageController _languageController;

  @override
  void initState() {
    super.initState();
    _languageController = LanguageController()..load();
  }

  @override
  void dispose() {
    _languageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _languageController,
      builder: (context, _) => LanguageScope(
          controller: _languageController,
          child: MaterialApp(
              locale: _languageController.locale,
              supportedLocales: appSupportedLocales,
              localizationsDelegates: appLocalizationsDelegates,
              localeResolutionCallback: (locale, supportedLocales) =>
                  resolveSupportedLocale(locale, supportedLocales),
              home: Scaffold(
                  body: HomePage(
                      open: (_) {},
                      selectTab: (_) {},
                      data: widget.snapshot ?? _testSnapshot())))));
}

class _MainTabsHarness extends StatefulWidget {
  const _MainTabsHarness({
    required this.client,
    this.dependencies,
    this.snapshot,
    this.forceAndroidForTesting,
  });

  final DaemonClient client;
  final AppDependencies? dependencies;
  final AppSnapshot? snapshot;
  final bool? forceAndroidForTesting;

  @override
  State<_MainTabsHarness> createState() => _MainTabsHarnessState();
}

class _MainTabsHarnessState extends State<_MainTabsHarness> {
  late final LanguageController _languageController;

  @override
  void initState() {
    super.initState();
    _languageController = LanguageController()..load();
  }

  @override
  void dispose() {
    _languageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _languageController,
      builder: (context, _) => LanguageScope(
          controller: _languageController,
          child: MaterialApp(
              locale: _languageController.locale,
              supportedLocales: appSupportedLocales,
              localizationsDelegates: appLocalizationsDelegates,
              localeResolutionCallback: (locale, supportedLocales) =>
                  resolveSupportedLocale(locale, supportedLocales),
              theme: theme.buildAppTheme(),
              home: MainTabsPage(
                  data: widget.snapshot ?? _testSnapshot(),
                  client: widget.client,
                  connectionConfig: const DaemonConnectionConfig(
                      addressInput: '127.0.0.1:4317',
                      proxyMode: DaemonProxyMode.system,
                      manualProxyInput: ''),
                  forceAndroidForTesting: widget.forceAndroidForTesting,
                  dependencies: widget.dependencies ??
                      AppDependencies.createDefault()))));
}

class _MobileConnectionHarness extends StatefulWidget {
  const _MobileConnectionHarness({required this.controller});

  final DaemonConnectionViewModel controller;

  @override
  State<_MobileConnectionHarness> createState() =>
      _MobileConnectionHarnessState();
}

class _MobileConnectionHarnessState extends State<_MobileConnectionHarness> {
  late final LanguageController _languageController;

  @override
  void initState() {
    super.initState();
    _languageController = LanguageController()..load();
  }

  @override
  void dispose() {
    _languageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _languageController,
      builder: (context, _) => LanguageScope(
          controller: _languageController,
          child: MaterialApp(
              locale: _languageController.locale,
              supportedLocales: appSupportedLocales,
              localizationsDelegates: appLocalizationsDelegates,
              localeResolutionCallback: (locale, supportedLocales) =>
                  resolveSupportedLocale(locale, supportedLocales),
              theme: theme.buildAppTheme(),
              home: MobileUi(connectionController: widget.controller))));
}

class _AdapterRefreshClient extends DaemonClient {
  _AdapterRefreshClient()
      : super(
            baseUri: Uri.parse('http://127.0.0.1:4317'),
            tokenStore: MemoryTokenStore());

  int listAdaptersCalls = 0;

  @override
  Future<List<AdapterStatus>> listAdapters() async {
    listAdaptersCalls++;
    return const <AdapterStatus>[
      AdapterStatus(adapter: 'codex', available: true, status: 'available'),
      AdapterStatus(
          adapter: 'synthetic-jsonl',
          available: true,
          status: 'available',
          version: 'synthetic'),
      AdapterStatus(
          adapter: 'synthetic-text',
          available: true,
          status: 'available',
          version: 'synthetic')
    ];
  }

  @override
  Future<List<ConversationSummary>> listConversations() async =>
      <ConversationSummary>[
        _conversationSummary(
          id: 'conv_lazy',
          workspaceId: 'workspace_1',
          status: 'completed',
          sessionBinding: 'confirmed',
          userMessageCount: 500,
        ),
      ];
}

class _ImmediateConnectUseCase implements ConnectToDaemonUseCase<DaemonClient> {
  const _ImmediateConnectUseCase(this.session);

  final ConnectedAppSession<DaemonClient> session;

  @override
  Future<ConnectedAppSession<DaemonClient>> connect({
    required String addressInput,
    required DaemonProxyMode proxyMode,
    required String manualProxyInput,
    bool Function()? shouldContinue,
    void Function()? onCheckingHealth,
    void Function()? onLoadingInitialData,
  }) async {
    onCheckingHealth?.call();
    onLoadingInitialData?.call();
    return session;
  }
}

class _PendingAdapterClient extends DaemonClient {
  _PendingAdapterClient()
      : super(
            baseUri: Uri.parse('http://127.0.0.1:4317'),
            tokenStore: MemoryTokenStore());

  int listAdaptersCalls = 0;
  Completer<List<AdapterStatus>> adaptersCompleter =
      Completer<List<AdapterStatus>>();

  @override
  Future<List<AdapterStatus>> listAdapters() {
    listAdaptersCalls++;
    return adaptersCompleter.future;
  }

  void completeWithAdapters() {
    adaptersCompleter.complete(const <AdapterStatus>[
      AdapterStatus(adapter: 'codex', available: true, status: 'available'),
    ]);
  }

  void completeWithError() {
    adaptersCompleter.completeError(Exception('adapter probe failed'));
  }

  void resetCompleter() {
    adaptersCompleter = Completer<List<AdapterStatus>>();
  }
}

AppUpdateManifest _widgetAppUpdateManifest() => AppUpdateManifest(
      schemaVersion: 1,
      platform: 'android',
      available: true,
      packageName: 'com.example.lan_ai_cli_control',
      versionName: '1.1.0',
      versionCode: 2,
      minSupportedVersionCode: 1,
      mandatory: false,
      apkUrl: '/api/app-updates/android/apk/2',
      sha256: 'a' * 64,
      sizeBytes: 10,
      etag: '"etag-2"',
      publishedAt: DateTime.utc(2026, 5, 24),
    );

class _WidgetAppUpdateRepository implements AppUpdateRepository {
  const _WidgetAppUpdateRepository(this.manifest);

  final AppUpdateManifest manifest;

  @override
  Future<AppUpdateManifest> fetchLatest({String? ifNoneMatch}) async =>
      manifest;
}

class _WidgetRecentAddressRepository implements RecentDaemonAddressRepository {
  _WidgetRecentAddressRepository(this.addresses);

  final List<String> addresses;
  final recordedAddresses = <String>[];

  @override
  Future<List<String>> loadRecentAddresses() async =>
      List<String>.unmodifiable(addresses);

  @override
  Future<void> recordSuccessfulAddress(String addressInput) async {
    recordedAddresses.add(addressInput);
    addresses
      ..removeWhere(
        (address) => address.toLowerCase() == addressInput.toLowerCase(),
      )
      ..insert(0, addressInput);
  }
}

class _WidgetAppUpdateInstaller implements PackageInstallerService {
  _WidgetAppUpdateInstaller({this.recoveredEvent});

  final AndroidInstallEvent? recoveredEvent;
  final _events = StreamController<AndroidInstallEvent>.broadcast();
  int recoverCalls = 0;

  void close() {
    unawaited(_events.close());
  }

  @override
  Stream<AndroidInstallEvent> get events => _events.stream;

  @override
  Future<int> availableBytes() async => 1000000;

  @override
  Future<bool> canRequestPackageInstalls() async => true;

  @override
  Future<int> installApk(String filePath) async => 22;

  @override
  Future<void> openInstallPermissionSettings() async {}

  @override
  Future<AndroidInstallEvent?> recoverInstallSession(int sessionId) async {
    recoverCalls += 1;
    return recoveredEvent;
  }
}

class _WidgetAppUpdateDownloader implements AppUpdateDownloader {
  AppUpdateInstallSessionRecord? installSession;
  int readSessionCalls = 0;

  @override
  Future<void> clearInstallSession(
    AppUpdateManifest manifest, {
    int? sessionId,
  }) async {}

  @override
  Future<void> clearAllInstallSessions() async {}

  @override
  Future<void> discard(int versionCode) async {}

  @override
  Future<AppUpdateDownloadResult> download(
    AppUpdateManifest manifest,
    Uri daemonBaseUri,
  ) async =>
      const AppUpdateDownloadResult(state: AppUpdateDownloadState.failed);

  @override
  Future<AppUpdateInstallSessionRecord?> readInstallSession(
    AppUpdateManifest manifest,
  ) async {
    readSessionCalls += 1;
    return installSession;
  }

  @override
  Future<void> recordInstallSession(
    AppUpdateManifest manifest,
    int sessionId,
  ) async {}
}

Finder _workbenchMessageList() => find.byWidgetPredicate(
      (widget) =>
          widget is ListView &&
          widget.key is ValueKey<String> &&
          ((widget.key as ValueKey<String>).value ==
                  'workbench-message-list-normal' ||
              (widget.key as ValueKey<String>).value ==
                  'workbench-message-list-reverse'),
    );

Widget _connectionPage(DaemonConnectionController controller) => MaterialApp(
      supportedLocales: appSupportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
      localeResolutionCallback: (locale, supportedLocales) =>
          resolveSupportedLocale(locale, supportedLocales),
      theme: theme.buildAppTheme(),
      home: MobileConnectionPage(controller: controller),
    );

class _LazyConversationRepository implements ConversationRepository {
  _LazyConversationRepository(this.messages);

  final List<ConversationEvent> messages;

  @override
  Future<ConversationSummary> answerConversationQuestion(
    String conversationId,
    String questionId,
    String text,
  ) async =>
      throw UnimplementedError();

  @override
  Future<ConversationSummary> cancelConversation(String conversationId) async =>
      throw UnimplementedError();

  @override
  Future<ConversationSummary> createConversation({
    required String workspaceId,
    String adapter = 'claude',
    String permissionMode = 'default',
    String? model,
  }) async =>
      throw UnimplementedError();

  @override
  Future<List<ConversationEvent>> fetchConversationEvents(
    String conversationId, {
    int afterSeq = 0,
  }) async =>
      messages;

  @override
  Stream<ConversationEvent> watchConversationEvents(
    String conversationId, {
    required int afterSeq,
  }) =>
      Stream<ConversationEvent>.fromIterable(messages);

  @override
  Future<List<ConversationSummary>> listConversations() async =>
      <ConversationSummary>[
        _conversationSummary(
          id: 'conv_lazy',
          workspaceId: 'workspace_1',
          status: 'completed',
          sessionBinding: 'confirmed',
          userMessageCount: messages.length,
        ),
      ];

  @override
  Future<ConversationSummary> respondConversationApproval(
    String conversationId,
    String approvalId,
    String decision,
  ) async =>
      throw UnimplementedError();

  @override
  Future<ConversationSummary> sendConversationMessage(
    String conversationId,
    ConversationMessageSendRequest request,
  ) async =>
      throw UnimplementedError();

  @override
  Future<ConversationSummary> updateConversationModel(
    String conversationId,
    String? model,
  ) async =>
      _conversationSummary(
        id: conversationId,
        workspaceId: 'workspace_1',
        status: 'idle',
        model: model,
      );
}

class _StoredHistoryConversationRepository extends _LazyConversationRepository {
  _StoredHistoryConversationRepository(super.messages);

  final List<int> fetchAfterSeqs = <int>[];
  final List<int> watchAfterSeqs = <int>[];

  @override
  Future<List<ConversationEvent>> fetchConversationEvents(
    String conversationId, {
    int afterSeq = 0,
  }) async {
    fetchAfterSeqs.add(afterSeq);
    return messages
        .where((event) => event.seq > afterSeq)
        .toList(growable: false);
  }

  @override
  Stream<ConversationEvent> watchConversationEvents(
    String conversationId, {
    required int afterSeq,
  }) {
    watchAfterSeqs.add(afterSeq);
    return const Stream<ConversationEvent>.empty();
  }
}

class _LifecycleConversationRepository implements ConversationRepository {
  final List<int> afterSeqs = <int>[];
  int cancelCalls = 0;
  int watchCalls = 0;
  String? sentText;

  @override
  Future<ConversationSummary> answerConversationQuestion(
    String conversationId,
    String questionId,
    String text,
  ) async =>
      throw UnimplementedError();

  @override
  Future<ConversationSummary> cancelConversation(String conversationId) async =>
      throw UnimplementedError();

  @override
  Future<ConversationSummary> createConversation({
    required String workspaceId,
    String adapter = 'claude',
    String permissionMode = 'default',
    String? model,
  }) async =>
      throw UnimplementedError();

  @override
  Future<List<ConversationEvent>> fetchConversationEvents(
    String conversationId, {
    int afterSeq = 0,
  }) async =>
      const <ConversationEvent>[];

  @override
  Stream<ConversationEvent> watchConversationEvents(
    String conversationId, {
    required int afterSeq,
  }) {
    watchCalls += 1;
    afterSeqs.add(afterSeq);
    late final StreamController<ConversationEvent> controller;
    controller = StreamController<ConversationEvent>(
      onCancel: () {
        cancelCalls += 1;
      },
    );
    return controller.stream;
  }

  @override
  Future<List<ConversationSummary>> listConversations() async =>
      const <ConversationSummary>[];

  @override
  Future<ConversationSummary> respondConversationApproval(
    String conversationId,
    String approvalId,
    String decision,
  ) async =>
      throw UnimplementedError();

  @override
  Future<ConversationSummary> sendConversationMessage(
    String conversationId,
    ConversationMessageSendRequest request,
  ) async {
    sentText = request.text;
    return _conversationSummary(
      id: conversationId,
      workspaceId: 'workspace_1',
      status: 'running',
      sessionBinding: 'confirmed',
      userMessageCount: 2,
    );
  }

  @override
  Future<ConversationSummary> updateConversationModel(
    String conversationId,
    String? model,
  ) async =>
      throw UnimplementedError();
}

class _NewSessionConversationRepository implements ConversationRepository {
  final sendCompleter = Completer<ConversationSummary>();

  String? sentText;

  @override
  Future<ConversationSummary> answerConversationQuestion(
    String conversationId,
    String questionId,
    String text,
  ) async =>
      throw UnimplementedError();

  @override
  Future<ConversationSummary> cancelConversation(String conversationId) async =>
      throw UnimplementedError();

  @override
  Future<ConversationSummary> createConversation({
    required String workspaceId,
    String adapter = 'claude',
    String permissionMode = 'default',
    String? model,
  }) async =>
      _conversationSummary(
        id: 'conv_new_running',
        workspaceId: workspaceId,
        status: 'idle',
        sessionBinding: 'pending',
        userMessageCount: 0,
      );

  @override
  Future<List<ConversationEvent>> fetchConversationEvents(
    String conversationId, {
    int afterSeq = 0,
  }) async =>
      const <ConversationEvent>[];

  @override
  Stream<ConversationEvent> watchConversationEvents(
    String conversationId, {
    required int afterSeq,
  }) =>
      const Stream<ConversationEvent>.empty();

  @override
  Future<List<ConversationSummary>> listConversations() async =>
      const <ConversationSummary>[];

  @override
  Future<ConversationSummary> respondConversationApproval(
    String conversationId,
    String approvalId,
    String decision,
  ) async =>
      throw UnimplementedError();

  @override
  Future<ConversationSummary> sendConversationMessage(
    String conversationId,
    ConversationMessageSendRequest request,
  ) {
    sentText = request.text;
    return sendCompleter.future;
  }

  @override
  Future<ConversationSummary> updateConversationModel(
    String conversationId,
    String? model,
  ) async =>
      _conversationSummary(
        id: conversationId,
        workspaceId: 'workspace_1',
        status: 'idle',
        model: model,
      );
}

class _WidgetTestWorkspaceRepository implements WorkspaceRepository {
  _WidgetTestWorkspaceRepository({
    List<DirectoryEntrySummary> roots = const <DirectoryEntrySummary>[],
    Map<String, DirectoryListing> directories =
        const <String, DirectoryListing>{},
  })  : _roots = roots,
        _directories = directories;

  final List<DirectoryEntrySummary> _roots;
  final Map<String, DirectoryListing> _directories;

  @override
  Future<CodeDiagnosticsSummary> codeDiagnostics(String workspaceId) async =>
      throw UnimplementedError();

  @override
  Future<WorkspaceSummary> createWorkspace({
    required String path,
    String? name,
  }) async =>
      throw UnimplementedError();

  @override
  Future<FileContent> fileContent(String workspaceId, String path) async =>
      throw UnimplementedError();

  @override
  Future<FileTreeResponse> fileTree(
    String workspaceId, {
    String path = '',
    int maxDepth = 8,
  }) async =>
      throw UnimplementedError();

  @override
  Future<List<DiffSummary>> gitDiff(String workspaceId) async =>
      throw UnimplementedError();

  @override
  Future<List<GitCommitSummary>> gitCommits(
    String workspaceId, {
    int limit = 20,
  }) async =>
      throw UnimplementedError();

  @override
  Future<GitStatusSummary> gitStatus(String workspaceId) async =>
      throw UnimplementedError();

  @override
  Future<DirectoryListing> listDirectory(String path) async =>
      _directories[path] ??
      (throw StateError('No test directory listing for $path'));

  @override
  Future<List<DirectoryEntrySummary>> listFileSystemRoots() async => _roots;

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() async =>
      const <WorkspaceSummary>[];

  @override
  Future<ProjectOverview> projectOverview(String workspaceId) async =>
      throw UnimplementedError();
}

AppSnapshot _testSnapshot({
  List<WorkspaceSummary>? workspaces,
  List<RunSummary> runs = const <RunSummary>[],
  List<ConversationSummary> conversations = const <ConversationSummary>[],
  List<QueueItem> queue = const <QueueItem>[],
  List<RecentFileSummary> recentFiles = const <RecentFileSummary>[],
  GitStatusSummary? gitStatus,
  CodeDiagnosticsSummary diagnostics = const CodeDiagnosticsSummary(
      workspaceId: 'workspace_1',
      available: true,
      diagnostics: <CodeDiagnostic>[]),
}) {
  const workspace = WorkspaceSummary(
      id: 'workspace_1',
      name: 'Current Project',
      path: r'D:\AiProject\vibe-coding');
  final resolvedWorkspaces = workspaces ?? const <WorkspaceSummary>[workspace];
  return AppSnapshot(
      health: DaemonHealth.fromJson(const <String, Object?>{
        'status': 'ok',
        'daemonVersion': 'test',
        'mode': 'test',
        'lanMode': false,
        'bindAddress': '127.0.0.1',
        'port': 4317,
        'security': {'tokenRequired': false}
      }),
      workspaces: resolvedWorkspaces,
      workspace: workspace,
      overview: ProjectOverview(
          workspaceId: 'workspace_1',
          name: 'vibe-coding',
          path: r'D:\AiProject\vibe-coding',
          fileCount: 0,
          codeLineCount: 0,
          symbolCount: 0,
          analysisScore: 0,
          recentFiles: recentFiles),
      adapters: const <AdapterStatus>[],
      runs: runs,
      conversations: conversations,
      queue: queue,
      templates: const <CommandTemplate>[],
      gitStatus: gitStatus ??
          const GitStatusSummary(
              workspaceId: 'workspace_1',
              clean: true,
              files: <GitStatusFile>[]),
      diffs: const <DiffSummary>[],
      commits: const <GitCommitSummary>[],
      fileTree: const FileTreeResponse(
          workspaceId: 'workspace_1', root: '', entries: <FileTreeEntry>[]),
      diagnostics: diagnostics,
      extensions: const <ExtensionSummary>[]);
}

ConversationSummary _conversationSummary({
  required String id,
  required String workspaceId,
  required String status,
  String? cliSessionId,
  String sessionBinding = 'unknown',
  int userMessageCount = 0,
  ConversationCapabilities? capabilities,
  ConversationBlockingItem? blockingItem,
  String? model,
  String? title,
}) =>
    ConversationSummary(
      id: id,
      workspaceId: workspaceId,
      adapter: 'codex',
      model: model,
      status: status,
      title: title,
      cliSessionId: cliSessionId,
      sessionBinding: sessionBinding,
      userMessageCount: userMessageCount,
      capabilities: capabilities ??
          ConversationCapabilities.fromJson(const <String, Object?>{}),
      createdAt: '2026-05-06T10:00:00.000Z',
      updatedAt: '2026-05-06T10:01:00.000Z',
      blockingItem: blockingItem,
    );

void main() {
  testWidgets('app renders English when forced to English',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});

    await tester.pumpWidget(const _LocalizedSettingsLabelApp());
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsWidgets);
  });

  testWidgets('app renders Chinese when forced to Simplified Chinese',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'zh-Hans-CN'});

    await tester.pumpWidget(const _LocalizedSettingsLabelApp());
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsWidgets);
  });

  testWidgets(
      'home command deck renders Chinese when forced to Simplified Chinese',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'zh-Hans-CN'});

    await tester.pumpWidget(const _LocalizedHomePageApp());
    await tester.pumpAndSettle();

    expect(find.text('新建任务'), findsWidgets);
    expect(find.text('工作区信号'), findsOneWidget);
    expect(find.text('快捷操作'), findsOneWidget);
    expect(find.text('命令模板'), findsOneWidget);
    expect(find.text('已连接'), findsNothing);
    expect(find.text('vibe-coding'), findsWidgets);
    expect(find.text('Command templates'), findsNothing);
    expect(find.text('Needs your approval'), findsNothing);
    expect(find.text('Modify file'), findsNothing);
    expect(find.text('online'), findsNothing);
  });

  testWidgets('home command deck hides connection controls',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});

    await tester.pumpWidget(const _LocalizedHomePageApp());
    await tester.pumpAndSettle();

    expect(find.text('Connected'), findsNothing);
    expect(find.text('127.0.0.1:4317'), findsNothing);
    expect(find.byIcon(Icons.qr_code_scanner_rounded), findsNothing);
  });

  testWidgets('home command deck shows global attention and activity',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final snapshot = _testSnapshot(
      runs: const <RunSummary>[
        RunSummary(
            id: 'run_failed',
            tool: 'codex',
            workspaceId: 'workspace_1',
            status: 'failed'),
      ],
      conversations: <ConversationSummary>[
        _conversationSummary(
          id: 'conv_approval',
          workspaceId: 'workspace_1',
          status: 'waiting_approval',
          blockingItem: const ConversationBlockingItem(
            type: 'approval_request',
            approvalId: 'ap1',
            summary: 'Modify file',
          ),
        ),
      ],
    );

    await tester.pumpWidget(_LocalizedHomePageApp(snapshot: snapshot));
    await tester.pumpAndSettle();

    expect(find.text('Modify file'), findsOneWidget);
    expect(find.textContaining('run_failed'), findsOneWidget);
  });

  testWidgets('home command deck surfaces other workspace running activity',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final snapshot = _testSnapshot(
      workspaces: const <WorkspaceSummary>[
        WorkspaceSummary(
            id: 'workspace_1',
            name: 'Current Project',
            path: r'D:\AiProject\vibe-coding'),
        WorkspaceSummary(
            id: 'workspace_2', name: 'daemon', path: r'D:\AiProject\daemon'),
      ],
      runs: const <RunSummary>[
        RunSummary(
            id: 'run_other',
            tool: 'claude',
            workspaceId: 'workspace_2',
            status: 'running'),
      ],
    );

    await tester.pumpWidget(_LocalizedHomePageApp(snapshot: snapshot));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -260));
    await tester.pumpAndSettle();

    expect(find.textContaining('daemon'), findsWidgets);
  });

  testWidgets('settings language picker shows self-identifying language names',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});

    await tester.pumpWidget(const _LocalizedSettingsPageApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();

    expect(find.text('System default'), findsOneWidget);
    expect(find.text('简体中文'), findsOneWidget);
    expect(find.text('English'), findsWidgets);
  });

  testWidgets('settings shows active daemon address and proxy mode',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});

    await tester.pumpWidget(const _LocalizedSettingsPageApp());
    await tester.pumpAndSettle();

    expect(find.text('Daemon address'), findsOneWidget);
    expect(find.text('192.168.1.20:4317'), findsOneWidget);
    expect(find.text('Proxy mode'), findsOneWidget);
    expect(find.text('Manual proxy'), findsOneWidget);
  });

  testWidgets('renders assistant markdown instead of raw syntax',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildAssistantMarkdownPreview(
        'Hello\n\n- **Code and debug**\n- `inline code`\n\n<script>alert(1)</script>'));
    await tester.pumpAndSettle();

    expect(find.text('Code and debug'), findsOneWidget);
    expect(find.text('inline code'), findsOneWidget);
    expect(find.textContaining('**Code and debug**'), findsNothing);
    expect(find.textContaining('<script>'), findsNothing);
  });

  testWidgets('app starts on editable connection page without bottom nav',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(const LanAiCliControlApp());
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Connection'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('System proxy'), findsOneWidget);
    expect(find.byType(BottomNav), findsNothing);

    final header = find.byKey(const ValueKey('connection-header'));
    expect(header, findsOneWidget);
    expect(
      find.descendant(of: header, matching: find.byType(IconButton)),
      findsNothing,
    );
    expect(
      find.descendant(
        of: header,
        matching: find.byType(PopupMenuButton<dynamic>),
      ),
      findsNothing,
    );
  });

  testWidgets(
      'connection page renders Chinese when forced to Simplified Chinese',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'zh-Hans-CN'});

    await tester.pumpWidget(const LanAiCliControlApp());
    await tester.pumpAndSettle();

    expect(find.text('\u8fde\u63a5'), findsWidgets);
    expect(find.text('\u8fde\u63a5\u5730\u5740'), findsOneWidget);
    expect(find.text('\u7f51\u7edc\u4ee3\u7406'), findsOneWidget);
    expect(find.text('\u76f4\u8fde'), findsWidgets);
    expect(find.text('\u672a\u8fde\u63a5'), findsOneWidget);
    expect(find.text('\u76ee\u6807'), findsOneWidget);
    expect(find.text('\u4ee3\u7406'), findsOneWidget);
    expect(find.text('Connection'), findsNothing);
    expect(find.text('Network proxy'), findsNothing);
    expect(find.text('Not connected'), findsNothing);
  });

  testWidgets('connection page keeps address and proxy editable after failure',
      (WidgetTester tester) async {
    final controller = DaemonConnectionController(
      store: DaemonConnectionConfigStore(),
      tokenStore: MemoryTokenStore(),
      snapshotLoader: (_) async => throw StateError('not used'),
      healthProbe: (_) async {
        throw const DaemonClientException(502, <String, Object?>{
          'error': 'invalid_response',
          'message': 'daemon returned an empty response body',
        });
      },
    );
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await controller.load();

    await tester.pumpWidget(MaterialApp(
      supportedLocales: appSupportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
      localeResolutionCallback: (locale, supportedLocales) =>
          resolveSupportedLocale(locale, supportedLocales),
      theme: theme.buildAppTheme(),
      home: MobileConnectionPage(controller: controller),
    ));

    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(find.text('Connection failed'), findsOneWidget);
    expect(find.textContaining('proxy or gateway'), findsOneWidget);
    expect(find.byType(TextField), findsWidgets);
    expect(find.text('System proxy'), findsOneWidget);
    expect(find.text('Manual proxy'), findsOneWidget);
    expect(find.text('Reconnect'), findsOneWidget);
    expect(find.byType(BottomNav), findsNothing);
  });

  testWidgets('connection address field shows recent addresses on focus',
      (WidgetTester tester) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    final controller = DaemonConnectionController(
      store: DaemonConnectionConfigStore(),
      tokenStore: MemoryTokenStore(),
      recentAddressRepository: _WidgetRecentAddressRepository(<String>[
        '192.168.1.50:4317',
        'http://devbox.local:4317',
      ]),
      snapshotLoader: (_) async => throw StateError('not used'),
      healthProbe: (_) async => throw StateError('not used'),
    );
    addTearDown(controller.dispose);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await controller.load();
    controller.setAddressInput('');

    await tester.pumpWidget(_connectionPage(controller));
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();

    expect(find.text('192.168.1.50:4317'), findsOneWidget);
    expect(find.text('http://devbox.local:4317'), findsOneWidget);
    expect(find.bySemanticsLabel('192.168.1.50:4317'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('192.168.1.50:4317'), findsNothing);

    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    expect(find.text('192.168.1.50:4317'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('192.168.1.50:4317'), findsNothing);
    expect(find.text('Connection'), findsOneWidget);
  });

  testWidgets('connection recent addresses filter and fill without connecting',
      (WidgetTester tester) async {
    var connectCalls = 0;
    final controller = DaemonConnectionController(
      store: DaemonConnectionConfigStore(),
      tokenStore: MemoryTokenStore(),
      recentAddressRepository: _WidgetRecentAddressRepository(<String>[
        '192.168.1.50:4317',
        'http://devbox.local:4317',
        'https://prod.local:443',
      ]),
      snapshotLoader: (_) async {
        connectCalls += 1;
        throw StateError('must not connect');
      },
      healthProbe: (_) async => throw StateError('must not connect'),
    );
    addTearDown(controller.dispose);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await controller.load();
    controller.setProxyMode(DaemonProxyMode.manual);
    controller.setManualProxyInput('http://proxy.local:8080');

    await tester.pumpWidget(_connectionPage(controller));
    await tester.tap(find.byType(TextField).first);
    await tester.enterText(find.byType(TextField).first, 'DEV');
    await tester.pumpAndSettle();

    expect(find.text('http://devbox.local:4317'), findsOneWidget);
    expect(find.text('192.168.1.50:4317'), findsNothing);

    await tester.tap(find.text('http://devbox.local:4317'));
    await tester.pumpAndSettle();

    expect(controller.addressInput, 'http://devbox.local:4317');
    expect(controller.proxyMode, DaemonProxyMode.manual);
    expect(controller.manualProxyInput, 'http://proxy.local:8080');
    expect(controller.status, DaemonConnectionStatus.idle);
    expect(connectCalls, 0);
    expect(find.text('http://devbox.local:4317'), findsNothing);
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets('connection recent dropdown clamps long history',
      (WidgetTester tester) async {
    final controller = DaemonConnectionController(
      store: DaemonConnectionConfigStore(),
      tokenStore: MemoryTokenStore(),
      recentAddressRepository: _WidgetRecentAddressRepository(<String>[
        for (var index = 1; index <= 8; index++)
          '192.168.1.$index:4317',
      ]),
      snapshotLoader: (_) async => throw StateError('not used'),
      healthProbe: (_) async => throw StateError('not used'),
    );
    addTearDown(controller.dispose);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await controller.load();
    controller.setAddressInput('');

    await tester.pumpWidget(_connectionPage(controller));
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();

    final dropdown = find.byKey(const ValueKey('connection-recent-dropdown'));
    expect(dropdown, findsOneWidget);
    expect(tester.getSize(dropdown).height, lessThanOrEqualTo(184));
    expect(find.text('192.168.1.1:4317'), findsOneWidget);
    expect(find.text('192.168.1.8:4317'), findsNothing);
  });

  testWidgets('connected empty workspace catalog keeps bottom tabs',
      (WidgetTester tester) async {
    final controller = DaemonConnectionController(
      store: DaemonConnectionConfigStore(),
      tokenStore: MemoryTokenStore(),
      connectToDaemon: _ImmediateConnectUseCase(
        ConnectedAppSession<DaemonClient>(
          client: _AdapterRefreshClient(),
          initialData: DaemonInitialData(
            health: _testSnapshot().health,
            workspaces: const <WorkspaceSummary>[],
            workspace: null,
            adapters: const <AdapterStatus>[],
            runs: const <RunSummary>[],
            conversations: const <ConversationSummary>[],
            queue: const <QueueItem>[],
          ),
          connectedConfig: const DaemonConnectionConfig(
            addressInput: '127.0.0.1:4317',
            proxyMode: DaemonProxyMode.system,
            manualProxyInput: '',
          ),
        ),
      ),
    );
    addTearDown(controller.dispose);
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(_MobileConnectionHarness(controller: controller));
    await controller.load();
    await controller.connect();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('workspace-list')), findsOneWidget);
    expect(find.byType(BottomNav), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Daemon address'), findsOneWidget);
    expect(find.text('127.0.0.1:4317'), findsOneWidget);
    expect(find.textContaining('Unable to connect'), findsNothing);
    expect(find.textContaining('Bad state'), findsNothing);
  });

  testWidgets('MobileUiFrame renders supplied child',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MobileUiFrame(child: Text('frame child')),
    ));

    expect(find.text('frame child'), findsOneWidget);
  });

  testWidgets('coding composer exposes voice input semantics',
      (WidgetTester tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
            body: CodingComposer(
                controller: controller,
                adapter: 'codex',
                workspace: const WorkspaceSummary(
                    id: 'workspace_1',
                    name: 'Current Project',
                    path: r'D:\AiProject\vibe-coding'),
                running: false,
                canSend: false,
                sending: false,
                voiceState: VoiceInputState.idle,
                voiceEnabled: true,
                voiceError: null,
                cliLocked: false,
                modelLocked: false,
                onCliTap: () {},
                onModelTap: () {},
                onVoiceStart: () {},
                onVoiceStop: () {},
                onVoiceCancel: () {},
                onTextChanged: (_) {},
                onSend: () {},
                onCancel: () {}))));

    expect(find.bySemanticsLabel('Voice input'), findsOneWidget);
  });

  testWidgets('coding composer does not send when voice pointer is released',
      (WidgetTester tester) async {
    var sends = 0;
    final controller = TextEditingController(text: 'hello');
    await tester.pumpWidget(MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
            body: CodingComposer(
                controller: controller,
                adapter: 'codex',
                workspace: const WorkspaceSummary(
                    id: 'workspace_1',
                    name: 'Current Project',
                    path: r'D:\AiProject\vibe-coding'),
                running: false,
                canSend: true,
                sending: false,
                voiceState: VoiceInputState.listening,
                voiceEnabled: true,
                voiceError: null,
                cliLocked: false,
                modelLocked: false,
                onCliTap: () {},
                onModelTap: () {},
                onVoiceStart: () {},
                onVoiceStop: () {},
                onVoiceCancel: () {},
                onTextChanged: (_) {},
                onSend: () => sends++,
                onCancel: () {}))));

    await tester.tap(find.bySemanticsLabel('Voice input'));
    await tester.pumpAndSettle();

    expect(sends, 0);
  });

  testWidgets('coding composer shows listening state while recording',
      (WidgetTester tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
            body: CodingComposer(
                controller: controller,
                adapter: 'codex',
                workspace: const WorkspaceSummary(
                    id: 'workspace_1',
                    name: 'Current Project',
                    path: r'D:\AiProject\vibe-coding'),
                running: false,
                canSend: false,
                sending: false,
                voiceState: VoiceInputState.listening,
                voiceEnabled: true,
                voiceError: null,
                cliLocked: false,
                modelLocked: false,
                onCliTap: () {},
                onModelTap: () {},
                onVoiceStart: () {},
                onVoiceStop: () {},
                onVoiceCancel: () {},
                onTextChanged: (_) {},
                onSend: () {},
                onCancel: () {}))));

    expect(find.textContaining('Listening'), findsOneWidget);
  });

  testWidgets('coding composer reports text edits while voice is listening',
      (WidgetTester tester) async {
    String? editedText;
    final controller = TextEditingController();
    await tester.pumpWidget(MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
            body: CodingComposer(
                controller: controller,
                adapter: 'codex',
                workspace: const WorkspaceSummary(
                    id: 'workspace_1',
                    name: 'Current Project',
                    path: r'D:\AiProject\vibe-coding'),
                running: false,
                canSend: false,
                sending: false,
                voiceState: VoiceInputState.listening,
                voiceEnabled: true,
                voiceError: null,
                cliLocked: false,
                modelLocked: false,
                onCliTap: () {},
                onModelTap: () {},
                onVoiceStart: () {},
                onVoiceStop: () {},
                onVoiceCancel: () {},
                onTextChanged: (text) => editedText = text,
                onSend: () {},
                onCancel: () {}))));

    await tester.enterText(find.byType(TextField), 'manual edit');

    expect(editedText, 'manual edit');
  });

  testWidgets('coding composer does not render voice errors inline',
      (WidgetTester tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
            body: CodingComposer(
                controller: controller,
                adapter: 'codex',
                workspace: const WorkspaceSummary(
                    id: 'workspace_1',
                    name: 'Current Project',
                    path: r'D:\AiProject\vibe-coding'),
                running: false,
                canSend: false,
                sending: false,
                voiceState: VoiceInputState.failed,
                voiceEnabled: true,
                voiceError: '未检测到可用麦克风，请连接或启用录音设备后重试。',
                cliLocked: false,
                modelLocked: false,
                onCliTap: () {},
                onModelTap: () {},
                onVoiceStart: () {},
                onVoiceStop: () {},
                onVoiceCancel: () {},
                onTextChanged: (_) {},
                onSend: () {},
                onCancel: () {}))));

    expect(find.textContaining('未检测到可用麦克风'), findsNothing);
  });

  testWidgets('coding composer renders separate CLI and model chips',
      (WidgetTester tester) async {
    var cliTaps = 0;
    var modelTaps = 0;
    final controller = TextEditingController();
    await tester.pumpWidget(MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
            body: CodingComposer(
                controller: controller,
                adapter: 'codex',
                model: 'GPT-5 Codex',
                modelNotice: 'Model changed to an available option',
                workspace: const WorkspaceSummary(
                    id: 'workspace_1',
                    name: 'Current Project',
                    path: r'D:\AiProject\vibe-coding'),
                running: false,
                cliLocked: false,
                modelLocked: false,
                canSend: false,
                sending: false,
                voiceState: VoiceInputState.idle,
                voiceEnabled: true,
                voiceError: null,
                onCliTap: () => cliTaps++,
                onModelTap: () => modelTaps++,
                onVoiceStart: () {},
                onVoiceStop: () {},
                onVoiceCancel: () {},
                onTextChanged: (_) {},
                onSend: () {},
                onCancel: () {}))));

    expect(find.text('codex'), findsOneWidget);
    expect(find.text('GPT-5 Codex'), findsOneWidget);
    expect(find.text('Model changed to an available option'), findsOneWidget);

    await tester.tap(find.text('codex'));
    await tester.tap(find.text('GPT-5 Codex'));

    expect(cliTaps, 1);
    expect(modelTaps, 1);
  });

  testWidgets('coding composer can lock CLI while model remains selectable',
      (WidgetTester tester) async {
    var cliTaps = 0;
    var modelTaps = 0;
    final controller = TextEditingController();
    await tester.pumpWidget(MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
            body: CodingComposer(
                controller: controller,
                adapter: 'codex',
                model: 'GPT-5 Codex',
                workspace: const WorkspaceSummary(
                    id: 'workspace_1',
                    name: 'Current Project',
                    path: r'D:\AiProject\vibe-coding'),
                running: false,
                cliLocked: true,
                modelLocked: false,
                canSend: false,
                sending: false,
                voiceState: VoiceInputState.idle,
                voiceEnabled: true,
                voiceError: null,
                onCliTap: () => cliTaps++,
                onModelTap: () => modelTaps++,
                onVoiceStart: () {},
                onVoiceStop: () {},
                onVoiceCancel: () {},
                onTextChanged: (_) {},
                onSend: () {},
                onCancel: () {}))));

    await tester.tap(find.text('codex'));
    await tester.tap(find.text('GPT-5 Codex'));

    expect(cliTaps, 0);
    expect(modelTaps, 1);
  });

  testWidgets('coding composer wraps long CLI and model chips on compact width',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = TextEditingController();
    await tester.pumpWidget(MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
            body: CodingComposer(
                controller: controller,
                adapter: 'very-long-codex-compatible-cli',
                model: 'GPT-5 Codex Experimental Long Context',
                workspace: const WorkspaceSummary(
                    id: 'workspace_1',
                    name: 'Current Project',
                    path: r'D:\AiProject\vibe-coding'),
                running: false,
                cliLocked: false,
                modelLocked: false,
                canSend: false,
                sending: false,
                voiceState: VoiceInputState.idle,
                voiceEnabled: true,
                voiceError: null,
                onCliTap: () {},
                onModelTap: () {},
                onVoiceStart: () {},
                onVoiceStop: () {},
                onVoiceCancel: () {},
                onTextChanged: (_) {},
                onSend: () {},
                onCancel: () {}))));

    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'coding composer renders attachment tray above input and deletes draft attachment',
      (WidgetTester tester) async {
    final controller = TextEditingController();
    var deleted = -1;
    await tester.pumpWidget(MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
            body: CodingComposer(
                controller: controller,
                adapter: 'codex',
                workspace: const WorkspaceSummary(
                    id: 'workspace_1',
                    name: 'Current Project',
                    path: r'D:\AiProject\vibe-coding'),
                running: false,
                canSend: true,
                sending: false,
                voiceState: VoiceInputState.idle,
                voiceEnabled: true,
                voiceError: null,
                cliLocked: false,
                modelLocked: false,
                model: 'gpt-5.3-codex',
                draftAttachments: const <DraftAttachment>[
                  DraftAttachment(
                    localPath: r'D:\tmp\screenshot.png',
                    name: 'screenshot.png',
                    mimeType: 'image/png',
                    kind: AttachmentKind.image,
                    sizeBytes: 120034,
                  ),
                ],
                onAttachmentTap: () {},
                onRemoveAttachment: (index) => deleted = index,
                onCliTap: () {},
                onModelTap: () {},
                onVoiceStart: () {},
                onVoiceStop: () {},
                onVoiceCancel: () {},
                onTextChanged: (_) {},
                onSend: () {},
                onCancel: () {}))));

    final inputTop = tester.getTopLeft(find.byType(TextField)).dy;
    final trayTop = tester.getTopLeft(find.text('screenshot.png')).dy;
    expect(trayTop, lessThan(inputTop));

    await tester.tap(find.byTooltip('Remove screenshot.png'));
    expect(deleted, 0);
  });

  testWidgets(
      'coding composer shows visible invalid attachment status for unsupported model',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController(text: '这个图片里面有什么?');
    await tester.pumpWidget(MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
            body: CodingComposer(
                controller: controller,
                adapter: 'codex',
                workspace: const WorkspaceSummary(
                    id: 'workspace_1',
                    name: 'Current Project',
                    path: r'D:\AiProject\vibe-coding'),
                running: false,
                canSend: false,
                sending: false,
                voiceState: VoiceInputState.idle,
                voiceEnabled: true,
                voiceError: null,
                cliLocked: false,
                modelLocked: false,
                model: 'text-only-model',
                draftAttachments: const <DraftAttachment>[
                  DraftAttachment(
                    localPath: r'D:\tmp\screenshot.png',
                    name: 'screenshot.png',
                    mimeType: 'image/png',
                    kind: AttachmentKind.image,
                    sizeBytes: 120034,
                    errorCode: 'attachment_kind_unsupported',
                  ),
                ],
                onAttachmentTap: () {},
                onRemoveAttachment: (_) {},
                onCliTap: () {},
                onModelTap: () {},
                onVoiceStart: () {},
                onVoiceStop: () {},
                onVoiceCancel: () {},
                onTextChanged: (_) {},
                onSend: () {},
                onCancel: () {}))));

    expect(
      find.text('This file is not supported by the selected model.'),
      findsOneWidget,
    );
  });

  testWidgets('coding back target renders workspace list',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildCodingSessionListPreview());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('workspace-list')), findsOneWidget);
    expect(find.text('Current Project'), findsOneWidget);
    expect(find.text('Other Project'), findsOneWidget);
  });

  testWidgets('coding entry defaults to workspace list',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildCodingWorkbenchEntryPreview());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('workspace-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('coding-session-list')), findsNothing);
    expect(find.byKey(const ValueKey('coding-workbench-detail')), findsNothing);
  });

  testWidgets('workbench conversation lazily builds large message lists',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final messages = List<ConversationEvent>.generate(
      500,
      (index) => ConversationEvent.fromJson(<String, Object?>{
        'seq': index + 1,
        'conversationId': 'conv_lazy',
        'type': 'user.message',
        'createdAt': '2026-05-16T00:00:00.000Z',
        'text': 'message $index',
      }),
    );
    final dependencies = AppDependencies.createDefault();
    final conversationRepository = _LazyConversationRepository(messages);
    final client = _AdapterRefreshClient();
    final connectedData = dependencies.data.forDaemonClient(client);
    final workbenchDependencies = dependencies.features
        .createWorkbenchDependencies(client, connectedData);
    final testDependencies = AppDependencies(
      network: dependencies.network,
      data: dependencies.data,
      domain: dependencies.domain,
      features: FeatureDependencies(
        createDaemonConnectionViewModel:
            dependencies.features.createDaemonConnectionViewModel,
        createDiagnosticsViewModel:
            dependencies.features.createDiagnosticsViewModel,
        createRunDetailViewModel:
            dependencies.features.createRunDetailViewModel,
        createAppUpdateViewModel:
            dependencies.features.createAppUpdateViewModel,
        createWorkbenchDependencies: (_, connectedData) =>
            WorkbenchDependencies(
          adapterRepository: connectedData.adapterRepository,
          asrModelManager: workbenchDependencies.asrModelManager,
          conversationRepository: conversationRepository,
          diagnosticsRepository: connectedData.diagnosticsRepository,
          runRepository: connectedData.runRepository,
          speechInputServiceBuilder:
              workbenchDependencies.speechInputServiceBuilder,
          workspaceRepository: connectedData.workspaceRepository,
        ),
      ),
    );

    await tester.pumpWidget(
      _MainTabsHarness(
        client: client,
        dependencies: testDependencies,
        snapshot: _testSnapshot(
          conversations: <ConversationSummary>[
            _conversationSummary(
              id: 'conv_lazy',
              workspaceId: 'workspace_1',
              status: 'completed',
              sessionBinding: 'confirmed',
              userMessageCount: messages.length,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Codex task lazy'));
    await tester.pumpAndSettle();

    expect(find.textContaining('message '), findsWidgets);
    expect(find.text('message 250'), findsNothing);
  });

  testWidgets('opening existing conversation scrolls to latest message',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final messages = List<ConversationEvent>.generate(
      80,
      (index) => ConversationEvent.fromJson(<String, Object?>{
        'seq': index + 1,
        'conversationId': 'conv_scroll',
        'type': index.isEven ? 'user.message' : 'assistant.message',
        'createdAt': '2026-05-16T00:00:00.000Z',
        'text': index == 79 ? 'latest visible sentinel' : 'message $index',
      }),
    );
    final dependencies = AppDependencies.createDefault();
    final conversationRepository = _LazyConversationRepository(messages);
    final client = _AdapterRefreshClient();
    final connectedData = dependencies.data.forDaemonClient(client);
    final workbenchDependencies = dependencies.features
        .createWorkbenchDependencies(client, connectedData);
    final testDependencies = AppDependencies(
      network: dependencies.network,
      data: dependencies.data,
      domain: dependencies.domain,
      features: FeatureDependencies(
        createDaemonConnectionViewModel:
            dependencies.features.createDaemonConnectionViewModel,
        createDiagnosticsViewModel:
            dependencies.features.createDiagnosticsViewModel,
        createRunDetailViewModel:
            dependencies.features.createRunDetailViewModel,
        createAppUpdateViewModel:
            dependencies.features.createAppUpdateViewModel,
        createWorkbenchDependencies: (_, connectedData) =>
            WorkbenchDependencies(
          adapterRepository: connectedData.adapterRepository,
          asrModelManager: workbenchDependencies.asrModelManager,
          conversationRepository: conversationRepository,
          diagnosticsRepository: connectedData.diagnosticsRepository,
          runRepository: connectedData.runRepository,
          speechInputServiceBuilder:
              workbenchDependencies.speechInputServiceBuilder,
          workspaceRepository: connectedData.workspaceRepository,
        ),
      ),
    );

    await tester.pumpWidget(
      _MainTabsHarness(
        client: client,
        dependencies: testDependencies,
        snapshot: _testSnapshot(
          conversations: <ConversationSummary>[
            _conversationSummary(
              id: 'conv_scroll',
              workspaceId: 'workspace_1',
              status: 'completed',
              sessionBinding: 'confirmed',
              userMessageCount: messages.length,
              title: 'Scroll regression conversation',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scroll regression conversation'));
    await tester.pumpAndSettle();

    expect(find.text('latest visible sentinel'), findsOneWidget);
    expect(find.text('message 0'), findsNothing);
  });

  testWidgets(
      'opening historical conversation loads stored events before watch',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final messages = <ConversationEvent>[
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 1,
        'conversationId': 'conv_history',
        'type': 'conversation.status_changed',
        'createdAt': '2026-05-16T00:00:00.000Z',
        'status': 'running'
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 2,
        'conversationId': 'conv_history',
        'type': 'user.message',
        'createdAt': '2026-05-16T00:00:01.000Z',
        'text': 'historical prompt'
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 3,
        'conversationId': 'conv_history',
        'type': 'tool.started',
        'createdAt': '2026-05-16T00:00:02.000Z',
        'toolUseId': 'tool_1',
        'toolName': 'command_execution',
        'input': {'command': 'dir'}
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 4,
        'conversationId': 'conv_history',
        'type': 'tool.completed',
        'createdAt': '2026-05-16T00:00:03.000Z',
        'toolUseId': 'tool_1',
        'toolName': 'command_execution',
        'exitCode': 0
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 5,
        'conversationId': 'conv_history',
        'type': 'assistant.message',
        'createdAt': '2026-05-16T00:00:04.000Z',
        'text': 'historical answer'
      }),
      ConversationEvent.fromJson(const <String, Object?>{
        'seq': 6,
        'conversationId': 'conv_history',
        'type': 'conversation.completed',
        'createdAt': '2026-05-16T00:00:05.000Z'
      }),
    ];
    final dependencies = AppDependencies.createDefault();
    final conversationRepository =
        _StoredHistoryConversationRepository(messages);
    final client = _AdapterRefreshClient();
    final connectedData = dependencies.data.forDaemonClient(client);
    final workbenchDependencies = dependencies.features
        .createWorkbenchDependencies(client, connectedData);
    final testDependencies = AppDependencies(
      network: dependencies.network,
      data: dependencies.data,
      domain: dependencies.domain,
      features: FeatureDependencies(
        createDaemonConnectionViewModel:
            dependencies.features.createDaemonConnectionViewModel,
        createDiagnosticsViewModel:
            dependencies.features.createDiagnosticsViewModel,
        createRunDetailViewModel:
            dependencies.features.createRunDetailViewModel,
        createAppUpdateViewModel:
            dependencies.features.createAppUpdateViewModel,
        createWorkbenchDependencies: (_, connectedData) =>
            WorkbenchDependencies(
          adapterRepository: connectedData.adapterRepository,
          asrModelManager: workbenchDependencies.asrModelManager,
          conversationRepository: conversationRepository,
          diagnosticsRepository: connectedData.diagnosticsRepository,
          runRepository: connectedData.runRepository,
          speechInputServiceBuilder:
              workbenchDependencies.speechInputServiceBuilder,
          workspaceRepository: connectedData.workspaceRepository,
        ),
      ),
    );

    await tester.pumpWidget(
      _MainTabsHarness(
        client: client,
        dependencies: testDependencies,
        snapshot: _testSnapshot(
          conversations: <ConversationSummary>[
            _conversationSummary(
              id: 'conv_history',
              workspaceId: 'workspace_1',
              status: 'completed',
              sessionBinding: 'confirmed',
              userMessageCount: 1,
              title: 'Historical task',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Historical task'));
    await tester.pumpAndSettle();

    expect(conversationRepository.fetchAfterSeqs, <int>[0]);
    expect(conversationRepository.watchAfterSeqs, <int>[6]);
    expect(find.text('historical prompt'), findsOneWidget);
    expect(find.text('historical answer'), findsOneWidget);
    expect(find.text('00:00'), findsNothing);
  });

  testWidgets(
      'workbench lifecycle restarts event subscription after background',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final dependencies = AppDependencies.createDefault();
    final conversationRepository = _LifecycleConversationRepository();
    Future<void> pumpNavigationFrame() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    Future<void> pumpUntilWatchCalls(int expected) async {
      for (var attempt = 0;
          attempt < 20 && conversationRepository.watchCalls < expected;
          attempt += 1) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    void backgroundApp() {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    }

    void resumeApp() {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }

    final client = _AdapterRefreshClient();
    final connectedData = dependencies.data.forDaemonClient(client);
    final workbenchDependencies = dependencies.features
        .createWorkbenchDependencies(client, connectedData);
    final testDependencies = AppDependencies(
      network: dependencies.network,
      data: dependencies.data,
      domain: dependencies.domain,
      features: FeatureDependencies(
        createDaemonConnectionViewModel:
            dependencies.features.createDaemonConnectionViewModel,
        createDiagnosticsViewModel:
            dependencies.features.createDiagnosticsViewModel,
        createRunDetailViewModel:
            dependencies.features.createRunDetailViewModel,
        createAppUpdateViewModel:
            dependencies.features.createAppUpdateViewModel,
        createWorkbenchDependencies: (_, connectedData) =>
            WorkbenchDependencies(
          adapterRepository: connectedData.adapterRepository,
          asrModelManager: workbenchDependencies.asrModelManager,
          conversationRepository: conversationRepository,
          diagnosticsRepository: connectedData.diagnosticsRepository,
          runRepository: connectedData.runRepository,
          speechInputServiceBuilder:
              workbenchDependencies.speechInputServiceBuilder,
          workspaceRepository: connectedData.workspaceRepository,
        ),
      ),
    );

    await tester.pumpWidget(
      _MainTabsHarness(
        client: client,
        dependencies: testDependencies,
        snapshot: _testSnapshot(
          conversations: <ConversationSummary>[
            _conversationSummary(
              id: 'conv_lifecycle',
              workspaceId: 'workspace_1',
              status: 'running',
              sessionBinding: 'confirmed',
              userMessageCount: 1,
              title: 'Lifecycle task',
            ),
          ],
        ),
      ),
    );
    await pumpNavigationFrame();

    await tester.tap(find.text('Coding'));
    await pumpNavigationFrame();
    await tester.tap(find.text('Current Project'));
    await pumpNavigationFrame();
    await tester.tap(find.text('Lifecycle task'));
    await pumpUntilWatchCalls(1);

    expect(conversationRepository.watchCalls, 1);
    expect(conversationRepository.cancelCalls, 0);

    backgroundApp();
    await tester.pump(const Duration(seconds: 5));
    resumeApp();
    await tester.pump();
    expect(conversationRepository.watchCalls, 1);
    expect(conversationRepository.cancelCalls, 0);

    backgroundApp();
    await tester.pump(const Duration(seconds: 29));
    expect(conversationRepository.cancelCalls, 0);
    await tester.pump(const Duration(seconds: 2));
    expect(conversationRepository.cancelCalls, 1);

    resumeApp();
    await pumpUntilWatchCalls(2);
    expect(conversationRepository.watchCalls, 2);
    expect(conversationRepository.afterSeqs, <int>[0, 0]);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('app update recovery runs on create and resume',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    PackageInfo.setMockInitialValues(
      appName: 'LAN AI CLI Control',
      packageName: 'com.example.lan_ai_cli_control',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    final manifest = _widgetAppUpdateManifest();
    final installer = _WidgetAppUpdateInstaller(
      recoveredEvent: const AndroidInstallEvent(
        status: AndroidInstallStatus.pendingUserAction,
        sessionId: 22,
        message: 'Confirm install in Android.',
      ),
    );
    addTearDown(installer.close);
    final downloader = _WidgetAppUpdateDownloader();
    final appUpdateViewModel = AppUpdateViewModel(
      installedVersionCode: 1,
      installedVersionName: '1.0.0',
      workflow: AppUpdateWorkflow(
        repository: _WidgetAppUpdateRepository(manifest),
        installerService: installer,
        downloaderService: downloader,
      ),
      daemonBaseUri: Uri.parse('http://127.0.0.1:4317'),
    );
    final dependencies = AppDependencies.createDefault();
    final client = _AdapterRefreshClient();
    final testDependencies = AppDependencies(
      network: dependencies.network,
      data: dependencies.data,
      domain: dependencies.domain,
      features: FeatureDependencies(
        createDaemonConnectionViewModel:
            dependencies.features.createDaemonConnectionViewModel,
        createDiagnosticsViewModel:
            dependencies.features.createDiagnosticsViewModel,
        createRunDetailViewModel:
            dependencies.features.createRunDetailViewModel,
        createAppUpdateViewModel: ({
          required DaemonClient client,
          required ConnectedDataDependencies connectedData,
          required int installedVersionCode,
          required String installedVersionName,
        }) async =>
            appUpdateViewModel,
        createWorkbenchDependencies:
            dependencies.features.createWorkbenchDependencies,
      ),
    );

    Future<void> pumpUntilRecoveryReads(int expected) async {
      for (var attempt = 0;
          attempt < 20 && downloader.readSessionCalls < expected;
          attempt += 1) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    void resumeAppThroughMainTabs() {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }

    await tester.pumpWidget(
      _MainTabsHarness(
        client: client,
        dependencies: testDependencies,
        forceAndroidForTesting: true,
      ),
    );
    await pumpUntilRecoveryReads(1);
    await tester.pump();

    expect(downloader.readSessionCalls, 1);
    expect(installer.recoverCalls, 0);

    downloader.installSession = AppUpdateInstallSessionRecord(
      sessionId: 22,
      file: File('ready.apk'),
    );
    resumeAppThroughMainTabs();
    await pumpUntilRecoveryReads(2);
    await tester.pump();

    expect(downloader.readSessionCalls, 2);
    expect(installer.recoverCalls, 1);
    expect(appUpdateViewModel.state.status,
        AppUpdateStatus.awaitingUserConfirmation);

    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(seconds: 10)));

  testWidgets('sending existing conversation keeps current event subscription',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final dependencies = AppDependencies.createDefault();
    final conversationRepository = _LifecycleConversationRepository();

    Future<void> pumpNavigationFrame() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    Future<void> pumpUntilWatchCalls(int expected) async {
      for (var attempt = 0;
          attempt < 20 && conversationRepository.watchCalls < expected;
          attempt += 1) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> pumpUntilTextField() async {
      for (var attempt = 0;
          attempt < 20 && find.byType(TextField).evaluate().isEmpty;
          attempt += 1) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> pumpUntilSentText() async {
      for (var attempt = 0;
          attempt < 20 && conversationRepository.sentText == null;
          attempt += 1) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    final client = _AdapterRefreshClient();
    final connectedData = dependencies.data.forDaemonClient(client);
    final workbenchDependencies = dependencies.features
        .createWorkbenchDependencies(client, connectedData);
    final testDependencies = AppDependencies(
      network: dependencies.network,
      data: dependencies.data,
      domain: dependencies.domain,
      features: FeatureDependencies(
        createDaemonConnectionViewModel:
            dependencies.features.createDaemonConnectionViewModel,
        createDiagnosticsViewModel:
            dependencies.features.createDiagnosticsViewModel,
        createRunDetailViewModel:
            dependencies.features.createRunDetailViewModel,
        createAppUpdateViewModel:
            dependencies.features.createAppUpdateViewModel,
        createWorkbenchDependencies: (_, connectedData) =>
            WorkbenchDependencies(
          adapterRepository: connectedData.adapterRepository,
          asrModelManager: workbenchDependencies.asrModelManager,
          conversationRepository: conversationRepository,
          diagnosticsRepository: connectedData.diagnosticsRepository,
          runRepository: connectedData.runRepository,
          speechInputServiceBuilder:
              workbenchDependencies.speechInputServiceBuilder,
          workspaceRepository: connectedData.workspaceRepository,
        ),
      ),
    );

    await tester.pumpWidget(
      _MainTabsHarness(
        client: client,
        dependencies: testDependencies,
        snapshot: _testSnapshot(
          conversations: <ConversationSummary>[
            _conversationSummary(
              id: 'conv_send_existing',
              workspaceId: 'workspace_1',
              status: 'idle',
              sessionBinding: 'confirmed',
              userMessageCount: 1,
              title: 'Follow-up task',
            ),
          ],
        ),
      ),
    );
    await pumpNavigationFrame();

    await tester.tap(find.text('Coding'));
    await pumpNavigationFrame();
    await tester.tap(find.text('Current Project'));
    await pumpNavigationFrame();
    await tester.tap(find.text('Follow-up task'));
    await pumpUntilWatchCalls(1);

    expect(conversationRepository.watchCalls, 1);
    expect(conversationRepository.cancelCalls, 0);

    await pumpUntilTextField();
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'continue');
    await tester.pump();
    await tester
        .tap(find.byKey(const ValueKey('workbench-send-prompt-button')));
    await pumpUntilSentText();

    expect(conversationRepository.sentText, 'continue');
    final composer = tester.widget<TextField>(find.byType(TextField));
    expect(composer.controller?.text, isEmpty);
    expect(conversationRepository.watchCalls, 1);
    expect(conversationRepository.cancelCalls, 0);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('opening short existing conversation keeps transcript near top',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final messages = <ConversationEvent>[
      ConversationEvent.fromJson(<String, Object?>{
        'seq': 1,
        'conversationId': 'conv_short',
        'type': 'user.message',
        'createdAt': '2026-05-16T00:00:00.000Z',
        'text': 'short opening prompt',
      }),
      ConversationEvent.fromJson(<String, Object?>{
        'seq': 2,
        'conversationId': 'conv_short',
        'type': 'assistant.message',
        'createdAt': '2026-05-16T00:00:00.000Z',
        'text': 'short assistant response',
      }),
    ];
    final dependencies = AppDependencies.createDefault();
    final conversationRepository = _LazyConversationRepository(messages);
    final client = _AdapterRefreshClient();
    final connectedData = dependencies.data.forDaemonClient(client);
    final workbenchDependencies = dependencies.features
        .createWorkbenchDependencies(client, connectedData);
    final testDependencies = AppDependencies(
      network: dependencies.network,
      data: dependencies.data,
      domain: dependencies.domain,
      features: FeatureDependencies(
        createDaemonConnectionViewModel:
            dependencies.features.createDaemonConnectionViewModel,
        createDiagnosticsViewModel:
            dependencies.features.createDiagnosticsViewModel,
        createRunDetailViewModel:
            dependencies.features.createRunDetailViewModel,
        createAppUpdateViewModel:
            dependencies.features.createAppUpdateViewModel,
        createWorkbenchDependencies: (_, connectedData) =>
            WorkbenchDependencies(
          adapterRepository: connectedData.adapterRepository,
          asrModelManager: workbenchDependencies.asrModelManager,
          conversationRepository: conversationRepository,
          diagnosticsRepository: connectedData.diagnosticsRepository,
          runRepository: connectedData.runRepository,
          speechInputServiceBuilder:
              workbenchDependencies.speechInputServiceBuilder,
          workspaceRepository: connectedData.workspaceRepository,
        ),
      ),
    );

    await tester.pumpWidget(
      _MainTabsHarness(
        client: client,
        dependencies: testDependencies,
        snapshot: _testSnapshot(
          conversations: <ConversationSummary>[
            _conversationSummary(
              id: 'conv_short',
              workspaceId: 'workspace_1',
              status: 'completed',
              sessionBinding: 'confirmed',
              userMessageCount: messages.length,
              title: 'Short regression conversation',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Short regression conversation'));
    await tester.pumpAndSettle();

    final transcriptList = _workbenchMessageList();
    expect(transcriptList, findsOneWidget);
    final scrollTop = tester.getTopLeft(transcriptList).dy;
    final scrollBottom = tester.getBottomLeft(transcriptList).dy;
    final promptTop = tester.getTopLeft(find.text('short opening prompt')).dy;

    expect(promptTop, lessThan(scrollTop + (scrollBottom - scrollTop) * .45));
  });

  testWidgets('new conversation keeps short transcript near top while running',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final conversationRepository = _NewSessionConversationRepository();
    final dependencies = AppDependencies.createDefault();
    final client = _AdapterRefreshClient();
    final connectedData = dependencies.data.forDaemonClient(client);
    final workbenchDependencies = dependencies.features
        .createWorkbenchDependencies(client, connectedData);
    final testDependencies = AppDependencies(
      network: dependencies.network,
      data: dependencies.data,
      domain: dependencies.domain,
      features: FeatureDependencies(
        createDaemonConnectionViewModel:
            dependencies.features.createDaemonConnectionViewModel,
        createDiagnosticsViewModel:
            dependencies.features.createDiagnosticsViewModel,
        createRunDetailViewModel:
            dependencies.features.createRunDetailViewModel,
        createAppUpdateViewModel:
            dependencies.features.createAppUpdateViewModel,
        createWorkbenchDependencies: (_, connectedData) =>
            WorkbenchDependencies(
          adapterRepository: connectedData.adapterRepository,
          asrModelManager: workbenchDependencies.asrModelManager,
          conversationRepository: conversationRepository,
          diagnosticsRepository: connectedData.diagnosticsRepository,
          runRepository: connectedData.runRepository,
          speechInputServiceBuilder:
              workbenchDependencies.speechInputServiceBuilder,
          workspaceRepository: connectedData.workspaceRepository,
        ),
      ),
    );

    await tester.pumpWidget(
      _MainTabsHarness(
        client: client,
        dependencies: testDependencies,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New Session'));
    await tester.pumpAndSettle();

    const prompt = 'Who are you?';
    await tester.enterText(find.byType(TextField).last, prompt);
    await tester.pump();
    await tester
        .tap(find.byKey(const ValueKey('workbench-send-prompt-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(conversationRepository.sentText, prompt);
    expect(conversationRepository.sendCompleter.isCompleted, isFalse);
    final promptMessage = find.descendant(
      of: find.byKey(const ValueKey('workbench-message-0-user')),
      matching: find.text(prompt),
    );
    expect(promptMessage, findsOneWidget);

    final transcriptList = _workbenchMessageList();
    expect(transcriptList, findsOneWidget);
    final scrollTop = tester.getTopLeft(transcriptList).dy;
    final scrollBottom = tester.getBottomLeft(transcriptList).dy;
    final promptTop = tester.getTopLeft(promptMessage).dy;

    expect(promptTop, lessThan(scrollTop + (scrollBottom - scrollTop) * .45));

    conversationRepository.sendCompleter.complete(_conversationSummary(
      id: 'conv_new_running',
      workspaceId: 'workspace_1',
      status: 'completed',
      sessionBinding: 'confirmed',
      userMessageCount: 1,
    ));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('connected app preloads adapters before new session',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final client = _AdapterRefreshClient();

    await tester.pumpWidget(_MainTabsHarness(client: client));
    await tester.pumpAndSettle();

    expect(client.listAdaptersCalls, 1);

    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();

    expect(client.listAdaptersCalls, 1);

    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New Session'));
    await tester.pumpAndSettle();

    expect(find.text('codex'), findsWidgets);
    expect(find.text('No available CLI adapter'), findsNothing);

    await tester.tap(find.text('codex').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('adapter-picker-sheet')), findsOneWidget);
    expect(find.text('synthetic-jsonl'), findsNothing);
    expect(find.text('synthetic-text'), findsNothing);
  });

  testWidgets('coding waits for pending adapter preload',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final client = _PendingAdapterClient();

    await tester.pumpWidget(_MainTabsHarness(client: client));
    await tester.pump();

    expect(client.listAdaptersCalls, 1);

    await tester.tap(find.text('Coding'));
    await tester.pump();

    expect(find.text('Loading CLI...'), findsOneWidget);
    expect(find.byKey(const ValueKey('workspace-list')), findsNothing);
    expect(find.byKey(const ValueKey('coding-session-list')), findsNothing);
    expect(find.text('New Session'), findsNothing);
    expect(client.listAdaptersCalls, 1);

    client.completeWithAdapters();
    await tester.pumpAndSettle();

    expect(find.text('Loading CLI...'), findsNothing);
    expect(find.byKey(const ValueKey('workspace-list')), findsOneWidget);
  });

  testWidgets('coding adapter preload failure can retry',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final client = _PendingAdapterClient();

    await tester.pumpWidget(_MainTabsHarness(client: client));
    await tester.pump();
    client.completeWithError();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();

    expect(find.text('Unable to load CLI adapters'), findsOneWidget);
    expect(find.text('Retry loading CLI'), findsOneWidget);

    client.resetCompleter();
    await tester.tap(find.text('Retry loading CLI'));
    await tester.pump();

    expect(find.text('Loading CLI...'), findsOneWidget);
    expect(client.listAdaptersCalls, 2);

    client.completeWithAdapters();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('workspace-list')), findsOneWidget);
    expect(find.text('Unable to load CLI adapters'), findsNothing);
  });

  testWidgets('adapter picker scrolls on compact screens',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(375, 440);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
        theme: theme.buildAppTheme(),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
            backgroundColor: theme.bg,
            body: AdapterPickerSheet(
                selected: 'codex',
                onSelected: (_) {},
                adapters: const <AdapterStatus>[
                  AdapterStatus(
                      adapter: 'claude',
                      available: true,
                      status: 'available',
                      version: '2.1.112 (Claude Code)'),
                  AdapterStatus(
                      adapter: 'codex',
                      available: true,
                      status: 'available',
                      version: 'codex-cli 0.128.0'),
                  AdapterStatus(
                      adapter: 'opencode',
                      available: true,
                      status: 'available',
                      version: '0.9.0'),
                  AdapterStatus(
                      adapter: 'custom-a',
                      available: true,
                      status: 'available',
                      version: '1.0.0'),
                  AdapterStatus(
                      adapter: 'custom-b',
                      available: true,
                      status: 'available',
                      version: '1.0.0'),
                ]))));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('adapter-picker-sheet')), findsOneWidget);
  });

  testWidgets('model picker shows fallback row when no model list exists',
      (WidgetTester tester) async {
    String? selected = 'unchanged';
    await tester.pumpWidget(MaterialApp(
        theme: theme.buildAppTheme(),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
            backgroundColor: theme.bg,
            body: ModelPickerSheet(
                selected: null,
                onSelected: (model) => selected = model,
                models: const <AdapterModelOption>[]))));

    expect(find.byKey(const ValueKey('model-picker-sheet')), findsOneWidget);
    expect(find.text('Default model'), findsOneWidget);
    expect(find.text('Uses the CLI configured default.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('model-option-default')));

    expect(selected, isNull);
  });

  testWidgets('model picker renders model source labels',
      (WidgetTester tester) async {
    String? selected;
    await tester.pumpWidget(MaterialApp(
        theme: theme.buildAppTheme(),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
            backgroundColor: theme.bg,
            body: ModelPickerSheet(
                selected: 'gpt-5-codex',
                onSelected: (model) => selected = model,
                models: const <AdapterModelOption>[
                  AdapterModelOption(
                      id: 'gpt-5-codex',
                      label: 'GPT-5 Codex',
                      source: 'codex_config',
                      selected: true),
                  AdapterModelOption(
                      id: 'gpt-5-catalog',
                      label: 'GPT-5 Catalog',
                      source: 'codex_catalog',
                      selected: false),
                  AdapterModelOption(
                      id: 'claude-sonnet',
                      label: 'Claude Sonnet',
                      source: 'claude_config',
                      selected: false),
                  AdapterModelOption(
                      id: 'cli-default',
                      label: 'CLI Default',
                      source: 'cli_default',
                      selected: false),
                  AdapterModelOption(
                      id: 'mystery',
                      label: 'Mystery',
                      source: 'future_source',
                      selected: false),
                ]))));

    expect(find.text('GPT-5 Codex'), findsOneWidget);
    expect(find.text('Codex config'), findsOneWidget);
    expect(find.text('Codex catalog'), findsOneWidget);
    expect(find.text('Claude config'), findsOneWidget);
    expect(find.text('CLI default'), findsOneWidget);
    expect(find.text('Unknown source'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('model-option-claude-sonnet')));

    expect(selected, 'claude-sonnet');
  });

  testWidgets('model picker shows pending update and disables selections',
      (WidgetTester tester) async {
    String? selected = 'unchanged';
    await tester.pumpWidget(MaterialApp(
        theme: theme.buildAppTheme(),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
            backgroundColor: theme.bg,
            body: ModelPickerSheet(
                selected: 'gpt-5-codex',
                updating: true,
                onSelected: (model) => selected = model,
                models: const <AdapterModelOption>[
                  AdapterModelOption(
                      id: 'gpt-5-codex',
                      label: 'GPT-5 Codex',
                      source: 'codex_config',
                      selected: true),
                  AdapterModelOption(
                      id: 'claude-sonnet',
                      label: 'Claude Sonnet',
                      source: 'claude_config',
                      selected: false),
                ]))));

    expect(find.byKey(const ValueKey('model-picker-updating')), findsOneWidget);
    expect(find.text('Updating model...'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('model-option-claude-sonnet')));

    expect(selected, 'unchanged');
  });

  testWidgets('model picker displays model update errors',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: theme.buildAppTheme(),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
            backgroundColor: theme.bg,
            body: ModelPickerSheet(
                selected: null,
                errorText: 'Model backend rejected this model.',
                onSelected: (_) {},
                models: const <AdapterModelOption>[]))));

    expect(find.byKey(const ValueKey('model-picker-error')), findsOneWidget);
    expect(find.text('Model backend rejected this model.'), findsOneWidget);
  });

  testWidgets('model picker keeps unsupported errors visible while disabled',
      (WidgetTester tester) async {
    String? selected = 'unchanged';
    await tester.pumpWidget(MaterialApp(
        theme: theme.buildAppTheme(),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
            backgroundColor: theme.bg,
            body: ModelPickerSheet(
                selected: 'gpt-5-codex',
                selectionDisabled: true,
                errorText:
                    'Update the desktop daemon to change models in existing '
                    'conversations.',
                onSelected: (model) => selected = model,
                models: const <AdapterModelOption>[
                  AdapterModelOption(
                      id: 'gpt-5-codex',
                      label: 'GPT-5 Codex',
                      source: 'codex_config',
                      selected: true),
                  AdapterModelOption(
                      id: 'claude-sonnet',
                      label: 'Claude Sonnet',
                      source: 'claude_config',
                      selected: false),
                ]))));

    expect(find.byKey(const ValueKey('model-picker-error')), findsOneWidget);
    expect(
        find.text('Update the desktop daemon to change models in existing '
            'conversations.'),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('model-option-claude-sonnet')));

    expect(selected, 'unchanged');
  });

  testWidgets('tapping current project opens workspace session list',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildCodingWorkbenchEntryPreview());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('coding-session-list')), findsOneWidget);
    expect(find.textContaining(RegExp('New Session|\u65b0\u5efa\u4f1a\u8bdd')),
        findsOneWidget);
    expect(find.text('Select workspace for this coding session'), findsNothing);
  });

  testWidgets('returning to coding tab shows workspace list',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    await tester.pumpWidget(_MainTabsHarness(client: _AdapterRefreshClient()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('coding-session-list')), findsOneWidget);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('workspace-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('coding-session-list')), findsNothing);
  });

  testWidgets('system back walks coding nested navigator before home',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    await tester.pumpWidget(_MainTabsHarness(client: _AdapterRefreshClient()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New Session'));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('coding-workbench-detail')), findsOneWidget);
    expect(find.byType(BottomNav), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('coding-session-list')), findsOneWidget);
    expect(find.byType(BottomNav), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('workspace-list')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Current Project'), findsWidgets);
    expect(find.byKey(const ValueKey('workspace-list')), findsNothing);
  });

  testWidgets('system back returns conversation to sessions',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    await tester.pumpWidget(_MainTabsHarness(client: _AdapterRefreshClient()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New Session'));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('coding-workbench-detail')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('coding-session-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('coding-workbench-detail')), findsNothing);
  });

  testWidgets('new coding session title uses active locale',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildCodingWorkbenchEntryPreview());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Current Project'));
    await tester.pumpAndSettle();
    await tester.tap(
        find.textContaining(RegExp('New Session|\u65b0\u5efa\u4f1a\u8bdd')));
    await tester.pumpAndSettle();

    expect(find.text('新的编码会话'), findsOneWidget);
    expect(find.text('New coding session'), findsNothing);
  });

  testWidgets('session list shows only selected workspace sessions',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildWorkspaceScopedSessionPreview());
    await tester.pumpAndSettle();

    expect(find.textContaining('current-1'), findsWidgets);
    expect(find.textContaining('other-1'), findsNothing);
  });

  testWidgets('session list prefers stable conversation title over uuid labels',
      (WidgetTester tester) async {
    const workspace = WorkspaceSummary(
        id: 'workspace_1',
        name: 'Current Project',
        path: r'D:\AiProject\vibe-coding');
    final conversation = _conversationSummary(
      id: 'conv_019e4d98',
      workspaceId: workspace.id,
      status: 'interrupted',
      cliSessionId: '019e4d98-348d-7840-b8ef-9b2dda2c1235',
      sessionBinding: 'confirmed',
      userMessageCount: 1,
      title: 'Fix mobile title rendering',
    );
    final data = _testSnapshot(conversations: <ConversationSummary>[
      conversation,
    ]);

    await tester.pumpWidget(MaterialApp(
      locale: theme.zhHansCnLocale,
      supportedLocales: const [theme.zhHansCnLocale, Locale('en', 'US')],
      localizationsDelegates: theme.appLocalizationsDelegates,
      theme: ThemeData(
          brightness: Brightness.dark,
          fontFamily: 'Segoe UI',
          fontFamilyFallback: theme.appFontFallback,
          useMaterial3: true),
      home: Scaffold(
        backgroundColor: theme.bg,
        body: CodingSessionListPage(
          data: data,
          items: <SessionItem>[
            SessionItem(
              run: const RunSummary(
                id: 'conv_019e4d98',
                tool: 'codex',
                workspaceId: 'workspace_1',
                status: 'interrupted',
                cliSessionId: '019e4d98-348d-7840-b8ef-9b2dda2c1235',
              ),
              conversation: conversation,
            ),
          ],
          currentWorkspace: workspace,
          onNewSession: () {},
          onSelectItem: (_) {},
          onBackToWorkspaces: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Fix mobile title rendering'), findsOneWidget);
    expect(find.text('Codex 会话 019e4d98'), findsNothing);
  });

  testWidgets('missing selected workspace falls back to workspace list',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildMissingWorkspaceFallbackPreview());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('workspace-list')), findsOneWidget);
    expect(find.text('Current Project'), findsOneWidget);
    expect(find.text('Stale Workspace'), findsNothing);
  });

  test('newly created coding runs appear before snapshot runs', () {
    const created = RunSummary(
        id: 'run_created',
        tool: 'claude',
        workspaceId: 'workspace_1',
        status: 'running');
    const staleCreated = RunSummary(
        id: 'run_created',
        tool: 'claude',
        workspaceId: 'workspace_1',
        status: 'completed');
    const older = RunSummary(
        id: 'run_older',
        tool: 'codex',
        workspaceId: 'workspace_1',
        status: 'completed');

    expect(
        debugMergeSessionRunIds(const <RunSummary>[created],
            const <RunSummary>[staleCreated, older]),
        const <String>['run_created', 'run_older']);
  });

  test('persisted coding conversations appear after Flutter restart', () {
    const local = RunSummary(
        id: 'conv_local',
        tool: 'claude',
        workspaceId: 'workspace_1',
        status: 'running');
    const persisted = ConversationSummary(
        id: 'conv_persisted',
        workspaceId: 'workspace_1',
        adapter: 'claude',
        status: 'interrupted',
        capabilities: ConversationCapabilities(
            longLivedProcess: true,
            waitingInput: true,
            waitingApproval: true,
            resume: true,
            partialOutput: true),
        createdAt: '2026-05-03T00:00:00.000Z',
        updatedAt: '2026-05-03T00:00:01.000Z',
        cliSessionId: 'claude-session');
    const emptyDraft = ConversationSummary(
        id: 'conv_empty',
        workspaceId: 'workspace_1',
        adapter: 'claude',
        status: 'idle',
        capabilities: ConversationCapabilities(
            longLivedProcess: true,
            waitingInput: true,
            waitingApproval: true,
            resume: true,
            partialOutput: true),
        createdAt: '2026-05-03T00:00:00.000Z',
        updatedAt: '2026-05-03T00:00:01.000Z');
    const legacyRun = RunSummary(
        id: 'run_legacy',
        tool: 'codex',
        workspaceId: 'workspace_1',
        status: 'completed');

    expect(
        debugMergeSessionIds(
            const <RunSummary>[local],
            const <ConversationSummary>[persisted, emptyDraft],
            const <RunSummary>[legacyRun]),
        const <String>['conv_local', 'conv_persisted', 'run_legacy']);
  });

  test(
      'cancelled failed and interrupted conversations stay conversation backed in session list',
      () {
    const capabilities = ConversationCapabilities(
      longLivedProcess: true,
      waitingInput: true,
      waitingApproval: true,
      resume: true,
      partialOutput: true,
    );
    final conversations = <ConversationSummary>[
      _conversationSummary(
        id: 'conv_cancelled',
        workspaceId: 'workspace_1',
        status: 'cancelled',
        cliSessionId: 'claude-session-1',
        sessionBinding: 'confirmed',
        capabilities: capabilities,
      ),
      _conversationSummary(
        id: 'conv_failed',
        workspaceId: 'workspace_1',
        status: 'failed',
        cliSessionId: 'claude-session-2',
        sessionBinding: 'confirmed',
        capabilities: capabilities,
      ),
      _conversationSummary(
        id: 'conv_interrupted',
        workspaceId: 'workspace_1',
        status: 'interrupted',
        sessionBinding: 'unknown',
        userMessageCount: 1,
        capabilities: capabilities,
      ),
    ];

    final items = mergeSessionItems(
      const <String, SessionItem>{},
      conversations,
      const <RunSummary>[],
    );

    expect(
      items.map((item) => item.id),
      <String>['conv_cancelled', 'conv_failed', 'conv_interrupted'],
    );
    expect(items.every((item) => item.conversation != null), isTrue);
    expect(items.last.run.status, 'interrupted');
  });

  test('idle empty draft without messages remains hidden from session list',
      () {
    final items = mergeSessionItems(
      const <String, SessionItem>{},
      <ConversationSummary>[
        _conversationSummary(
          id: 'conv_empty',
          workspaceId: 'workspace_1',
          status: 'idle',
          sessionBinding: 'unknown',
          userMessageCount: 0,
        ),
      ],
      const <RunSummary>[],
    );

    expect(items, isEmpty);
  });

  test('approval response restarts events only for active conversations', () {
    const capabilities = ConversationCapabilities(
      longLivedProcess: true,
      waitingInput: true,
      waitingApproval: true,
      resume: true,
      partialOutput: true,
    );
    const running = ConversationSummary(
      id: 'conv_running',
      workspaceId: 'workspace_1',
      adapter: 'claude',
      status: 'running',
      capabilities: capabilities,
      createdAt: '2026-05-03T00:00:00.000Z',
      updatedAt: '2026-05-03T00:00:01.000Z',
    );
    const idle = ConversationSummary(
      id: 'conv_idle',
      workspaceId: 'workspace_1',
      adapter: 'claude',
      status: 'idle',
      capabilities: capabilities,
      createdAt: '2026-05-03T00:00:00.000Z',
      updatedAt: '2026-05-03T00:00:01.000Z',
    );

    expect(debugShouldRestartEventsAfterApproval(running), isTrue);
    expect(debugShouldRestartEventsAfterApproval(idle), isFalse);
  });

  test('historical sessions do not count as explicit workspace selection', () {
    expect(
        debugHasExplicitWorkspaceSelection(
          workspaceConfirmedForSession: false,
          activeRunId: null,
          hasLocalSessions: true,
        ),
        isFalse);
    expect(
        debugHasExplicitWorkspaceSelection(
          workspaceConfirmedForSession: true,
          activeRunId: null,
          hasLocalSessions: false,
        ),
        isTrue);
    expect(
        debugHasExplicitWorkspaceSelection(
          workspaceConfirmedForSession: false,
          activeRunId: 'conv_1',
          hasLocalSessions: false,
        ),
        isTrue);
  });

  test('approval cards only show the current blocking approval', () {
    const capabilities = ConversationCapabilities(
      longLivedProcess: true,
      waitingInput: true,
      waitingApproval: true,
      resume: true,
      partialOutput: true,
    );
    const conversation = ConversationSummary(
      id: 'conv_1',
      workspaceId: 'workspace_1',
      adapter: 'claude',
      status: 'waiting_approval',
      capabilities: capabilities,
      createdAt: '2026-05-03T00:00:00.000Z',
      updatedAt: '2026-05-03T00:00:02.000Z',
      blockingItem: ConversationBlockingItem(
        type: 'approval_request',
        approvalId: 'ap2',
        toolName: 'Bash',
        summary: 'python intro.py',
      ),
    );
    final events = <Map<String, Object?>>[
      const <String, Object?>{
        'seq': 1,
        'conversationId': 'conv_1',
        'type': 'approval.requested',
        'createdAt': '2026-05-03T00:00:00.000Z',
        'approvalId': 'ap1',
        'toolName': 'Write',
        'summary': r'C:\Users\W2830\intro.py'
      },
      const <String, Object?>{
        'seq': 2,
        'conversationId': 'conv_1',
        'type': 'approval.requested',
        'createdAt': '2026-05-03T00:00:01.000Z',
        'approvalId': 'ap2',
        'toolName': 'Bash',
        'summary': r'python intro.py'
      },
    ];

    expect(debugVisibleApprovalIdsForConversation(events, conversation),
        const <String>['ap2']);
  });

  testWidgets('running composer shows stop action instead of send',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildRunningComposerPreview());
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
  });

  testWidgets('new coding session workspace preview shows workspace list',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildNewSessionWorkspacePickerPreview());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('workspace-list')), findsOneWidget);
    expect(find.text('Current Project'), findsOneWidget);
  });

  test('workspace list presentation deduplicates duplicate paths', () {
    final visible = dedupeWorkspacesByPath(const <WorkspaceSummary>[
      WorkspaceSummary(
          id: 'workspace_a', name: 'Agent', path: r'D:\AiProject\Agent'),
      WorkspaceSummary(
          id: 'workspace_b', name: 'Agent copy', path: r'D:\AiProject\Agent'),
      WorkspaceSummary(
          id: 'workspace_c', name: 'cli-ui', path: r'D:\AiProject\cli-ui'),
    ]);

    expect(visible.map((workspace) => workspace.id),
        const <String>['workspace_a', 'workspace_c']);
  });

  testWidgets('workspace search placeholder uses active locale',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildNewSessionWorkspacePickerPreview());
    await tester.pumpAndSettle();

    expect(find.text('搜索会话、命令或文件路径...'), findsOneWidget);
    expect(find.text('Search sessions, commands, file paths...'), findsNothing);
  });

  testWidgets('add workspace sheet uses active locale',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
        locale: theme.zhHansCnLocale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        localeResolutionCallback: (locale, supportedLocales) =>
            resolveSupportedLocale(locale, supportedLocales),
        theme: theme.buildAppTheme(),
        home: Scaffold(
            body: AddWorkspaceSheet(
                workspaceRepository: _WidgetTestWorkspaceRepository()))));

    expect(find.text('添加工作区'), findsOneWidget);
    expect(find.text('浏览'), findsOneWidget);
    expect(find.text('选择或输入文件夹路径'), findsOneWidget);
    expect(find.text('名称（可选）'), findsOneWidget);
    expect(find.text('创建并使用'), findsOneWidget);
    expect(find.text('Add workspace'), findsNothing);
    expect(find.text('Browse'), findsNothing);
  });

  testWidgets('directory browser localizes labels and returns to drive list',
      (WidgetTester tester) async {
    final repository = _WidgetTestWorkspaceRepository(
      roots: const <DirectoryEntrySummary>[
        DirectoryEntrySummary(name: r'D:\', path: r'D:\'),
      ],
      directories: const <String, DirectoryListing>{
        r'D:\': DirectoryListing(
          path: r'D:\',
          directories: <DirectoryEntrySummary>[
            DirectoryEntrySummary(name: 'AIProject', path: r'D:\AIProject'),
          ],
        ),
      },
    );

    await tester.pumpWidget(MaterialApp(
        locale: theme.zhHansCnLocale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        localeResolutionCallback: (locale, supportedLocales) =>
            resolveSupportedLocale(locale, supportedLocales),
        theme: theme.buildAppTheme(),
        home: Scaffold(
            backgroundColor: theme.bg,
            body: DirectoryBrowserSheet.forWorkspaceRepository(
                repository: repository))));
    await tester.pumpAndSettle();

    expect(find.text('选择文件夹'), findsOneWidget);
    expect(find.text('选择磁盘或根目录后继续进入文件夹'), findsOneWidget);
    expect(find.text('Choose folder'), findsNothing);

    await tester.tap(find.text(r'D:\').first);
    await tester.pumpAndSettle();

    expect(find.text('选择当前'), findsOneWidget);
    expect(find.byTooltip('返回'), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();

    expect(find.text('选择磁盘或根目录后继续进入文件夹'), findsOneWidget);
    expect(find.text('选择当前'), findsNothing);
  });

  testWidgets('completed command card shows duration and success status icon',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildCompletedCommandCardPreview());
    await tester.pumpAndSettle();

    expect(find.text('npm run lint && npm test'), findsWidgets);
    expect(find.textContaining('执行 1 条命令'), findsOneWidget);
    expect(find.textContaining('cwd resolved'), findsOneWidget);
    expect(find.textContaining('2.1s'), findsOneWidget);
    expect(find.byKey(const ValueKey('tool-status-ok')), findsOneWidget);
  });

  testWidgets('command output opens a full detail sheet',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildConversationCommandCardPreview());
    await tester.pumpAndSettle();

    await tester.tap(find.text('hello from intro').first);
    await tester.pumpAndSettle();

    expect(find.text('输出详情'), findsOneWidget);
    expect(find.byTooltip('复制全文'), findsOneWidget);
    expect(find.text('hello from intro'), findsWidgets);
  });

  testWidgets('command preview wraps long text but defaults to two lines',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const longCommand =
        r'"C:\Program Files\PowerShell\7\pwsh.exe" -NoLogo -NoProfile -Command "Get-ChildItem D:\AIProject\vibe-coding\mobile\lib\src\ui\features\workbench\workbench_event_cards.dart"';

    await tester.pumpWidget(MaterialApp(
        locale: theme.zhHansCnLocale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        localeResolutionCallback: (locale, supportedLocales) =>
            resolveSupportedLocale(locale, supportedLocales),
        theme: theme.buildAppTheme(),
        home: Scaffold(
            backgroundColor: theme.bg,
            body: Padding(
                padding: const EdgeInsets.all(16),
                child: WorkbenchMessageCard(
                    message: const WorkbenchMessage(
                        'command', 'command_execution', longCommand,
                        completed: true,
                        duration: Duration(milliseconds: 2550)),
                    onApproval: (_) {},
                    onSuggestion: (_) {},
                    expandThinking: false)))));
    await tester.pumpAndSettle();

    expect(
        find.byWidgetPredicate((widget) =>
            widget is Text &&
            widget.data == longCommand &&
            widget.maxLines == 2 &&
            widget.overflow == TextOverflow.ellipsis),
        findsOneWidget);

    await tester.tap(find.text(longCommand).last);
    await tester.pumpAndSettle();

    expect(find.text('命令详情'), findsOneWidget);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is SelectableText &&
            widget.data == longCommand &&
            widget.maxLines == null),
        findsOneWidget);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal),
        findsNothing);
  });

  testWidgets(
      'large command output defaults to two-line preview and opens details',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildLargeOutputCommandCardPreview());
    await tester.pumpAndSettle();

    expect(
        find.byWidgetPredicate((widget) =>
            widget is Text &&
            widget.data?.startsWith('line 0') == true &&
            widget.maxLines == 2 &&
            widget.overflow == TextOverflow.ellipsis),
        findsOneWidget);
    expect(find.text('Show more'), findsNothing);

    await tester.tap(find.textContaining('line 0'));
    await tester.pumpAndSettle();

    expect(find.text('Output details'), findsOneWidget);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is SelectableText &&
            widget.data?.contains('line 204') == true),
        findsOneWidget);
    expect(find.text('Show less'), findsNothing);
  });

  testWidgets(
      'pending sentinel is compact and does not show adapter or action list',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildPendingSentinelPreview());
    await tester.pump();

    expect(find.text('claude running'), findsNothing);
    expect(find.text('Claude requesting'), findsNothing);
  });

  testWidgets('pending sentinel shows elapsed running time',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildPendingSentinelPreview());
    await tester.pump();

    expect(find.text('00:00'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));

    expect(find.text('00:02'), findsOneWidget);
  });

  testWidgets('pending sentinel resumes elapsed time from stable start',
      (WidgetTester tester) async {
    var now = DateTime.utc(2026, 5, 25, 12);
    final startedAt = now.subtract(const Duration(seconds: 65));
    await tester.pumpWidget(MaterialApp(
        locale: theme.zhHansCnLocale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        theme: theme.buildAppTheme(),
        home: Scaffold(
            backgroundColor: theme.bg,
            body: Padding(
                padding: const EdgeInsets.all(16),
                child: PendingSentinel(
                  adapter: 'claude',
                  statusText: 'Receiving CLI output...',
                  startedAt: startedAt,
                  now: () => now,
                )))));
    await tester.pump();

    expect(find.text('01:05'), findsOneWidget);

    now = now.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('01:07'), findsOneWidget);
  });

  testWidgets('file change card shows edited path and diff preview',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
        locale: theme.zhHansCnLocale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        localeResolutionCallback: (locale, supportedLocales) =>
            resolveSupportedLocale(locale, supportedLocales),
        theme: theme.buildAppTheme(),
        home: Scaffold(
            backgroundColor: theme.bg,
            body: Padding(
                padding: const EdgeInsets.all(16),
                child: WorkbenchMessageCard(
                    message: const WorkbenchMessage(
                        'file_change',
                        'File changes',
                        'File changed: updated mobile/test/example_test.dart',
                        fileChanges: <ConversationFileChange>[
                          ConversationFileChange(
                              path: 'mobile/test/example_test.dart',
                              kind: 'update',
                              diff:
                                  '@@ -1,3 +1,3 @@\n-  old expectation\n+  new expectation')
                        ]),
                    onApproval: _noopString,
                    onSuggestion: _noopString,
                    expandThinking: false)))));
    await tester.pumpAndSettle();

    expect(find.text('Edited example_test.dart'), findsOneWidget);
    expect(find.text('mobile/test/example_test.dart'), findsOneWidget);
    expect(find.text('@@ -1,3 +1,3 @@'), findsOneWidget);
    expect(find.text('-  old expectation'), findsOneWidget);
    expect(find.text('+  new expectation'), findsOneWidget);
    expect(find.text('System notice'), findsNothing);
  });

  testWidgets('thinking card title uses active locale',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
        locale: theme.zhHansCnLocale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        localeResolutionCallback: (locale, supportedLocales) =>
            resolveSupportedLocale(locale, supportedLocales),
        theme: theme.buildAppTheme(),
        home: Scaffold(
            backgroundColor: theme.bg,
            body: Padding(
                padding: const EdgeInsets.all(16),
                child: WorkbenchMessageCard(
                    message: const WorkbenchMessage(
                        'thinking', 'Thinking process', '正在分析上下文'),
                    onApproval: (_) {},
                    onSuggestion: (_) {},
                    expandThinking: false)))));

    expect(find.text('思考过程'), findsOneWidget);
    expect(find.text('Thinking process'), findsNothing);
  });

  testWidgets('assistant code blocks expose a compact copy action',
      (WidgetTester tester) async {
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (MethodCall methodCall) async {
      if (methodCall.method == 'Clipboard.setData') {
        final data = methodCall.arguments as Map<Object?, Object?>;
        clipboardText = data['text'] as String?;
      }
      return null;
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        theme: theme.buildAppTheme(),
        home: Scaffold(
            backgroundColor: theme.bg,
            body: Padding(
                padding: const EdgeInsets.all(16),
                child: WorkbenchMessageCard(
                    message: const WorkbenchMessage('assistant', 'Codex',
                        'Run this:\n\n```powershell\nflutter analyze\n```\n\nThen continue.'),
                    onApproval: (_) {},
                    onSuggestion: (_) {},
                    expandThinking: false)))));

    final copyButton = find.byKey(const Key('workbench-markdown-code-copy'));
    expect(copyButton, findsOneWidget);
    expect(find.byIcon(Icons.copy_rounded), findsOneWidget);

    await tester.tap(copyButton);
    await tester.pump();

    expect(clipboardText, 'flutter analyze');
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    final feedbackShell = tester.widget<AnimatedContainer>(
        find.byKey(const Key('workbench-markdown-code-copy-feedback')));
    final decoration = feedbackShell.decoration as BoxDecoration;
    expect(decoration.color, const Color(0xFFE7ECF8));
    expect(decoration.border, isNotNull);
    final copiedIcon = tester.widget<Icon>(find.byIcon(Icons.check_rounded));
    expect(copiedIcon.color, const Color(0xFF0B0C0E));

    await tester.pump(const Duration(milliseconds: 2200));
    await tester.pump(const Duration(milliseconds: 180));

    expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
    clipboardText = null;

    await tester.tap(copyButton);
    await tester.pump();

    expect(clipboardText, 'flutter analyze');
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2200));
    await tester.pump(const Duration(milliseconds: 180));
  });

  testWidgets('user message card splits image attachment and text preview',
      (WidgetTester tester) async {
    final tempDir =
        Directory.systemTemp.createTempSync('workbench-preview-test-');
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
    final imageFile = File(
      '${tempDir.path}${Platform.pathSeparator}workbench-preview.png',
    );
    imageFile.writeAsBytesSync(<int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      0x00,
      0x00,
      0x00,
      0x0D,
      0x49,
      0x48,
      0x44,
      0x52,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x01,
      0x08,
      0x06,
      0x00,
      0x00,
      0x00,
      0x1F,
      0x15,
      0xC4,
      0x89,
      0x00,
      0x00,
      0x00,
      0x0A,
      0x49,
      0x44,
      0x41,
      0x54,
      0x78,
      0x9C,
      0x63,
      0x00,
      0x01,
      0x00,
      0x00,
      0x05,
      0x00,
      0x01,
      0x0D,
      0x0A,
      0x2D,
      0xB4,
      0x00,
      0x00,
      0x00,
      0x00,
      0x49,
      0x45,
      0x4E,
      0x44,
      0xAE,
      0x42,
      0x60,
      0x82,
    ]);

    await tester.pumpWidget(MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        theme: theme.buildAppTheme(),
        home: Scaffold(
            backgroundColor: theme.bg,
            body: Padding(
                padding: const EdgeInsets.all(16),
                child: WorkbenchMessageCard(
                    message: WorkbenchMessage(
                      'user',
                      'You',
                      '这个图片里面有什么？',
                      attachments: <CommittedAttachment>[
                        CommittedAttachment(
                          id: 'att_0',
                          name: 'screenshot.png',
                          kind: AttachmentKind.image,
                          mimeType: 'image/png',
                          sizeBytes: 1219716,
                          handling: AttachmentHandling.native,
                          localPath: imageFile.path,
                        ),
                      ],
                    ),
                    onApproval: (_) {},
                    onSuggestion: (_) {},
                    expandThinking: false)))));

    expect(find.text('这个图片里面有什么？'), findsOneWidget);
    expect(find.text('screenshot.png'), findsOneWidget);
    expect(find.byKey(const Key('workbench-user-attachment-bubble')),
        findsOneWidget);
    expect(find.byKey(const Key('workbench-user-text-bubble')), findsOneWidget);
    expect(find.byKey(const Key('workbench-message-image-preview')),
        findsOneWidget);
    expect(find.byKey(const Key('workbench-message-image-preview-shell')),
        findsOneWidget);
    final imagePreviewShell = tester.widget<Container>(
        find.byKey(const Key('workbench-message-image-preview-shell')));
    expect((imagePreviewShell.decoration! as BoxDecoration).border, isNotNull);
    final borderedAttachmentContainers = tester
        .widgetList<Container>(find.descendant(
            of: find.byKey(const Key('workbench-user-attachment-bubble')),
            matching: find.byType(Container)))
        .where((container) =>
            container.decoration is BoxDecoration &&
            (container.decoration! as BoxDecoration).border != null);
    expect(borderedAttachmentContainers.map((container) => container.key),
        <Key>[const Key('workbench-message-image-preview-shell')]);

    await tester.pumpWidget(const SizedBox.shrink());
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets('user message card shows image placeholder on cache miss',
      (WidgetTester tester) async {
    final tempDir = Directory.systemTemp.createTempSync('workbench-miss-test-');
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });
    final missingPath =
        '${tempDir.path}${Platform.pathSeparator}missing-preview.png';

    await tester.pumpWidget(MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        theme: theme.buildAppTheme(),
        home: Scaffold(
            backgroundColor: theme.bg,
            body: Padding(
                padding: const EdgeInsets.all(16),
                child: WorkbenchMessageCard(
                    message: WorkbenchMessage(
                      'user',
                      'You',
                      '重启后缓存没命中',
                      attachments: <CommittedAttachment>[
                        CommittedAttachment(
                          id: 'att_0',
                          name: 'persisted.png',
                          kind: AttachmentKind.image,
                          mimeType: 'image/png',
                          sizeBytes: 1219716,
                          handling: AttachmentHandling.native,
                          localPath: missingPath,
                        ),
                      ],
                    ),
                    onApproval: (_) {},
                    onSuggestion: (_) {},
                    expandThinking: false)))));

    expect(find.text('重启后缓存没命中'), findsOneWidget);
    expect(find.text('persisted.png'), findsOneWidget);
    expect(find.byKey(const Key('workbench-user-attachment-bubble')),
        findsOneWidget);
    expect(find.byKey(const Key('workbench-user-text-bubble')), findsOneWidget);
    expect(find.byKey(const Key('workbench-message-image-preview')),
        findsOneWidget);
    expect(find.byKey(const Key('workbench-message-image-preview-shell')),
        findsOneWidget);
    expect(find.byIcon(Icons.image_outlined), findsNWidgets(2));
    expect(find.text('1.2 MB'), findsOneWidget);
    final borderedAttachmentContainers = tester
        .widgetList<Container>(find.descendant(
            of: find.byKey(const Key('workbench-user-attachment-bubble')),
            matching: find.byType(Container)))
        .where((container) =>
            container.decoration is BoxDecoration &&
            (container.decoration! as BoxDecoration).border != null)
        .toList(growable: false);
    expect(borderedAttachmentContainers.length, 1);
    expect(borderedAttachmentContainers.map((container) => container.key),
        <Key>[const Key('workbench-message-image-preview-shell')]);

    await tester.pumpWidget(const SizedBox.shrink());
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets('user message card opens image attachment viewer',
      (WidgetTester tester) async {
    final tempDir =
        Directory.systemTemp.createTempSync('workbench-image-viewer-test-');
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
    final imageFile = File(
      '${tempDir.path}${Platform.pathSeparator}workbench-viewer.png',
    )..writeAsBytesSync(<int>[0x00]);

    await tester.pumpWidget(MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        theme: theme.buildAppTheme(),
        home: Scaffold(
            backgroundColor: theme.bg,
            body: Padding(
                padding: const EdgeInsets.all(16),
                child: WorkbenchMessageCard(
                    message: WorkbenchMessage(
                      'user',
                      'You',
                      '查看这张图',
                      attachments: <CommittedAttachment>[
                        CommittedAttachment(
                          id: 'att_0',
                          name: 'viewer.png',
                          kind: AttachmentKind.image,
                          mimeType: 'image/png',
                          sizeBytes: 1,
                          handling: AttachmentHandling.native,
                          localPath: imageFile.path,
                        ),
                      ],
                    ),
                    onApproval: (_) {},
                    onSuggestion: (_) {},
                    expandThinking: false)))));

    expect(
        find.byKey(const Key('workbench-message-image-viewer')), findsNothing);

    await tester.tap(find.byKey(const Key('workbench-message-image-preview')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('workbench-message-image-viewer')),
        findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byKey(const Key('workbench-message-image-viewer-image')),
        findsOneWidget);

    await tester
        .tap(find.byKey(const Key('workbench-message-image-viewer-close')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('workbench-message-image-viewer')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets(
      'user message card ignores deleted cached image before viewer tap',
      (WidgetTester tester) async {
    final tempDir = Directory.systemTemp
        .createTempSync('workbench-image-viewer-eviction-test-');
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
    final imageFile = File(
      '${tempDir.path}${Platform.pathSeparator}evicted-viewer.png',
    )..writeAsBytesSync(<int>[0x00]);

    await tester.pumpWidget(MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        theme: theme.buildAppTheme(),
        home: Scaffold(
            backgroundColor: theme.bg,
            body: Padding(
                padding: const EdgeInsets.all(16),
                child: WorkbenchMessageCard(
                    message: WorkbenchMessage(
                      'user',
                      'You',
                      '查看这张已缓存图片',
                      attachments: <CommittedAttachment>[
                        CommittedAttachment(
                          id: 'att_0',
                          name: 'evicted-viewer.png',
                          kind: AttachmentKind.image,
                          mimeType: 'image/png',
                          sizeBytes: 1,
                          handling: AttachmentHandling.native,
                          localPath: imageFile.path,
                        ),
                      ],
                    ),
                    onApproval: (_) {},
                    onSuggestion: (_) {},
                    expandThinking: false)))));

    expect(find.byKey(const Key('workbench-message-image-preview')),
        findsOneWidget);
    expect(
        find.byKey(const Key('workbench-message-image-viewer')), findsNothing);

    imageFile.deleteSync();
    await tester.tap(find.byKey(const Key('workbench-message-image-preview')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('workbench-message-image-viewer')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  test('conversation pending status text uses active locale', () {
    final event = ConversationEvent.fromJson(const <String, Object?>{
      'seq': 1,
      'conversationId': 'conv_1',
      'type': 'conversation.started',
      'createdAt': '2026-05-03T00:00:00.000Z',
    });

    expect(
        debugConversationPendingStatusText('running',
            locale: const Locale('zh', 'CN'),
            events: <ConversationEvent>[event]),
        'CLI 会话已启动，正在读取上下文...');
    expect(
        debugConversationPendingStatusText('running',
            locale: const Locale('en', 'US'),
            events: <ConversationEvent>[event]),
        'CLI session started. Reading context...');
  });

  test('conversation pending status text surfaces reconnect notices', () {
    final event = ConversationEvent.fromJson(const <String, Object?>{
      'seq': 1,
      'conversationId': 'conv_1',
      'type': 'system.notice',
      'createdAt': '2026-05-09T00:00:00.000Z',
      'text': 'Reconnecting... 1/5 (stream disconnected before completion)'
    });

    expect(
        debugConversationPendingStatusText('running',
            locale: const Locale('en', 'US'),
            events: <ConversationEvent>[event]),
        'Reconnecting... 1/5 (stream disconnected before completion)');
  });

  test('ASR model download dialog strings use active locale', () {
    final zh = lookupAppLocalizations(theme.zhHansCnLocale);
    final en = lookupAppLocalizations(const Locale('en', 'US'));

    expect(zh.asrModelDialogTitle, '语音模型');
    expect(zh.asrModelDownloading('zipformer'), '正在下载 zipformer');
    expect(zh.asrModelPauseAction, '暂停');
    expect(zh.asrModelCancelAction, '取消');
    expect(en.asrModelDialogTitle, 'Voice model');
    expect(en.asrModelDownloading('zipformer'), 'Downloading zipformer');
  });

  test('duplicate approvals collapse and approval response becomes command',
      () {
    final events = <Map<String, Object?>>[
      const <String, Object?>{
        'type': 'approval.required',
        'seq': 1,
        'runId': 'run_1',
        'createdAt': '2026-05-03T00:00:00.000Z',
        'approvalId': 'approval_1',
        'toolName': 'Bash',
        'input': {'command': 'npm test'}
      },
      const <String, Object?>{
        'type': 'approval.required',
        'seq': 2,
        'runId': 'run_1',
        'createdAt': '2026-05-03T00:00:01.000Z',
        'approvalId': 'approval_1',
        'toolName': 'Bash',
        'input': {'command': 'npm test'}
      },
      const <String, Object?>{
        'type': 'approval.responded',
        'seq': 3,
        'runId': 'run_1',
        'createdAt': '2026-05-03T00:00:02.000Z',
        'approvalId': 'approval_1',
        'decision': 'allow',
        'toolName': 'Write',
        'input': {'command': 'Write'}
      },
      const <String, Object?>{
        'type': 'tool.started',
        'seq': 4,
        'runId': 'run_1',
        'createdAt': '2026-05-03T00:00:03.000Z',
        'toolName': 'Write',
        'input': {'command': r'Write C:\Users\W2830\python_intro.py'}
      },
    ];

    expect(debugWorkbenchMessageRolesAfterEvents(events),
        const <String>[r'command:Write C:\Users\W2830\python_intro.py']);
  });

  test('conversation approval resolution becomes a command card', () {
    const capabilities = ConversationCapabilities(
      longLivedProcess: true,
      waitingInput: true,
      waitingApproval: true,
      resume: true,
      partialOutput: true,
    );
    const conversation = ConversationSummary(
      id: 'conv_1',
      workspaceId: 'workspace_1',
      adapter: 'claude',
      status: 'running',
      capabilities: capabilities,
      createdAt: '2026-05-03T00:00:00.000Z',
      updatedAt: '2026-05-03T00:00:02.000Z',
    );
    final events = <Map<String, Object?>>[
      const <String, Object?>{
        'seq': 1,
        'conversationId': 'conv_1',
        'type': 'approval.requested',
        'createdAt': '2026-05-03T00:00:00.000Z',
        'approvalId': 'approval_1',
        'toolName': 'Bash',
        'input': {'command': 'python intro.py'},
        'summary': 'python intro.py'
      },
      const <String, Object?>{
        'seq': 2,
        'conversationId': 'conv_1',
        'type': 'approval.resolved',
        'createdAt': '2026-05-03T00:00:01.000Z',
        'approvalId': 'approval_1',
        'decision': 'allow',
        'toolName': 'Bash',
        'input': {'command': 'python intro.py'},
        'summary': 'python intro.py'
      },
    ];

    expect(
        debugWorkbenchMessageRolesForConversationEvents(events, conversation),
        const <String>['command:python intro.py']);
  });

  test('conversation approval preserves command metadata from blocking item',
      () {
    const capabilities = ConversationCapabilities(
      longLivedProcess: true,
      waitingInput: true,
      waitingApproval: true,
      resume: true,
      partialOutput: true,
    );
    const conversation = ConversationSummary(
      id: 'conv_1',
      workspaceId: 'workspace_1',
      adapter: 'claude',
      status: 'running',
      capabilities: capabilities,
      createdAt: '2026-05-03T00:00:00.000Z',
      updatedAt: '2026-05-03T00:00:02.000Z',
    );
    final events = <Map<String, Object?>>[
      const <String, Object?>{
        'seq': 1,
        'conversationId': 'conv_1',
        'type': 'approval.requested',
        'createdAt': '2026-05-03T00:00:00.000Z',
        'approvalId': 'approval_1',
        'toolUseId': 'toolu_1',
        'toolName': 'Write',
        'input': {
          'file_path': r'D:\AiProject\vibe-coding\python_concurrency_learn.py'
        },
        'summary': r'D:\AiProject\vibe-coding\python_concurrency_learn.py'
      },
      const <String, Object?>{
        'seq': 2,
        'conversationId': 'conv_1',
        'type': 'approval.resolved',
        'createdAt': '2026-05-03T00:00:01.000Z',
        'approvalId': 'approval_1',
        'toolUseId': 'toolu_1',
        'decision': 'allow',
        'toolName': 'Write',
        'input': {
          'file_path': r'D:\AiProject\vibe-coding\python_concurrency_learn.py'
        },
        'summary': r'D:\AiProject\vibe-coding\python_concurrency_learn.py'
      },
    ];

    expect(
        debugWorkbenchMessageRolesForConversationEvents(events, conversation),
        const <String>[
          r'command:D:\AiProject\vibe-coding\python_concurrency_learn.py'
        ]);
  });

  testWidgets('conversation command card shows output and duration',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildConversationCommandCardPreview());
    await tester.pumpAndSettle();

    expect(find.text('python intro.py'), findsWidgets);
    expect(find.textContaining('执行 1 条命令'), findsOneWidget);
    expect(find.text('hello from intro'), findsOneWidget);
    expect(find.textContaining('2.0s'), findsOneWidget);
    expect(find.byKey(const ValueKey('tool-status-ok')), findsOneWidget);
  });

  testWidgets('task progress card shows badge and item statuses',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildTaskProgressCardPreview());
    await tester.pumpAndSettle();

    expect(find.text('任务进度'), findsOneWidget);
    expect(find.text('1 / 3 完成'), findsOneWidget);
    expect(find.text('分析工作区结构'), findsOneWidget);
    expect(find.text('实现进度卡片'), findsOneWidget);
    expect(find.text('运行回归测试'), findsOneWidget);
    expect(find.text('完成'), findsWidgets);
    expect(find.text('正在执行'), findsWidgets);
    expect(find.text('等待执行'), findsWidgets);
  });

  test('empty completed conversation shows diagnostic warning', () {
    const capabilities = ConversationCapabilities(
      longLivedProcess: true,
      waitingInput: true,
      waitingApproval: true,
      resume: true,
      partialOutput: true,
    );
    const conversation = ConversationSummary(
      id: 'conv_empty',
      workspaceId: 'workspace_1',
      adapter: 'claude',
      status: 'idle',
      capabilities: capabilities,
      createdAt: '2026-05-03T00:00:00.000Z',
      updatedAt: '2026-05-03T00:00:02.000Z',
    );
    final diagnostic = debugEmptyConversationCompletionDiagnostic(
      const <Map<String, Object?>>[
        <String, Object?>{
          'seq': 1,
          'conversationId': 'conv_empty',
          'type': 'conversation.started',
          'createdAt': '2026-05-03T00:00:00.000Z'
        },
        <String, Object?>{
          'seq': 2,
          'conversationId': 'conv_empty',
          'type': 'protocol.warning',
          'createdAt': '2026-05-03T00:00:01.000Z',
          'text': 'Claude exited before returning content'
        },
        <String, Object?>{
          'seq': 3,
          'conversationId': 'conv_empty',
          'type': 'conversation.completed',
          'createdAt': '2026-05-03T00:00:02.000Z'
        },
      ],
      conversation,
    );

    expect(diagnostic, contains('CLI returned no content'));
    expect(diagnostic, contains('Claude exited before returning content'));
  });

  test('cancelled run does not render a visible status card', () {
    final body = debugVisibleWorkbenchBodyFromEvent(const <String, Object?>{
      'type': 'run.cancelled',
      'seq': 9,
      'runId': 'run_1',
      'createdAt': '2026-05-03T00:00:04.000Z',
      'reason': 'user_cancelled'
    });

    expect(body, isNull);
  });

  test('AskUserQuestion command card shows the actual question', () {
    final body = debugVisibleWorkbenchBodyFromEvent(const <String, Object?>{
      'type': 'tool.started',
      'seq': 10,
      'runId': 'run_ask',
      'createdAt': '2026-05-03T00:00:05.000Z',
      'toolName': 'AskUserQuestion',
      'input': {'question': 'Which script direction do you want?'}
    });

    expect(body, 'Which script direction do you want?');
    expect(body, isNot('AskUserQuestion'));
  });

  test('AskUserQuestion approval card shows the actual question', () {
    final body = debugVisibleWorkbenchBodyFromEvent(const <String, Object?>{
      'type': 'approval.required',
      'seq': 11,
      'runId': 'run_ask',
      'createdAt': '2026-05-03T00:00:06.000Z',
      'approvalId': 'approval_ask',
      'toolName': 'AskUserQuestion',
      'input': {
        'question': 'Which advanced features should the script include?'
      }
    });

    expect(
        body, contains('Which advanced features should the script include?'));
    expect(body, isNot('AskUserQuestion'));
  });

  test('AskUserQuestion approval reads nested control request input', () {
    final body = debugVisibleWorkbenchBodyFromEvent(const <String, Object?>{
      'type': 'approval.required',
      'seq': 12,
      'runId': 'run_ask',
      'createdAt': '2026-05-03T00:00:07.000Z',
      'approvalId': 'approval_nested',
      'toolName': 'AskUserQuestion',
      'raw': {
        'request': {
          'subtype': 'can_use_tool',
          'tool_name': 'AskUserQuestion',
          'input': {'question': 'Files, network, or concurrency?'}
        }
      }
    });

    expect(body, contains('Files, network, or concurrency?'));
  });

  test(
      'AskUserQuestion approval without input does not infer from assistant text',
      () {
    final events = <Map<String, Object?>>[
      const <String, Object?>{
        'type': 'assistant.delta',
        'seq': 1,
        'runId': 'run_ask',
        'createdAt': '2026-05-03T00:00:05.000Z',
        'raw': {'type': 'result', 'result': 'What should this script do?'}
      },
      const <String, Object?>{
        'type': 'approval.required',
        'seq': 2,
        'runId': 'run_ask',
        'createdAt': '2026-05-03T00:00:06.000Z',
        'approvalId': 'approval_ask',
        'toolName': 'AskUserQuestion'
      },
    ];

    expect(debugWorkbenchMessageRolesAfterEvents(events).first,
        'assistant:What should this script do?');
    expect(debugWorkbenchMessageRolesAfterEvents(events).last,
        contains('AskUserQuestion'));
  });

  test('assistant question event shows suggestions without approval', () {
    final events = <Map<String, Object?>>[
      const <String, Object?>{
        'type': 'assistant.question',
        'seq': 1,
        'runId': 'run_ask',
        'createdAt': '2026-05-03T00:00:05.000Z',
        'text': 'Which direction should this Python script take?',
        'suggestions': ['automation', 'async', 'logs']
      },
    ];

    expect(debugWorkbenchMessageRolesAfterEvents(events), const <String>[
      'question:Which direction should this Python script take?'
    ]);
    expect(debugVisibleWorkbenchBodyFromEvent(events.first),
        'Which direction should this Python script take?');
  });

  test('final assistant result replaces partial same-run response', () {
    final events = <Map<String, Object?>>[
      const <String, Object?>{
        'type': 'assistant.delta',
        'seq': 1,
        'runId': 'run_1',
        'createdAt': '2026-05-03T00:00:05.000Z',
        'raw': {
          'type': 'assistant',
          'message': {
            'role': 'assistant',
            'content': [
              {'type': 'text', 'text': 'I need more detail.'}
            ]
          }
        }
      },
      const <String, Object?>{
        'type': 'assistant.delta',
        'seq': 2,
        'runId': 'run_1',
        'createdAt': '2026-05-03T00:00:06.000Z',
        'raw': {
          'type': 'result',
          'result':
              'Advanced script is broad. What should it do?\n\n1. automation\n2. async\n3. logs'
        }
      },
    ];

    expect(debugWorkbenchMessageRolesAfterEvents(events), const <String>[
      'assistant:Advanced script is broad. What should it do?\n\n1. automation\n2. async\n3. logs'
    ]);
  });

  test('final assistant result removes temporary question card', () {
    final events = <Map<String, Object?>>[
      const <String, Object?>{
        'type': 'assistant.question',
        'seq': 1,
        'runId': 'run_1',
        'createdAt': '2026-05-03T00:00:05.000Z',
        'text': 'Need more info.',
        'suggestions': ['automation', 'async']
      },
      const <String, Object?>{
        'type': 'assistant.delta',
        'seq': 2,
        'runId': 'run_1',
        'createdAt': '2026-05-03T00:00:06.000Z',
        'raw': {
          'type': 'result',
          'result':
              'Advanced Python script can mean many things. Pick a direction:\n\n- web scraping\n- CLI tool\n- data processing\n- automation\n- API service\n- AI integration'
        }
      },
    ];

    expect(debugWorkbenchMessageRolesAfterEvents(events), const <String>[
      'assistant:Advanced Python script can mean many things. Pick a direction:\n\n- web scraping\n- CLI tool\n- data processing\n- automation\n- API service\n- AI integration'
    ]);
  });

  test('filters escaped Claude protocol payloads from assistant bubbles', () {
    final body = debugVisibleWorkbenchBodyFromEvent(const <String, Object?>{
      'type': 'assistant.delta',
      'seq': 12,
      'runId': 'run_1',
      'createdAt': '2026-05-02T00:00:00.000Z',
      'raw': {
        'type': 'assistant',
        'message': {
          'role': 'assistant',
          'content': [
            {
              'type': 'text',
              'text':
                  '\\n"Fix this bug" -> debugging first, then domain-specific skills.\\n\\n## Skill Types\\n\\nRigid (TDD, debugging): Follow exactly.'
            }
          ]
        },
        'parent_tool_use_id': null,
        'session_id': 'leaked-session'
      }
    });

    expect(body, isNull);
  });
}
