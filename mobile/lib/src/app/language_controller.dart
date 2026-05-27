import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'language_mode.dart';

class LanguageController extends ChangeNotifier {
  LanguageModePreference _mode = LanguageModePreference.system;
  bool _loaded = false;
  bool _disposed = false;

  LanguageModePreference get mode => _mode;
  bool get loaded => _loaded;

  Locale? get locale => switch (_mode) {
        LanguageModePreference.system => null,
        LanguageModePreference.zhHansCn => AppLanguage.zhHansCnLocale,
        LanguageModePreference.enUs => const Locale('en', 'US'),
      };

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    if (_disposed) return;
    _mode = LanguageModePreference.fromStorageValue(
        prefs.getString(AppLanguage.storageKey));
    _loaded = true;
    notifyListeners();
  }

  Future<void> setMode(LanguageModePreference mode) async {
    if (_disposed) return;
    if (_mode == mode && _loaded) return;
    _mode = mode;
    _loaded = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppLanguage.storageKey, mode.storageValue);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
