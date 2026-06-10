import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart' as theme;
import '../../../core/widgets/widgets.dart';
import '../voice_input.dart';

class VoiceInputErrorDialog extends StatelessWidget {
  const VoiceInputErrorDialog({super.key, required this.kind});

  final VoiceInputErrorKind kind;

  @override
  Widget build(BuildContext context) {
    final copy = voiceInputErrorCopy(context, kind);
    return Dialog(
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
                      Text(copy.title,
                          style: const TextStyle(
                              color: theme.text,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              height: 1.25)),
                      const SizedBox(height: 7),
                      Text(copy.message,
                          style: const TextStyle(
                              color: theme.muted, fontSize: 13, height: 1.45))
                    ]))
              ]),
              const SizedBox(height: 18),
              Align(
                  alignment: Alignment.centerRight,
                  child: TinyActionButton(copy.actionLabel,
                      primary: true,
                      onTap: () => Navigator.of(context).pop()))
            ])));
  }
}

({String title, String message, String actionLabel}) voiceInputErrorCopy(
  BuildContext context,
  VoiceInputErrorKind kind,
) {
  final language = Localizations.localeOf(context).languageCode.toLowerCase();
  final zh = language == 'zh';
  final title = zh ? '语音输入不可用' : 'Voice input unavailable';
  final actionLabel = zh ? '知道了' : 'OK';
  final message = switch (kind) {
    VoiceInputErrorKind.unavailable => zh
        ? '语音输入暂时不可用，请稍后重试。'
        : 'Voice input is temporarily unavailable. Try again later.',
    VoiceInputErrorKind.noRecordingDevice => zh
        ? '未检测到可用麦克风，请连接或启用录音设备后重试。'
        : 'No microphone was detected. Connect or enable a recording device, then try again.',
    VoiceInputErrorKind.permissionDenied => zh
        ? '麦克风权限未开启，请允许访问麦克风后重试。'
        : 'Microphone permission is disabled. Allow microphone access, then try again.',
    VoiceInputErrorKind.generic => zh
        ? '语音输入暂时不可用，请检查麦克风权限或设备状态后重试。'
        : 'Voice input is temporarily unavailable. Check microphone permission or device status, then try again.',
  };
  return (title: title, message: message, actionLabel: actionLabel);
}
