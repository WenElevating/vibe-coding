import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart' as theme;
import '../models/home_command_deck_model.dart';

class HomeStatusGlyph extends StatelessWidget {
  const HomeStatusGlyph({super.key, required this.kind, this.small = false});

  final HomeSignalKind kind;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final color = homeSignalColor(kind);
    final size = small ? 28.0 : 36.0;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(small ? 10 : 13),
        border: Border.all(color: color.withValues(alpha: .24)),
      ),
      child: Icon(homeSignalIcon(kind), color: color, size: small ? 15 : 19),
    );
  }
}

IconData homeSignalIcon(HomeSignalKind kind) => switch (kind) {
      HomeSignalKind.approval => Icons.rule_rounded,
      HomeSignalKind.failure => Icons.error_outline_rounded,
      HomeSignalKind.running => Icons.play_arrow_rounded,
      HomeSignalKind.queue => Icons.queue_rounded,
      HomeSignalKind.idle => Icons.check_rounded,
    };

Color homeSignalColor(HomeSignalKind kind) => switch (kind) {
      HomeSignalKind.approval => theme.amber,
      HomeSignalKind.failure => theme.red,
      HomeSignalKind.running => theme.green,
      HomeSignalKind.queue => theme.purple,
      HomeSignalKind.idle => theme.muted,
    };
