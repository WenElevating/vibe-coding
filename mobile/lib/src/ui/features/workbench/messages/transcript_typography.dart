import 'package:flutter/material.dart';

const workbenchMonoFontFallback = <String>[
  'Consolas',
  'Courier New',
  'monospace',
];

class WorkbenchTranscriptTypography {
  const WorkbenchTranscriptTypography._();

  static const assistantAccent = Color(0xFF3A96DD);

  static const assistantBody = TextStyle(
    color: Color(0xFFD8DCE5),
    fontSize: 14.7,
    height: 1.62,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
  );

  static const assistantStrong = TextStyle(
    color: Color(0xFFF1F3F7),
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
  );

  static const commandSummary = TextStyle(
    color: Color(0xFF868B94),
    fontSize: 12,
    height: 1.25,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
  );

  static const commandSummaryActive = TextStyle(
    color: Color(0xFF9298A2),
    fontSize: 12,
    height: 1.25,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
  );

  static const toolTitle = TextStyle(
    color: Color(0xFF9097A2),
    fontSize: 12.2,
    height: 1.22,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
  );

  static const toolMeta = TextStyle(
    color: Color(0xFF767D88),
    fontSize: 10.5,
    height: 1.2,
    fontFamily: 'Cascadia Mono',
    fontFamilyFallback: workbenchMonoFontFallback,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );

  static const shellLabel = TextStyle(
    color: Color(0xFF8E949D),
    fontSize: 10.2,
    height: 1,
    fontFamily: 'Cascadia Mono',
    fontFamilyFallback: workbenchMonoFontFallback,
    fontWeight: FontWeight.w800,
    letterSpacing: .2,
  );

  static const shellCommand = TextStyle(
    color: Color(0xFFF0F2F6),
    fontSize: 12.5,
    height: 1.46,
    fontFamily: 'Cascadia Mono',
    fontFamilyFallback: workbenchMonoFontFallback,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );

  static const shellOutput = TextStyle(
    color: Color(0xFFAAB1BC),
    fontSize: 12,
    height: 1.44,
    fontFamily: 'Cascadia Mono',
    fontFamilyFallback: workbenchMonoFontFallback,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
  );

  static const inlineCode = TextStyle(
    color: Color(0xFFE9ECF3),
    backgroundColor: Color(0xFF181A1E),
    fontFamily: 'Cascadia Mono',
    fontFamilyFallback: workbenchMonoFontFallback,
    fontSize: 12.6,
    height: 1.45,
    letterSpacing: 0,
  );
}
