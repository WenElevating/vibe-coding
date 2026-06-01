import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart' as theme;

class MiniInput extends StatelessWidget {
  const MiniInput({
    super.key,
    required this.controller,
    required this.hint,
    this.icon,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String hint;
  final IconData? icon;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => TextField(
      controller: controller,
      autofocus: autofocus,
      style: theme.appTextStyle.copyWith(color: theme.text, fontSize: 12.5),
      decoration: InputDecoration(
          isDense: true,
          prefixIcon:
              icon == null ? null : Icon(icon, color: theme.faint, size: 16),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 38, minHeight: 38),
          hintText: hint,
          hintStyle:
              theme.appTextStyle.copyWith(color: theme.faint, fontSize: 12.5),
          filled: true,
          fillColor: const Color(0xFF151A20),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: .1))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: .1))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide(
                  color: theme.activeStroke.withValues(alpha: .85),
                  width: 1.2)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 11, vertical: 11)));
}
