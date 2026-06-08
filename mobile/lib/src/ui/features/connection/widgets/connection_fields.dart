import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart' as theme;

class ConnectionSection extends StatelessWidget {
  const ConnectionSection({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 9),
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                color: theme.faint,
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
          child,
        ],
      );
}

class ConnectionTextField extends StatelessWidget {
  const ConnectionTextField({
    super.key,
    required this.controller,
    this.focusNode,
    this.onTap,
    required this.enabled,
    required this.hintText,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final VoidCallback? onTap;
  final bool enabled;
  final String hintText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        onTap: onTap,
        onChanged: onChanged,
        style: const TextStyle(
          color: theme.text,
          fontSize: 15,
          fontWeight: FontWeight.w700,
          fontFamily: 'Consolas',
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(color: theme.faint, fontSize: 13),
          filled: true,
          fillColor: const Color(0xFF0D0F12),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: _border(Colors.white.withValues(alpha: .07)),
          enabledBorder: _border(Colors.white.withValues(alpha: .07)),
          focusedBorder: _border(theme.activeStroke),
          disabledBorder: _border(Colors.white.withValues(alpha: .055)),
        ),
      );

  OutlineInputBorder _border(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color),
      );
}
