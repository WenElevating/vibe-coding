import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../core/widgets/widgets.dart';
import '../models/home_command_deck_model.dart';
import 'home_signal_row.dart';

class HomeInterruptLane extends StatelessWidget {
  const HomeInterruptLane({super.key, required this.items, required this.l10n});

  final List<HomeSignalItem> items;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(l10n.homeInterruptsTitle),
          const SizedBox(height: 10),
          for (final item in items) ...[
            HomeSignalRow(item: item, prominent: true),
            if (item != items.last) const SizedBox(height: 8),
          ],
        ],
      );
}
