import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart' as theme;
import '../../../core/widgets/widgets.dart';

class VoiceInputErrorDialog extends StatelessWidget {
  const VoiceInputErrorDialog({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
      child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.fromLTRB(18, 17, 18, 16),
          decoration: BoxDecoration(
              color: const Color(0xFF111214),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: .10)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: .48),
                    blurRadius: 28,
                    offset: const Offset(0, 18))
              ]),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                      color: theme.amber.withValues(alpha: .12),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: theme.amber.withValues(alpha: .28))),
                  child: const Icon(Icons.mic_off_rounded,
                      color: theme.amber, size: 18)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const Text('语音输入不可用',
                        style: TextStyle(
                            color: theme.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            height: 1.25)),
                    const SizedBox(height: 7),
                    Text(message,
                        style: const TextStyle(
                            color: theme.muted, fontSize: 13, height: 1.45))
                  ]))
            ]),
            const SizedBox(height: 18),
            Align(
                alignment: Alignment.centerRight,
                child: TinyActionButton('知道了',
                    primary: true, onTap: () => Navigator.of(context).pop()))
          ])));
}
