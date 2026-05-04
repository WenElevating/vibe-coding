part of '../../app/app.dart';

class _CodingComposer extends StatelessWidget {
  const _CodingComposer(
      {required this.controller,
      required this.adapter,
      required this.workspace,
      required this.running,
      required this.canSend,
      required this.sending,
      required this.onModelTap,
      required this.onSend,
      required this.onCancel});
  final TextEditingController controller;
  final String? adapter;
  final WorkspaceSummary workspace;
  final bool running;
  final bool canSend;
  final bool sending;
  final VoidCallback onModelTap;
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
                  style: _appTextStyle.copyWith(
                      color: _text,
                      fontSize: 15,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0),
                  decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: adapter == null
                          ? '没有可用 CLI adapter'
                          : running
                              ? '要求后续变更…'
                              : 'Add feedback...',
                      hintStyle: _appTextStyle.copyWith(
                          color: _faint,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w400),
                      contentPadding: EdgeInsets.zero),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) {
                    if (canSend) onSend();
                  },
                ),
                const SizedBox(height: 8),
                Row(children: [
                  InkWell(
                      onTap: running ? null : onModelTap,
                      borderRadius: BorderRadius.circular(999),
                      child: _ComposerModelPill(adapter: adapter)),
                  const Spacer(),
                  const _ComposerIcon(Icons.add_rounded),
                  const SizedBox(width: 12),
                  const _ComposerIcon(Icons.keyboard_command_key_rounded),
                  const SizedBox(width: 12),
                  _SendPromptButton(
                      enabled: canSend,
                      busy: sending,
                      running: running,
                      onTap: running ? onCancel : (canSend ? onSend : null)),
                ])
              ]))));
}

class _ComposerWorkspaceCloud extends StatelessWidget {
  const _ComposerWorkspaceCloud(
      {required this.workspace, required this.running, required this.onTap});
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
                            color: _muted, size: 16),
                        const SizedBox(width: 10),
                        Text(_workspaceDisplayName(workspace),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: _muted,
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
                    color:
                        active ? Colors.white.withValues(alpha: .18) : _stroke),
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
                            valueColor: AlwaysStoppedAnimation<Color>(
                                active ? const Color(0xFF08090B) : _faint)))
                    : running
                        ? Icon(Icons.stop_rounded,
                            color: active ? const Color(0xFF08090B) : _faint,
                            size: 17)
                        : _SendGlyph(
                            color:
                                active ? const Color(0xFF08090B) : _faint))));
  }
}

class _ComposerModelPill extends StatelessWidget {
  const _ComposerModelPill({required this.adapter});
  final String? adapter;

  @override
  Widget build(BuildContext context) => Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
          color: const Color(0xFF111214),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: .075))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.code_rounded, color: _muted, size: 14),
        const SizedBox(width: 7),
        Text(adapter ?? 'CLI',
            style: const TextStyle(
                color: _text,
                fontSize: 11.5,
                fontFamily: 'Consolas',
                fontWeight: FontWeight.w800)),
      ]));
}

class _ComposerIcon extends StatelessWidget {
  const _ComposerIcon(this.icon);
  final IconData icon;

  @override
  Widget build(BuildContext context) => Icon(icon, color: _muted, size: 19);
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

RunSummary _runSummaryFromConversation(ConversationSummary conversation) {
  return RunSummary(
      id: conversation.id,
      tool: conversation.adapter,
      workspaceId: conversation.workspaceId,
      status: _runStatusFromConversation(conversation.status),
      cliSessionId: conversation.cliSessionId);
}
