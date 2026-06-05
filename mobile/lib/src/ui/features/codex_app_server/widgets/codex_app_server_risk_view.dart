import 'package:flutter/material.dart';

import '../../../../domain/models/codex_app_server_models.dart';
import '../../../core/theme/theme.dart' as theme;
import '../../../core/widgets/widgets.dart';

class CodexAppServerRiskView extends StatelessWidget {
  const CodexAppServerRiskView({super.key, required this.capabilities});

  final CodexAppServerCapabilities? capabilities;

  @override
  Widget build(BuildContext context) {
    final routes = capabilities?.routes ?? const <Map<String, Object?>>[];
    final highRisk = routes.where(_isHighRiskRoute).length;
    final readOnly = routes.length - highRisk;
    return PageScroll(
      children: [
        const SizedBox(height: 14),
        _RiskSummary(
          readOnly: readOnly < 0 ? 0 : readOnly,
          highRisk: highRisk,
        ),
        const SizedBox(height: 14),
        const _RiskPolicyRow(
          icon: Icons.verified_user_rounded,
          title: 'Workspace authorization',
          detail: 'Workspace routes resolve through authorized daemon scope.',
        ),
        const _RiskPolicyRow(
          icon: Icons.fact_check_rounded,
          title: 'Approval boundary',
          detail:
              'Write, process, network, and permission operations require policy or approval.',
        ),
        const _RiskPolicyRow(
          icon: Icons.receipt_long_rounded,
          title: 'Audit trail',
          detail:
              'High-risk operations are expected to produce controlled errors and audit records.',
        ),
      ],
    );
  }
}

class _RiskSummary extends StatelessWidget {
  const _RiskSummary({required this.readOnly, required this.highRisk});

  final int readOnly;
  final int highRisk;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _RiskCounter(
            label: 'Read / diagnostic',
            value: readOnly,
            color: const Color(0xFF63D297),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _RiskCounter(
            label: 'Guarded risk',
            value: highRisk,
            color: const Color(0xFFFFC15A),
          ),
        ),
      ],
    );
  }
}

class _RiskCounter extends StatelessWidget {
  const _RiskCounter({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101113),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: .07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: theme.muted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$value',
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _RiskPolicyRow extends StatelessWidget {
  const _RiskPolicyRow({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFFFFC15A)),
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
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    style: const TextStyle(
                      color: theme.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

bool _isHighRiskRoute(Map<String, Object?> route) {
  final risk = route['risk']?.toString();
  return const {'write', 'process', 'network', 'permission', 'account'}
      .contains(risk);
}
