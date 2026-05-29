import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/shell/app_route.dart';
import 'package:lan_ai_cli_control/src/ui/view_models/main_tabs_shell_view_model.dart';

void main() {
  test('selectTab changes only shell state', () {
    final viewModel = MainTabsShellViewModel();

    viewModel.selectTab(1);

    expect(viewModel.activeTab, 1);
    expect(viewModel.activeRoute, RoutePage.tabs);
    expect(viewModel.openSessionListRequest, 1);
  });

  test('overlay is independent from business data', () {
    final viewModel = MainTabsShellViewModel();

    viewModel.openOverlay(RoutePage.approval);
    expect(viewModel.isOverlayActive, isTrue);

    viewModel.closeOverlay();
    expect(viewModel.isOverlayActive, isFalse);
  });

  test('defaults new coding sessions to auto permission mode', () {
    final viewModel = MainTabsShellViewModel();
    addTearDown(viewModel.dispose);

    expect(viewModel.permissionMode, 'auto');
  });

  test('stream output and expand thinking toggle', () {
    final viewModel = MainTabsShellViewModel();
    addTearDown(viewModel.dispose);

    viewModel.setStreamOutput(true);
    expect(viewModel.streamOutput, isTrue);

    viewModel.setExpandThinking(true);
    expect(viewModel.expandThinking, isTrue);

    viewModel.setStreamOutput(true);
    expect(viewModel.streamOutput, isTrue);
  });

  test('reportSessionListOpen tracks open state', () {
    final viewModel = MainTabsShellViewModel();
    addTearDown(viewModel.dispose);

    expect(viewModel.codingSessionListOpen, isTrue);

    viewModel.reportSessionListOpen(false);
    expect(viewModel.codingSessionListOpen, isFalse);

    viewModel.reportSessionListOpen(false);
    expect(viewModel.codingSessionListOpen, isFalse);
  });
}
