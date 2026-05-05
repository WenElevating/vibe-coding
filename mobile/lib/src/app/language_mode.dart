import 'package:flutter/material.dart';

enum LanguageModePreference {
  system('system'),
  zhHansCn('zh-Hans-CN'),
  enUs('en-US');

  const LanguageModePreference(this.storageValue);

  final String storageValue;

  static LanguageModePreference fromStorageValue(String? value) {
    for (final mode in values) {
      if (mode.storageValue == value) return mode;
    }
    return system;
  }
}

abstract final class AppLanguage {
  static const storageKey = 'app.languageMode';
  static const zhHansCnLocale = Locale.fromSubtags(
      languageCode: 'zh', scriptCode: 'Hans', countryCode: 'CN');
  static const supportedLocales = <Locale>[
    zhHansCnLocale,
    Locale('en', 'US'),
  ];
}

Locale resolveSupportedLocale(
    Locale? locale, Iterable<Locale> supportedLocales) {
  if (locale == null) return const Locale('en', 'US');
  for (final supported in supportedLocales) {
    if (supported.languageCode == locale.languageCode &&
        supported.scriptCode == locale.scriptCode &&
        supported.countryCode == locale.countryCode) {
      return supported;
    }
  }
  if (locale.languageCode == 'zh') return AppLanguage.zhHansCnLocale;
  return const Locale('en', 'US');
}
