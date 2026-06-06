import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../models/protocol.dart';
import '../../core/theme/theme.dart' as theme;
import '../workspace_picker/workspace_picker.dart';
import 'attachments/draft_attachment.dart';
import 'voice_input.dart';

const _codexComposerBackground = Color(0xFF151515);
const _codexComposerSurface = Color(0xFF2D2D2D);
const _codexComposerSurfaceBorder = Color(0xFF333333);
const _codexComposerPill = Color(0xFF252525);
const _codexComposerMenu = Color(0xFF2A2A2A);

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
        _firstLocalizedAttachmentError(context, widget.draftAttachments);
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
    final menuHeight = _SlashCommandMenu.heightFor(widget.slashCommands.length);
    final top = math.max(0.0, offset.dy - menuHeight - 8);
    return Positioned(
        left: offset.dx + 12,
        top: top,
        width: width,
        height: menuHeight,
        child: _SlashCommandMenu(
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
                    _AttachmentTray(
                        attachments: widget.draftAttachments,
                        onRemove: widget.onRemoveAttachment),
                    if (attachmentStatus != null) ...[
                      const SizedBox(height: 7),
                      _AttachmentStatus(attachmentStatus),
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
                    _VoiceInputStatus(l10n.workbenchVoiceListeningStatus),
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
                                child: _ComposerModelPill(
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
                                          _ComposerIcon(Icons.add_rounded))))),
                      const SizedBox(width: 12),
                      _VoiceInputButton(
                          state: widget.voiceState,
                          enabled: widget.voiceEnabled &&
                              !widget.running &&
                              !widget.sending,
                          onStart: widget.onVoiceStart,
                          onStop: widget.onVoiceStop,
                          onCancel: widget.onVoiceCancel),
                      const SizedBox(width: 12),
                      _SendPromptButton(
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

class _SlashCommandMenu extends StatefulWidget {
  const _SlashCommandMenu({
    required this.commands,
    required this.onSelected,
  });

  static const double rowHeight = 42;
  static const int maxVisibleRows = 6;

  final List<SlashCommand> commands;
  final ValueChanged<SlashCommand>? onSelected;

  static double heightFor(int count) {
    final visibleCount = count > maxVisibleRows ? maxVisibleRows : count;
    return rowHeight * visibleCount + 8;
  }

  @override
  State<_SlashCommandMenu> createState() => _SlashCommandMenuState();
}

class _SlashCommandMenuState extends State<_SlashCommandMenu> {
  int _selectedIndex = 0;

  @override
  void didUpdateWidget(covariant _SlashCommandMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedIndex >= widget.commands.length) {
      _selectedIndex = math.max(0, widget.commands.length - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
        decoration: BoxDecoration(
            color: _codexComposerMenu,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF383838)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: .30),
                  blurRadius: 22,
                  offset: const Offset(0, 12)),
            ]),
        child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: ListView.builder(
                padding: const EdgeInsets.all(4),
                itemExtent: _SlashCommandMenu.rowHeight,
                itemCount: widget.commands.length,
                itemBuilder: (context, index) {
                  final command = widget.commands[index];
                  return _SlashCommandRow(
                      command: command,
                      selected: index == _selectedIndex,
                      onHover: () => setState(() => _selectedIndex = index),
                      onTapDown: () => setState(() => _selectedIndex = index),
                      onTap: widget.onSelected == null
                          ? null
                          : () => widget.onSelected?.call(command));
                })));
  }
}

class _SlashCommandRow extends StatelessWidget {
  const _SlashCommandRow({
    required this.command,
    required this.selected,
    required this.onHover,
    required this.onTapDown,
    required this.onTap,
  });

  final SlashCommand command;
  final bool selected;
  final VoidCallback onHover;
  final VoidCallback onTapDown;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selectedFill = colorScheme.primary.withValues(alpha: .15);
    final selectedOutline = colorScheme.primary.withValues(alpha: .34);
    final commandColor = selected ? colorScheme.onSurface : colorScheme.primary;
    final descriptionColor = selected
        ? colorScheme.onSurface.withValues(alpha: .78)
        : colorScheme.onSurface.withValues(alpha: .60);

    return Semantics(
        selected: selected,
        button: true,
        child: MouseRegion(
            onEnter: (_) => onHover(),
            child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: AnimatedContainer(
                    key: ValueKey<String>(
                        'slash-command-row-${command.command}'),
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOutCubic,
                    decoration: BoxDecoration(
                        color: selected ? selectedFill : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: selected
                                ? selectedOutline
                                : Colors.transparent)),
                    child: InkWell(
                        onTap: onTap,
                        onTapDown: (_) => onTapDown(),
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Row(children: [
                              SizedBox(
                                  width: 122,
                                  child: Text(command.command,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.appTextStyle.copyWith(
                                          color: commandColor,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0))),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Text(command.description,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.appTextStyle.copyWith(
                                          color: descriptionColor,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0))),
                            ])))))));
  }
}

class _AttachmentTray extends StatelessWidget {
  const _AttachmentTray({required this.attachments, required this.onRemove});

  final List<DraftAttachment> attachments;
  final ValueChanged<int>? onRemove;

  @override
  Widget build(BuildContext context) => SizedBox(
      height: 56,
      width: double.infinity,
      child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          itemBuilder: (context, index) => _AttachmentTile(
              attachment: attachments[index],
              onRemove: onRemove == null ? null : () => onRemove?.call(index)),
          separatorBuilder: (context, index) => const SizedBox(width: 8),
          itemCount: attachments.length));
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({required this.attachment, required this.onRemove});

  final DraftAttachment attachment;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final invalid = !attachment.isValid;
    final errorMessage = _localizedAttachmentError(context, attachment);
    return Tooltip(
        message: errorMessage ?? attachment.name,
        child: Container(
            width: 154,
            height: 56,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: const Color(0xFF111214),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: invalid
                        ? theme.red.withValues(alpha: .72)
                        : Colors.white.withValues(alpha: .085))),
            child: Row(children: [
              _AttachmentPreview(attachment),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(attachment.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: invalid ? theme.red : theme.text,
                          fontSize: 11.5,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0))),
              const SizedBox(width: 4),
              Tooltip(
                  message:
                      l10n.workbenchAttachmentRemoveTooltip(attachment.name),
                  child: InkWell(
                      onTap: onRemove,
                      borderRadius: BorderRadius.circular(999),
                      child: SizedBox(
                          width: 22,
                          height: 22,
                          child: Icon(Icons.close_rounded,
                              color: invalid ? theme.red : theme.muted,
                              size: 15)))),
            ])));
  }
}

String? _localizedAttachmentError(
  BuildContext context,
  DraftAttachment attachment,
) {
  final code = attachment.errorCode;
  if (code == null) return null;
  final l10n = AppLocalizations.of(context);
  return switch (code) {
    'attachment_kind_unsupported' => l10n.workbenchAttachmentUnsupported,
    'attachment_too_large' ||
    'attachment_total_too_large' =>
      l10n.workbenchAttachmentTooLarge,
    _ => attachment.errorMessage,
  };
}

String? _firstLocalizedAttachmentError(
  BuildContext context,
  List<DraftAttachment> attachments,
) {
  for (final attachment in attachments) {
    final error = _localizedAttachmentError(context, attachment);
    if (error != null && error.trim().isNotEmpty) return error;
  }
  return null;
}

class _AttachmentStatus extends StatelessWidget {
  const _AttachmentStatus(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Row(children: [
        const Icon(Icons.error_outline_rounded, color: theme.red, size: 14),
        const SizedBox(width: 7),
        Expanded(
            child: Text(text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: theme.red,
                    fontSize: 12,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0)))
      ]);
}

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview(this.attachment);

  final DraftAttachment attachment;

  @override
  Widget build(BuildContext context) => ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
          width: 42,
          height: 42,
          color: Colors.white.withValues(alpha: .045),
          child: _previewChild()));

  Widget _previewChild() {
    if (attachment.kind == AttachmentKind.image) {
      return Image.file(
        File(attachment.localPath),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.image_outlined, color: theme.muted, size: 20),
      );
    }
    final icon = attachment.kind == AttachmentKind.pdf
        ? Icons.picture_as_pdf_outlined
        : Icons.description_outlined;
    return Icon(icon, color: theme.muted, size: 20);
  }
}

class ComposerWorkspaceCloud extends StatelessWidget {
  const ComposerWorkspaceCloud(
      {super.key,
      required this.workspace,
      required this.adapter,
      required this.running,
      required this.cliLocked,
      required this.onCliTap,
      required this.onTap});
  final WorkspaceSummary workspace;
  final String? adapter;
  final bool running;
  final bool cliLocked;
  final VoidCallback onCliTap;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
      width: double.infinity,
      color: const Color(0xF608090B),
      padding: const EdgeInsets.fromLTRB(23, 0, 18, 7),
      child: SafeArea(
          top: false,
          child: Row(children: [
            Expanded(
                child: Align(
                    alignment: Alignment.centerLeft,
                    child: InkWell(
                        key: const ValueKey('composer-cli-picker'),
                        onTap: cliLocked ? null : onCliTap,
                        borderRadius: BorderRadius.circular(999),
                        child: _ComposerCliLabel(
                            adapter: adapter, locked: cliLocked)))),
            const SizedBox(width: 10),
            InkWell(
                onTap: running ? null : onTap,
                borderRadius: BorderRadius.circular(999),
                child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.cloud_outlined,
                          color: theme.muted, size: 16),
                      const SizedBox(width: 10),
                      ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 168),
                          child: Text(workspaceDisplayName(workspace),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: theme.muted,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500))),
                    ]))),
          ])));
}

class _SendPromptButton extends StatelessWidget {
  const _SendPromptButton(
      {super.key,
      required this.enabled,
      required this.busy,
      required this.running,
      required this.onTap});
  final bool enabled;
  final bool busy;
  final bool running;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final active = enabled || running;
    final glow =
        active ? Colors.white.withValues(alpha: .10) : Colors.transparent;
    return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                gradient: active
                    ? const LinearGradient(
                        colors: [Color(0xFFF7F7F7), Color(0xFFE8E8E8)])
                    : const LinearGradient(
                        colors: [Color(0xFF141518), Color(0xFF101113)]),
                shape: BoxShape.circle,
                border: Border.all(
                    color: active
                        ? Colors.white.withValues(alpha: .18)
                        : theme.stroke),
                boxShadow: [
                  BoxShadow(
                      color: glow,
                      blurRadius: active ? 14 : 0,
                      spreadRadius: -7,
                      offset: const Offset(0, 6)),
                ]),
            child: Center(
                child: busy
                    ? SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            valueColor: AlwaysStoppedAnimation<Color>(active
                                ? const Color(0xFF08090B)
                                : theme.faint)))
                    : running
                        ? Icon(Icons.stop_rounded,
                            color:
                                active ? const Color(0xFF08090B) : theme.faint,
                            size: 17)
                        : _SendGlyph(
                            color: active
                                ? const Color(0xFF08090B)
                                : theme.faint))));
  }
}

class _ComposerCliLabel extends StatelessWidget {
  const _ComposerCliLabel({required this.adapter, required this.locked});
  final String? adapter;
  final bool locked;

  @override
  Widget build(BuildContext context) => Opacity(
      opacity: locked ? .58 : 1,
      child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.terminal_rounded,
                color: locked ? theme.faint : theme.muted, size: 16),
            const SizedBox(width: 10),
            Flexible(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 168),
                    child: Text(adapter ?? 'CLI',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: theme.muted,
                            fontSize: 12.5,
                            fontFamily: 'Consolas',
                            fontWeight: FontWeight.w800)))),
          ])));
}

class _ComposerModelPill extends StatelessWidget {
  const _ComposerModelPill({required this.model, required this.locked});
  final String? model;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final label =
        model ?? AppLocalizations.of(context).workbenchComposerDefaultModel;
    return _ComposerPillShell(
        locked: locked,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.memory_rounded,
              color: locked ? theme.faint : theme.muted, size: 14),
          const SizedBox(width: 7),
          Flexible(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 126),
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: locked ? theme.muted : theme.text,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700)))),
        ]));
  }
}

class _ComposerPillShell extends StatelessWidget {
  const _ComposerPillShell({required this.locked, required this.child});
  final bool locked;
  final Widget child;

  @override
  Widget build(BuildContext context) => Opacity(
      opacity: locked ? .58 : 1,
      child: Container(
          height: 28,
          constraints: const BoxConstraints(maxWidth: 168),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
              color: _codexComposerPill,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFF383838))),
          child: child));
}

class _ComposerIcon extends StatelessWidget {
  const _ComposerIcon(this.icon);
  final IconData icon;

  @override
  Widget build(BuildContext context) =>
      Icon(icon, color: theme.muted, size: 19);
}

class _VoiceInputButton extends StatelessWidget {
  const _VoiceInputButton(
      {required this.state,
      required this.enabled,
      required this.onStart,
      required this.onStop,
      required this.onCancel});

  final VoiceInputState state;
  final bool enabled;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onCancel;

  bool get _active =>
      state == VoiceInputState.initializing ||
      state == VoiceInputState.listening ||
      state == VoiceInputState.stopping;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
        label: l10n.workbenchVoiceInputSemantics,
        button: true,
        enabled: enabled,
        child: GestureDetector(
            onTap: enabled ? (_active ? onStop : onStart) : null,
            onLongPressStart: enabled ? (_) => onStart() : null,
            onLongPressEnd: enabled ? (_) => onStop() : null,
            onLongPressCancel: enabled ? onCancel : null,
            child: Tooltip(
                message: enabled
                    ? l10n.workbenchVoiceInputEnabledTooltip
                    : l10n.workbenchVoiceInputUnavailableTooltip,
                child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                        color: _active
                            ? theme.purple.withValues(alpha: .18)
                            : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color:
                                _active ? theme.purple : Colors.transparent)),
                    child: Icon(
                        _active ? Icons.mic_rounded : Icons.mic_none_rounded,
                        color: enabled ? theme.muted : theme.faint,
                        size: 19)))));
  }
}

class _VoiceInputStatus extends StatelessWidget {
  const _VoiceInputStatus(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Row(children: [
        const Icon(Icons.graphic_eq_rounded, color: theme.muted, size: 14),
        const SizedBox(width: 7),
        Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: theme.muted, fontSize: 12)))
      ]);
}

class _SendGlyph extends StatelessWidget {
  const _SendGlyph({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(14, 14), painter: _SendGlyphPainter(color));
}

class _SendGlyphPainter extends CustomPainter {
  const _SendGlyphPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.65
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(size.width * .50, size.height * .82)
      ..lineTo(size.width * .50, size.height * .20)
      ..moveTo(size.width * .24, size.height * .45)
      ..lineTo(size.width * .50, size.height * .20)
      ..lineTo(size.width * .76, size.height * .45);
    canvas.drawPath(path, paint);
    final railPaint = Paint()
      ..color = color.withValues(alpha: .42)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(size.width * .27, size.height * .86),
        Offset(size.width * .73, size.height * .86), railPaint);
  }

  @override
  bool shouldRepaint(covariant _SendGlyphPainter oldDelegate) =>
      oldDelegate.color != color;
}
