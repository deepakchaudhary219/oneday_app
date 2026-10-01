import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens/motion.dart';
import '../tokens/spacing.dart';
import 'pressable.dart';

/// Selectable chip (activities, filters, lenses).
class OdChip extends StatelessWidget {
  const OdChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.od;
    return OdPressable(
      onTap: onTap,
      haptic: OdHaptic.selection,
      semanticLabel: label,
      child: AnimatedContainer(
        duration: OdMotion.of(context, OdMotion.quick),
        curve: OdMotion.standardCurve,
        height:
            36 + (MediaQuery.textScalerOf(context).scale(13) - 13).clamp(0, 24),
        padding: const EdgeInsets.symmetric(horizontal: OdSpace.x1_5),
        decoration: BoxDecoration(
          gradient: selected ? c.brandGradient : null,
          color: selected ? null : c.surfaceRaised,
          borderRadius: BorderRadius.circular(OdRadius.pill),
          border: Border.all(color: selected ? Colors.transparent : c.outline),
        ),
        // Bounded so a long label (or 200% text) ellipsizes instead of overflowing, even in a horizontal list.
        constraints: const BoxConstraints(maxWidth: 240),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: selected ? c.onBrand : c.textSecondary,
              ),
              const SizedBox(width: OdSpace.x0_5),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.type.labelMedium?.copyWith(
                  color: selected ? c.onBrand : c.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "LIVE" badge for live captures and live sessions.
class OdLiveBadge extends StatelessWidget {
  const OdLiveBadge({super.key, this.label = 'LIVE'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: OdSpace.x1, vertical: 3),
      decoration: BoxDecoration(
        color: context.od.live,
        borderRadius: BorderRadius.circular(OdRadius.sm),
      ),
      child: Text(
        label,
        style: context.type.labelSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// A time-left pill (Reaction Window, Right Now). Calm wording, never a ticking countdown: urgency is stated,
/// not manufactured.
class OdTimePill extends StatelessWidget {
  const OdTimePill({
    super.key,
    required this.text,
    this.icon = Icons.schedule_rounded,
  });

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.od;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: OdSpace.x1,
        vertical: OdSpace.x0_5,
      ),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(OdRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c.textSecondary),
          const SizedBox(width: 4),
          Text(text, style: context.type.labelSmall),
        ],
      ),
    );
  }
}
