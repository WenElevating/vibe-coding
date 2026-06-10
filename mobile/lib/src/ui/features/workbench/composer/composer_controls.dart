import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../../models/protocol.dart';
import '../../../core/theme/theme.dart' as theme;
import '../../workspace_picker/workspace_display.dart';
import '../voice_input.dart';

const _codexComposerBackground = Color(0xFF151515);
const _codexComposerPill = Color(0xFF252525);

class ComposerWorkspaceCloud extends StatelessWidget {
  const ComposerWorkspaceCloud(
      {super.key,
      required this.workspace,
      required this.adapter,
      required this.running,
      required this.cliLocked,
      required this.onCliTap,
      required this.onTap});

  final WorkspaceSummary workspace;
  final String? adapter;
  final bool running;
  final bool cliLocked;
  final VoidCallback onCliTap;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
      width: double.infinity,
      decoration: const BoxDecoration(color: _codexComposerBackground),
      padding: const EdgeInsets.fromLTRB(23, 3, 18, 7),
      child: SafeArea(
          top: false,
          child: Row(children: [
            Expanded(
                child: Align(
                    alignment: Alignment.centerLeft,
                    child: InkWell(
                        key: const ValueKey('composer-cli-picker'),
                        onTap: cliLocked ? null : onCliTap,
                        borderRadius: BorderRadius.circular(999),
                        child: _ComposerCliLabel(
                            adapter: adapter, locked: cliLocked)))),
            const SizedBox(width: 10),
            InkWell(
                onTap: running ? null : onTap,
                borderRadius: BorderRadius.circular(999),
                child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.cloud_outlined,
                          color: theme.muted, size: 16),
                      const SizedBox(width: 10),
                      ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 168),
                          child: Text(
                              workspaceDisplayName(workspace,
                                  fallbackName: AppLocalizations.of(context)
                                      .workspaceCurrentFallback),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: theme.muted,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500))),
                    ]))),
          ])));
}

class SendPromptButton extends StatelessWidget {
  const SendPromptButton(
      {super.key,
      required this.enabled,
      required this.busy,
      required this.running,
      required this.onTap});

  final bool enabled;
  final bool busy;
  final bool running;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final active = enabled || running;
    final glow =
        active ? Colors.white.withValues(alpha: .10) : Colors.transparent;
    return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                gradient: active
                    ? const LinearGradient(
                        colors: [Color(0xFFF7F7F7), Color(0xFFE8E8E8)])
                    : const LinearGradient(
                        colors: [Color(0xFF141518), Color(0xFF101113)]),
                shape: BoxShape.circle,
                border: Border.all(
                    color: active
                        ? Colors.white.withValues(alpha: .18)
                        : theme.stroke),
                boxShadow: [
                  BoxShadow(
                      color: glow,
                      blurRadius: active ? 14 : 0,
                      spreadRadius: -7,
                      offset: const Offset(0, 6)),
                ]),
            child: Center(
                child: busy
                    ? SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            valueColor: AlwaysStoppedAnimation<Color>(active
                                ? const Color(0xFF08090B)
                                : theme.faint)))
                    : running
                        ? Icon(Icons.stop_rounded,
                            color:
                                active ? const Color(0xFF08090B) : theme.faint,
                            size: 17)
                        : SendGlyph(
                            color: active
                                ? const Color(0xFF08090B)
                                : theme.faint))));
  }
}

class ComposerModelPill extends StatelessWidget {
  const ComposerModelPill(
      {super.key, required this.model, required this.locked});

  final String? model;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final label =
        model ?? AppLocalizations.of(context).workbenchComposerDefaultModel;
    return _ComposerPillShell(
        locked: locked,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.memory_rounded,
              color: locked ? theme.faint : theme.muted, size: 14),
          const SizedBox(width: 7),
          Flexible(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 126),
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: locked ? theme.muted : theme.text,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700)))),
        ]));
  }
}

class ComposerIcon extends StatelessWidget {
  const ComposerIcon(this.icon, {super.key});

  final IconData icon;

  @override
  Widget build(BuildContext context) =>
      Icon(icon, color: theme.muted, size: 19);
}

class VoiceInputButton extends StatelessWidget {
  const VoiceInputButton(
      {super.key,
      required this.state,
      required this.enabled,
      required this.onStart,
      required this.onStop,
      required this.onCancel});

  final VoiceInputState state;
  final bool enabled;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onCancel;

  bool get _active =>
      state == VoiceInputState.initializing ||
      state == VoiceInputState.listening ||
      state == VoiceInputState.stopping;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
        label: l10n.workbenchVoiceInputSemantics,
        button: true,
        enabled: enabled,
        child: GestureDetector(
            onTap: enabled ? (_active ? onStop : onStart) : null,
            onLongPressStart: enabled ? (_) => onStart() : null,
            onLongPressEnd: enabled ? (_) => onStop() : null,
            onLongPressCancel: enabled ? onCancel : null,
            child: Tooltip(
                message: enabled
                    ? l10n.workbenchVoiceInputEnabledTooltip
                    : l10n.workbenchVoiceInputUnavailableTooltip,
                child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                        color: _active
                            ? theme.purple.withValues(alpha: .18)
                            : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color:
                                _active ? theme.purple : Colors.transparent)),
                    child: Icon(
                        _active ? Icons.mic_rounded : Icons.mic_none_rounded,
                        color: enabled ? theme.muted : theme.faint,
                        size: 19)))));
  }
}

class VoiceInputStatus extends StatelessWidget {
  const VoiceInputStatus(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Row(children: [
        const Icon(Icons.graphic_eq_rounded, color: theme.muted, size: 14),
        const SizedBox(width: 7),
        Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: theme.muted, fontSize: 12)))
      ]);
}

class _ComposerCliLabel extends StatelessWidget {
  const _ComposerCliLabel({required this.adapter, required this.locked});

  final String? adapter;
  final bool locked;

  @override
  Widget build(BuildContext context) => Opacity(
      opacity: locked ? .58 : 1,
      child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.terminal_rounded,
                color: locked ? theme.faint : theme.muted, size: 16),
            const SizedBox(width: 10),
            Flexible(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 168),
                    child: Text(adapter ?? 'CLI',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: theme.muted,
                            fontSize: 12.5,
                            fontFamily: 'Consolas',
                            fontWeight: FontWeight.w800)))),
          ])));
}

class _ComposerPillShell extends StatelessWidget {
  const _ComposerPillShell({required this.locked, required this.child});

  final bool locked;
  final Widget child;

  @override
  Widget build(BuildContext context) => Opacity(
      opacity: locked ? .58 : 1,
      child: Container(
          height: 28,
          constraints: const BoxConstraints(maxWidth: 168),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
              color: _codexComposerPill,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFF383838))),
          child: child));
}

class SendGlyph extends StatelessWidget {
  const SendGlyph({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(14, 14), painter: _SendGlyphPainter(color));
}

class _SendGlyphPainter extends CustomPainter {
  const _SendGlyphPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.65
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(size.width * .50, size.height * .82)
      ..lineTo(size.width * .50, size.height * .20)
      ..moveTo(size.width * .24, size.height * .45)
      ..lineTo(size.width * .50, size.height * .20)
      ..lineTo(size.width * .76, size.height * .45);
    canvas.drawPath(path, paint);
    final railPaint = Paint()
      ..color = color.withValues(alpha: .42)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(size.width * .27, size.height * .86),
        Offset(size.width * .73, size.height * .86), railPaint);
  }

  @override
  bool shouldRepaint(covariant _SendGlyphPainter oldDelegate) =>
      oldDelegate.color != color;
}
