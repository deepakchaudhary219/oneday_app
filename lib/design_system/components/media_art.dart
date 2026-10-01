import 'package:flutter/material.dart';

import '../illustration/portrait.dart';
import '../illustration/scene.dart';

export '../illustration/scene.dart' show SceneKind;

/// Stand-in media until real photos and videos load (and in demo mode): a painted place, optionally with the
/// person in it, deterministic per seed so screens look inhabited and screenshots stay stable.
class OdMediaArt extends StatelessWidget {
  const OdMediaArt({
    super.key,
    required this.seed,
    this.activity,
    this.scene,
    this.subject,
    this.child,
  });

  final int seed;

  /// Picks a fitting place ("sunrise trek" → mountains) when [scene] isn't given.
  final String? activity;
  final SceneKind? scene;

  /// The person in the shot, by their seed; null for a scenery-only moment.
  final int? subject;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final kind = scene ?? SceneKind.of(activity, seed);
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: OdScenePainter(kind: kind, seed: seed),
          ),
          if (subject != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                widthFactor: 0.92,
                heightFactor: 0.62,
                child: CustomPaint(
                  painter: OdPortraitPainter(subject!, background: false),
                ),
              ),
            ),
          ?child,
        ],
      ),
    );
  }
}

/// An illustrated person filling its box (square crop), used by avatars without a photo.
class OdPortrait extends StatelessWidget {
  const OdPortrait({super.key, required this.seed, this.background = true});

  final int seed;
  final bool background;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: OdPortraitPainter(seed, background: background),
      size: Size.infinite,
    ),
  );
}
