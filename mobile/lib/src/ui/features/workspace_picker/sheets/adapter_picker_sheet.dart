import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../../models/protocol.dart';
import '../../../core/theme/theme.dart' as theme;
import '../../../core/widgets/widgets.dart';

class AdapterPickerSheet extends StatelessWidget {
  const AdapterPickerSheet({
    super.key,
    required this.adapters,
    required this.selected,
    required this.onSelected,
  });

  final List<AdapterStatus> adapters;
  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
        top: false,
        child: Container(
            key: const ValueKey('adapter-picker-sheet'),
            margin: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * .72),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            decoration: BoxDecoration(
                color: const Color(0xFF111820),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: .1)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: .42),
                      blurRadius: 30,
                      offset: const Offset(0, 18))
                ]),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .045),
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: .13))),
                        child: const Icon(Icons.terminal_rounded,
                            size: 17, color: theme.active)),
                    const SizedBox(width: 11),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(l10n.workspaceAdapterPickerTitle,
                              style: const TextStyle(
                                  color: theme.text,
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0)),
                          const SizedBox(height: 2),
                          Text(l10n.workspaceAdapterPickerSubtitle,
                              style: const TextStyle(
                                  color: theme.muted,
                                  fontSize: 11.5,
                                  height: 1.2)),
                        ])),
                  ]),
                  const SizedBox(height: 13),
                  Flexible(
                      child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: adapters.length,
                          itemBuilder: (context, index) {
                            final adapter = adapters[index];
                            return _AdapterChoiceRow(
                                adapter: adapter,
                                selected: adapter.adapter == selected,
                                onTap: () => onSelected(adapter.adapter));
                          })),
                ])));
  }
}

class _AdapterChoiceRow extends StatelessWidget {
  const _AdapterChoiceRow({
    required this.adapter,
    required this.selected,
    required this.onTap,
  });

  final AdapterStatus adapter;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFF1A212A)
                  : Colors.white.withValues(alpha: .03),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: selected
                      ? theme.activeStroke.withValues(alpha: .75)
                      : theme.stroke)),
          child: Row(children: [
            _AdapterBrandIcon(adapter: adapter.adapter),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(adapter.adapter,
                      style: const TextStyle(
                          color: theme.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0)),
                  const SizedBox(height: 2),
                  Text(displayVersion(adapter.version),
                      style:
                          const TextStyle(color: theme.muted, fontSize: 11.5))
                ])),
            if (selected)
              Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .06),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: theme.activeStroke.withValues(alpha: .7))),
                  child: const Icon(Icons.check_rounded,
                      color: theme.active, size: 12))
          ])));
}

class _AdapterBrandIcon extends StatelessWidget {
  const _AdapterBrandIcon({required this.adapter});

  final String adapter;

  @override
  Widget build(BuildContext context) {
    final assetPath = _adapterAssetPath(adapter);
    if (assetPath != null) {
      return SizedBox(
          width: 24,
          height: 24,
          child: Image.asset(assetPath, fit: BoxFit.contain));
    }
    return AgentIcon(color: toolColor(adapter));
  }
}

String? _adapterAssetPath(String adapter) {
  final lower = adapter.toLowerCase();
  if (lower.contains('claude') && lower.contains('code')) {
    return 'assets/lobe-icons/claudecode-color.png';
  }
  if (lower.contains('claude')) return 'assets/lobe-icons/claude-color.png';
  if (lower.contains('codex')) return 'assets/lobe-icons/codex-color.png';
  if (lower.contains('opencode')) return 'assets/lobe-icons/opencode.png';
  if (lower.contains('gemini')) return 'assets/lobe-icons/geminicli-color.png';
  return null;
}
