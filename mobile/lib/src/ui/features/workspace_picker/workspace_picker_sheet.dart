import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../domain/repositories/workspace_repository.dart';
import '../../../models/protocol.dart';
import '../../core/theme/theme.dart' as theme;
import '../../core/widgets/widgets.dart';

class WorkspaceCreationRequest {
  const WorkspaceCreationRequest({required this.path, this.name});

  final String path;
  final String? name;
}

class AdapterPickerSheet extends StatelessWidget {
  const AdapterPickerSheet(
      {super.key,
      required this.adapters,
      required this.selected,
      required this.onSelected});
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

class WorkspaceListPage extends StatelessWidget {
  const WorkspaceListPage({
    super.key,
    required this.workspaces,
    required this.onSelected,
    required this.onAddWorkspace,
  });

  final List<WorkspaceSummary> workspaces;
  final ValueChanged<WorkspaceSummary> onSelected;
  final VoidCallback onAddWorkspace;

  @override
  Widget build(BuildContext context) {
    final visibleWorkspaces = dedupeWorkspacesByPath(workspaces);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Column(key: const ValueKey('workspace-list'), children: [
      Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
              color: const Color(0xEE0A0B0D),
              border: Border(
                  bottom:
                      BorderSide(color: Colors.white.withValues(alpha: .07)))),
          child: Row(children: [
            const SizedBox(width: 36),
            Expanded(
                child: Text(AppLocalizations.of(context).workspaceListTitle,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: theme.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0))),
            _WorkspaceAddIconButton(onTap: onAddWorkspace),
          ])),
      Expanded(
          child: ListView(
              padding: EdgeInsets.fromLTRB(12, 12, 12, 96 + bottomInset),
              children: [
            const SessionSearchBox(),
            const SizedBox(height: 14),
            _WorkspaceSectionHeader(
                title: AppLocalizations.of(context).workspaceAvailableSection,
                meta: '${visibleWorkspaces.length}'),
            const SizedBox(height: 8),
            for (final workspace in visibleWorkspaces)
              _WorkspaceChoiceRow(
                  workspace: workspace,
                  selected: false,
                  allowSelectedTap: true,
                  onTap: () => onSelected(workspace)),
            Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                child: Text(AppLocalizations.of(context).workspaceListFootnote,
                    style: const TextStyle(
                        color: Color(0xFF666D77),
                        fontSize: 11.5,
                        height: 1.5))),
          ])),
    ]);
  }
}

List<WorkspaceSummary> dedupeWorkspacesByPath(
    Iterable<WorkspaceSummary> workspaces) {
  final seen = <String>{};
  final visible = <WorkspaceSummary>[];
  for (final workspace in workspaces) {
    final key = workspace.path.replaceAll('\\', '/').toLowerCase();
    if (!seen.add(key)) continue;
    visible.add(workspace);
  }
  return visible;
}

class _AdapterChoiceRow extends StatelessWidget {
  const _AdapterChoiceRow(
      {required this.adapter, required this.selected, required this.onTap});
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
                    _SheetIconButton(
                        label: l10n.workspaceBrowseAction,
                        icon: Icons.drive_folder_upload_rounded,
                        onTap: _browse),
                  ]),
                  const SizedBox(height: 13),
                  _MiniInput(
                      controller: _path,
                      hint: l10n.workspaceChoosePathHint,
                      icon: Icons.folder_rounded,
                      autofocus: true),
                  const SizedBox(height: 9),
                  _MiniInput(
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

class _SheetIconButton extends StatelessWidget {
  const _SheetIconButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
              color: const Color(0xFF171E26),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: Colors.white.withValues(alpha: .12))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: theme.muted, size: 15),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    color: theme.text,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800)),
          ])));
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

class _WorkspaceSectionHeader extends StatelessWidget {
  const _WorkspaceSectionHeader({required this.title, required this.meta});
  final String title;
  final String meta;

  @override
  Widget build(BuildContext context) => Row(children: [
        Text(title,
            style: const TextStyle(
                color: Color(0xFFD8D8D8),
                fontSize: 12.5,
                fontWeight: FontWeight.w800)),
        const Spacer(),
        Text(meta,
            style: const TextStyle(
                color: Color(0xFF6F757E),
                fontSize: 10.5,
                fontFamily: 'Consolas')),
      ]);
}

class _WorkspaceChoiceRow extends StatelessWidget {
  const _WorkspaceChoiceRow(
      {required this.workspace,
      required this.selected,
      required this.onTap,
      this.allowSelectedTap = false});
  final WorkspaceSummary workspace;
  final bool selected;
  final VoidCallback onTap;
  final bool allowSelectedTap;

  @override
  Widget build(BuildContext context) => InkWell(
      onTap: selected && !allowSelectedTap ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
              color: selected ? theme.activePanel : const Color(0xFF101113),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: selected
                      ? theme.activeStroke.withValues(alpha: .9)
                      : Colors.white.withValues(alpha: .075))),
          child: Row(children: [
            Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF242B34)
                        : const Color(0xFF18191C),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: selected
                            ? theme.activeStroke.withValues(alpha: .55)
                            : Colors.white.withValues(alpha: .055))),
                child: Icon(Icons.folder_rounded,
                    color: selected ? theme.active : theme.muted, size: 17)),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(workspace.name.isEmpty ? workspace.id : workspace.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: theme.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w900)),
                  const SizedBox(height: 3),
                  Text(workspace.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Color(0xFF858A94),
                          fontSize: 10.8,
                          fontFamily: 'Consolas'))
                ])),
            if (selected)
              Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: theme.active.withValues(alpha: .16),
                      borderRadius: BorderRadius.circular(11)),
                  child: const Icon(Icons.check_rounded,
                      color: theme.active, size: 15))
          ])));
}

class _WorkspaceAddIconButton extends StatelessWidget {
  const _WorkspaceAddIconButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
      message: AppLocalizations.of(context).workspaceAddTitle,
      child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: theme.purple.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: theme.purple.withValues(alpha: .42))),
              child:
                  const Icon(Icons.add_rounded, color: theme.text, size: 24))));
}

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
                                        return _DirectoryRow(
                                            name: l10n.commonBack,
                                            path: parent,
                                            icon: Icons.arrow_upward_rounded,
                                            emphasized: true,
                                            onTap: () => _goBack(parent));
                                      }
                                      final entry = entries[
                                          index - (parent == null ? 0 : 1)];
                                      return _DirectoryRow(
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

class _DirectoryRow extends StatelessWidget {
  const _DirectoryRow(
      {required this.name,
      required this.path,
      required this.onTap,
      this.icon = Icons.folder_rounded,
      this.emphasized = false});
  final String name;
  final String path;
  final VoidCallback onTap;
  final IconData icon;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(children: [
            Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: emphasized
                        ? theme.activePanel.withValues(alpha: .72)
                        : const Color(0xFF151A20),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                        color: emphasized
                            ? theme.activeStroke.withValues(alpha: .44)
                            : Colors.white.withValues(alpha: .045))),
                child: Icon(icon,
                    color: emphasized ? theme.active : theme.muted, size: 16)),
            const SizedBox(width: 9),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: emphasized ? theme.active : theme.text,
                          fontSize: 12.8,
                          fontWeight:
                              emphasized ? FontWeight.w900 : FontWeight.w800,
                          letterSpacing: 0)),
                  const SizedBox(height: 3),
                  Text(path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: theme.faint,
                          fontSize: 10.8,
                          fontFamily: 'Consolas',
                          height: 1.15)),
                ])),
            const Icon(Icons.chevron_right_rounded,
                color: theme.faint, size: 18)
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

class _MiniInput extends StatelessWidget {
  const _MiniInput({
    required this.controller,
    required this.hint,
    this.icon,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String hint;
  final IconData? icon;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => TextField(
      controller: controller,
      autofocus: autofocus,
      style: theme.appTextStyle.copyWith(color: theme.text, fontSize: 12.5),
      decoration: InputDecoration(
          isDense: true,
          prefixIcon:
              icon == null ? null : Icon(icon, color: theme.faint, size: 16),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 38, minHeight: 38),
          hintText: hint,
          hintStyle:
              theme.appTextStyle.copyWith(color: theme.faint, fontSize: 12.5),
          filled: true,
          fillColor: const Color(0xFF151A20),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: .1))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: .1))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide(
                  color: theme.activeStroke.withValues(alpha: .85),
                  width: 1.2)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 11, vertical: 11)));
}
