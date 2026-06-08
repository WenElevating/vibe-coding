import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../../domain/models/daemon_connection_config.dart';
import '../../../mobile_ui_frame.dart';
import '../view_models/daemon_connection_view_model.dart';
import '../widgets/connection_action_button.dart';
import '../widgets/connection_fields.dart';
import '../widgets/connection_header.dart';
import '../widgets/connection_labels.dart';
import '../widgets/connection_proxy_mode_row.dart';
import '../widgets/connection_recent_address_dropdown.dart';
import '../widgets/connection_status_panel.dart';

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
            child: RecentAddressDropdown(
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
                  ConnectionHeader(
                    key: const ValueKey('connection-header'),
                    title: l10n.connectionTitle,
                    subtitle: l10n.connectionSubtitle,
                  ),
                  const SizedBox(height: 22),
                  ConnectionSection(
                    title: l10n.connectionAddressSection,
                    child: CompositedTransformTarget(
                      key: _addressFieldKey,
                      link: _addressFieldLayerLink,
                      child: ConnectionTextField(
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
                  ConnectionSection(
                    title: l10n.connectionProxySection,
                    child: Column(
                      children: [
                        for (final mode in DaemonProxyMode.values)
                          ProxyModeRow(
                            mode: mode,
                            label: connectionProxyModeLabel(l10n, mode),
                            selected: controller.proxyMode == mode,
                            enabled: !controller.isBusy,
                            onTap: () => controller.setProxyMode(mode),
                          ),
                        if (controller.proxyMode == DaemonProxyMode.manual) ...[
                          const SizedBox(height: 2),
                          ConnectionTextField(
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
                  ConnectionStatusPanel(controller: controller, l10n: l10n),
                  const SizedBox(height: 20),
                  ConnectionActionButton(
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
