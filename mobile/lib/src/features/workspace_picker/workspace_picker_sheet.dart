part of '../../app/app.dart';

class _AdapterPickerSheet extends StatelessWidget {
  const _AdapterPickerSheet(
      {required this.adapters,
      required this.selected,
      required this.onSelected});
  final List<AdapterStatus> adapters;
  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => SafeArea(
      top: false,
      child: Container(
          margin: const EdgeInsets.all(12),
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * .68),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
              color: const Color(0xFF0D131D),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: Colors.white.withValues(alpha: .08)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: .45),
                    blurRadius: 28,
                    offset: const Offset(0, 18))
              ]),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('选择模型 / CLI',
                    style: TextStyle(
                        color: _text,
                        fontSize: 16,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                const Text('会用于下一次真实 daemon run，运行中不可切换。',
                    style: TextStyle(color: _muted, fontSize: 12)),
                const SizedBox(height: 12),
                for (final adapter in adapters)
                  _AdapterChoiceRow(
                      adapter: adapter,
                      selected: adapter.adapter == selected,
                      onTap: () => onSelected(adapter.adapter)),
              ])));
}

class _WorkspaceListPage extends StatelessWidget {
  const _WorkspaceListPage({
    required this.workspaces,
    required this.selected,
    required this.onSelected,
    required this.onAddWorkspace,
  });

  final List<WorkspaceSummary> workspaces;
  final WorkspaceSummary selected;
  final ValueChanged<WorkspaceSummary> onSelected;
  final VoidCallback onAddWorkspace;

  @override
  Widget build(BuildContext context) =>
      Column(key: const ValueKey('workspace-list'), children: [
        Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
                color: const Color(0xEE0A0B0D),
                border: Border(
                    bottom: BorderSide(
                        color: Colors.white.withValues(alpha: .07)))),
            child: Row(children: [
              const SizedBox(width: 36),
              Expanded(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    const Text('Workspaces',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: _text,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -.15)),
                    const SizedBox(height: 3),
                    Text(_compactWorkspacePath(selected.path),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: _faint,
                            fontSize: 10.5,
                            fontFamily: 'Consolas')),
                  ])),
              _WorkspaceAddIconButton(onTap: onAddWorkspace),
            ])),
        Expanded(
            child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                children: [
              const _SessionSearchBox(),
              const SizedBox(height: 14),
              _WorkspaceSectionHeader(
                  title: 'Available Workspaces', meta: '${workspaces.length}'),
              const SizedBox(height: 8),
              for (final workspace in workspaces)
                _WorkspaceChoiceRow(
                    workspace: workspace,
                    selected: workspace.id == selected.id,
                    allowSelectedTap: true,
                    onTap: () => onSelected(workspace)),
              const Padding(
                  padding: EdgeInsets.fromLTRB(4, 6, 4, 0),
                  child: Text(
                      'Choose the folder where CLI commands will run, then open or create a session inside it.',
                      style: TextStyle(
                          color: Color(0xFF666D77),
                          fontSize: 11.5,
                          height: 1.5))),
            ])),
      ]);
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
      borderRadius: BorderRadius.circular(16),
      child: Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: selected
                  ? _purple.withValues(alpha: .16)
                  : Colors.white.withValues(alpha: .035),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: selected ? _purple.withValues(alpha: .45) : _stroke)),
          child: Row(children: [
            _AgentIcon(color: _toolColor(adapter.adapter)),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(adapter.adapter,
                      style: const TextStyle(
                          color: _text, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 3),
                  Text(_displayVersion(adapter.version),
                      style: const TextStyle(color: _muted, fontSize: 12))
                ])),
            if (selected)
              const Icon(Icons.check_circle_rounded, color: _purple, size: 19)
          ])));
}

class _WorkspacePickerSheet extends StatefulWidget {
  const _WorkspacePickerSheet(
      {required this.workspaces,
      required this.selected,
      required this.client,
      required this.onSelected,
      required this.onCreated});
  final List<WorkspaceSummary> workspaces;
  final WorkspaceSummary selected;
  final DaemonClient client;
  final ValueChanged<WorkspaceSummary> onSelected;
  final ValueChanged<WorkspaceSummary> onCreated;

  @override
  State<_WorkspacePickerSheet> createState() => _WorkspacePickerSheetState();
}

class _WorkspacePickerSheetState extends State<_WorkspacePickerSheet> {
  final _path = TextEditingController();
  final _name = TextEditingController();
  bool _creating = false;
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
        builder: (context) => _DirectoryBrowserSheet(client: widget.client));
    if (selectedPath != null && selectedPath.isNotEmpty) {
      setState(() => _path.text = selectedPath);
    }
  }

  Future<void> _create() async {
    final path = _path.text.trim();
    if (_creating) return;
    if (path.isEmpty) {
      setState(() => _error = 'Choose or enter a folder path first.');
      return;
    }
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final workspace =
          await widget.client.createWorkspace(path: path, name: _name.text);
      widget.onCreated(workspace);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
      top: false,
      child: Container(
          margin: const EdgeInsets.all(12),
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * .78),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          decoration: BoxDecoration(
              color: const Color(0xF608090B),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withValues(alpha: .075)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: .56),
                    blurRadius: 34,
                    offset: const Offset(0, 20))
              ]),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _WorkspaceSheetHeader(
                    title: '工作区', subtitle: '切换 CLI 执行目录，当前会话会继续保留。'),
                const SizedBox(height: 12),
                Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: const Color(0xFF101113),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: .075))),
                    child: Column(children: [
                      Row(children: [
                        Expanded(
                            child: _MiniInput(
                                controller: _path, hint: '输入或浏览文件夹路径')),
                        const SizedBox(width: 8),
                        _TinyActionButton('浏览', onTap: _browse),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                            child:
                                _MiniInput(controller: _name, hint: '名称（可选）')),
                        const SizedBox(width: 8),
                        _TinyActionButton(_creating ? '创建中' : '创建',
                            onTap: _creating ? null : _create, primary: true),
                      ]),
                    ])),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _red, fontSize: 11)),
                ],
                const SizedBox(height: 14),
                const _WorkspaceSectionHeader(title: '已有工作区', meta: '安全执行目录'),
                const SizedBox(height: 6),
                Flexible(
                    child: ListView(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        children: [
                      for (final workspace in widget.workspaces)
                        _WorkspaceChoiceRow(
                            workspace: workspace,
                            selected: workspace.id == widget.selected.id,
                            onTap: () => widget.onSelected(workspace)),
                    ])),
              ])));
}

class _AddWorkspaceSheet extends StatefulWidget {
  const _AddWorkspaceSheet({required this.client});
  final DaemonClient client;

  @override
  State<_AddWorkspaceSheet> createState() => _AddWorkspaceSheetState();
}

class _AddWorkspaceSheetState extends State<_AddWorkspaceSheet> {
  final _path = TextEditingController();
  final _name = TextEditingController();
  bool _creating = false;
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
        builder: (context) => _DirectoryBrowserSheet(client: widget.client));
    if (selectedPath != null && selectedPath.isNotEmpty) {
      setState(() => _path.text = selectedPath);
    }
  }

  Future<void> _create() async {
    final path = _path.text.trim();
    if (path.isEmpty || _creating) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final workspace =
          await widget.client.createWorkspace(path: path, name: _name.text);
      if (mounted) Navigator.of(context).pop(workspace);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
      top: false,
      child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
              color: const Color(0xFF0D131D),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: .08))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              const Expanded(
                  child: Text('添加工作区',
                      style: TextStyle(
                          color: _text,
                          fontSize: 16,
                          fontWeight: FontWeight.w900))),
              _TinyActionButton('浏览', onTap: _browse),
            ]),
            const SizedBox(height: 10),
            _MiniInput(controller: _path, hint: '选择或输入文件夹路径'),
            const SizedBox(height: 8),
            _MiniInput(controller: _name, hint: '名称（可选）'),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _red, fontSize: 11)),
            ],
            const SizedBox(height: 12),
            SizedBox(
                width: double.infinity,
                child: _TinyActionButton(_creating ? '创建中' : '创建并使用',
                    onTap: _creating ? null : _create, primary: true)),
          ])));
}

class _WorkspaceSheetHeader extends StatelessWidget {
  const _WorkspaceSheetHeader({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: const Color(0xFF141518),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: Colors.white.withValues(alpha: .075))),
            child: const Icon(Icons.folder_open_rounded,
                color: Color(0xFF9EA3AD), size: 16)),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  color: _text,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.15)),
          const SizedBox(height: 3),
          Text(subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Color(0xFF858A94), fontSize: 11.5, height: 1.35)),
        ])),
      ]);
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
              color: selected ? _activePanel : const Color(0xFF101113),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: selected
                      ? _activeStroke.withValues(alpha: .9)
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
                            ? _activeStroke.withValues(alpha: .55)
                            : Colors.white.withValues(alpha: .055))),
                child: Icon(Icons.folder_rounded,
                    color: selected ? _active : _muted, size: 17)),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(workspace.name.isEmpty ? workspace.id : workspace.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: _text,
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
                      color: _active.withValues(alpha: .16),
                      borderRadius: BorderRadius.circular(11)),
                  child:
                      const Icon(Icons.check_rounded, color: _active, size: 15))
          ])));
}

class _WorkspaceAddIconButton extends StatelessWidget {
  const _WorkspaceAddIconButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
      message: 'Add workspace',
      child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: _purple.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _purple.withValues(alpha: .42))),
              child: const Icon(Icons.add_rounded, color: _text, size: 24))));
}

class _DirectoryBrowserSheet extends StatefulWidget {
  const _DirectoryBrowserSheet({required this.client});
  final DaemonClient client;

  @override
  State<_DirectoryBrowserSheet> createState() => _DirectoryBrowserSheetState();
}

class _DirectoryBrowserSheetState extends State<_DirectoryBrowserSheet> {
  Future<Object>? _future;
  String? _currentPath;

  @override
  void initState() {
    super.initState();
    _future = widget.client.listFileSystemRoots();
  }

  void _open(String path) => setState(() {
        _currentPath = path;
        _future = widget.client.listDirectory(path);
      });

  @override
  Widget build(BuildContext context) => SafeArea(
      top: false,
      child: Container(
          margin: const EdgeInsets.all(12),
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * .78),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
              color: const Color(0xFF0D131D),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: Colors.white.withValues(alpha: .08))),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(
                  child: Text('选择文件夹',
                      style: TextStyle(
                          color: _text,
                          fontSize: 16,
                          fontWeight: FontWeight.w900))),
              if (_currentPath != null)
                _TinyActionButton('选择当前',
                    onTap: () => Navigator.of(context).pop(_currentPath),
                    primary: true),
            ]),
            const SizedBox(height: 6),
            Text(_currentPath ?? '选择磁盘或根目录后继续进入文件夹',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _muted, fontSize: 12)),
            const SizedBox(height: 12),
            Expanded(
                child: FutureBuilder<Object>(
                    future: _future,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(
                            child: CircularProgressIndicator(color: _purple));
                      }
                      if (snapshot.hasError) {
                        return Text(snapshot.error.toString(),
                            style: const TextStyle(color: _red, fontSize: 12));
                      }
                      final data = snapshot.requireData;
                      final entries = data is DirectoryListing
                          ? data.directories
                          : (data as List<DirectoryEntrySummary>);
                      final parent =
                          data is DirectoryListing ? data.parent : null;
                      return ListView(children: [
                        if (parent != null)
                          _DirectoryRow(
                              name: '..',
                              path: parent,
                              onTap: () => _open(parent)),
                        for (final entry in entries)
                          _DirectoryRow(
                              name: entry.name,
                              path: entry.path,
                              onTap: () => _open(entry.path)),
                      ]);
                    }))
          ])));
}

class _DirectoryRow extends StatelessWidget {
  const _DirectoryRow(
      {required this.name, required this.path, required this.onTap});
  final String name;
  final String path;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(children: [
            const Icon(Icons.folder_rounded, color: _purple, size: 17),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: _text, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _faint, fontSize: 11)),
                ])),
            const Icon(Icons.chevron_right_rounded, color: _muted, size: 18)
          ])));
}

class _MiniInput extends StatelessWidget {
  const _MiniInput({required this.controller, required this.hint});
  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) => TextField(
      controller: controller,
      style: _appTextStyle.copyWith(color: _text, fontSize: 12.5),
      decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: _appTextStyle.copyWith(color: _faint, fontSize: 12),
          filled: true,
          fillColor: Colors.white.withValues(alpha: .035),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _stroke)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _stroke)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 10)));
}

class _TinyActionButton extends StatelessWidget {
  const _TinyActionButton(this.label,
      {required this.onTap, this.primary = false});
  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
          height: 38,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
              color: primary
                  ? _purple.withValues(alpha: .24)
                  : Colors.white.withValues(alpha: .04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: primary ? _purple.withValues(alpha: .42) : _stroke)),
          child: Text(label,
              style: TextStyle(
                  color: primary ? _text : _muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w900))));
}

String _compactWorkspacePath(String path) {
  if (path.isEmpty) return '未设置路径';
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/').where((part) => part.isNotEmpty).toList();
  if (parts.length <= 2) return path;
  return '…/${parts[parts.length - 2]}/${parts.last}';
}

String _workspaceDisplayName(WorkspaceSummary workspace) {
  return workspaceDisplayName(workspace);
}
