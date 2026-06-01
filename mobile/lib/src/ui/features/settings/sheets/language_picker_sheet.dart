import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../../app/language_mode.dart';
import '../../../../app/language_scope.dart';
import '../../../core/theme/theme.dart' as theme;

String languageModeLabel(AppLocalizations l10n, LanguageModePreference mode) =>
    switch (mode) {
      LanguageModePreference.system => l10n.settingsLanguageSystem,
      LanguageModePreference.zhHansCn => '简体中文',
      LanguageModePreference.enUs => 'English',
    };

void showLanguagePicker(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  final controller = LanguageScope.read(context);
  showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _LanguagePickerSheet(
          title: l10n.settingsLanguagePickerTitle,
          selected: controller.mode,
          onSelected: (mode) async {
            Navigator.of(context).pop();
            await controller.setMode(mode);
          }));
}

class _LanguagePickerSheet extends StatelessWidget {
  const _LanguagePickerSheet({
    required this.title,
    required this.selected,
    required this.onSelected,
  });

  final String title;
  final LanguageModePreference selected;
  final ValueChanged<LanguageModePreference> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final options = <(LanguageModePreference, String)>[
      (LanguageModePreference.system, l10n.settingsLanguageSystem),
      (LanguageModePreference.zhHansCn, '简体中文'),
      (LanguageModePreference.enUs, 'English'),
    ];
    return SafeArea(
        child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            decoration: BoxDecoration(
                color: const Color(0xFF101113),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: .08))),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            color: theme.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w900))),
                IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded,
                        color: theme.muted, size: 18)),
              ]),
              for (final option in options)
                ListTile(
                    dense: true,
                    title: Text(option.$2),
                    trailing: selected == option.$1
                        ? const Icon(Icons.check_rounded,
                            color: theme.green, size: 18)
                        : null,
                    onTap: () => onSelected(option.$1)),
            ])));
  }
}
