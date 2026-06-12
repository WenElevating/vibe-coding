import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../core/theme/theme.dart' as theme;

@visibleForTesting
Widget buildPendingTranscriptTransitionPreview() => MaterialApp(
    locale: theme.zhHansCnLocale,
    supportedLocales: const [theme.zhHansCnLocale, Locale('en', 'US')],
    localizationsDelegates: theme.appLocalizationsDelegates,
    theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'Segoe UI',
        fontFamilyFallback: theme.appFontFallback,
        useMaterial3: true),
    home: const Scaffold(
        backgroundColor: theme.bg,
        body: Padding(
            padding: EdgeInsets.all(16),
            child: PendingTranscriptTransition(
                statusText: '我先按项目说明和已有记忆快速确认一下，不直接按年月目录名猜用途。'))));

class PendingTranscriptTransition extends StatefulWidget {
  const PendingTranscriptTransition({
    super.key,
    required this.statusText,
    this.startedAt,
    this.now,
  });

  final String statusText;
  final DateTime? startedAt;
  final DateTime Function()? now;

  @override
  State<PendingTranscriptTransition> createState() =>
      _PendingTranscriptTransitionState();
}

class _PendingTranscriptTransitionState
    extends State<PendingTranscriptTransition> {
  Timer? _elapsedTimer;
  var _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    _elapsedSeconds = _initialElapsedSeconds();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsedSeconds = widget.startedAt == null
            ? _elapsedSeconds + 1
            : _elapsedSecondsSince(widget.startedAt!);
      });
    });
  }

  @override
  void didUpdateWidget(covariant PendingTranscriptTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startedAt != widget.startedAt) {
      _elapsedSeconds = _initialElapsedSeconds();
    }
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final resolvedStatus = _displayStatusText(context);
    final isTransitionOnly = _isTransitionOnlyStatus(l10n, resolvedStatus);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Container(
        margin: const EdgeInsets.only(top: 0, bottom: 10),
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_elapsedLabel(l10n, _elapsedSeconds),
              key: const ValueKey('workbench-pending-transcript-elapsed'),
              style: TextStyle(
                  color: theme.text.withValues(alpha: .64),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  height: 1.2)),
          const SizedBox(height: 11),
          Container(
              key: const ValueKey('workbench-pending-transcript-divider'),
              height: 1,
              width: double.infinity,
              color: Colors.white.withValues(alpha: .08)),
          const SizedBox(height: 14),
          KeyedSubtree(
              key: const ValueKey('workbench-pending-transcript-status'),
              child: reduceMotion
                  ? _PendingStatusText(
                      text: resolvedStatus,
                      transitionOnly: isTransitionOnly,
                    )
                  : AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      switchInCurve: Curves.easeOutQuart,
                      switchOutCurve: Curves.easeOutCubic,
                      transitionBuilder: (child, animation) {
                        final offset = Tween<Offset>(
                                begin: const Offset(0, .08), end: Offset.zero)
                            .animate(CurvedAnimation(
                                parent: animation, curve: Curves.easeOutQuart));
                        return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                                position: offset, child: child));
                      },
                      child: KeyedSubtree(
                          key: ValueKey(
                              'workbench-pending-status-$resolvedStatus'),
                          child: _PendingStatusText(
                            text: resolvedStatus,
                            transitionOnly: isTransitionOnly,
                          )))),
        ]));
  }

  String _displayStatusText(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (widget.statusText == l10n.workbenchPendingSearchingWeb) {
      return _elapsedSeconds >= 30
          ? l10n.workbenchPendingSearchingWebStill
          : widget.statusText;
    }
    if (widget.statusText != l10n.workbenchPendingWaitingNextEvent) {
      return widget.statusText;
    }
    final phase = (_elapsedSeconds ~/ 5) % 4;
    return switch (phase) {
      0 => l10n.workbenchPendingBrewing,
      1 => l10n.workbenchPendingThinking,
      2 => l10n.workbenchPendingWorking,
      _ => l10n.workbenchPendingAlmostThere,
    };
  }

  bool _isTransitionOnlyStatus(AppLocalizations l10n, String status) =>
      status == l10n.workbenchPendingGenerating ||
      status == l10n.workbenchPendingWaitingNextEvent ||
      status == l10n.workbenchPendingBrewing ||
      status == l10n.workbenchPendingThinking ||
      status == l10n.workbenchPendingWorking ||
      status == l10n.workbenchPendingAlmostThere;

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  int _initialElapsedSeconds() =>
      widget.startedAt == null ? 0 : _elapsedSecondsSince(widget.startedAt!);

  int _elapsedSecondsSince(DateTime startedAt) {
    final elapsed = _now().difference(startedAt).inSeconds;
    return elapsed < 0 ? 0 : elapsed;
  }
}

class _PendingStatusText extends StatelessWidget {
  const _PendingStatusText({
    required this.text,
    required this.transitionOnly,
  });

  final String text;
  final bool transitionOnly;

  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(
          color: transitionOnly
              ? const Color(0xFF9298A2)
              : theme.text.withValues(alpha: .97),
          fontSize: transitionOnly ? 13 : 15,
          fontWeight: transitionOnly ? FontWeight.w600 : FontWeight.w700,
          height: transitionOnly ? 1.38 : 1.58));
}

String _elapsedLabel(AppLocalizations l10n, int seconds) {
  final elapsed = _formatPendingElapsedCompact(seconds);
  if (l10n.localeName.startsWith('zh')) {
    return '已处理 $elapsed';
  }
  return 'Processed $elapsed';
}

String _formatPendingElapsedCompact(int seconds) {
  final normalized = seconds < 0 ? 0 : seconds;
  final hours = normalized ~/ 3600;
  final minutes = (normalized % 3600) ~/ 60;
  final remainingSeconds = normalized % 60;
  final twoDigitSeconds = remainingSeconds.toString().padLeft(2, '0');
  if (hours > 0) {
    return '${hours}h ${minutes}m ${twoDigitSeconds}s';
  }
  if (minutes > 0) {
    return '${minutes}m ${twoDigitSeconds}s';
  }
  return '${remainingSeconds}s';
}
