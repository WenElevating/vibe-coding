import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../core/theme/theme.dart' as theme;
import '../../../core/widgets/widgets.dart';
import '../models/home_command_deck_model.dart';
import 'home_surface.dart';

class HomeWorkspaceSignals extends StatelessWidget {
  const HomeWorkspaceSignals(
      {super.key, required this.data, required this.l10n});

  final HomeWorkspaceSignalsData data;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(l10n.homeWorkspaceSignalsTitle),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 2.55,
            children: [
              _SignalMetricTile(
                icon: Icons.commit_rounded,
                label: l10n.homeGitChangedLabel,
                value: _signalValue(data.changedFiles),
                color: theme.purple,
              ),
              _SignalMetricTile(
                icon: Icons.health_and_safety_rounded,
                label: l10n.homeDiagnosticsLabel,
                value: _signalValue(data.diagnostics),
                color: theme.amber,
              ),
              _SignalMetricTile(
                icon: Icons.queue_rounded,
                label: l10n.homeQueueLabel,
                value: '${data.queue}',
                color: theme.green,
              ),
              _SignalMetricTile(
                icon: Icons.history_rounded,
                label: l10n.homeRecentFilesLabel,
                value: _signalValue(data.recentFiles),
                color: const Color(0xFF8BC7FF),
              ),
            ],
          ),
        ],
      );
}

class _SignalMetricTile extends StatelessWidget {
  const _SignalMetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => HomeSurface(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(11, 9, 10, 9),
          child: Row(
            children: [
              Icon(icon, color: color, size: 17),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: theme.muted, fontSize: 11.5)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

String _signalValue(int? value) => value == null ? '-' : '$value';
