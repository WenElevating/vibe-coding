import 'package:flutter/material.dart';

class ConnectionActionButton extends StatelessWidget {
  const ConnectionActionButton(
    this.text, {
    super.key,
    required this.enabled,
    required this.onTap,
  });

  final String text;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final backgroundColor =
        enabled ? const Color(0xFFE3E6EA) : const Color(0xFF333941);
    final foregroundColor =
        enabled ? const Color(0xFF080A0D) : const Color(0xFF888F98);

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: .12)),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: foregroundColor,
            fontSize: 13.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}
