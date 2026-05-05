import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';

import '../models/protocol.dart';
import '../services/daemon_client.dart';
import '../state/conversation_reducer.dart';
import '../shell/shell.dart';
import '../theme/theme.dart';
import '../features/adapters/adapters.dart';
import '../features/diagnostics/diagnostics.dart';
import '../features/notifications/notifications.dart';
import '../features/run_detail/run_detail.dart';
import '../features/sessions/sessions.dart';
import '../features/settings/settings.dart';
import '../features/workspace_picker/workspace_picker.dart';
import '../widgets/widgets.dart';

part '../testing/debug_helpers.dart';
part '../shell/mobile_shell.dart';
part '../features/workbench/coding_workbench_page.dart';
part '../features/workbench/coding_composer.dart';
part '../features/workbench/workbench_messages.dart';
part '../features/workbench/workbench_event_cards.dart';
part '../features/workbench/approval_page.dart';
part '../widgets/shared_widgets.dart';

const _bg = bg;
const _stroke = stroke;
const _purple = purple;
const _purple2 = purple2;
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
