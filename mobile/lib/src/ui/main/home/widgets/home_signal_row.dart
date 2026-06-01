import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart' as theme;
import '../models/home_command_deck_model.dart';
import 'home_status_glyph.dart';
import 'home_surface.dart';

class HomeSignalRow extends StatelessWidget {
  const HomeSignalRow({super.key, required this.item, this.prominent = false});

  final HomeSignalItem item;
  final bool prominent;

  @override
  Widget build(BuildContext context) => HomeSurface(
        prominent: prominent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              HomeStatusGlyph(kind: item.kind, small: true),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 13.5)),
                    const SizedBox(height: 3),
                    Text('${item.workspaceName} / ${item.detail}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(color: theme.muted, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
