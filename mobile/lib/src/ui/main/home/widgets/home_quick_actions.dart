import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../core/theme/theme.dart' as theme;
import '../../../core/widgets/widgets.dart';
import 'home_controls.dart';

class HomeQuickActions extends StatelessWidget {
  const HomeQuickActions({
    super.key,
    required this.selectTab,
    required this.l10n,
  });

  final ValueChanged<int> selectTab;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(l10n.homeQuickActionsTitle),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: HomeQuickActionTile(
                  icon: Icons.add_rounded,
                  title: l10n.homeNewTaskTitle,
                  subtitle: l10n.homeNewTaskSubtitle,
                  color: theme.purple,
                  onTap: () => selectTab(1),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: HomeQuickActionTile(
                  icon: Icons.terminal_rounded,
                  title: l10n.homeCommandTemplatesTitle,
                  subtitle: l10n.homeCommandTemplatesSubtitle,
                  color: theme.green,
                  onTap: () => selectTab(1),
                ),
              ),
            ],
          ),
        ],
      );
}
