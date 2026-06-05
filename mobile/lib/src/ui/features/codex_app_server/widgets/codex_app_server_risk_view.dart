import 'package:flutter/material.dart';

import '../../../../domain/models/codex_app_server_models.dart';
import '../../../core/theme/theme.dart' as theme;
import '../../../core/widgets/widgets.dart';
import 'codex_app_server_ui.dart';

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
        _RiskSummary(
          readOnly: readOnly < 0 ? 0 : readOnly,
          highRisk: highRisk,
        ),
        const CodexSectionHeader(
          label: 'Controls',
          trailing: 'Daemon enforced',
        ),
        const CodexSurface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _RiskPolicyRow(
                icon: Icons.verified_user_outlined,
                title: 'Workspace authorization',
                detail: 'Routes resolve through authorized daemon scope.',
              ),
              Divider(height: 1, color: codexLine),
              _RiskPolicyRow(
                icon: Icons.fact_check_outlined,
                title: 'Approval boundary',
                detail: 'Write, process, network, and permission operations.',
              ),
              Divider(height: 1, color: codexLine),
              _RiskPolicyRow(
                icon: Icons.receipt_long_outlined,
                title: 'Audit trail',
                detail: 'Downstream failures stay controlled and traceable.',
              ),
            ],
          ),
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
    return CodexSurface(
      child: Row(
        children: [
          Expanded(
            child: _RiskCounter(
              label: 'Read / diagnostic',
              value: readOnly,
              color: codexSuccess,
            ),
          ),
          Container(width: 1, height: 38, color: codexLine),
          Expanded(
            child: _RiskCounter(
              label: 'Guarded risk',
              value: highRisk,
              color: codexWarning,
            ),
          ),
        ],
      ),
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
    return Padding(
      padding: const EdgeInsets.only(left: 4),
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
          const SizedBox(height: 5),
          Text(
            '$value',
            style: TextStyle(
              color: color,
              fontSize: 20,
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: codexWarning.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: codexWarning, size: 17),
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
    );
  }
}

bool _isHighRiskRoute(Map<String, Object?> route) {
  final risk = route['risk']?.toString();
  return const {'write', 'process', 'network', 'permission', 'account'}
      .contains(risk);
}
