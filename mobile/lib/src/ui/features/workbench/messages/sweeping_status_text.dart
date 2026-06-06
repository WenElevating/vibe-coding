import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart' as theme;

class SweepingStatusText extends StatefulWidget {
  const SweepingStatusText({
    super.key,
    required this.text,
    this.running = true,
    this.duration = const Duration(milliseconds: 2400),
    this.style,
    this.baseColor,
    this.highlightColor,
    this.highlightFraction = .16,
    this.progressKey,
  });

  final String text;
  final bool running;
  final Duration duration;
  final TextStyle? style;
  final Color? baseColor;
  final Color? highlightColor;
  final double highlightFraction;
  final Key? progressKey;

  @override
  State<SweepingStatusText> createState() => _SweepingStatusTextState();
}

class _SweepingStatusTextState extends State<SweepingStatusText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.duration);

  @override
  void initState() {
    super.initState();
    if (widget.running) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant SweepingStatusText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
    if (widget.running && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.running && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final baseStyle = (widget.style ??
            const TextStyle(
                fontSize: 12.8, height: 1.2, fontWeight: FontWeight.w800))
        .copyWith(color: widget.baseColor ?? theme.faint);
    if (!widget.running || reduceMotion) {
      return Text(widget.text,
          maxLines: 1, overflow: TextOverflow.ellipsis, style: baseStyle);
    }
    final highlightStyle =
        baseStyle.copyWith(color: widget.highlightColor ?? Colors.white);
    return ClipRect(
        child: LayoutBuilder(
            builder: (context, constraints) => Stack(children: [
                  Text(widget.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: baseStyle),
                  AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) {
                        final width = constraints.maxWidth.isFinite
                            ? constraints.maxWidth
                            : 260.0;
                        final bandWidth =
                            width * widget.highlightFraction.clamp(.12, .18);
                        final x = -bandWidth +
                            (width + bandWidth * 2) * _controller.value;
                        return Stack(children: [
                          if (widget.progressKey != null)
                            SizedBox(
                                key: widget.progressKey,
                                width: _controller.value,
                                height: 0),
                          ClipRect(
                              clipper:
                                  _HighlightClipper(left: x, width: bandWidth),
                              child: Text(widget.text,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: highlightStyle)),
                        ]);
                      }),
                ])));
  }
}

class _HighlightClipper extends CustomClipper<Rect> {
  const _HighlightClipper({required this.left, required this.width});

  final double left;
  final double width;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(left, 0, width.clamp(0, size.width), size.height);

  @override
  bool shouldReclip(covariant _HighlightClipper oldClipper) =>
      oldClipper.left != left || oldClipper.width != width;
}
