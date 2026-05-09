// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'AI CLI 控制台';

  @override
  String get navHome => '首页';

  @override
  String get navRuns => '运行';

  @override
  String get navCoding => '编码';

  @override
  String get navDevices => '设备';

  @override
  String get navSettings => '设置';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsPreferencesSection => '偏好设置';

  @override
  String get settingsLanguageTitle => '语言';

  @override
  String get settingsLanguageSystem => '系统默认';

  @override
  String get settingsLanguageZhHans => '简体中文';

  @override
  String get settingsLanguageEn => 'English';

  @override
  String get settingsLanguagePickerTitle => '选择语言';

  @override
  String get settingsCodingControlSection => '编码控制';

  @override
  String get settingsStreamOutputTitle => '流式输出';

  @override
  String get settingsStreamOutputSubtitle => '关闭时只显示最终回复，避免 delta 与完整消息重复。';

  @override
  String get settingsExpandThinkingTitle => '显示思考过程';

  @override
  String get settingsExpandThinkingSubtitle => '开启后默认展开模型 thinking；关闭时折叠显示。';

  @override
  String get settingsPermissionModeTitle => '权限模式';

  @override
  String get settingsPermissionDefault => '默认';

  @override
  String get settingsPermissionAuto => '自动';

  @override
  String get settingsPermissionSubtitle => '默认会请求 CLI 权限确认；自动模式由 CLI 处理。';

  @override
  String get settingsDataStatusSection => '数据状态';

  @override
  String get settingsDiagnosticsTitle => '代码诊断';

  @override
  String settingsDiagnosticsCount(int count) {
    return '$count 条';
  }

  @override
  String get settingsGitStatusTitle => 'Git 状态';

  @override
  String get settingsGitClean => '干净';

  @override
  String settingsGitFiles(int count) {
    return '$count 个文件';
  }

  @override
  String get settingsAboutSection => '关于';

  @override
  String get settingsExtensionsTitle => '扩展';

  @override
  String settingsExtensionsCount(int count) {
    return '$count 个';
  }

  @override
  String get settingsAdaptersAction => '适配器';

  @override
  String get settingsNotificationsAction => '通知';

  @override
  String get settingsGenerateDiagnosticsAction => '生成诊断信息';

  @override
  String get settingsCurrentConnectionTitle => '当前连接';

  @override
  String get settingsConnected => '已连接';

  @override
  String get settingsWorkspaceLabel => '工作区';

  @override
  String get settingsSecurityModeLabel => '安全模式';

  @override
  String get settingsDaemonAddressLabel => '守护进程地址';

  @override
  String get settingsProxyModeLabel => '代理模式';

  @override
  String get settingsProxyDirect => '直连';

  @override
  String get settingsProxySystem => '系统代理';

  @override
  String get settingsProxyManual => '手动代理';

  @override
  String get connectionTitle => '连接';

  @override
  String get connectionSubtitle => '加载工作区前确认 daemon 目标';

  @override
  String get connectionAddressSection => '连接地址';

  @override
  String get connectionProxySection => '网络代理';

  @override
  String get connectionConnectAction => '连接';

  @override
  String get connectionReconnectAction => '重连';

  @override
  String get connectionStatusLoadingConfig => '正在加载连接设置';

  @override
  String get connectionStatusIdle => '未连接';

  @override
  String get connectionStatusValidating => '正在解析连接地址';

  @override
  String get connectionStatusCheckingHealth => '正在检查 daemon 状态';

  @override
  String get connectionStatusLoadingSnapshot => '正在同步工作区状态';

  @override
  String get connectionStatusConnected => '已连接';

  @override
  String get connectionStatusFailed => '连接失败';

  @override
  String get connectionStatusReady => '就绪';

  @override
  String get connectionStatusError => '错误';

  @override
  String get connectionTargetLabel => '目标';

  @override
  String get connectionProxyLabel => '代理';

  @override
  String get homeOverviewTitle => '概览';

  @override
  String get homeRunningMetricLabel => '运行中';

  @override
  String get homeRunningMetricNote => '活跃任务';

  @override
  String get homeQueuedMetricLabel => '待审批';

  @override
  String get homeQueuedMetricNote => '队列任务';

  @override
  String get homeCompletedMetricLabel => '已完成 (24h)';

  @override
  String homeFilesLinesNote(int files, int lines) {
    return '$files 个文件 · $lines 行';
  }

  @override
  String get homeRecentRunsTitle => '最近运行';

  @override
  String get homeViewAllAction => '查看全部';

  @override
  String get homeNoRuns => '暂无运行记录';

  @override
  String get homeQuickActionsTitle => '快捷操作';

  @override
  String get homeNewTaskTitle => '新建任务';

  @override
  String get homeNewTaskSubtitle => '创建新任务';

  @override
  String get homeCommandTemplatesTitle => '命令模板';

  @override
  String get homeCommandTemplatesSubtitle => '执行预设命令';

  @override
  String get homeViewQueueTitle => '查看队列';

  @override
  String get homeViewQueueSubtitle => '查看排队任务';

  @override
  String get homeNowTitle => '当前焦点';

  @override
  String get homeInterruptsTitle => '需要关注';

  @override
  String get homeExecutionStreamTitle => '执行流';

  @override
  String get homeWorkspaceSignalsTitle => '工作区信号';

  @override
  String get homeIdleNow => '当前工作区无阻塞';

  @override
  String get homeNoRecentActivity => '当前工作区暂无活动';

  @override
  String get homeGitChangedLabel => 'Git 变更';

  @override
  String get homeDiagnosticsLabel => '诊断';

  @override
  String get homeQueueLabel => '队列';

  @override
  String get homeRecentFilesLabel => '最近文件';

  @override
  String homeMoreSignalsLabel(int count) {
    return '+$count 项';
  }

  @override
  String get runsTitle => '运行';

  @override
  String runsAllPill(int count) {
    return '全部 $count';
  }

  @override
  String runsRunningPill(int count) {
    return '运行中 $count';
  }

  @override
  String runsCompletedPill(int count) {
    return '已完成 $count';
  }

  @override
  String runsFailedPill(int count) {
    return '失败 $count';
  }

  @override
  String get runsEmpty => '暂无运行记录。可以从命令模板启动真实 AI CLI 任务。';

  @override
  String get queueTitle => '运行队列';

  @override
  String queueCountAction(int count) {
    return '$count 项';
  }

  @override
  String queueRunningPill(int count) {
    return '运行中 $count';
  }

  @override
  String queueWaitingPill(int count) {
    return '排队中 $count';
  }

  @override
  String queueTotalPill(int count) {
    return '总计 $count';
  }

  @override
  String get queueRunningSection => '运行中';

  @override
  String get queueWaitingSection => '排队中';

  @override
  String get queueNoRunning => '暂无运行中队列项';

  @override
  String get queueNoWaiting => '暂无等待任务';

  @override
  String get queueFootnote => '队列数据来自 daemon。任务会按工作区顺序运行。';

  @override
  String get commonBack => '返回';

  @override
  String get adaptersTitle => '适配器状态';

  @override
  String adaptersCount(int count) {
    return '$count 项';
  }

  @override
  String get adaptersEmpty => 'daemon 未返回适配器';

  @override
  String get adaptersExtensionsSection => '扩展';

  @override
  String get adaptersNoExtensions => '暂无扩展信息';

  @override
  String get adaptersNotInstalled => '未安装';

  @override
  String get adaptersStatusOk => '状态                         正常';

  @override
  String get adaptersCapabilitiesLabel => '状态                         正常';

  @override
  String get diagnosticsTitle => '诊断';

  @override
  String get diagnosticsDescription => '导出已脱敏的诊断包，用于排查问题';

  @override
  String get diagnosticsSystemInfo => '系统信息';

  @override
  String get diagnosticsAdapterStatus => '适配器状态';

  @override
  String get diagnosticsRunLogsRecent => '运行日志（最近 7 天）';

  @override
  String get diagnosticsEventRecordsRecent => '事件记录（最近 7 天）';

  @override
  String get diagnosticsConfigInfo => '配置信息';

  @override
  String get diagnosticsEstimatedSize => '预估大小';

  @override
  String get diagnosticsGenerateAction => '生成诊断包';

  @override
  String get notificationsTitle => '通知';

  @override
  String get notificationsTabAll => '全部';

  @override
  String get notificationsTabUnread => '未读';

  @override
  String get notificationsTabMentions => '提及我';

  @override
  String get notificationsApprovalRequired => '需要审批';

  @override
  String get notificationsRequestModify =>
      'Claude Code 请求修改\nlib/services/auth_service.dart';

  @override
  String get notificationsTaskComplete => '任务完成';

  @override
  String get notificationsRunCompletedDuration =>
      '为用户服务添加单元测试\n运行完成，用时 28m 15s';

  @override
  String get notificationsTaskFailed => '任务失败';

  @override
  String get notificationsDataSyncBody => '优化数据同步逻辑\n运行失败，查看详情';

  @override
  String get notificationsYesterday1422 => '昨天 14:22';

  @override
  String get notificationsQueueUpdate => '队列更新';

  @override
  String get notificationsCacheBody => '优化缓存策略\n已开始运行';

  @override
  String get notificationsYesterday1315 => '昨天 13:15';

  @override
  String get notificationsSystemMessage => '系统消息';

  @override
  String get notificationsConnectedBody => '已连接到 DESKTOP-DEV';

  @override
  String get notificationsYesterday1001 => '昨天 10:01';

  @override
  String get runDetailTitle => '运行详情';

  @override
  String get runDetailMockTask => '修复登录 API 测试失败';

  @override
  String get runDetailRunningStatus => '运行中';

  @override
  String get runDetailStartedDuration => '10:32 开始 · 用时 12m 45s';

  @override
  String get runDetailTabOverview => '概览';

  @override
  String get runDetailTabEvents => '事件';

  @override
  String get runDetailTabFileChanges => '文件变更';

  @override
  String get runDetailTabConfig => '配置';

  @override
  String get runDetailUserPromptTitle => '用户提示';

  @override
  String get runDetailUserPromptBody => '修复登录 API 测试失败，并添加边界条件测试。';

  @override
  String get runDetailThinkingTitle => 'Claude 开始思考';

  @override
  String get runDetailThinkingBody => '正在分析问题和相关代码...';

  @override
  String get runDetailReadFileTitle => '读取文件';

  @override
  String get runDetailSearchCodeTitle => '搜索代码';

  @override
  String get runDetailSearchBody => '搜索：\"login failure test\"\n找到 12 条结果';

  @override
  String get runDetailEditFileTitle => '编辑文件';

  @override
  String get runDetailRunCommandTitle => '运行命令';

  @override
  String get runDetailCommandBody =>
      'dart test tests/login_test.dart      运行中 ·';

  @override
  String get sessionsTitle => '会话';

  @override
  String get sessionsCurrentProject => '当前项目';

  @override
  String get sessionsSearchPlaceholder => '搜索会话、命令或文件路径...';

  @override
  String get sessionsFootnote => '此列表仅显示当前工作区内的会话。';

  @override
  String get sessionsEmptyTitle => '这个工作区还没有会话';

  @override
  String get sessionsNewSession => '新建会话';

  @override
  String get sessionsWaitingApproval => '等待审批';

  @override
  String get sessionsPendingBadge => '待处理';

  @override
  String get sessionsRunning => '运行中';

  @override
  String get sessionsFailed => '失败';

  @override
  String get sessionsDone => '已完成';

  @override
  String get sessionsSessionNoun => '会话';

  @override
  String get sessionsTaskNoun => '任务';

  @override
  String get workspaceAdapterPickerTitle => '选择模型 / CLI';

  @override
  String get workspaceAdapterPickerSubtitle => '会用于下一次真实 daemon run，运行中不可切换。';

  @override
  String get workspaceListTitle => '工作区';

  @override
  String get workspaceAvailableSection => '可用工作区';

  @override
  String get workspaceListFootnote => '选择 CLI 命令的运行文件夹，然后打开或创建其中的会话。';

  @override
  String get workspaceCurrentFallback => '当前工作区';

  @override
  String get workspaceSheetTitle => '工作区';

  @override
  String get workspaceSheetSubtitle => '切换 CLI 执行目录，当前会话会继续保留。';

  @override
  String get workspacePathHint => '输入或浏览文件夹路径';

  @override
  String get workspaceBrowseAction => '浏览';

  @override
  String get workspaceNameHint => '名称（可选）';

  @override
  String get workspaceCreatingAction => '创建中';

  @override
  String get workspaceCreateAction => '创建';

  @override
  String get workspacePathRequiredError => '请先选择或输入文件夹路径。';

  @override
  String get workspaceExistingSection => '已有工作区';

  @override
  String get workspaceSafeDirectoryMeta => '安全执行目录';

  @override
  String get workspaceAddTitle => '添加工作区';

  @override
  String get workspaceChoosePathHint => '选择或输入文件夹路径';

  @override
  String get workspaceCreateAndUseAction => '创建并使用';

  @override
  String get workspaceChooseFolderTitle => '选择文件夹';

  @override
  String get workspaceSelectCurrentAction => '选择当前';

  @override
  String get workspaceBrowserPlaceholder => '选择磁盘或根目录后继续进入文件夹';

  @override
  String get workbenchComposerNoAdapter => '没有可用 CLI adapter';

  @override
  String get workbenchComposerFollowUpHint => '要求后续变更…';

  @override
  String get workbenchApprovalPageTitle => '需要你审批';

  @override
  String get workbenchModifyFileTitle => '修改文件';

  @override
  String get workbenchDiffTab => '差异';

  @override
  String get workbenchFileContentTab => '文件内容';

  @override
  String get workbenchApprovalActionsSection => '审批操作';

  @override
  String get workbenchClaudeSuggestionTitle => 'Claude 建议的变更';

  @override
  String get workbenchMockFixEmptyResponse => '修复空响应导致的测试失败问题';

  @override
  String get workbenchRejectAction => '拒绝';

  @override
  String get workbenchApproveAction => '批准';

  @override
  String get workbenchInlineReady => '准备好接收编码任务';

  @override
  String workbenchInlineCompleted(int count) {
    return '本次 CLI 会话已完成 · $count 个事件已处理';
  }

  @override
  String workbenchInlineConnecting(String adapter, int count) {
    return '正在连接 $adapter · 已处理 $count 个事件';
  }

  @override
  String get workbenchApprovalMissingId => 'daemon 未提供 approvalId，无法在移动端处理。';

  @override
  String get workbenchQuestionTitle => '需要你补充方向';

  @override
  String get workbenchCommandDetailTitle => '命令详情';

  @override
  String get workbenchOutputDetailTitle => '输出详情';

  @override
  String get workbenchCommandMetaEmpty => '执行 1 条命令';

  @override
  String workbenchCommandMetaWithTitle(String title) {
    return '执行 1 条命令 · $title';
  }

  @override
  String get workbenchCopyAllTooltip => '复制全文';

  @override
  String get workbenchCopiedSnack => '已复制到剪贴板';

  @override
  String get workbenchCloseTooltip => '关闭';

  @override
  String get workbenchPendingRunning => '正在运行';

  @override
  String get workbenchPreviewReceivingOutput => '正在接收 CLI 输出...';

  @override
  String get workbenchPreviewStartedSession => '已启动 claude 会话';

  @override
  String get workbenchApprovalCardTitle => '需要审批';

  @override
  String get workbenchRunErrorPrefix => '运行错误：';

  @override
  String get workbenchPendingInterrupted => '会话已中断，发送新消息可恢复上下文';

  @override
  String get workbenchPendingWaitingInput => '正在等待你的回复...';

  @override
  String get workbenchPendingWaitingApproval => '正在等待权限确认...';

  @override
  String get workbenchPendingStarting => '正在启动 CLI 会话...';

  @override
  String get workbenchPendingGenerating => '正在生成回复...';

  @override
  String workbenchPendingRunningTool(String tool) {
    return '正在运行 $tool...';
  }

  @override
  String get workbenchPendingToolFallback => '工具调用';

  @override
  String get workbenchPendingReceivingToolOutput => '正在接收工具输出...';

  @override
  String get workbenchPendingSummarizingDiff => '正在汇总文件变更...';

  @override
  String get workbenchPendingReadingContext => 'CLI 会话已启动，正在读取上下文...';

  @override
  String get workbenchPendingWaitingNextEvent => '正在等待下一个事件...';

  @override
  String get workbenchThinkingProcessTitle => '思考过程';

  @override
  String get workbenchNewSessionTitle => '新的编码会话';

  @override
  String get asrModelDialogTitle => '语音模型';

  @override
  String get asrModelPreparing => '正在准备语音模型...';

  @override
  String get asrModelChecking => '正在检查配对 daemon 模型...';

  @override
  String asrModelDownloading(String version) => '正在下载 $version';

  @override
  String get asrModelFallbackName => '模型';

  @override
  String get asrModelPaused => '下载已暂停';

  @override
  String get asrModelVerifying => '正在校验已下载模型...';

  @override
  String get asrModelExtracting => '正在解压模型文件...';

  @override
  String get asrModelReady => '语音模型已就绪';

  @override
  String get asrModelFailed => '语音模型准备失败';

  @override
  String get asrModelCancelled => '语音模型下载已取消';

  @override
  String get asrModelWaitingSize => '正在等待文件大小';

  @override
  String asrModelTraceId(String traceId) => '追踪 ID：$traceId';

  @override
  String get asrModelCopyAction => '复制';

  @override
  String get asrModelPauseAction => '暂停';

  @override
  String get asrModelResumeAction => '继续';

  @override
  String get asrModelRetryAction => '重试';

  @override
  String get asrModelCancelAction => '取消';
}
