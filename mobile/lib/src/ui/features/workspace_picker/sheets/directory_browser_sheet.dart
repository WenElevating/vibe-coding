import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../../domain/repositories/workspace_repository.dart';
import '../../../../models/protocol.dart';
import '../../../core/theme/theme.dart' as theme;
import '../widgets/directory_row.dart';

class DirectoryBrowserSheet extends StatefulWidget {
  DirectoryBrowserSheet.forWorkspaceRepository({
    super.key,
    required WorkspaceRepository repository,
  })  : _listFileSystemRoots = repository.listFileSystemRoots,
        _listDirectory = repository.listDirectory;

  final Future<List<DirectoryEntrySummary>> Function() _listFileSystemRoots;
  final Future<DirectoryListing> Function(String path) _listDirectory;

  @override
  State<DirectoryBrowserSheet> createState() => _DirectoryBrowserSheetState();
}

class _DirectoryBrowserSheetState extends State<DirectoryBrowserSheet> {
  Future<Object>? _future;
  String? _currentPath;
  final List<String?> _history = <String?>[];

  @override
  void initState() {
    super.initState();
    _future = widget._listFileSystemRoots();
  }

  void _open(String path) => setState(() {
        _history.add(_currentPath);
        _currentPath = path;
        _future = widget._listDirectory(path);
      });

  void _goBack([String? fallbackParent]) => setState(() {
        final target =
            _history.isNotEmpty ? _history.removeLast() : fallbackParent;
        _currentPath = target;
        _future = target == null
            ? widget._listFileSystemRoots()
            : widget._listDirectory(target);
      });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currentPath = _currentPath;
    return SafeArea(
        top: false,
        child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * .76),
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
            decoration: BoxDecoration(
                color: const Color(0xFF101418),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withValues(alpha: .09)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: .46),
                      blurRadius: 34,
                      offset: const Offset(0, 16))
                ]),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    if (currentPath != null) ...[
                      _DirectoryBackButton(
                          label: l10n.commonBack, onTap: () => _goBack()),
                      const SizedBox(width: 10),
                    ] else ...[
                      const _DirectoryHeaderIcon(),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                        child: Text(l10n.workspaceChooseFolderTitle,
                            style: const TextStyle(
                                color: theme.text,
                                fontSize: 16.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0))),
                    if (currentPath != null)
                      _DirectorySelectButton(
                          label: l10n.workspaceSelectCurrentAction,
                          onTap: () => Navigator.of(context).pop(currentPath)),
                  ]),
                  const SizedBox(height: 10),
                  _DirectoryPathBar(
                      text: currentPath ?? l10n.workspaceBrowserPlaceholder,
                      isPlaceholder: currentPath == null),
                  const SizedBox(height: 10),
                  Flexible(
                      child: FutureBuilder<Object>(
                          future: _future,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState !=
                                ConnectionState.done) {
                              return const SizedBox(
                                  height: 128,
                                  child: Center(
                                      child: CircularProgressIndicator(
                                          color: theme.active)));
                            }
                            if (snapshot.hasError) {
                              return Text(snapshot.error.toString(),
                                  style: const TextStyle(
                                      color: theme.red, fontSize: 12));
                            }
                            final data = snapshot.requireData;
                            final entries = data is DirectoryListing
                                ? data.directories
                                : (data as List<DirectoryEntrySummary>);
                            final parent =
                                data is DirectoryListing ? data.parent : null;
                            final isRootList = data is! DirectoryListing;
                            return DecoratedBox(
                                decoration: BoxDecoration(
                                    color: const Color(0xFF0B0F13),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                        color: Colors.white
                                            .withValues(alpha: .055))),
                                child: ListView.separated(
                                    shrinkWrap: true,
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 6),
                                    itemCount: entries.length +
                                        (parent == null ? 0 : 1),
                                    separatorBuilder: (_, __) => Padding(
                                        padding: const EdgeInsets.only(
                                            left: 48, right: 10),
                                        child: Divider(
                                            height: 1,
                                            thickness: 1,
                                            color: Colors.white
                                                .withValues(alpha: .035))),
                                    itemBuilder: (context, index) {
                                      if (parent != null && index == 0) {
                                        return DirectoryRow(
                                            name: l10n.commonBack,
                                            path: parent,
                                            icon: Icons.arrow_upward_rounded,
                                            emphasized: true,
                                            onTap: () => _goBack(parent));
                                      }
                                      final entry = entries[
                                          index - (parent == null ? 0 : 1)];
                                      return DirectoryRow(
                                          name: entry.name,
                                          path: entry.path,
                                          icon: isRootList
                                              ? Icons.storage_rounded
                                              : Icons.folder_rounded,
                                          onTap: () => _open(entry.path));
                                    }));
                          }))
                ])));
  }
}

class _DirectoryHeaderIcon extends StatelessWidget {
  const _DirectoryHeaderIcon();

  @override
  Widget build(BuildContext context) => Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .04),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: Colors.white.withValues(alpha: .11))),
      child:
          const Icon(Icons.folder_open_rounded, color: theme.muted, size: 18));
}

class _DirectoryPathBar extends StatelessWidget {
  const _DirectoryPathBar({required this.text, required this.isPlaceholder});

  final String text;
  final bool isPlaceholder;

  @override
  Widget build(BuildContext context) => Container(
      height: 34,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
          color: const Color(0xFF0C1015),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: .06))),
      child: Row(children: [
        Icon(isPlaceholder ? Icons.explore_outlined : Icons.folder_rounded,
            color: isPlaceholder ? theme.faint : theme.muted, size: 15),
        const SizedBox(width: 8),
        Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: isPlaceholder ? theme.faint : theme.muted,
                    fontSize: 11.5,
                    fontFamily: isPlaceholder ? null : 'Consolas',
                    height: 1.2))),
      ]));
}

class _DirectorySelectButton extends StatelessWidget {
  const _DirectorySelectButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
              color: const Color(0xFF202832),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: theme.activeStroke.withValues(alpha: .72))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.check_rounded, color: theme.active, size: 14),
            const SizedBox(width: 5),
            Text(label,
                style: const TextStyle(
                    color: theme.text,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0)),
          ])));
}

class _DirectoryBackButton extends StatelessWidget {
  const _DirectoryBackButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
      message: label,
      child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .04),
                  borderRadius: BorderRadius.circular(11),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: .11))),
              child: const Icon(Icons.arrow_back_rounded,
                  color: theme.muted, size: 18))));
}
