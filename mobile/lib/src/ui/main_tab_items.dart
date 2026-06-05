import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'core/widgets/widgets.dart';

List<NavSpec> mainTabItems(AppLocalizations l10n) => [
      NavSpec(Icons.terminal_rounded, l10n.navCoding),
      const NavSpec(Icons.api_rounded, 'Codex'),
      NavSpec(Icons.settings_rounded, l10n.navSettings),
    ];
