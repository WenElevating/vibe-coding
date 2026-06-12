import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../core/theme/theme.dart' as theme;
import 'sweeping_status_text.dart';

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
    this.showElapsed = true,
  });

  final String statusText;
  final DateTime? startedAt;
  final DateTime Function()? now;
  final bool showElapsed;

  @override
  State<PendingTranscriptTransition> createState() =>
      _PendingTranscriptTransitionState();
}

bool shouldShowPendingTranscriptElapsed(
        AppLocalizations l10n, String statusText) =>
    !_isRawLightweightPendingStatus(l10n, statusText);

bool isPendingTranscriptRunningTool(AppLocalizations l10n, String statusText) {
  const sentinel = '__tool__';
  final template = l10n.workbenchPendingRunningTool(sentinel);
  final sentinelIndex = template.indexOf(sentinel);
  if (sentinelIndex < 0) return false;

  final prefix = template.substring(0, sentinelIndex);
  final suffix = template.substring(sentinelIndex + sentinel.length);
  return statusText.startsWith(prefix) && statusText.endsWith(suffix);
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
    final isTransitionOnly = _isTransitionOnlyStatus(l10n, widget.statusText,
        resolvedStatus: resolvedStatus);
    final showElapsedProgress = widget.showElapsed &&
        shouldShowPendingTranscriptElapsed(l10n, widget.statusText);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final horizontalInset = showElapsedProgress ? 7.0 : 17.0;
    return Container(
        margin: const EdgeInsets.only(top: 0, bottom: 10),
        padding: EdgeInsets.fromLTRB(horizontalInset, 0, horizontalInset, 2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (showElapsedProgress) ...[
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
          ],
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
                            sweeping: isTransitionOnly,
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
    if (widget.statusText == l10n.workbenchPendingStarting ||
        widget.statusText == l10n.workbenchPendingReadingContext ||
        widget.statusText == l10n.workbenchPendingWaitingNextEvent) {
      return _thinkingStatusText(l10n);
    }
    if (_isRunningToolStatus(l10n, widget.statusText)) {
      return _thinkingStatusText(l10n);
    }
    return widget.statusText;
  }

  bool _isTransitionOnlyStatus(
    AppLocalizations l10n,
    String status, {
    required String resolvedStatus,
  }) =>
      _isLightweightStatus(l10n, status, resolvedStatus: resolvedStatus);

  bool _isLightweightStatus(
    AppLocalizations l10n,
    String status, {
    required String resolvedStatus,
  }) =>
      _isRawLightweightStatus(l10n, status) ||
      resolvedStatus == _thinkingStatusText(l10n);

  bool _isRawLightweightStatus(AppLocalizations l10n, String status) =>
      _isRawLightweightPendingStatus(l10n, status);

  bool _isRunningToolStatus(AppLocalizations l10n, String status) {
    return isPendingTranscriptRunningTool(l10n, status);
  }

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  int _initialElapsedSeconds() =>
      widget.startedAt == null ? 0 : _elapsedSecondsSince(widget.startedAt!);

  int _elapsedSecondsSince(DateTime startedAt) {
    final elapsed = _now().difference(startedAt).inSeconds;
    return elapsed < 0 ? 0 : elapsed;
  }
}

class PendingTranscriptElapsedProgress extends StatefulWidget {
  const PendingTranscriptElapsedProgress({
    super.key,
    this.startedAt,
    this.endedAt,
    this.now,
  });

  final DateTime? startedAt;
  final DateTime? endedAt;
  final DateTime Function()? now;

  @override
  State<PendingTranscriptElapsedProgress> createState() =>
      _PendingTranscriptElapsedProgressState();
}

class _PendingTranscriptElapsedProgressState
    extends State<PendingTranscriptElapsedProgress> {
  Timer? _elapsedTimer;
  late int _elapsedSeconds;

  @override
  void initState() {
    super.initState();
    _elapsedSeconds = _initialElapsedSeconds();
    _syncElapsedTimer();
  }

  @override
  void didUpdateWidget(covariant PendingTranscriptElapsedProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startedAt != widget.startedAt ||
        oldWidget.endedAt != widget.endedAt) {
      _elapsedSeconds = _initialElapsedSeconds();
      _syncElapsedTimer();
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
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 0, 7, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
        ],
      ),
    );
  }

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  void _syncElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    if (widget.endedAt != null) return;
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsedSeconds = widget.startedAt == null
            ? _elapsedSeconds + 1
            : _elapsedSecondsSince(widget.startedAt!);
      });
    });
  }

  int _initialElapsedSeconds() =>
      widget.startedAt == null ? 0 : _elapsedSecondsSince(widget.startedAt!);

  int _elapsedSecondsSince(DateTime startedAt) {
    final elapsed = (widget.endedAt ?? _now()).difference(startedAt).inSeconds;
    return elapsed < 0 ? 0 : elapsed;
  }
}

bool _isRawLightweightPendingStatus(AppLocalizations l10n, String status) =>
    status == l10n.workbenchPendingStarting ||
    status == l10n.workbenchPendingGenerating ||
    status == l10n.workbenchPendingReadingContext ||
    status == l10n.workbenchPendingWaitingNextEvent ||
    status == l10n.workbenchPendingBrewing ||
    status == l10n.workbenchPendingThinking ||
    status == l10n.workbenchPendingWorking ||
    status == l10n.workbenchPendingAlmostThere;

class _PendingStatusText extends StatelessWidget {
  const _PendingStatusText({
    required this.text,
    required this.transitionOnly,
    this.sweeping = false,
  });

  final String text;
  final bool transitionOnly;
  final bool sweeping;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
        color: transitionOnly
            ? const Color(0xFF737983)
            : theme.text.withValues(alpha: .97),
        fontSize: transitionOnly ? 13 : 15,
        fontWeight: transitionOnly ? FontWeight.w500 : FontWeight.w700,
        height: transitionOnly ? 1.28 : 1.58);
    if (!sweeping) {
      return Text(text, style: style);
    }
    return SweepingStatusText(
        text: text,
        style: style,
        baseColor: const Color(0xFF737983),
        highlightColor: const Color(0xFFBBC3CE),
        progressKey: const ValueKey('workbench-pending-status-sweep-progress'));
  }
}

String _elapsedLabel(AppLocalizations l10n, int seconds) {
  final elapsed = _formatPendingElapsedCompact(seconds);
  if (l10n.localeName.startsWith('zh')) {
    return '已处理 $elapsed';
  }
  return 'Processed $elapsed';
}

String _thinkingStatusText(AppLocalizations l10n) =>
    l10n.localeName.startsWith('zh') ? '正在思考' : 'Thinking';

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
