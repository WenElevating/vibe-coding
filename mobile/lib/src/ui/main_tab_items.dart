import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../widgets/widgets.dart';

List<NavSpec> mainTabItems(AppLocalizations l10n) => [
      NavSpec(Icons.home_rounded, l10n.navHome),
      NavSpec(Icons.manage_search_rounded, l10n.navRuns),
      NavSpec(Icons.terminal_rounded, l10n.navCoding),
      NavSpec(Icons.format_list_bulleted_rounded, l10n.navDevices),
      NavSpec(Icons.settings_rounded, l10n.navSettings),
    ];
