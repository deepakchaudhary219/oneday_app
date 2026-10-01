import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens/motion.dart';
import 'media_art.dart';

/// Profile picture with an optional story ring. The ring shows only for live (24 h) stories: a pre-attentive
/// "something new" cue, with no seen/unseen pressure (seen rings simply turn neutral).
class OdAvatar extends StatelessWidget {
  const OdAvatar({
    super.key,
    required this.name,
    this.size = 56,
    this.ring = OdRing.none,
    this.seed,
    this.imageUrl,
  });

  final String name;
  final double size;
  final OdRing ring;

  /// Stable illustrated look per person (until they have a photo).
  final int? seed;

  /// The person's photo; the illustration shows while it loads or if it fails.
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final c = context.od;
    final personSeed = seed ?? name.hashCode;
    // A photo when there is one, fading in over the illustrated stand-in (which also covers load errors).
    final face = SizedBox.square(
      dimension: size,
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            OdPortrait(seed: personSeed),
            if (imageUrl != null)
              Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                    .round(),
                frameBuilder: (context, child, frame, sync) => AnimatedOpacity(
                  opacity: sync || frame != null ? 1 : 0,
                  duration: OdMotion.of(context, OdMotion.standard),
                  child: child,
                ),
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
          ],
        ),
      ),
    );
    if (ring == OdRing.none) {
      return Semantics(label: name, image: true, child: face);
    }
    final gap = size * 0.06;
    final stroke = math.max(2.0, size * 0.05);
    return Semantics(
      label: ring == OdRing.live ? '$name, new story' : name,
      image: true,
      child: AnimatedContainer(
        duration: OdMotion.of(context, OdMotion.standard),
        padding: EdgeInsets.all(stroke),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: ring == OdRing.live ? c.brandGradient : null,
          color: ring == OdRing.seen ? c.outline : null,
        ),
        child: Container(
          padding: EdgeInsets.all(gap),
          decoration: BoxDecoration(shape: BoxShape.circle, color: c.canvas),
          child: face,
        ),
      ),
    );
  }
}

enum OdRing { none, live, seen }
