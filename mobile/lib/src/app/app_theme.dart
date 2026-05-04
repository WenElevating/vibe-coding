import 'package:flutter/material.dart';

import 'app_localization.dart';

const appBg = Color(0xFF0A0B0D);
const appPanel = Color(0xE6111214);
const appPanelHi = Color(0xF2161719);
const appStroke = Color(0x16FFFFFF);
const appPurple = Color(0xFFA78BFA);
const appPurple2 = Color(0xFF8AB4FF);
const appActive = Color(0xFFE3E6EA);
const appActivePanel = Color(0xFF1B2027);
const appActiveStroke = Color(0xFF44505C);
const appGreen = Color(0xFF32D583);
const appAmber = Color(0xFFF2C572);
const appRed = Color(0xFFFF6B6B);
const appOrange = Color(0xFFF2C572);
const appText = Color(0xFFEDEDED);
const appMuted = Color(0xFFA9ADB5);
const appFaint = Color(0xFF747982);

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
    locale: appZhHansCnLocale);

ThemeData buildAppTheme() => ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: appBg,
      fontFamily: 'Segoe UI',
      fontFamilyFallback: appFontFallback,
      colorScheme: const ColorScheme.dark(
          primary: appPurple, surface: appPanel, onSurface: appText),
      textTheme: const TextTheme(
          bodyMedium: appTextStyle,
          bodyLarge: appTextStyle,
          bodySmall: appTextStyle),
      useMaterial3: true,
    );
