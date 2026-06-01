import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../../services/asr_model_manager.dart';
import '../../../core/theme/theme.dart' as theme;

class AsrModelDownloadDialog extends StatefulWidget {
  const AsrModelDownloadDialog({super.key, required this.manager});

  final AsrModelManager manager;

  @override
  State<AsrModelDownloadDialog> createState() => _AsrModelDownloadDialogState();
}

class _AsrModelDownloadDialogState extends State<AsrModelDownloadDialog> {
  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    unawaited(widget.manager.ensureReady().then((path) {
      if (mounted) Navigator.of(context).pop(path);
    }).catchError((_) {}));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.manager,
      builder: (context, _) {
        final state = widget.manager.state;
        final failed = state.status == AsrModelStatus.failed;
        final paused = state.status == AsrModelStatus.paused;
        final l10n = AppLocalizations.of(context);
        return AlertDialog(
            backgroundColor: const Color(0xFF111214),
            title: Text(l10n.asrModelDialogTitle,
                style: const TextStyle(color: theme.text, fontSize: 17)),
            content: SizedBox(
                width: 340,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Align(
                      alignment: Alignment.centerLeft,
                      child: Text(_statusLabel(l10n, state),
                          style: const TextStyle(
                              color: theme.muted, fontSize: 13, height: 1.35))),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                      value: state.totalBytes > 0 ? state.progress : null,
                      minHeight: 5,
                      backgroundColor: Colors.white.withValues(alpha: .08),
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(theme.purple)),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                        child: Text(_bytesLabel(state),
                            style: const TextStyle(
                                color: theme.faint, fontSize: 12))),
                    Text(_speedLabel(state),
                        style:
                            const TextStyle(color: theme.faint, fontSize: 12)),
                  ]),
                  if (state.errorMessage != null) ...[
                    const SizedBox(height: 12),
                    SelectableText(state.errorMessage!,
                        style: const TextStyle(
                            color: theme.red, fontSize: 12, height: 1.35)),
                  ],
                  if (state.traceId != null) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                          child: SelectableText(
                              l10n.asrModelTraceId(state.traceId!),
                              style: const TextStyle(
                                  color: theme.muted, fontSize: 12))),
                      TextButton(
                          onPressed: () => Clipboard.setData(
                              ClipboardData(text: state.traceId!)),
                          child: Text(l10n.asrModelCopyAction)),
                    ]),
                  ],
                ])),
            actions: [
              if (state.status == AsrModelStatus.downloading)
                TextButton(
                    onPressed: widget.manager.pause,
                    child: Text(l10n.asrModelPauseAction)),
              if (paused)
                TextButton(
                    onPressed: widget.manager.resume,
                    child: Text(l10n.asrModelResumeAction)),
              if (failed)
                TextButton(
                    onPressed: _start, child: Text(l10n.asrModelRetryAction)),
              TextButton(
                  onPressed: () {
                    widget.manager.cancel();
                    Navigator.of(context).pop();
                  },
                  child: Text(l10n.asrModelCancelAction)),
            ]);
      });

  String _statusLabel(AppLocalizations l10n, AsrModelState state) =>
      switch (state.status) {
        AsrModelStatus.idle => l10n.asrModelPreparing,
        AsrModelStatus.checking => l10n.asrModelChecking,
        AsrModelStatus.downloading =>
          l10n.asrModelDownloading(state.version ?? l10n.asrModelFallbackName),
        AsrModelStatus.paused => l10n.asrModelPaused,
        AsrModelStatus.verifying => l10n.asrModelVerifying,
        AsrModelStatus.extracting => l10n.asrModelExtracting,
        AsrModelStatus.ready => l10n.asrModelReady,
        AsrModelStatus.failed => l10n.asrModelFailed,
        AsrModelStatus.cancelled => l10n.asrModelCancelled,
      };

  String _bytesLabel(AsrModelState state) {
    if (state.totalBytes <= 0) {
      return AppLocalizations.of(context).asrModelWaitingSize;
    }
    return '${_formatBytes(state.downloadedBytes)} / ${_formatBytes(state.totalBytes)}';
  }

  String _speedLabel(AsrModelState state) {
    if (state.speedBytesPerSecond <= 0 ||
        state.status != AsrModelStatus.downloading) {
      return '';
    }
    return '${_formatBytes(state.speedBytesPerSecond.round())}/s';
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }
}
