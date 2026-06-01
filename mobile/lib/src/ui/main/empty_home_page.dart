import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../core/theme/theme.dart' as theme;
import '../core/widgets/widgets.dart';

class EmptyHomePage extends StatelessWidget {
  const EmptyHomePage({super.key, required this.onCreateWorkspace});

  final VoidCallback onCreateWorkspace;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PageScroll(children: [
      const SizedBox(height: 8),
      Text(
        l10n.workspaceListTitle,
        style: const TextStyle(
          color: theme.text,
          fontSize: 28,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 10),
      Text(
        l10n.workspaceListFootnote,
        style: const TextStyle(color: theme.muted, fontSize: 13, height: 1.45),
      ),
      const SizedBox(height: 18),
      PrimaryButton(l10n.workspaceAddTitle, onTap: onCreateWorkspace),
    ]);
  }
}
