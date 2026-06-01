import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart' as theme;
import 'home_surface.dart';

class HomeCommandButton extends StatelessWidget {
  const HomeCommandButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: primary
                ? color.withValues(alpha: .2)
                : Colors.white.withValues(alpha: .045),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: primary
                    ? color.withValues(alpha: .38)
                    : Colors.white.withValues(alpha: .08)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 7),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w900)),
              ),
            ],
          ),
        ),
      );
}

class HomeQuickActionTile extends StatelessWidget {
  const HomeQuickActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: HomeSurface(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(height: 10),
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 13)),
                const SizedBox(height: 4),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: theme.muted, fontSize: 11.5)),
              ],
            ),
          ),
        ),
      );
}

class HomeRoundIconButton extends StatelessWidget {
  const HomeRoundIconButton({
    super.key,
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .045),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: .08)),
          ),
          child: Icon(icon, color: theme.muted, size: 21),
        ),
      );
}
