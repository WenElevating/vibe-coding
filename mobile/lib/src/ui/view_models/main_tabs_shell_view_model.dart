import 'package:flutter/foundation.dart';

import '../../shell/app_route.dart';

class MainTabsShellViewModel extends ChangeNotifier {
  int _activeTab = 0;
  bool _streamOutput = false;
  bool _expandThinking = false;
  String _permissionMode = 'auto';
  bool _codingSessionListOpen = true;
  int _openSessionListRequest = 0;
  RoutePage _activeRoute = RoutePage.tabs;

  int get activeTab => _activeTab;
  bool get streamOutput => _streamOutput;
  bool get expandThinking => _expandThinking;
  String get permissionMode => _permissionMode;
  bool get codingSessionListOpen => _codingSessionListOpen;
  int get openSessionListRequest => _openSessionListRequest;
  RoutePage get activeRoute => _activeRoute;
  bool get isOverlayActive => _activeRoute != RoutePage.tabs;

  void openOverlay(RoutePage route) {
    _activeRoute = route;
    notifyListeners();
  }

  void closeOverlay() {
    _activeRoute = RoutePage.tabs;
    notifyListeners();
  }

  void selectTab(int index) {
    _activeTab = index;
    _activeRoute = RoutePage.tabs;
    if (index == 1) {
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
