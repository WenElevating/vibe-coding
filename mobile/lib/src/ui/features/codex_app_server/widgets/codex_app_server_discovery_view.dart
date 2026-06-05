import 'package:flutter/material.dart';

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
    final discovery = this.discovery;
    return PageScroll(
      children: [
        _MetricStrip(
          totalMethods: capabilities?.totalMethods ?? 0,
          providers: _count(discovery?.models['providers']),
          mcpServers: _count(discovery?.mcpServers['servers']),
        ),
        const CodexSectionHeader(label: 'Status'),
        _StatusSection(
          modelsStatus:
              _availableStatus(_count(discovery?.models['providers'])),
          configStatus:
              _availableStatus(discovery?.config.isEmpty == false ? 1 : 0),
          capabilitiesStatus: capabilities == null
              ? 'Unknown'
              : capabilities!.totalMethods > 0
                  ? 'Available'
                  : 'Empty',
        ),
        const CodexSectionHeader(
          label: 'Discovery',
          trailing: 'Read-only',
        ),
        CodexSurface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _DiscoveryRow(
                title: 'Models',
                detail: 'Configured model providers',
                icon: Icons.auto_awesome_outlined,
                count: _count(discovery?.models['providers']),
              ),
              const Divider(height: 1, color: codexLine),
              _DiscoveryRow(
                title: 'MCP Servers',
                detail: 'Connected tool servers',
                icon: Icons.hub_outlined,
                count: _count(discovery?.mcpServers['servers']),
              ),
              const Divider(height: 1, color: codexLine),
              _DiscoveryRow(
                title: 'Skills',
                detail: 'Codex skill entries',
                icon: Icons.psychology_outlined,
                count: _count(discovery?.skills['skills']),
              ),
              const Divider(height: 1, color: codexLine),
              _DiscoveryRow(
                title: 'Plugins',
                detail: 'Installed plugin surfaces',
                icon: Icons.extension_outlined,
                count: _count(discovery?.plugins['plugins']),
              ),
              const Divider(height: 1, color: codexLine),
              _DiscoveryRow(
                title: 'Apps',
                detail: 'Registered app integrations',
                icon: Icons.apps_outlined,
                count: _count(discovery?.apps['apps']),
              ),
              const Divider(height: 1, color: codexLine),
              _DiscoveryRow(
                title: 'Config',
                detail: 'Resolved app-server config',
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
    required this.modelsStatus,
    required this.configStatus,
    required this.capabilitiesStatus,
  });

  final String modelsStatus;
  final String configStatus;
  final String capabilitiesStatus;

  @override
  Widget build(BuildContext context) {
    return CodexSurface(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _StatusRow(label: 'Model status', value: modelsStatus),
          const Divider(height: 1, color: Color(0x1AFFFFFF)),
          _StatusRow(label: 'Config status', value: configStatus),
          const Divider(height: 1, color: Color(0x1AFFFFFF)),
          _StatusRow(label: 'Capability status', value: capabilitiesStatus),
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
    required this.totalMethods,
    required this.providers,
    required this.mcpServers,
  });

  final int totalMethods;
  final int providers;
  final int mcpServers;

  @override
  Widget build(BuildContext context) {
    return CodexSurface(
      child: Row(
        children: [
          Expanded(child: _Metric(label: 'Methods', value: '$totalMethods')),
          const _MetricDivider(),
          Expanded(child: _Metric(label: 'Providers', value: '$providers')),
          const _MetricDivider(),
          Expanded(child: _Metric(label: 'MCP', value: '$mcpServers')),
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

String _availableStatus(int count) {
  if (count > 0) return 'Available';
  return 'Missing';
}
