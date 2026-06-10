import 'package:flutter/foundation.dart';

import '../../shell/app_route.dart';

class MainShellViewModel extends ChangeNotifier {
  static const int codingTabIndex = 0;
  static const int codexTabIndex = 1;
  static const int settingsTabIndex = 2;
  static const int tabCount = 3;

  int _activeTab = 0;
  bool _streamOutput = false;
  bool _expandThinking = false;
  bool _expandToolDetails = false;
  String _permissionMode = 'default';
  bool _codingSessionListOpen = true;
  int _openSessionListRequest = 0;
  AppRoute _activeRoute = const AppRoute.tabs();

  int get activeTab => _activeTab;
  bool get streamOutput => _streamOutput;
  bool get expandThinking => _expandThinking;
  bool get expandToolDetails => _expandToolDetails;
  String get permissionMode => _permissionMode;
  bool get codingSessionListOpen => _codingSessionListOpen;
  int get openSessionListRequest => _openSessionListRequest;
  AppRoute get activeRoute => _activeRoute;
  RoutePage get activeRoutePage => _activeRoute.page;
  bool get isOverlayActive => _activeRoute.page != RoutePage.tabs;

  void openOverlay(RoutePage route) {
    openRoute(AppRoute(route));
  }

  void openRoute(AppRoute route) {
    _activeRoute = route;
    notifyListeners();
  }

  void closeOverlay() {
    _activeRoute = const AppRoute.tabs();
    notifyListeners();
  }

  void selectTab(int index) {
    _activeTab = index.clamp(0, tabCount - 1);
    _activeRoute = const AppRoute.tabs();
    if (_activeTab == codingTabIndex) {
      _codingSessionListOpen = true;
      _openSessionListRequest++;
    }
    notifyListeners();
  }

  void setStreamOutput(bool value) {
    if (_streamOutput == value) return;
    _streamOutput = value;
    notifyListeners();
  }

  void setExpandThinking(bool value) {
    if (_expandThinking == value) return;
    _expandThinking = value;
    notifyListeners();
  }

  void setExpandToolDetails(bool value) {
    if (_expandToolDetails == value) return;
    _expandToolDetails = value;
    notifyListeners();
  }

  void setPermissionMode(String value) {
    if (_permissionMode == value) return;
    _permissionMode = value;
    notifyListeners();
  }

  void reportSessionListOpen(bool open) {
    if (_codingSessionListOpen == open) return;
    _codingSessionListOpen = open;
    notifyListeners();
  }
}
