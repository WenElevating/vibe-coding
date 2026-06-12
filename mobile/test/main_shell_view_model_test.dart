import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/shell/app_route.dart';
import 'package:lan_ai_cli_control/src/ui/main/main_shell_view_model.dart';

void main() {
  test('defaults to coding as the root tab', () {
    final viewModel = MainShellViewModel();
    addTearDown(viewModel.dispose);

    expect(MainShellViewModel.tabCount, 2);
    expect(MainShellViewModel.settingsTabIndex, 1);
    expect(viewModel.activeTab, MainShellViewModel.codingTabIndex);
    expect(viewModel.openSessionListRequest, 0);
  });

  test('selectTab changes only shell state', () {
    final viewModel = MainShellViewModel();
    addTearDown(viewModel.dispose);

    viewModel.selectTab(MainShellViewModel.settingsTabIndex);

    expect(viewModel.activeTab, MainShellViewModel.settingsTabIndex);
    expect(viewModel.activeRoutePage, RoutePage.tabs);
    expect(viewModel.openSessionListRequest, 0);

    viewModel.selectTab(MainShellViewModel.codingTabIndex);

    expect(viewModel.activeTab, MainShellViewModel.codingTabIndex);
    expect(viewModel.openSessionListRequest, 1);
  });

  test('selectTab clamps removed or invalid tab indexes', () {
    final viewModel = MainShellViewModel();
    addTearDown(viewModel.dispose);

    viewModel.selectTab(99);

    expect(viewModel.activeTab, MainShellViewModel.settingsTabIndex);
  });

  test('overlay is independent from business data', () {
    final viewModel = MainShellViewModel();

    viewModel.openOverlay(RoutePage.approval);
    expect(viewModel.isOverlayActive, isTrue);
    expect(viewModel.activeRoutePage, RoutePage.approval);

    viewModel.closeOverlay();
    expect(viewModel.isOverlayActive, isFalse);
  });

  test('route payload is cleared when returning to tabs', () {
    final viewModel = MainShellViewModel();
    addTearDown(viewModel.dispose);

    viewModel.openRoute(const AppRoute.detail(runId: 'run_2'));

    expect(viewModel.isOverlayActive, isTrue);
    expect(viewModel.activeRoute, const AppRoute.detail(runId: 'run_2'));

    viewModel.selectTab(MainShellViewModel.settingsTabIndex);

    expect(viewModel.activeRoute, const AppRoute.tabs());
    expect(viewModel.activeRoute.runId, isNull);
  });

  test('defaults new coding sessions to default permission mode', () {
    final viewModel = MainShellViewModel();
    addTearDown(viewModel.dispose);

    expect(viewModel.permissionMode, 'default');
  });

  test('stream output and expand thinking toggle', () {
    final viewModel = MainShellViewModel();
    addTearDown(viewModel.dispose);

    expect(viewModel.expandToolDetails, isFalse);

    viewModel.setStreamOutput(true);
    expect(viewModel.streamOutput, isTrue);

    viewModel.setExpandThinking(true);
    expect(viewModel.expandThinking, isTrue);

    viewModel.setExpandToolDetails(true);
    expect(viewModel.expandToolDetails, isTrue);

    viewModel.setStreamOutput(true);
    expect(viewModel.streamOutput, isTrue);
  });

  test('reportSessionListOpen tracks open state', () {
    final viewModel = MainShellViewModel();
    addTearDown(viewModel.dispose);

    expect(viewModel.codingSessionListOpen, isTrue);

    viewModel.reportSessionListOpen(false);
    expect(viewModel.codingSessionListOpen, isFalse);

    viewModel.reportSessionListOpen(false);
    expect(viewModel.codingSessionListOpen, isFalse);
  });
}
