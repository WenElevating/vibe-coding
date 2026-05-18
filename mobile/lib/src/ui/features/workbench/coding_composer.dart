import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../models/protocol.dart';
import '../../core/theme/theme.dart' as theme;
import '../workspace_picker/workspace_picker.dart';
import 'voice_input.dart';

class CodingComposer extends StatelessWidget {
  const CodingComposer(
      {super.key,
      required this.controller,
      required this.adapter,
      required this.workspace,
      required this.running,
      required this.canSend,
      required this.sending,
      required this.voiceState,
      required this.voiceEnabled,
      required this.voiceError,
      required this.cliLocked,
      required this.modelLocked,
      this.model,
      this.modelNotice,
      required this.onCliTap,
      required this.onModelTap,
      required this.onVoiceStart,
      required this.onVoiceStop,
      required this.onVoiceCancel,
      required this.onTextChanged,
      required this.onSend,
      required this.onCancel});
  final TextEditingController controller;
  final String? adapter;
  final WorkspaceSummary workspace;
  final bool running;
  final bool canSend;
  final bool sending;
  final VoiceInputState voiceState;
  final bool voiceEnabled;
  final String? voiceError;
  final bool cliLocked;
  final bool modelLocked;
  final String? model;
  final String? modelNotice;
  final VoidCallback onCliTap;
  final VoidCallback onModelTap;
  final VoidCallback onVoiceStart;
  final VoidCallback onVoiceStop;
  final VoidCallback onVoiceCancel;
  final ValueChanged<String> onTextChanged;
  final VoidCallback onSend;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      decoration: BoxDecoration(
          color: const Color(0xF608090B),
          border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: .06))),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: .28),
                blurRadius: 24,
                offset: const Offset(0, -10))
          ]),
      child: SafeArea(
          top: false,
          child: Container(
              padding: const EdgeInsets.fromLTRB(13, 9, 8, 7),
              decoration: BoxDecoration(
                  color: const Color(0xFF161719),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: .085))),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 3,
                  style: theme.appTextStyle.copyWith(
                      color: theme.text,
                      fontSize: 15,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0),
                  decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: adapter == null
                          ? AppLocalizations.of(context)
                              .workbenchComposerNoAdapter
                          : running
                              ? AppLocalizations.of(context)
                                  .workbenchComposerFollowUpHint
                              : 'Add feedback...',
                      hintStyle: theme.appTextStyle.copyWith(
                          color: theme.faint,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w400),
                      contentPadding: EdgeInsets.zero),
                  textInputAction: TextInputAction.send,
                  onChanged: onTextChanged,
                  onSubmitted: (_) {
                    if (canSend) onSend();
                  },
                ),
                if (voiceState == VoiceInputState.initializing ||
                    voiceState == VoiceInputState.listening ||
                    voiceState == VoiceInputState.stopping) ...[
                  const SizedBox(height: 8),
                  const _VoiceInputStatus('Listening… release to finish'),
                ],
                if (modelNotice != null && modelNotice!.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                      alignment: Alignment.centerLeft,
                      child: Text(modelNotice!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: theme.muted,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500))),
                ],
                const SizedBox(height: 8),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Flexible(
                      child: Wrap(spacing: 8, runSpacing: 6, children: [
                    InkWell(
                        onTap: cliLocked ? null : onCliTap,
                        borderRadius: BorderRadius.circular(999),
                        child: _ComposerCliPill(
                            adapter: adapter, locked: cliLocked)),
                    InkWell(
                        onTap: modelLocked ? null : onModelTap,
                        borderRadius: BorderRadius.circular(999),
                        child: _ComposerModelPill(
                            model: model, locked: modelLocked)),
                  ])),
                  const SizedBox(width: 8),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const _ComposerIcon(Icons.add_rounded),
                    const SizedBox(width: 12),
                    _VoiceInputButton(
                        state: voiceState,
                        enabled: voiceEnabled && !running && !sending,
                        onStart: onVoiceStart,
                        onStop: onVoiceStop,
                        onCancel: onVoiceCancel),
                    const SizedBox(width: 12),
                    _SendPromptButton(
                        enabled: canSend,
                        busy: sending,
                        running: running,
                        onTap: running ? onCancel : (canSend ? onSend : null)),
                  ]),
                ])
              ]))));
}

class ComposerWorkspaceCloud extends StatelessWidget {
  const ComposerWorkspaceCloud(
      {super.key,
      required this.workspace,
      required this.running,
      required this.onTap});
  final WorkspaceSummary workspace;
  final bool running;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
      width: double.infinity,
      color: const Color(0xF608090B),
      padding: const EdgeInsets.fromLTRB(23, 0, 28, 7),
      child: SafeArea(
          top: false,
          child: Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                  onTap: running ? null : onTap,
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 4),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.cloud_outlined,
                            color: theme.muted, size: 16),
                        const SizedBox(width: 10),
                        Text(workspaceDisplayName(workspace),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: theme.muted,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500)),
                      ]))))));
}

class _SendPromptButton extends StatelessWidget {
  const _SendPromptButton(
      {required this.enabled,
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
                        : _SendGlyph(
                            color: active
                                ? const Color(0xFF08090B)
                                : theme.faint))));
  }
}

class _ComposerCliPill extends StatelessWidget {
  const _ComposerCliPill({required this.adapter, required this.locked});
  final String? adapter;
  final bool locked;

  @override
  Widget build(BuildContext context) => _ComposerPillShell(
      locked: locked,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.terminal_rounded,
            color: locked ? theme.faint : theme.muted, size: 14),
        const SizedBox(width: 7),
        ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 126),
            child: Text(adapter ?? 'CLI',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: locked ? theme.muted : theme.text,
                    fontSize: 11.5,
                    fontFamily: 'Consolas',
                    fontWeight: FontWeight.w800))),
      ]));
}

class _ComposerModelPill extends StatelessWidget {
  const _ComposerModelPill({required this.model, required this.locked});
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
          ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 126),
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: locked ? theme.muted : theme.text,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700))),
        ]));
  }
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
              color: const Color(0xFF111214),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: .075))),
          child: child));
}

class _ComposerIcon extends StatelessWidget {
  const _ComposerIcon(this.icon);
  final IconData icon;

  @override
  Widget build(BuildContext context) =>
      Icon(icon, color: theme.muted, size: 19);
}

class _VoiceInputButton extends StatelessWidget {
  const _VoiceInputButton(
      {required this.state,
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
  Widget build(BuildContext context) => Semantics(
      label: 'Voice input',
      button: true,
      enabled: enabled,
      child: GestureDetector(
          onTap: enabled ? (_active ? onStop : onStart) : null,
          onLongPressStart: enabled ? (_) => onStart() : null,
          onLongPressEnd: enabled ? (_) => onStop() : null,
          onLongPressCancel: enabled ? onCancel : null,
          child: Tooltip(
              message: enabled
                  ? 'Tap or hold to speak'
                  : 'Voice input is not available on this platform yet.',
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
                          color: _active ? theme.purple : Colors.transparent)),
                  child: Icon(
                      _active ? Icons.mic_rounded : Icons.mic_none_rounded,
                      color: enabled ? theme.muted : theme.faint,
                      size: 19)))));
}

class _VoiceInputStatus extends StatelessWidget {
  const _VoiceInputStatus(this.text);

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

class _SendGlyph extends StatelessWidget {
  const _SendGlyph({required this.color});
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
