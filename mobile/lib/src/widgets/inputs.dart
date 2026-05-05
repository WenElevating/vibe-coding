import 'package:flutter/material.dart';

import '../theme/theme.dart' as theme;

class AppSearchBar extends StatelessWidget {
  const AppSearchBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
              color: theme.panelHi,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.stroke)),
          child: const Row(children: [
            Icon(Icons.search_rounded, color: theme.muted, size: 18),
            SizedBox(width: 8),
            Text('鎼滅储浠诲姟銆佹弿杩般€佸伐鍏?..',
                style: TextStyle(color: theme.faint, fontSize: 13))
          ]),
        ),
      ),
      const SizedBox(width: 9),
      Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
              color: theme.panelHi,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.stroke)),
          child: const Icon(Icons.filter_alt_rounded,
              color: theme.text, size: 18)),
    ]);
  }
}
