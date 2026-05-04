import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';

import '../models/protocol.dart';
import '../services/daemon_client.dart';
import '../state/conversation_reducer.dart';

part '../testing/debug_helpers.dart';
part '../shell/mobile_shell.dart';
part '../features/workbench/coding_workbench_page.dart';
part '../features/sessions/coding_session_list_page.dart';
part '../features/workspace_picker/workspace_picker_sheet.dart';
part '../features/workbench/coding_composer.dart';
part '../features/workbench/workbench_messages.dart';
part '../features/workbench/workbench_event_cards.dart';
part '../features/workbench/approval_page.dart';
part '../features/settings/settings_page.dart';
part '../widgets/shared_widgets.dart';
part '../features/run_detail/run_detail_page.dart';
part '../features/adapters/adapters_page.dart';
part '../features/notifications/notifications_page.dart';
part '../features/diagnostics/diagnostics_page.dart';

const _bg = Color(0xFF0A0B0D);
const _panel = Color(0xE6111214);
const _panelHi = Color(0xF2161719);
const _stroke = Color(0x16FFFFFF);
const _purple = Color(0xFFA78BFA);
const _purple2 = Color(0xFF8AB4FF);
const _active = Color(0xFFE3E6EA);
const _activePanel = Color(0xFF1B2027);
const _activeStroke = Color(0xFF44505C);
const _green = Color(0xFF32D583);
const _amber = Color(0xFFF2C572);
const _red = Color(0xFFFF6B6B);
const _orange = Color(0xFFF2C572);
const _text = Color(0xFFEDEDED);
const _muted = Color(0xFFA9ADB5);
const _faint = Color(0xFF747982);
const _zhHansCnLocale = Locale.fromSubtags(
    languageCode: 'zh', scriptCode: 'Hans', countryCode: 'CN');
const _appFontFallback = <String>[
  'PingFang SC',
  'Microsoft YaHei UI',
  'Noto Sans CJK SC',
  'Noto Sans SC',
  'sans-serif',
];
const _appTextStyle = TextStyle(
    fontFamily: 'Segoe UI',
    fontFamilyFallback: _appFontFallback,
    locale: _zhHansCnLocale);
const _appLocalizationsDelegates = <LocalizationsDelegate<Object>>[
  GlobalMaterialLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];

class LanAiCliControlApp extends StatelessWidget {
  const LanAiCliControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AI CLI 控制台',
      locale: _zhHansCnLocale,
      supportedLocales: const [_zhHansCnLocale, Locale('en', 'US')],
      localizationsDelegates: _appLocalizationsDelegates,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _bg,
        fontFamily: 'Segoe UI',
        fontFamilyFallback: _appFontFallback,
        colorScheme: const ColorScheme.dark(
            primary: _purple, surface: _panel, onSurface: _text),
        textTheme: const TextTheme(
            bodyMedium: _appTextStyle,
            bodyLarge: _appTextStyle,
            bodySmall: _appTextStyle),
        useMaterial3: true,
      ),
      home: const MobileShell(),
    );
  }
}
