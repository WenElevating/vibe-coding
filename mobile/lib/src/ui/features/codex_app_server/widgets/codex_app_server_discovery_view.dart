import 'package:flutter/material.dart';

import '../../../../domain/models/codex_app_server_models.dart';
import '../../../core/theme/theme.dart' as theme;
import '../../../core/widgets/widgets.dart';

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
        const SizedBox(height: 14),
        _MetricStrip(
          totalMethods: capabilities?.totalMethods ?? 0,
          providers: _count(discovery?.models['providers']),
          mcpServers: _count(discovery?.mcpServers['servers']),
        ),
        const SizedBox(height: 14),
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
        const SizedBox(height: 14),
        _DiscoverySection(
          title: 'Models',
          icon: Icons.auto_awesome_rounded,
          count: _count(discovery?.models['providers']),
        ),
        _DiscoverySection(
          title: 'MCP Servers',
          icon: Icons.hub_rounded,
          count: _count(discovery?.mcpServers['servers']),
        ),
        _DiscoverySection(
          title: 'Skills',
          icon: Icons.psychology_rounded,
          count: _count(discovery?.skills['skills']),
        ),
        _DiscoverySection(
          title: 'Plugins',
          icon: Icons.extension_rounded,
          count: _count(discovery?.plugins['plugins']),
        ),
        _DiscoverySection(
          title: 'Apps',
          icon: Icons.apps_rounded,
          count: _count(discovery?.apps['apps']),
        ),
        _DiscoverySection(
          title: 'Config',
          icon: Icons.tune_rounded,
          count: discovery?.config.isEmpty == false ? 1 : 0,
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
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF101113),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: .07)),
      ),
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
    return Row(
      children: [
        Expanded(child: _Metric(label: 'Methods', value: '$totalMethods')),
        const SizedBox(width: 8),
        Expanded(child: _Metric(label: 'Providers', value: '$providers')),
        const SizedBox(width: 8),
        Expanded(child: _Metric(label: 'MCP', value: '$mcpServers')),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF101113),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: .07)),
      ),
      child: Column(
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
      ),
    );
  }
}

class _DiscoverySection extends StatelessWidget {
  const _DiscoverySection({
    required this.title,
    required this.icon,
    required this.count,
  });

  final String title;
  final IconData icon;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF101113),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: .07)),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF8DB4FF)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              '$count',
              style: const TextStyle(
                color: theme.muted,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

int _count(Object? value) => value is List ? value.length : 0;

String _availableStatus(int count) {
  if (count > 0) return 'Available';
  return 'Missing';
}
