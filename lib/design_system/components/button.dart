import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens/motion.dart';
import '../tokens/spacing.dart';
import 'pressable.dart';

enum OdButtonVariant {
  /// The one main action on a screen: the brand gradient.
  primary,

  /// Secondary actions: a solid neutral.
  secondary,

  /// Low emphasis: text only.
  ghost,

  /// Irreversible actions (block, delete).
  danger,
}

/// Pill button with a loading state that keeps its size, so layouts never jump.
class OdButton extends StatelessWidget {
  const OdButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = OdButtonVariant.primary,
    this.icon,
    this.loading = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final OdButtonVariant variant;
  final IconData? icon;
  final bool loading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = context.od;
    final foreground = switch (variant) {
      OdButtonVariant.primary || OdButtonVariant.danger => c.onBrand,
      OdButtonVariant.secondary => c.textPrimary,
      OdButtonVariant.ghost => c.brand,
    };
    final decoration = switch (variant) {
      OdButtonVariant.primary => BoxDecoration(
        gradient: c.brandGradient,
        borderRadius: BorderRadius.circular(OdRadius.pill),
        boxShadow: [
          BoxShadow(
            color: c.brand.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      OdButtonVariant.secondary => BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(OdRadius.pill),
        border: Border.all(color: c.outline),
      ),
      OdButtonVariant.ghost => const BoxDecoration(),
      OdButtonVariant.danger => BoxDecoration(
        color: c.danger,
        borderRadius: BorderRadius.circular(OdRadius.pill),
      ),
    };
    final content = AnimatedSwitcher(
      duration: OdMotion.of(context, OdMotion.quick),
      child: loading
          ? SizedBox.square(
              key: const ValueKey('loading'),
              dimension: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: foreground,
              ),
            )
          : Row(
              key: const ValueKey('label'),
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: foreground),
                  const SizedBox(width: OdSpace.x1),
                ],
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: context.type.labelLarge?.copyWith(color: foreground),
                  ),
                ),
              ],
            ),
    );
    return OdPressable(
      onTap: loading ? null : onPressed,
      semanticLabel: label,
      haptic: variant == OdButtonVariant.danger
          ? OdHaptic.medium
          : OdHaptic.light,
      child: Container(
        constraints: const BoxConstraints(
          minHeight: OdSpace.minTap,
          minWidth: OdSpace.minTap * 2,
        ),
        width: expand ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: OdSpace.x3),
        decoration: decoration,
        alignment: Alignment.center,
        child: content,
      ),
    );
  }
}

/// A circular icon button with a frosted or solid background, used over media and in bars.
class OdIconButton extends StatelessWidget {
  const OdIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.size = 44,
    this.background,
    this.foreground,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String semanticLabel;
  final double size;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final c = context.od;
    return OdPressable(
      onTap: onPressed,
      semanticLabel: semanticLabel,
      haptic: OdHaptic.selection,
      pressedScale: 0.9,
      child: SizedBox.square(
        dimension: OdSpace.minTap,
        child: Center(
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: background ?? c.surfaceRaised,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: size * 0.5,
              color: foreground ?? c.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
