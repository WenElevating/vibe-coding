import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../core/theme/theme.dart' as theme;
import '../../../core/widgets/widgets.dart';
import '../models/home_command_deck_model.dart';
import 'home_signal_row.dart';
import 'home_surface.dart';

class HomeExecutionStream extends StatelessWidget {
  const HomeExecutionStream({
    super.key,
    required this.items,
    required this.l10n,
    required this.onTap,
  });

  final List<HomeSignalItem> items;
  final AppLocalizations l10n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(l10n.homeExecutionStreamTitle,
              action: l10n.homeViewAllAction, onAction: onTap),
          const SizedBox(height: 10),
          if (items.isEmpty)
            HomeSurface(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.inbox_rounded,
                        color: theme.faint, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(l10n.homeNoRecentActivity,
                          style: const TextStyle(
                              color: theme.muted, fontSize: 13)),
                    ),
                  ],
                ),
              ),
            )
          else
            for (final item in items) ...[
              InkWell(onTap: onTap, child: HomeSignalRow(item: item)),
              if (item != items.last) const SizedBox(height: 8),
            ],
        ],
      );
}
