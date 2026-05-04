part of '../../app/app.dart';

class _SettingsPage extends StatelessWidget {
  const _SettingsPage(
      {required this.open,
      required this.data,
      required this.streamOutput,
      required this.expandThinking,
      required this.permissionMode,
      required this.onPermissionModeChanged,
      required this.onStreamOutputChanged,
      required this.onExpandThinkingChanged});
  final ValueChanged<_RoutePage> open;
  final _AppSnapshot data;
  final bool streamOutput;
  final bool expandThinking;
  final String permissionMode;
  final ValueChanged<String> onPermissionModeChanged;
  final ValueChanged<bool> onStreamOutputChanged;
  final ValueChanged<bool> onExpandThinkingChanged;

  @override
  Widget build(BuildContext context) {
    return _PageScroll(
      children: [
        const _TopBar(title: '设置'),
        const SizedBox(height: 14),
        _SettingsConnectionCard(
            workspace: data.workspace,
            mode: data.health.mode,
            lanMode: data.health.lanMode),
        const SizedBox(height: 20),
        _Subhead('编码控制'),
        _SettingsCard(children: [
          _PermissionModeRow(
              value: permissionMode, onChanged: onPermissionModeChanged),
          _SettingsSwitchRow(
              title: '流式输出',
              subtitle: '关闭时只显示最终回复，避免 delta 与完整消息重复。',
              value: streamOutput,
              onChanged: onStreamOutputChanged),
          _SettingsSwitchRow(
              title: '显示思考过程',
              subtitle: '开启后默认展开模型 thinking；关闭时折叠显示。',
              value: expandThinking,
              onChanged: onExpandThinkingChanged),
        ]),
        const SizedBox(height: 20),
        _Subhead('数据状态'),
        _SettingsCard(children: [
          _SettingsRow(
              title: '代码诊断', value: '${data.diagnostics.diagnostics.length} 条'),
          _SettingsRow(
              title: 'Git 状态',
              value: data.gitStatus?.clean == true
                  ? '干净'
                  : '${data.gitStatus?.files.length ?? 0} 文件'),
        ]),
        const SizedBox(height: 20),
        _Subhead('关于'),
        _SettingsCard(children: [
          _SettingsRow(title: 'daemon', value: data.health.daemonVersion),
          _SettingsRow(title: '扩展', value: '${data.extensions.length} 个'),
        ]),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
              child: _SettingsActionButton('适配器',
                  icon: Icons.extension_rounded,
                  onTap: () => open(_RoutePage.adapters))),
          const SizedBox(width: 10),
          Expanded(
              child: _SettingsActionButton('通知',
                  icon: Icons.notifications_rounded,
                  onTap: () => open(_RoutePage.notifications))),
        ]),
        const SizedBox(height: 10),
        _SettingsActionButton('生成诊断信息',
            icon: Icons.health_and_safety_rounded,
            fullWidth: true,
            onTap: () => open(_RoutePage.diagnostics)),
      ],
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: const Color(0xFF101113),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: .07))),
      child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Column(children: [
            for (var i = 0; i < children.length; i++) ...[
              children[i],
              if (i != children.length - 1) const _Hairline()
            ],
          ])),
    );
  }
}

class _SettingsConnectionCard extends StatelessWidget {
  const _SettingsConnectionCard(
      {required this.workspace, required this.mode, required this.lanMode});
  final WorkspaceSummary workspace;
  final String mode;
  final bool lanMode;

  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: const Color(0xFF101113),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: .075))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: const Color(0xFF18191C),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: .055))),
              child: const Icon(Icons.lan_rounded, color: _active, size: 18)),
          const SizedBox(width: 11),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('当前连接',
                    style:
                        TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                const SizedBox(height: 4),
                Text(workspace.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color(0xFF858A94),
                        fontSize: 11.5,
                        fontFamily: 'Consolas')),
              ])),
          const _SettingsPill('已连接')
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
              child: _SettingsMetric(
                  label: '工作区', value: _workspaceDisplayName(workspace))),
          const SizedBox(width: 10),
          Expanded(
              child: _SettingsMetric(
                  label: '安全模式', value: lanMode ? 'LAN' : mode)),
        ]),
      ]));
}

class _SettingsMetric extends StatelessWidget {
  const _SettingsMetric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
          color: const Color(0xFF0B0C0E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: .055))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(color: _faint, fontSize: 10.5, height: 1)),
        const SizedBox(height: 7),
        Text(value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900)),
      ]));
}

class _SettingsPill extends StatelessWidget {
  const _SettingsPill(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
          color: _active.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _active.withValues(alpha: .16))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const _Dot(color: _green, size: 5),
        const SizedBox(width: 6),
        Text(text,
            style: const TextStyle(
                color: _active, fontSize: 11, fontWeight: FontWeight.w900)),
      ]));
}

class _SettingsActionButton extends StatelessWidget {
  const _SettingsActionButton(this.text,
      {required this.icon, required this.onTap, this.fullWidth = false});
  final String text;
  final IconData icon;
  final VoidCallback onTap;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
          height: 46,
          width: fullWidth ? double.infinity : null,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
              color: const Color(0xFF101113),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.white.withValues(alpha: .075))),
          child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: _active, size: 16),
                const SizedBox(width: 8),
                Text(text,
                    style: const TextStyle(
                        color: _active,
                        fontSize: 13,
                        fontWeight: FontWeight.w900)),
              ])));
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.title, required this.value});
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(children: [
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
        ])),
        Text(value,
            style: const TextStyle(
                color: _muted, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _PermissionModeRow extends StatelessWidget {
  const _PermissionModeRow({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
              child: Text('权限模式',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14))),
          _PermissionChip(
              label: '默认',
              selected: value == 'default',
              onTap: () => onChanged('default')),
          const SizedBox(width: 8),
          _PermissionChip(
              label: '自动',
              selected: value == 'auto',
              onTap: () => onChanged('auto')),
        ]),
        const SizedBox(height: 8),
        const Text('默认会请求 CLI 权限确认；自动模式由 CLI 处理。',
            style: TextStyle(
                color: Color(0xFF858A94), fontSize: 11.5, height: 1.35)),
      ]));
}

class _PermissionChip extends StatelessWidget {
  const _PermissionChip(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color:
                  selected ? _activePanel : Colors.white.withValues(alpha: .04),
              border: Border.all(
                  color: selected
                      ? _activeStroke.withValues(alpha: .9)
                      : _stroke)),
          child: Text(label,
              style: TextStyle(
                  color: selected ? _active : _muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w900))));
}

class _SettingsSwitchRow extends StatelessWidget {
  const _SettingsSwitchRow(
      {required this.title,
      required this.subtitle,
      required this.value,
      required this.onChanged});
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(children: [
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(subtitle,
              style: const TextStyle(
                  color: Color(0xFF858A94), fontSize: 11.5, height: 1.35))
        ])),
        Switch(
            value: value,
            activeThumbColor: _active,
            activeTrackColor: _activeStroke.withValues(alpha: .55),
            inactiveThumbColor: _faint,
            inactiveTrackColor: _panelHi,
            onChanged: onChanged),
      ]),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      const Spacer(),
      if (action != null)
        GestureDetector(
          onTap: onAction,
          child: Text(action!,
              style: const TextStyle(
                  color: _purple, fontSize: 12, fontWeight: FontWeight.w800)),
        )
    ]);
  }
}

class _Subhead extends StatelessWidget {
  const _Subhead(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: const TextStyle(fontWeight: FontWeight.w800, color: _text)));
}
