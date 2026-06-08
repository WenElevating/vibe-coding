import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../models/protocol.dart';
import '../../../core/theme/theme.dart' as theme;

const _codexComposerMenu = Color(0xFF2A2A2A);

class WorkbenchSlashCommandMenu extends StatefulWidget {
  const WorkbenchSlashCommandMenu({
    super.key,
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
  State<WorkbenchSlashCommandMenu> createState() =>
      _WorkbenchSlashCommandMenuState();
}

class _WorkbenchSlashCommandMenuState extends State<WorkbenchSlashCommandMenu> {
  int _selectedIndex = 0;

  @override
  void didUpdateWidget(covariant WorkbenchSlashCommandMenu oldWidget) {
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
                itemExtent: WorkbenchSlashCommandMenu.rowHeight,
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
