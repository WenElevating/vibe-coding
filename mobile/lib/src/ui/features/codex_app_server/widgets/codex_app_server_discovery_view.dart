import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../../domain/models/codex_app_server_models.dart';
import '../../../core/theme/theme.dart' as theme;
import '../../../core/widgets/widgets.dart';
import 'codex_app_server_ui.dart';

class CodexAppServerDiscoveryView extends StatelessWidget {
  const CodexAppServerDiscoveryView({
    super.key,
    required this.discovery,
    required this.capabilities,
  });

  final CodexAppServerDiscoverySnapshot? discovery;
  final CodexAppServerCapabilities? capabilities;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final discovery = this.discovery;
    return PageScroll(
      children: [
        _MetricStrip(
          l10n: l10n,
          totalMethods: capabilities?.totalMethods ?? 0,
          providers: _count(discovery?.models['providers']),
          mcpServers: _count(discovery?.mcpServers['servers']),
        ),
        CodexSectionHeader(label: l10n.codexAppServerStatusSection),
        _StatusSection(
          l10n: l10n,
          modelsStatus: _availableStatus(
            l10n,
            _count(discovery?.models['providers']),
          ),
          configStatus: _availableStatus(
              l10n, discovery?.config.isEmpty == false ? 1 : 0),
          capabilitiesStatus: capabilities == null
              ? l10n.codexAppServerStatusUnknown
              : capabilities!.totalMethods > 0
                  ? l10n.codexAppServerStatusAvailable
                  : l10n.codexAppServerStatusEmpty,
        ),
        CodexSectionHeader(
          label: l10n.codexAppServerDiscoverySection,
          trailing: l10n.codexAppServerReadOnly,
        ),
        CodexSurface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _DiscoveryRow(
                title: l10n.codexAppServerModelsTitle,
                detail: l10n.codexAppServerModelsDetail,
                icon: Icons.auto_awesome_outlined,
                count: _count(discovery?.models['providers']),
              ),
              const Divider(height: 1, color: codexLine),
              _DiscoveryRow(
                title: l10n.codexAppServerMcpServersTitle,
                detail: l10n.codexAppServerMcpServersDetail,
                icon: Icons.hub_outlined,
                count: _count(discovery?.mcpServers['servers']),
              ),
              const Divider(height: 1, color: codexLine),
              _DiscoveryRow(
                title: l10n.codexAppServerSkillsTitle,
                detail: l10n.codexAppServerSkillsDetail,
                icon: Icons.psychology_outlined,
                count: _count(discovery?.skills['skills']),
              ),
              const Divider(height: 1, color: codexLine),
              _DiscoveryRow(
                title: l10n.codexAppServerPluginsTitle,
                detail: l10n.codexAppServerPluginsDetail,
                icon: Icons.extension_outlined,
                count: _count(discovery?.plugins['plugins']),
              ),
              const Divider(height: 1, color: codexLine),
              _DiscoveryRow(
                title: l10n.codexAppServerAppsTitle,
                detail: l10n.codexAppServerAppsDetail,
                icon: Icons.apps_outlined,
                count: _count(discovery?.apps['apps']),
              ),
              const Divider(height: 1, color: codexLine),
              _DiscoveryRow(
                title: l10n.codexAppServerConfigTitle,
                detail: l10n.codexAppServerConfigDetail,
                icon: Icons.tune_outlined,
                count: discovery?.config.isEmpty == false ? 1 : 0,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusSection extends StatelessWidget {
  const _StatusSection({
    required this.l10n,
    required this.modelsStatus,
    required this.configStatus,
    required this.capabilitiesStatus,
  });

  final AppLocalizations l10n;
  final String modelsStatus;
  final String configStatus;
  final String capabilitiesStatus;

  @override
  Widget build(BuildContext context) {
    return CodexSurface(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _StatusRow(
            label: l10n.codexAppServerModelStatus,
            value: modelsStatus,
          ),
          const Divider(height: 1, color: Color(0x1AFFFFFF)),
          _StatusRow(
            label: l10n.codexAppServerConfigStatus,
            value: configStatus,
          ),
          const Divider(height: 1, color: Color(0x1AFFFFFF)),
          _StatusRow(
            label: l10n.codexAppServerCapabilityStatus,
            value: capabilitiesStatus,
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: theme.muted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricStrip extends StatelessWidget {
  const _MetricStrip({
    required this.l10n,
    required this.totalMethods,
    required this.providers,
    required this.mcpServers,
  });

  final AppLocalizations l10n;
  final int totalMethods;
  final int providers;
  final int mcpServers;

  @override
  Widget build(BuildContext context) {
    return CodexSurface(
      child: Row(
        children: [
          Expanded(
            child: _Metric(
              label: l10n.codexAppServerMethodsMetric,
              value: '$totalMethods',
            ),
          ),
          const _MetricDivider(),
          Expanded(
            child: _Metric(
              label: l10n.codexAppServerProvidersMetric,
              value: '$providers',
            ),
          ),
          const _MetricDivider(),
          Expanded(
            child: _Metric(
              label: l10n.codexAppServerMcpMetric,
              value: '$mcpServers',
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
              color: theme.muted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            )),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
            )),
      ],
    );
  }
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 34, color: codexLine);
  }
}

class _DiscoveryRow extends StatelessWidget {
  const _DiscoveryRow({
    required this.title,
    required this.detail,
    required this.icon,
    required this.count,
  });

  final String title;
  final String detail;
  final IconData icon;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: codexAccent.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: codexAccent, size: 17),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: theme.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          CodexStatusPill(
            label: '$count',
            color: count > 0 ? codexAccent : theme.faint,
          ),
        ],
      ),
    );
  }
}

int _count(Object? value) => value is List ? value.length : 0;

String _availableStatus(AppLocalizations l10n, int count) {
  if (count > 0) return l10n.codexAppServerStatusAvailable;
  return l10n.codexAppServerStatusMissing;
}
