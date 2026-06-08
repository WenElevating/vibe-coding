import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../core/theme/theme.dart' as theme;
import '../workbench_messages.dart';

class SystemNoticeEventCard extends StatelessWidget {
  const SystemNoticeEventCard({super.key, required this.message});
  final WorkbenchMessage message;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final noticeKind = _noticeKind(message);
    final severity = _noticeSeverity(message, noticeKind);
    final copy = _noticeCopy(l10n, message, noticeKind, severity);
    final accent = _noticeAccent(severity);
    return Container(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
        decoration: BoxDecoration(
            color: const Color(0xE60F1012),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withValues(alpha: .18))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: accent.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(_noticeIcon(severity),
                  color: accent.withValues(alpha: .92), size: 15)),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  Expanded(
                      child: Text(copy.title,
                          style: const TextStyle(
                              color: theme.text,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0))),
                  const SizedBox(width: 8),
                  Text(copy.meta,
                      style: const TextStyle(
                          color: theme.faint,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0)),
                ]),
                const SizedBox(height: 7),
                Text(copy.body,
                    style: TextStyle(
                        color: severity == _NoticeSeverity.error
                            ? theme.text
                            : theme.muted,
                        fontSize: 12.5,
                        height: 1.48,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0)),
              ])),
        ]));
  }
}

enum _NoticeSeverity { info, warning, error }

class _NoticeCopy {
  const _NoticeCopy({
    required this.title,
    required this.meta,
    required this.body,
  });

  final String title;
  final String meta;
  final String body;
}

_NoticeCopy _noticeCopy(
  AppLocalizations l10n,
  WorkbenchMessage message,
  String noticeKind,
  _NoticeSeverity severity,
) {
  if (noticeKind == 'codex_policy_blocked') {
    return _NoticeCopy(
      title: l10n.workbenchNoticePolicyBlockedTitle,
      meta: l10n.workbenchNoticePolicyBlockedMeta,
      body: l10n.workbenchNoticePolicyBlockedBody,
    );
  }
  if (noticeKind == 'opencode_session_expired') {
    return _NoticeCopy(
      title: l10n.workbenchNoticeOpenCodeSessionExpiredTitle,
      meta: l10n.workbenchNoticeOpenCodeSessionExpiredMeta,
      body: l10n.workbenchNoticeOpenCodeSessionExpiredBody,
    );
  }
  if (noticeKind == 'opencode_session_diff') {
    return _NoticeCopy(
      title: l10n.workbenchNoticeOpenCodeDiffUnavailableTitle,
      meta: l10n.workbenchNoticeOpenCodeDiffUnavailableMeta,
      body: l10n.workbenchNoticeOpenCodeDiffUnavailableBody,
    );
  }
  if (noticeKind == 'opencode_file_edited') {
    final path = _noticePath(message);
    return _NoticeCopy(
      title: l10n.workbenchNoticeOpenCodeFileEditedTitle,
      meta: l10n.workbenchNoticeOpenCodeFileEditedMeta,
      body: path == null
          ? message.body
          : l10n.workbenchNoticeOpenCodeFileEditedBody(path),
    );
  }
  if (_isProviderAuthNotice(message)) {
    return _NoticeCopy(
      title: l10n.workbenchNoticeProviderAuthTitle,
      meta: l10n.workbenchNoticeProviderAuthMeta,
      body: message.body,
    );
  }
  if (_isRunFailedNotice(message)) {
    return _NoticeCopy(
      title: l10n.workbenchNoticeRunFailedTitle,
      meta: l10n.workbenchNoticeRunFailedMeta,
      body: message.body,
    );
  }
  return _NoticeCopy(
    title: severity == _NoticeSeverity.error
        ? l10n.workbenchNoticeCliErrorTitle
        : l10n.workbenchNoticeSystemTitle,
    meta: severity == _NoticeSeverity.error
        ? l10n.workbenchNoticeErrorMeta
        : l10n.workbenchNoticeInfoMeta,
    body: message.body,
  );
}

_NoticeSeverity _noticeSeverity(WorkbenchMessage message, String noticeKind) {
  if (message.isError) return _NoticeSeverity.error;
  if (noticeKind == 'codex_policy_blocked') return _NoticeSeverity.warning;
  return _NoticeSeverity.info;
}

IconData _noticeIcon(_NoticeSeverity severity) => switch (severity) {
      _NoticeSeverity.error => Icons.error_outline_rounded,
      _NoticeSeverity.warning => Icons.gpp_maybe_outlined,
      _NoticeSeverity.info => Icons.info_outline_rounded,
    };

Color _noticeAccent(_NoticeSeverity severity) => switch (severity) {
      _NoticeSeverity.error => theme.red,
      _NoticeSeverity.warning => theme.text,
      _NoticeSeverity.info => theme.faint,
    };

String _noticeKind(WorkbenchMessage message) {
  final value = message.event?.raw['noticeKind'];
  return value is String ? value.trim().toLowerCase() : '';
}

String? _noticePath(WorkbenchMessage message) {
  final value = message.event?.raw['path'];
  final nested = message.event?.raw['input'];
  final pathValue = value is String
      ? value
      : nested is Map
          ? nested['path']
          : null;
  if (pathValue is! String) return null;
  final path = pathValue.trim();
  return path.isEmpty ? null : path;
}

bool _isProviderAuthNotice(WorkbenchMessage message) {
  final text = message.body.toLowerCase();
  return text.contains('claude') &&
      (text.contains('auth') || text.contains('401'));
}

bool _isRunFailedNotice(WorkbenchMessage message) =>
    _noticeKind(message) == 'run_failed' ||
    message.body.toLowerCase().startsWith('run error:');
