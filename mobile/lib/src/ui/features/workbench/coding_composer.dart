import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../models/protocol.dart';
import '../../core/theme/theme.dart' as theme;
import 'attachments/draft_attachment.dart';
import 'composer/attachment_tray.dart';
import 'composer/composer_controls.dart';
import 'composer/slash_command_menu.dart';
import 'voice_input.dart';

export 'composer/composer_controls.dart' show ComposerWorkspaceCloud;

const _codexComposerBackground = Color(0xFF151515);
const _codexComposerSurface = Color(0xFF2D2D2D);
const _codexComposerSurfaceBorder = Color(0xFF333333);

class CodingComposer extends StatefulWidget {
  const CodingComposer(
      {super.key,
      required this.controller,
      required this.adapter,
      required this.workspace,
      required this.running,
      required this.canSend,
      required this.sending,
      required this.voiceState,
      required this.voiceEnabled,
      required this.voiceError,
      required this.cliLocked,
      required this.modelLocked,
      this.model,
      this.modelNotice,
      this.draftAttachments = const <DraftAttachment>[],
      this.slashCommands = const <SlashCommand>[],
      this.onSlashCommandSelected,
      this.onAttachmentTap,
      this.onRemoveAttachment,
      required this.onCliTap,
      required this.onModelTap,
      required this.onVoiceStart,
      required this.onVoiceStop,
      required this.onVoiceCancel,
      required this.onTextChanged,
      required this.onSend,
      required this.onCancel});

  final TextEditingController controller;
  final String? adapter;
  final WorkspaceSummary workspace;
  final bool running;
  final bool canSend;
  final bool sending;
  final VoiceInputState voiceState;
  final bool voiceEnabled;
  final String? voiceError;
  final bool cliLocked;
  final bool modelLocked;
  final String? model;
  final String? modelNotice;
  final List<DraftAttachment> draftAttachments;
  final List<SlashCommand> slashCommands;
  final ValueChanged<SlashCommand>? onSlashCommandSelected;
  final VoidCallback? onAttachmentTap;
  final ValueChanged<int>? onRemoveAttachment;
  final VoidCallback onCliTap;
  final VoidCallback onModelTap;
  final VoidCallback onVoiceStart;
  final VoidCallback onVoiceStop;
  final VoidCallback onVoiceCancel;
  final ValueChanged<String> onTextChanged;
  final VoidCallback onSend;
  final VoidCallback onCancel;

  @override
  State<CodingComposer> createState() => _CodingComposerState();
}

class _CodingComposerState extends State<CodingComposer>
    with WidgetsBindingObserver {
  final _slashMenuController = OverlayPortalController();
  final _promptFocusNode = FocusNode();
  final _surfaceKey = GlobalKey();
  double _lastViewInsetBottom = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _promptFocusNode.addListener(_syncSlashMenuOverlay);
    _syncSlashMenuOverlay();
  }

  @override
  void didUpdateWidget(covariant CodingComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slashCommands.isEmpty != widget.slashCommands.isEmpty) {
      _syncSlashMenuOverlay();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _promptFocusNode.removeListener(_syncSlashMenuOverlay);
    _promptFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final insetBottom = _viewInsetBottom(context);
      final keyboardDismissed = _lastViewInsetBottom > 0 &&
          insetBottom <= 0 &&
          _promptFocusNode.hasFocus;
      _lastViewInsetBottom = insetBottom;
      if (keyboardDismissed) {
        _promptFocusNode.unfocus();
      }
      _syncSlashMenuOverlay();
      if (_slashMenuController.isShowing) {
        setState(() {});
      }
    });
  }

  void _syncSlashMenuOverlay() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _lastViewInsetBottom = _viewInsetBottom(context);
      if (widget.slashCommands.isEmpty || !_promptFocusNode.hasFocus) {
        _slashMenuController.hide();
      } else {
        _slashMenuController.show();
      }
    });
  }

  double _viewInsetBottom(BuildContext context) {
    final view = View.maybeOf(context);
    if (view == null) return MediaQuery.viewInsetsOf(context).bottom;
    return view.viewInsets.bottom / view.devicePixelRatio;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final attachmentStatus =
        firstLocalizedAttachmentError(context, widget.draftAttachments);
    return OverlayPortal(
        controller: _slashMenuController,
        overlayLocation: OverlayChildLocation.rootOverlay,
        overlayChildBuilder: _buildSlashMenuOverlay,
        child: _buildComposerSurface(context,
            l10n: l10n, attachmentStatus: attachmentStatus));
  }

  Widget _buildSlashMenuOverlay(BuildContext context) {
    final renderObject = _surfaceKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.hasSize ||
        widget.slashCommands.isEmpty) {
      return const SizedBox.shrink();
    }
    final offset = renderObject.localToGlobal(Offset.zero);
    final width = math.max(0.0, renderObject.size.width - 24);
    final menuHeight =
        WorkbenchSlashCommandMenu.heightFor(widget.slashCommands.length);
    final top = math.max(0.0, offset.dy - menuHeight - 8);
    return Positioned(
        left: offset.dx + 12,
        top: top,
        width: width,
        height: menuHeight,
        child: WorkbenchSlashCommandMenu(
            commands: widget.slashCommands,
            onSelected: widget.onSlashCommandSelected));
  }

  Widget _buildComposerSurface(
    BuildContext context, {
    required AppLocalizations l10n,
    required String? attachmentStatus,
  }) {
    return Container(
        key: _surfaceKey,
        padding: const EdgeInsets.fromLTRB(29, 8, 29, 4),
        decoration: const BoxDecoration(color: _codexComposerBackground),
        child: SafeArea(
            top: false,
            child: Container(
                padding: const EdgeInsets.fromLTRB(13, 10, 9, 8),
                decoration: BoxDecoration(
                    color: _codexComposerSurface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _codexComposerSurfaceBorder)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (widget.draftAttachments.isNotEmpty) ...[
                    WorkbenchAttachmentTray(
                        attachments: widget.draftAttachments,
                        onRemove: widget.onRemoveAttachment),
                    if (attachmentStatus != null) ...[
                      const SizedBox(height: 7),
                      WorkbenchAttachmentStatus(attachmentStatus),
                    ],
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: widget.controller,
                    focusNode: _promptFocusNode,
                    minLines: 1,
                    maxLines: 3,
                    style: theme.appTextStyle.copyWith(
                        color: theme.text,
                        fontSize: 15,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0),
                    decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: widget.adapter == null
                            ? l10n.workbenchComposerNoAdapter
                            : widget.running
                                ? l10n.workbenchComposerFollowUpHint
                                : widget.draftAttachments.isNotEmpty
                                    ? l10n.workbenchAttachmentAddInstruction
                                    : l10n.workbenchComposerPromptHint,
                        hintStyle: theme.appTextStyle.copyWith(
                            color: const Color(0xFF8C8C8C),
                            fontSize: 14.5,
                            fontWeight: FontWeight.w400),
                        contentPadding: EdgeInsets.zero),
                    textInputAction: TextInputAction.send,
                    onChanged: widget.onTextChanged,
                    onSubmitted: (_) {
                      if (widget.canSend) widget.onSend();
                    },
                  ),
                  if (widget.voiceState == VoiceInputState.initializing ||
                      widget.voiceState == VoiceInputState.listening ||
                      widget.voiceState == VoiceInputState.stopping) ...[
                    const SizedBox(height: 8),
                    VoiceInputStatus(l10n.workbenchVoiceListeningStatus),
                  ],
                  if (widget.modelNotice != null &&
                      widget.modelNotice!.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Align(
                        alignment: Alignment.centerLeft,
                        child: Text(widget.modelNotice!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: theme.muted,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500))),
                  ],
                  const SizedBox(height: 8),
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Flexible(
                        child: Align(
                            alignment: Alignment.centerLeft,
                            child: InkWell(
                                key: const ValueKey('composer-model-pill'),
                                onTap: widget.modelLocked
                                    ? null
                                    : widget.onModelTap,
                                borderRadius: BorderRadius.circular(999),
                                child: ComposerModelPill(
                                    model: widget.model,
                                    locked: widget.modelLocked)))),
                    const SizedBox(width: 8),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Tooltip(
                          message: l10n.workbenchAttachmentAddTooltip,
                          child: InkWell(
                              onTap: widget.running || widget.sending
                                  ? null
                                  : widget.onAttachmentTap,
                              borderRadius: BorderRadius.circular(16),
                              child: const SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: Center(
                                      child:
                                          ComposerIcon(Icons.add_rounded))))),
                      const SizedBox(width: 12),
                      VoiceInputButton(
                          state: widget.voiceState,
                          enabled: widget.voiceEnabled &&
                              !widget.running &&
                              !widget.sending,
                          onStart: widget.onVoiceStart,
                          onStop: widget.onVoiceStop,
                          onCancel: widget.onVoiceCancel),
                      const SizedBox(width: 12),
                      SendPromptButton(
                          key: const ValueKey('workbench-send-prompt-button'),
                          enabled: widget.canSend,
                          busy: widget.sending,
                          running: widget.running,
                          onTap: widget.running
                              ? widget.onCancel
                              : (widget.canSend ? widget.onSend : null)),
                    ]),
                  ])
                ]))));
  }
}
