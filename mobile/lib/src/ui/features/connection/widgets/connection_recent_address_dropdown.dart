import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart' as theme;

class RecentAddressDropdown extends StatelessWidget {
  const RecentAddressDropdown({
    super.key,
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
