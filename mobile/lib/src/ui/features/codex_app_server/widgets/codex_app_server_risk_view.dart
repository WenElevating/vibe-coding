import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../../domain/models/codex_app_server_models.dart';
import '../../../core/theme/theme.dart' as theme;
import '../../../core/widgets/widgets.dart';
import 'codex_app_server_ui.dart';

class CodexAppServerRiskView extends StatelessWidget {
  const CodexAppServerRiskView({super.key, required this.capabilities});

  final CodexAppServerCapabilities? capabilities;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final routes = capabilities?.routes ?? const <Map<String, Object?>>[];
    final guarded = routes.where(_isGuardedRoute).length;
    final readOnly = routes.length - guarded;
    return PageScroll(
      children: [
        _RiskSummary(
          l10n: l10n,
          readOnly: readOnly < 0 ? 0 : readOnly,
          guarded: guarded,
        ),
        CodexSectionHeader(
          label: l10n.codexAppServerControlsSection,
          trailing: l10n.codexAppServerDaemonEnforced,
        ),
        CodexSurface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _RiskPolicyRow(
                icon: Icons.verified_user_outlined,
                title: l10n.codexAppServerWorkspaceAuthorization,
                detail: l10n.codexAppServerWorkspaceAuthorizationDetail,
              ),
              const Divider(height: 1, color: codexLine),
              _RiskPolicyRow(
                icon: Icons.fact_check_outlined,
                title: l10n.codexAppServerApprovalBoundary,
                detail: l10n.codexAppServerApprovalBoundaryDetail,
              ),
              const Divider(height: 1, color: codexLine),
              _RiskPolicyRow(
                icon: Icons.receipt_long_outlined,
                title: l10n.codexAppServerAuditTrail,
                detail: l10n.codexAppServerAuditTrailDetail,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RiskSummary extends StatelessWidget {
  const _RiskSummary({
    required this.l10n,
    required this.readOnly,
    required this.guarded,
  });

  final AppLocalizations l10n;
  final int readOnly;
  final int guarded;

  @override
  Widget build(BuildContext context) {
    return CodexSurface(
      child: Row(
        children: [
          Expanded(
            child: _RiskCounter(
              label: l10n.codexAppServerReadDiagnostic,
              value: readOnly,
              color: codexSuccess,
            ),
          ),
          Container(width: 1, height: 38, color: codexLine),
          Expanded(
            child: _RiskCounter(
              label: l10n.codexAppServerGuardedRisk,
              value: guarded,
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

bool _isGuardedRoute(Map<String, Object?> route) {
  return _isHighRiskRoute(route) ||
      _isTruthy(route['approvalRequired']) ||
      _isTruthy(route['requiresApproval']) ||
      _isTruthy(route['guarded']);
}

bool _isTruthy(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'true' ||
        normalized == 'yes' ||
        normalized == 'required' ||
        normalized == 'approval_required';
  }
  return false;
}
