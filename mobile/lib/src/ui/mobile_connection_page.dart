import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../domain/models/daemon_connection_config.dart';
import 'features/connection/view_models/daemon_connection_view_model.dart';
import 'core/theme/theme.dart' as theme;
import 'mobile_ui_frame.dart';

class MobileConnectionPage extends StatefulWidget {
  const MobileConnectionPage({super.key, required this.controller});

  final DaemonConnectionViewModel controller;

  @override
  State<MobileConnectionPage> createState() => _MobileConnectionPageState();
}

class _MobileConnectionPageState extends State<MobileConnectionPage> {
  static const double _recentDropdownGap = 8;

  late final TextEditingController _addressController;
  late final TextEditingController _manualProxyController;
  late final FocusNode _addressFocusNode;
  final LayerLink _addressFieldLayerLink = LayerLink();
  final GlobalKey _addressFieldKey = GlobalKey();
  OverlayEntry? _recentDropdownEntry;
  bool _recentDropdownOpen = false;
  bool _suppressNextRecentFocusOpen = false;

  @override
  void initState() {
    super.initState();
    _addressController =
        TextEditingController(text: widget.controller.addressInput);
    _manualProxyController =
        TextEditingController(text: widget.controller.manualProxyInput);
    _addressFocusNode = FocusNode(onKeyEvent: _handleAddressKeyEvent)
      ..addListener(_handleAddressFocusChanged);
    widget.controller.addListener(_syncFields);
  }

  @override
  void dispose() {
    _removeRecentDropdownOverlay();
    widget.controller.removeListener(_syncFields);
    _addressFocusNode
      ..removeListener(_handleAddressFocusChanged)
      ..dispose();
    _addressController.dispose();
    _manualProxyController.dispose();
    super.dispose();
  }

  void _handleAddressFocusChanged() {
    if (!_addressFocusNode.hasFocus) {
      _closeRecentDropdown();
      return;
    }
    if (_suppressNextRecentFocusOpen) {
      _suppressNextRecentFocusOpen = false;
      return;
    }
    _openRecentDropdown();
  }

  KeyEventResult _handleAddressKeyEvent(FocusNode node, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    return _handleEscape() ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  void _openRecentDropdown() {
    if (widget.controller.recentAddresses.isEmpty) {
      _closeRecentDropdown();
      return;
    }
    if (_filteredRecentAddresses(widget.controller).isEmpty) {
      _closeRecentDropdown();
      return;
    }
    if (!_recentDropdownOpen) {
      setState(() => _recentDropdownOpen = true);
    }
    _scheduleRecentDropdownOverlaySync();
  }

  void _closeRecentDropdown() {
    _removeRecentDropdownOverlay();
    if (!_recentDropdownOpen || !mounted) {
      return;
    }
    setState(() => _recentDropdownOpen = false);
  }

  void _syncFields() {
    if (_addressController.text != widget.controller.addressInput) {
      _addressController.text = widget.controller.addressInput;
    }
    if (_manualProxyController.text != widget.controller.manualProxyInput) {
      _manualProxyController.text = widget.controller.manualProxyInput;
    }
    if (!_recentDropdownOpen) {
      return;
    }
    if (_recentDropdownVisible()) {
      _scheduleRecentDropdownOverlaySync();
    } else {
      _closeRecentDropdown();
    }
  }

  void _handleAddressChanged(String value) {
    widget.controller.setAddressInput(value);
    if (!_addressFocusNode.hasFocus) {
      return;
    }
    _openRecentDropdown();
  }

  void _selectRecentAddress(String address) {
    _suppressNextRecentFocusOpen = true;
    widget.controller.selectRecentAddress(address);
    _addressController.selection = TextSelection.collapsed(
      offset: _addressController.text.length,
    );
    _closeRecentDropdown();
    _addressFocusNode.requestFocus();
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.show'));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _suppressNextRecentFocusOpen = false;
    });
  }

  bool _handleEscape() {
    if (!_recentDropdownVisible()) {
      return false;
    }
    _closeRecentDropdown();
    return true;
  }

  void _handlePopInvoked(bool didPop) {
    if (!didPop && _recentDropdownVisible()) {
      _closeRecentDropdown();
    }
  }

  bool _recentDropdownVisible() {
    return _recentDropdownOpen &&
        _filteredRecentAddresses(widget.controller).isNotEmpty;
  }

  void _scheduleRecentDropdownOverlaySync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (_recentDropdownVisible()) {
        _showOrUpdateRecentDropdownOverlay();
      } else {
        _removeRecentDropdownOverlay();
      }
    });
  }

  void _showOrUpdateRecentDropdownOverlay() {
    if (_recentDropdownEntry == null) {
      final overlay = Overlay.of(context);
      _recentDropdownEntry = OverlayEntry(
        builder: _buildRecentDropdownOverlay,
      );
      overlay.insert(_recentDropdownEntry!);
      return;
    }
    _recentDropdownEntry?.markNeedsBuild();
  }

  void _removeRecentDropdownOverlay() {
    _recentDropdownEntry?.remove();
    _recentDropdownEntry = null;
  }

  Widget _buildRecentDropdownOverlay(BuildContext context) {
    final fieldContext = _addressFieldKey.currentContext;
    final renderObject = fieldContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return const SizedBox.shrink();
    }
    final addresses = _filteredRecentAddresses(widget.controller);
    if (addresses.isEmpty) {
      return const SizedBox.shrink();
    }
    return Positioned.fill(
      child: CompositedTransformFollower(
        link: _addressFieldLayerLink,
        showWhenUnlinked: false,
        targetAnchor: Alignment.bottomLeft,
        followerAnchor: Alignment.topLeft,
        offset: const Offset(0, _recentDropdownGap),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: renderObject.size.width,
            child: _RecentAddressDropdown(
              addresses: addresses,
              onSelected: _selectRecentAddress,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final l10n = AppLocalizations.of(context);
        final filteredRecentAddresses = _filteredRecentAddresses(controller);
        final showRecentDropdown =
            _recentDropdownOpen && filteredRecentAddresses.isNotEmpty;
        _scheduleRecentDropdownOverlaySync();

        final page = PopScope(
          canPop: !showRecentDropdown,
          onPopInvokedWithResult: (didPop, result) => _handlePopInvoked(didPop),
          child: Scaffold(
            body: MobileUiFrame(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
                children: [
                  _ConnectionHeader(
                    key: const ValueKey('connection-header'),
                    title: l10n.connectionTitle,
                    subtitle: l10n.connectionSubtitle,
                  ),
                  const SizedBox(height: 22),
                  _ConnectionSection(
                    title: l10n.connectionAddressSection,
                    child: CompositedTransformTarget(
                      key: _addressFieldKey,
                      link: _addressFieldLayerLink,
                      child: _ConnectionTextField(
                        controller: _addressController,
                        focusNode: _addressFocusNode,
                        enabled: !controller.isBusy,
                        hintText: '127.0.0.1:4317',
                        onTap: _openRecentDropdown,
                        onChanged: _handleAddressChanged,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _ConnectionSection(
                    title: l10n.connectionProxySection,
                    child: Column(
                      children: [
                        for (final mode in DaemonProxyMode.values)
                          _ProxyModeRow(
                            mode: mode,
                            label: _proxyModeLabel(l10n, mode),
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
                  const SizedBox(height: 18),
                  _ConnectionStatusPanel(controller: controller, l10n: l10n),
                  const SizedBox(height: 20),
                  _ConnectionActionButton(
                    controller.status == DaemonConnectionStatus.failed
                        ? l10n.connectionReconnectAction
                        : l10n.connectionConnectAction,
                    enabled: !controller.isBusy,
                    onTap: controller.connect,
                  ),
                ],
              ),
            ),
          ),
        );
        if (!showRecentDropdown) {
          return page;
        }
        return Shortcuts(
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              DismissIntent: CallbackAction<DismissIntent>(
                onInvoke: (intent) {
                  _handleEscape();
                  return null;
                },
              ),
            },
            child: page,
          ),
        );
      },
    );
  }

  List<String> _filteredRecentAddresses(DaemonConnectionViewModel controller) {
    final query = _addressController.text.toLowerCase();
    if (query.isEmpty) {
      return controller.recentAddresses;
    }
    return controller.recentAddresses
        .where((address) => address.toLowerCase().contains(query))
        .toList(growable: false);
  }
}

class _ConnectionHeader extends StatelessWidget {
  const _ConnectionHeader({
    super.key,
    required this.title,
    required this.subtitle,
  });
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              color: theme.faint,
              fontSize: 12.5,
              height: 1.35,
              letterSpacing: .1,
            ),
          ),
        ],
      );
}

class _ConnectionSection extends StatelessWidget {
  const _ConnectionSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 9),
              child: Text(title.toUpperCase(),
                  style: const TextStyle(
                      color: theme.faint,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.1))),
          child,
        ],
      );
}

class _ConnectionTextField extends StatelessWidget {
  const _ConnectionTextField({
    required this.controller,
    this.focusNode,
    this.onTap,
    required this.enabled,
    required this.hintText,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final VoidCallback? onTap;
  final bool enabled;
  final String hintText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        onTap: onTap,
        onChanged: onChanged,
        style: const TextStyle(
            color: theme.text,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            fontFamily: 'Consolas'),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(color: theme.faint, fontSize: 13),
          filled: true,
          fillColor: const Color(0xFF0D0F12),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: _border(Colors.white.withValues(alpha: .07)),
          enabledBorder: _border(Colors.white.withValues(alpha: .07)),
          focusedBorder: _border(theme.activeStroke),
          disabledBorder: _border(Colors.white.withValues(alpha: .055)),
        ),
      );

  OutlineInputBorder _border(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color),
      );
}

class _RecentAddressDropdown extends StatelessWidget {
  const _RecentAddressDropdown({
    required this.addresses,
    required this.onSelected,
  });

  static const double _rowHeight = 44;
  static const double _maxHeight = 184;

  final List<String> addresses;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => Material(
        key: const ValueKey('connection-recent-address-dropdown'),
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(12),
        elevation: 12,
        shadowColor: Colors.black.withValues(alpha: .38),
        child: Container(
          constraints: const BoxConstraints(maxHeight: _maxHeight),
          decoration: BoxDecoration(
            color: const Color(0xFF101419),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: .10)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .34),
                blurRadius: 18,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              shrinkWrap: true,
              itemExtent: _rowHeight,
              itemCount: addresses.length,
              itemBuilder: (context, index) {
                final address = addresses[index];
                void selectAddress() => onSelected(address);
                return Semantics(
                  label: address,
                  button: true,
                  onTap: selectAddress,
                  child: ExcludeSemantics(
                    child: InkWell(
                      onTap: selectAddress,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            address,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: theme.muted,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Consolas',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
}

class _ProxyModeRow extends StatelessWidget {
  const _ProxyModeRow({
    required this.mode,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final DaemonProxyMode mode;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 42,
          margin: const EdgeInsets.only(bottom: 7),
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF151A20) : const Color(0xFF0D0F12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: selected
                    ? const Color(0xFF586574)
                    : Colors.white.withValues(alpha: .065)),
          ),
          child: Row(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                  color: selected ? theme.green : theme.faint,
                  shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: selected ? theme.text : theme.muted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900)),
            ),
            if (selected)
              const Icon(Icons.check_rounded, color: theme.active, size: 17),
          ]),
        ),
      );
}

class _ConnectionStatusPanel extends StatelessWidget {
  const _ConnectionStatusPanel({required this.controller, required this.l10n});

  final DaemonConnectionViewModel controller;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final failed = controller.status == DaemonConnectionStatus.failed;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0F12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: .07)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                  color: failed ? theme.red : theme.green,
                  shape: BoxShape.circle)),
          const SizedBox(width: 9),
          Expanded(
              child: Text(_connectionStatusLabel(l10n, controller.status),
                  style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.1))),
          _ConnectionStatusTrailing(controller: controller, l10n: l10n),
        ]),
        const SizedBox(height: 12),
        _ConnectionMetaRow(
            label: l10n.connectionTargetLabel, value: controller.addressInput),
        const SizedBox(height: 6),
        _ConnectionMetaRow(
            label: l10n.connectionProxyLabel,
            value: _proxyModeLabel(l10n, controller.proxyMode)),
        if (controller.inputError != null ||
            controller.errorSummary != null) ...[
          const SizedBox(height: 12),
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

class _ConnectionStatusTrailing extends StatelessWidget {
  const _ConnectionStatusTrailing(
      {required this.controller, required this.l10n});
  final DaemonConnectionViewModel controller;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    if (controller.isBusy) {
      return const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.green,
              backgroundColor: Color(0x2232D583)));
    }
    if (controller.status == DaemonConnectionStatus.failed) {
      return Text(l10n.connectionStatusError,
          style: const TextStyle(
              color: theme.red,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.1));
    }
    return const SizedBox.shrink();
  }
}

String _connectionStatusLabel(
        AppLocalizations l10n, DaemonConnectionStatus status) =>
    switch (status) {
      DaemonConnectionStatus.loadingConfig =>
        l10n.connectionStatusLoadingConfig,
      DaemonConnectionStatus.idle => l10n.connectionStatusIdle,
      DaemonConnectionStatus.validating => l10n.connectionStatusValidating,
      DaemonConnectionStatus.checkingHealth =>
        l10n.connectionStatusCheckingHealth,
      DaemonConnectionStatus.loadingSnapshot =>
        l10n.connectionStatusLoadingSnapshot,
      DaemonConnectionStatus.connected => l10n.connectionStatusConnected,
      DaemonConnectionStatus.failed => l10n.connectionStatusFailed,
    };

String _proxyModeLabel(AppLocalizations l10n, DaemonProxyMode mode) =>
    switch (mode) {
      DaemonProxyMode.direct => l10n.settingsProxyDirect,
      DaemonProxyMode.system => l10n.settingsProxySystem,
      DaemonProxyMode.manual => l10n.settingsProxyManual,
    };

class _ConnectionMetaRow extends StatelessWidget {
  const _ConnectionMetaRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(children: [
        SizedBox(
            width: 48,
            child: Text(label,
                style: const TextStyle(
                    color: theme.faint,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .2))),
        Expanded(
            child: Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: theme.muted,
                    fontSize: 12,
                    fontFamily: 'Consolas',
                    height: 1.35))),
      ]);
}

class _ConnectionActionButton extends StatelessWidget {
  const _ConnectionActionButton(this.text,
      {required this.enabled, required this.onTap});
  final String text;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final backgroundColor =
        enabled ? const Color(0xFFE3E6EA) : const Color(0xFF333941);
    final foregroundColor =
        enabled ? const Color(0xFF080A0D) : const Color(0xFF888F98);

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: .12))),
          child: Text(text,
              style: TextStyle(
                  color: foregroundColor,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .1))),
    );
  }
}
