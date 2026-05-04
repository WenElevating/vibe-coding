import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

const appZhHansCnLocale = Locale.fromSubtags(
    languageCode: 'zh', scriptCode: 'Hans', countryCode: 'CN');

const appSupportedLocales = <Locale>[
  appZhHansCnLocale,
  Locale('en', 'US'),
];

const appLocalizationsDelegates = <LocalizationsDelegate<Object>>[
  GlobalMaterialLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];
