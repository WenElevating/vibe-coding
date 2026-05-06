import 'package:flutter/material.dart';

import '../services/daemon_connection_config.dart';
import '../state/daemon_connection_controller.dart';
import '../theme/theme.dart' as theme;
import '../widgets/widgets.dart';
import 'mobile_ui_frame.dart';

class MobileConnectionPage extends StatefulWidget {
  const MobileConnectionPage({super.key, required this.controller});

  final DaemonConnectionController controller;

  @override
  State<MobileConnectionPage> createState() => _MobileConnectionPageState();
}

class _MobileConnectionPageState extends State<MobileConnectionPage> {
  late final TextEditingController _addressController;
  late final TextEditingController _manualProxyController;

  @override
  void initState() {
    super.initState();
    _addressController =
        TextEditingController(text: widget.controller.addressInput);
    _manualProxyController =
        TextEditingController(text: widget.controller.manualProxyInput);
    widget.controller.addListener(_syncFields);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFields);
    _addressController.dispose();
    _manualProxyController.dispose();
    super.dispose();
  }

  void _syncFields() {
    if (_addressController.text != widget.controller.addressInput) {
      _addressController.text = widget.controller.addressInput;
    }
    if (_manualProxyController.text != widget.controller.manualProxyInput) {
      _manualProxyController.text = widget.controller.manualProxyInput;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        return Scaffold(
          body: MobileUiFrame(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
              children: [
                const TopBar(
                    title: 'Connection',
                    subtitle: 'Confirm daemon target before workspaces load'),
                const SizedBox(height: 18),
                _ConnectionSection(
                  title: 'Connection address',
                  child: _ConnectionTextField(
                    controller: _addressController,
                    enabled: !controller.isBusy,
                    hintText: '127.0.0.1:4317',
                    onChanged: controller.setAddressInput,
                  ),
                ),
                const SizedBox(height: 16),
                _ConnectionSection(
                  title: 'Network proxy',
                  child: Column(
                    children: [
                      for (final mode in DaemonProxyMode.values)
                        _ProxyModeRow(
                          mode: mode,
                          selected: controller.proxyMode == mode,
                          enabled: !controller.isBusy,
                          onTap: () => controller.setProxyMode(mode),
                        ),
                      if (controller.proxyMode == DaemonProxyMode.manual) ...[
                        const SizedBox(height: 2),
                        _ConnectionTextField(
                          controller: _manualProxyController,
                          enabled: !controller.isBusy,
                          hintText: 'http://proxy.local:8080',
                          onChanged: controller.setManualProxyInput,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _ConnectionStatusPanel(controller: controller),
                const SizedBox(height: 18),
                PrimaryButton(
                  controller.status == DaemonConnectionStatus.failed
                      ? 'Reconnect'
                      : 'Connect',
                  onTap: controller.isBusy ? () {} : controller.connect,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ConnectionSection extends StatelessWidget {
  const _ConnectionSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Subhead(title),
          child,
        ],
      );
}

class _ConnectionTextField extends StatelessWidget {
  const _ConnectionTextField({
    required this.controller,
    required this.enabled,
    required this.hintText,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool enabled;
  final String hintText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        enabled: enabled,
        onChanged: onChanged,
        style: const TextStyle(
            color: theme.text,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            fontFamily: 'Consolas'),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(color: theme.faint, fontSize: 13),
          filled: true,
          fillColor: const Color(0xFF101113),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
          border: _border(Colors.white.withValues(alpha: .075)),
          enabledBorder: _border(Colors.white.withValues(alpha: .075)),
          focusedBorder: _border(theme.activeStroke),
          disabledBorder: _border(Colors.white.withValues(alpha: .055)),
        ),
      );

  OutlineInputBorder _border(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color),
      );
}

class _ProxyModeRow extends StatelessWidget {
  const _ProxyModeRow({
    required this.mode,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final DaemonProxyMode mode;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 44,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? theme.activePanel : const Color(0xFF101113),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: selected
                    ? theme.activeStroke
                    : Colors.white.withValues(alpha: .075)),
          ),
          child: Row(children: [
            Expanded(
              child: Text(mode.label,
                  style: TextStyle(
                      color: selected ? theme.active : theme.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w900)),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded,
                  color: theme.muted, size: 18),
          ]),
        ),
      );
}

class _ConnectionStatusPanel extends StatelessWidget {
  const _ConnectionStatusPanel({required this.controller});

  final DaemonConnectionController controller;

  @override
  Widget build(BuildContext context) {
    final failed = controller.status == DaemonConnectionStatus.failed;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101113),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: .075)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Dot(color: failed ? theme.red : theme.green, size: 7),
          const SizedBox(width: 8),
          Text(controller.statusLabel,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
        ]),
        const SizedBox(height: 9),
        Text('Target: ${controller.addressInput}',
            style:
                const TextStyle(color: theme.muted, fontSize: 12, height: 1.4)),
        const SizedBox(height: 4),
        Text('Proxy: ${controller.proxyMode.label}',
            style:
                const TextStyle(color: theme.muted, fontSize: 12, height: 1.4)),
        if (controller.inputError != null ||
            controller.errorSummary != null) ...[
          const SizedBox(height: 10),
          Text(controller.inputError ?? controller.errorSummary!,
              style:
                  const TextStyle(color: theme.red, fontSize: 12, height: 1.4)),
        ],
        if (controller.errorDetail != null) ...[
          const SizedBox(height: 6),
          Text(controller.errorDetail!,
              style: const TextStyle(
                  color: theme.faint, fontSize: 11, height: 1.35)),
        ],
      ]),
    );
  }
}
