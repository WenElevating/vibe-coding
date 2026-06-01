import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart' as theme;

class SettingsRow extends StatelessWidget {
  const SettingsRow({super.key, required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(children: [
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
        ])),
        Text(value,
            style: const TextStyle(
                color: theme.muted, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class SettingsTapRow extends StatelessWidget {
  const SettingsTapRow({
    super.key,
    required this.title,
    this.value,
    required this.onTap,
  });

  final String title;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    return InkWell(
        onTap: onTap,
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(children: [
              Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w800))),
              SettingsTapRowTrailing(value: value),
            ])));
  }
}

class SettingsTapRowTrailing extends StatelessWidget {
  const SettingsTapRowTrailing({super.key, required this.value});

  final String? value;

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        if (value != null && value!.isNotEmpty) ...[
          ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      color: theme.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700))),
          const SizedBox(width: 6),
        ],
        const Icon(Icons.chevron_right_rounded, color: theme.faint, size: 18),
      ]);
}
