import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../../domain/repositories/workspace_repository.dart';
import '../../../core/theme/theme.dart' as theme;
import '../models/workspace_creation_request.dart';
import '../widgets/mini_input.dart';
import '../widgets/sheet_icon_button.dart';
import 'directory_browser_sheet.dart';

class AddWorkspaceSheet extends StatefulWidget {
  const AddWorkspaceSheet({super.key, required this.workspaceRepository});

  final WorkspaceRepository workspaceRepository;

  @override
  State<AddWorkspaceSheet> createState() => _AddWorkspaceSheetState();
}

class _AddWorkspaceSheetState extends State<AddWorkspaceSheet> {
  final _path = TextEditingController();
  final _name = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _path.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _browse() async {
    final selectedPath = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => DirectoryBrowserSheet.forWorkspaceRepository(
              repository: widget.workspaceRepository,
            ));
    if (selectedPath != null && selectedPath.isNotEmpty) {
      if (!mounted) return;
      setState(() => _path.text = selectedPath);
    }
  }

  Future<void> _create() async {
    final path = _path.text.trim();
    if (path.isEmpty) {
      setState(() =>
          _error = AppLocalizations.of(context).workspacePathRequiredError);
      return;
    }
    final name = _name.text.trim();
    Navigator.of(context).pop(WorkspaceCreationRequest(
      path: path,
      name: name.isEmpty ? null : name,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
        top: false,
        child: Container(
            margin: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            decoration: BoxDecoration(
                color: const Color(0xFF111820),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: .1)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: .5),
                      blurRadius: 32,
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
                        child: const Icon(Icons.folder_open_rounded,
                            color: theme.active, size: 18)),
                    const SizedBox(width: 11),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(l10n.workspaceAddTitle,
                              style: const TextStyle(
                                  color: theme.text,
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0)),
                          const SizedBox(height: 2),
                          Text(l10n.workspaceListFootnote,
                              style: const TextStyle(
                                  color: theme.muted,
                                  fontSize: 11.5,
                                  height: 1.2)),
                        ])),
                    SheetIconButton(
                        label: l10n.workspaceBrowseAction,
                        icon: Icons.drive_folder_upload_rounded,
                        onTap: _browse),
                  ]),
                  const SizedBox(height: 13),
                  MiniInput(
                      controller: _path,
                      hint: l10n.workspaceChoosePathHint,
                      icon: Icons.folder_rounded,
                      autofocus: true),
                  const SizedBox(height: 9),
                  MiniInput(
                      controller: _name,
                      hint: l10n.workspaceNameHint,
                      icon: Icons.label_outline_rounded),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 11, vertical: 9),
                        decoration: BoxDecoration(
                            color: theme.red.withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: theme.red.withValues(alpha: .24))),
                        child: Row(children: [
                          const Icon(Icons.error_outline_rounded,
                              color: theme.red, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(_error!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: theme.red,
                                      fontSize: 11.5,
                                      height: 1.25))),
                        ])),
                  ],
                  const SizedBox(height: 13),
                  _CreateWorkspaceButton(
                      label: l10n.workspaceCreateAndUseAction, onTap: _create),
                ])));
  }
}

class _CreateWorkspaceButton extends StatelessWidget {
  const _CreateWorkspaceButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
          height: 42,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: const Color(0xFF202832),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: .16)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: .18),
                    blurRadius: 14,
                    offset: const Offset(0, 8))
              ]),
          child: Text(label,
              style: const TextStyle(
                  color: theme.text,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900))));
}
