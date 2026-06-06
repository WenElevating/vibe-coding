import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../core/theme/theme.dart' as theme;
import 'sweeping_status_text.dart';

@visibleForTesting
Widget buildPendingSentinelPreview() => MaterialApp(
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
            child: PendingSentinel(
                adapter: 'claude',
                statusText: 'Receiving CLI output...',
                actions: <String>[
                  'Started claude session',
                  'Claude requesting'
                ]))));

class PendingSentinel extends StatefulWidget {
  const PendingSentinel({
    super.key,
    required this.adapter,
    required this.statusText,
    this.startedAt,
    this.now,
    this.actions = const <String>[],
  });

  final String adapter;
  final String statusText;
  final DateTime? startedAt;
  final DateTime Function()? now;
  final List<String> actions;

  @override
  State<PendingSentinel> createState() => _PendingSentinelState();
}

class _PendingSentinelState extends State<PendingSentinel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _elapsedTimer;
  var _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 850))
      ..repeat();
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
  void didUpdateWidget(covariant PendingSentinel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startedAt != widget.startedAt) {
      _elapsedSeconds = _initialElapsedSeconds();
    }
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final displayStatus = _displayStatusText(context);
        return Container(
            margin: const EdgeInsets.only(top: 2, bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: .07)),
                gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xF2141517), Color(0xEE0E0F11)])),
            child: Row(children: [
              _RunningOrb(progress: _controller.value),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(AppLocalizations.of(context).workbenchPendingRunning,
                        style: TextStyle(
                            color: theme.text,
                            fontWeight: FontWeight.w800,
                            fontSize: 13)),
                    const SizedBox(height: 5),
                    AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        transitionBuilder: (child, animation) {
                          final slide = Tween<Offset>(
                                  begin: const Offset(0, .18), end: Offset.zero)
                              .animate(CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeOutCubic));
                          return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                  position: slide, child: child));
                        },
                        child: SweepingStatusText(
                            key: ValueKey(displayStatus),
                            text: displayStatus,
                            style: const TextStyle(fontSize: 12, height: 1.3),
                            baseColor: _stableStatusTextColor(displayStatus),
                            progressKey: const ValueKey(
                                'workbench-pending-status-sweep-progress'))),
                  ])),
              const SizedBox(width: 10),
              _ElapsedTimerPill(text: _formatPendingElapsed(_elapsedSeconds)),
              const SizedBox(width: 10),
              SizedBox(
                  width: 18,
                  height: 24,
                  child:
                      Center(child: _PulseBars(progress: _controller.value))),
            ]));
      });

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

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  int _initialElapsedSeconds() =>
      widget.startedAt == null ? 0 : _elapsedSecondsSince(widget.startedAt!);

  int _elapsedSecondsSince(DateTime startedAt) {
    final elapsed = _now().difference(startedAt).inSeconds;
    return elapsed < 0 ? 0 : elapsed;
  }
}

Color _stableStatusTextColor(String text) {
  const palette = <Color>[
    Color(0xFFB8C7FF),
    Color(0xFF8FE8B5),
    Color(0xFF9DD6FF),
    Color(0xFFD4C2FF),
  ];
  var hash = 0;
  for (final unit in text.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return palette[hash % palette.length];
}

String _formatPendingElapsed(int seconds) {
  final normalized = seconds < 0 ? 0 : seconds;
  final hours = normalized ~/ 3600;
  final minutes = (normalized % 3600) ~/ 60;
  final remainingSeconds = normalized % 60;
  final twoDigitMinutes = minutes.toString().padLeft(2, '0');
  final twoDigitSeconds = remainingSeconds.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:$twoDigitMinutes:$twoDigitSeconds';
  }
  return '$twoDigitMinutes:$twoDigitSeconds';
}

class _ElapsedTimerPill extends StatelessWidget {
  const _ElapsedTimerPill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
      constraints: const BoxConstraints(minWidth: 44),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: theme.purple.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: theme.purple.withValues(alpha: .14))),
      child: Text(text,
          maxLines: 1,
          style: TextStyle(
              color: theme.text.withValues(alpha: .78),
              fontSize: 11,
              fontFeatures: const [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w700,
              height: 1)));
}

class _RunningOrb extends StatelessWidget {
  const _RunningOrb({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    final pulse = progress < .5 ? progress * 2 : (1 - progress) * 2;
    return Container(
        width: 18,
        height: 18,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.purple.withValues(alpha: .08 + pulse * .08),
            border: Border.all(color: theme.purple.withValues(alpha: .18))),
        child: Container(
            width: 7 + pulse * 2,
            height: 7 + pulse * 2,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.purple2.withValues(alpha: .75),
                boxShadow: [
                  BoxShadow(
                      color: theme.purple.withValues(alpha: .22 + pulse * .18),
                      blurRadius: 8 + pulse * 8)
                ])));
  }
}

class _PulseBars extends StatelessWidget {
  const _PulseBars({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) => Row(
          children: List.generate(3, (index) {
        final phase = (progress + index * .22) % 1;
        final height = 6 + (phase < .5 ? phase : 1 - phase) * 18;
        return Container(
            margin: const EdgeInsets.only(left: 3),
            width: 3,
            height: height,
            decoration: BoxDecoration(
                color: theme.purple.withValues(alpha: .28 + phase * .34),
                borderRadius: BorderRadius.circular(999)));
      }));
}
