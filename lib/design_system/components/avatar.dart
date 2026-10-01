import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens/motion.dart';

/// Initials avatar with an optional story ring. The ring shows only for live (24 h) stories: a pre-attentive
/// "something new" cue, with no seen/unseen pressure (seen rings simply turn neutral).
class OdAvatar extends StatelessWidget {
  const OdAvatar({
    super.key,
    required this.name,
    this.size = 56,
    this.ring = OdRing.none,
    this.seed,
  });

  final String name;
  final double size;
  final OdRing ring;

  /// Stable colour per person.
  final int? seed;

  @override
  Widget build(BuildContext context) {
    final c = context.od;
    final palette = [
      const Color(0xFF8A4DFF),
      const Color(0xFFFF6B5A),
      const Color(0xFF2EC4B6),
      const Color(0xFFF2387F),
      const Color(0xFF3A86FF),
      const Color(0xFFFFB547),
    ];
    final color = palette[(seed ?? name.hashCode).abs() % palette.length];
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().characters.first.toUpperCase();
    final face = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, Color.lerp(color, Colors.black, 0.35)!],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.4,
          fontWeight: FontWeight.w700,
          height: 1,
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
