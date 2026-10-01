import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Placeholder "media" until real photos and videos flow from the API: a deterministic, painterly gradient
/// per seed, so screens look like real content (and screenshots stay stable).
class OdMediaArt extends StatelessWidget {
  const OdMediaArt({super.key, required this.seed, this.child});

  final int seed;
  final Widget? child;

  static const _palettes = [
    [Color(0xFFFF9A62), Color(0xFFE2366F), Color(0xFF3B1E6B)], // sunset
    [Color(0xFF52E5C4), Color(0xFF2A7FDB), Color(0xFF14204A)], // lagoon
    [Color(0xFFFFE07A), Color(0xFF7BC86C), Color(0xFF1D4D3A)], // monsoon green
    [Color(0xFFB794F6), Color(0xFF6B46C1), Color(0xFF1A103D)], // dusk
    [Color(0xFFFFB199), Color(0xFFFF0844), Color(0xFF3D0A1E)], // holi
    [Color(0xFF9BE15D), Color(0xFF00C9A7), Color(0xFF0B3D3A)], // western ghats
  ];

  @override
  Widget build(BuildContext context) {
    final rnd = math.Random(seed);
    final colors = _palettes[seed.abs() % _palettes.length];
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(
              rnd.nextDouble() * 1.6 - 0.8,
              rnd.nextDouble() * 1.2 - 0.9,
            ),
            radius: 1.3,
            colors: colors,
            stops: const [0, 0.55, 1],
          ),
        ),
        child: child ?? const SizedBox.expand(),
      ),
    );
  }
}
