import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';

import '../models/protocol.dart';
import '../services/daemon_client.dart';
import '../state/conversation_reducer.dart';
import '../theme/theme.dart';

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

const _bg = bg;
const _panel = panel;
const _panelHi = panelHi;
const _stroke = stroke;
const _purple = purple;
const _purple2 = purple2;
const _active = active;
const _activePanel = activePanel;
const _activeStroke = activeStroke;
const _green = green;
const _amber = amber;
const _red = red;
const _orange = orange;
const _text = text;
const _muted = muted;
const _faint = faint;
const _zhHansCnLocale = zhHansCnLocale;
const _appFontFallback = appFontFallback;
const _appTextStyle = appTextStyle;
const _appLocalizationsDelegates = appLocalizationsDelegates;

class LanAiCliControlApp extends StatelessWidget {
  const LanAiCliControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AI CLI 控制台',
      locale: zhHansCnLocale,
      supportedLocales: const [zhHansCnLocale, Locale('en', 'US')],
      localizationsDelegates: appLocalizationsDelegates,
      theme: buildAppTheme(),
      home: const MobileShell(),
    );
  }
}
