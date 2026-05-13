import 'package:flutter/material.dart';

import 'app_colors.dart' as colors;
import 'app_typography.dart';

ThemeData buildAppTheme() => ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: colors.bg,
      fontFamily: 'Segoe UI',
      fontFamilyFallback: appFontFallback,
      colorScheme: const ColorScheme.dark(
          primary: colors.purple,
          surface: colors.panel,
          onSurface: colors.text),
      textTheme: const TextTheme(
          bodyMedium: appTextStyle,
          bodyLarge: appTextStyle,
          bodySmall: appTextStyle),
      useMaterial3: true,
    );
