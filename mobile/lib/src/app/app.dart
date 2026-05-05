import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../theme/theme.dart';
import '../ui/ui.dart';
import 'language_controller.dart';
import 'language_mode.dart';
import 'language_scope.dart';

class LanAiCliControlApp extends StatefulWidget {
  const LanAiCliControlApp({super.key});

  @override
  State<LanAiCliControlApp> createState() => _LanAiCliControlAppState();
}

class _LanAiCliControlAppState extends State<LanAiCliControlApp> {
  late final LanguageController _languageController;

  @override
  void initState() {
    super.initState();
    _languageController = LanguageController()..load();
  }

  @override
  void dispose() {
    _languageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _languageController,
      builder: (context, _) {
        final locale = _languageController.locale;
        final titleLocale = locale ?? const Locale('en');
        return LanguageScope(
            controller: _languageController,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              title: lookupAppLocalizations(titleLocale).appTitle,
              locale: locale,
              supportedLocales: appSupportedLocales,
              localizationsDelegates: appLocalizationsDelegates,
              localeResolutionCallback: (locale, supportedLocales) =>
                  resolveSupportedLocale(locale, supportedLocales),
              theme: buildAppTheme(),
              home: const MobileUi(),
            ));
      });
}
