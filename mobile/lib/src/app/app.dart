import 'package:flutter/material.dart';

import '../shell/shell.dart';
import '../theme/theme.dart';

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
