import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../../models/protocol.dart';
import '../../../core/theme/theme.dart' as theme;

class ModelPickerSheet extends StatelessWidget {
  const ModelPickerSheet({
    super.key,
    required this.models,
    required this.selected,
    required this.onSelected,
    this.updating = false,
    this.selectionDisabled = false,
    this.pendingModel,
    this.errorText,
  });

  final List<AdapterModelOption> models;
  final String? selected;
  final ValueChanged<String?> onSelected;
  final bool updating;
  final bool selectionDisabled;
  final String? pendingModel;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final visibleModels = models
        .where((model) => model.id.trim().isNotEmpty)
        .toList(growable: false);
    final normalizedError = errorText?.trim();
    final normalizedPending = pendingModel?.trim();
    final choicesDisabled = updating || selectionDisabled;
    return SafeArea(
        top: false,
        child: Container(
            key: const ValueKey('model-picker-sheet'),
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
                        child: const Icon(Icons.memory_rounded,
                            size: 17, color: theme.active)),
                    const SizedBox(width: 11),
                    Expanded(
                        child: Text(l10n.modelPickerTitle,
                            style: const TextStyle(
                                color: theme.text,
                                fontSize: 16.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0))),
                  ]),
                  const SizedBox(height: 13),
                  if (updating)
                    Container(
                        key: const ValueKey('model-picker-updating'),
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 11, vertical: 10),
                        decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .035),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: theme.stroke)),
                        child: Row(children: [
                          const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: theme.active)),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Text(
                                  normalizedPending == null ||
                                          normalizedPending.isEmpty
                                      ? _modelPickerUpdatingText(context)
                                      : '${_modelPickerUpdatingText(context)} $normalizedPending',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: theme.muted,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700)))
                        ])),
                  if (normalizedError != null && normalizedError.isNotEmpty)
                    Container(
                        key: const ValueKey('model-picker-error'),
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 11, vertical: 10),
                        decoration: BoxDecoration(
                            color: theme.red.withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: theme.red.withValues(alpha: .28))),
                        child: Row(children: [
                          Icon(Icons.error_outline_rounded,
                              color: theme.red.withValues(alpha: .92),
                              size: 16),
                          const SizedBox(width: 9),
                          Expanded(
                              child: Text(normalizedError,
                                  style: TextStyle(
                                      color: theme.red.withValues(alpha: .95),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700)))
                        ])),
                  Flexible(
                      child: ListView(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          children: visibleModels.isEmpty
                              ? <Widget>[
                                  _ModelChoiceRow(
                                      key: const ValueKey(
                                          'model-option-default'),
                                      title: l10n.modelPickerDefaultModel,
                                      source: _modelPickerCliDefaultDetailText(
                                          context),
                                      selected: selected == null,
                                      onTap: choicesDisabled
                                          ? null
                                          : () => onSelected(null)),
                                ]
                              : <Widget>[
                                  for (final model in visibleModels)
                                    _ModelChoiceRow(
                                        key: ValueKey(
                                            'model-option-${model.id}'),
                                        title: model.label.isEmpty
                                            ? model.id
                                            : model.label,
                                        source: _modelSourceLabel(
                                            l10n, model.source),
                                        selected: model.id == selected,
                                        onTap: choicesDisabled
                                            ? null
                                            : () => onSelected(model.id)),
                                ])),
                ])));
  }
}

class _ModelChoiceRow extends StatelessWidget {
  const _ModelChoiceRow({
    super.key,
    required this.title,
    required this.source,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String source;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
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
              Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .045),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: .08))),
                  child: const Icon(Icons.memory_rounded,
                      color: theme.muted, size: 14)),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: enabled
                                ? theme.text
                                : theme.text.withValues(alpha: .45),
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0)),
                    const SizedBox(height: 2),
                    Text(source,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: enabled
                                ? theme.muted
                                : theme.muted.withValues(alpha: .45),
                            fontSize: 11.5))
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
}

String _modelSourceLabel(AppLocalizations l10n, String source) =>
    switch (source) {
      'codex_config' => l10n.modelPickerSourceCodexConfig,
      'codex_catalog' => l10n.modelPickerSourceCodexCatalog,
      'app_server' => _modelPickerAppServerSourceText(l10n),
      'claude_config' => l10n.modelPickerSourceClaudeEnv,
      'claude_env' => l10n.modelPickerSourceClaudeEnv,
      'cli_default' => l10n.modelPickerSourceCliDefault,
      _ => l10n.modelPickerSourceUnknown,
    };

String _modelPickerAppServerSourceText(AppLocalizations l10n) => 'App Server';

String _modelPickerUpdatingText(BuildContext context) =>
    _modelPickerFallbackText(
        context: context, en: 'Updating model...', zh: '正在更新模型...');

String modelPickerUnsupportedDaemonText(BuildContext context) =>
    _modelPickerFallbackText(
        context: context,
        en: 'Update the desktop daemon to change models in existing '
            'conversations.',
        zh: '请更新桌面端 daemon 后再修改已有对话的模型。');

String modelPickerBusyText(BuildContext context) => _modelPickerFallbackText(
    context: context,
    en: 'Wait for the current turn to finish before changing model.',
    zh: '当前轮次结束后才能切换模型。');

String _modelPickerCliDefaultDetailText(BuildContext context) =>
    _modelPickerFallbackText(
        context: context,
        en: 'Uses the CLI configured default.',
        zh: '使用 CLI 当前配置的默认模型。');

String _modelPickerFallbackText(
    {required BuildContext context, required String en, required String zh}) {
  return Localizations.localeOf(context).languageCode.toLowerCase() == 'zh'
      ? zh
      : en;
}
