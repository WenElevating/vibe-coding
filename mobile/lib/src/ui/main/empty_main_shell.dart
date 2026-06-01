import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../domain/models/daemon_connection_config.dart';
import '../../models/protocol.dart';
import '../core/theme/theme.dart' as theme;
import '../core/widgets/widgets.dart';
import '../features/settings/settings.dart' show AppUpdateViewModel;
import '../features/workspace_picker/workspace_picker_sheet.dart';
import '../main_tab_items.dart';
import '../mobile_ui_frame.dart';
import 'empty_home_page.dart';
import 'empty_settings_page.dart';

class EmptyMainShell extends StatelessWidget {
  const EmptyMainShell({
    super.key,
    required this.activeTab,
    required this.workspaces,
    required this.health,
    required this.connectionConfig,
    required this.creatingWorkspace,
    required this.loadingWorkspace,
    required this.error,
    required this.appUpdateViewModel,
    required this.onCreateWorkspace,
    required this.onOpenWorkspace,
    required this.onTabSelected,
    required this.onSystemBack,
  });

  final int activeTab;
  final List<WorkspaceSummary> workspaces;
  final DaemonHealth? health;
  final DaemonConnectionConfig connectionConfig;
  final bool creatingWorkspace;
  final bool loadingWorkspace;
  final Object? error;
  final AppUpdateViewModel? appUpdateViewModel;
  final VoidCallback onCreateWorkspace;
  final ValueChanged<WorkspaceSummary> onOpenWorkspace;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onSystemBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pages = [
      EmptyHomePage(onCreateWorkspace: onCreateWorkspace),
      WorkspaceListPage(
        workspaces: workspaces,
        onSelected: onOpenWorkspace,
        onAddWorkspace: onCreateWorkspace,
      ),
      EmptySettingsPage(
        health: health,
        connectionConfig: connectionConfig,
        appUpdateViewModel: appUpdateViewModel,
      ),
    ];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) onSystemBack();
      },
      child: Scaffold(
        body: MobileUiFrame(
          child: Stack(children: [
            IndexedStack(index: activeTab, children: pages),
            if (creatingWorkspace || loadingWorkspace)
              const _EmptyShellLoadingOverlay(),
            if (error != null) _EmptyShellErrorBanner(error: error!),
          ]),
        ),
        bottomNavigationBar: BottomNav(
          selected: activeTab,
          items: mainTabItems(l10n),
          onTap: onTabSelected,
        ),
        extendBody: true,
      ),
    );
  }
}

class _EmptyShellLoadingOverlay extends StatelessWidget {
  const _EmptyShellLoadingOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: .24),
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF111820),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: .1)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text(
              'Loading workspace...',
              style: TextStyle(color: theme.text, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyShellErrorBanner extends StatelessWidget {
  const _EmptyShellErrorBanner({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 20 + MediaQuery.paddingOf(context).bottom,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.red.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.red.withValues(alpha: .24)),
        ),
        child: Row(children: [
          const Icon(Icons.error_outline_rounded, color: theme.red, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$error',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: theme.red, fontSize: 11.5),
            ),
          ),
        ]),
      ),
    );
  }
}
