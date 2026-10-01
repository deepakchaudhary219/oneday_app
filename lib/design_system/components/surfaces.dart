import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens/spacing.dart';

/// Frosted glass for chrome over media (camera, stories, pager). Depth comes from blur, not shadows, so the
/// content stays the hero.
class OdFrosted extends StatelessWidget {
  const OdFrosted({
    super.key,
    required this.child,
    this.radius = OdRadius.pill,
    this.padding,
    this.opacity = 0.32,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: opacity),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Top and bottom gradient scrims keep overlaid text legible on any photo.
class OdScrim extends StatelessWidget {
  const OdScrim({super.key, this.top = 0.28, this.bottom = 0.4});

  final double top;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final scrim = context.od.scrim;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [scrim, Colors.transparent, Colors.transparent, scrim],
            stops: [0, top, 1 - bottom, 1],
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// A card surface with continuous-looking corners. It is a [Material], so list tiles and other ink inside it
/// show their press feedback correctly.
class OdCard extends StatelessWidget {
  const OdCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(OdSpace.x2),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.od;
    return Material(
      color: c.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(OdRadius.lg),
        side: BorderSide(color: c.outline.withValues(alpha: 0.6)),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
