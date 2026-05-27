import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/app/language_controller.dart';
import 'package:lan_ai_cli_control/src/app/language_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('LanguageMode parses persisted values and falls back to system', () {
    expect(LanguageModePreference.fromStorageValue('system'),
        LanguageModePreference.system);
    expect(LanguageModePreference.fromStorageValue('zh-Hans-CN'),
        LanguageModePreference.zhHansCn);
    expect(LanguageModePreference.fromStorageValue('en-US'),
        LanguageModePreference.enUs);
    expect(LanguageModePreference.fromStorageValue('ja-JP'),
        LanguageModePreference.system);
  });

  test('resolveSupportedLocale handles exact, Chinese, and fallback locales',
      () {
    expect(
        resolveSupportedLocale(
            const Locale('en', 'US'), AppLanguage.supportedLocales),
        const Locale('en', 'US'));
    expect(
        resolveSupportedLocale(
            const Locale.fromSubtags(languageCode: 'zh', countryCode: 'TW'),
            AppLanguage.supportedLocales),
        AppLanguage.zhHansCnLocale);
    expect(
        resolveSupportedLocale(
            const Locale('ja', 'JP'), AppLanguage.supportedLocales),
        const Locale('en', 'US'));
  });

  test('LanguageController loads and persists selected mode', () async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final controller = LanguageController();

    await controller.load();

    expect(controller.mode, LanguageModePreference.enUs);
    expect(controller.locale, const Locale('en', 'US'));

    await controller.setMode(LanguageModePreference.zhHansCn);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(AppLanguage.storageKey), 'zh-Hans-CN');
    expect(controller.locale, AppLanguage.zhHansCnLocale);
  });

  test('LanguageController suppresses pending load after dispose', () async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{AppLanguage.storageKey: 'en-US'});
    final controller = LanguageController();
    var notified = false;
    controller.addListener(() {
      notified = true;
    });

    final loading = controller.load();
    controller.dispose();

    await loading;

    expect(notified, isFalse);
    expect(controller.loaded, isFalse);
  });
}
