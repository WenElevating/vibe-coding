import 'package:flutter/material.dart';

const zhHansCnLocale = Locale.fromSubtags(
    languageCode: 'zh', scriptCode: 'Hans', countryCode: 'CN');

const appFontFallback = <String>[
  'PingFang SC',
  'Microsoft YaHei UI',
  'Noto Sans CJK SC',
  'Noto Sans SC',
  'sans-serif',
];

const appTextStyle = TextStyle(
    fontFamily: 'Segoe UI',
    fontFamilyFallback: appFontFallback,
    locale: zhHansCnLocale);
