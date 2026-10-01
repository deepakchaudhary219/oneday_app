import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A deterministic illustrated person (head and shoulders) for demo data, empty states and avatars without a
/// photo. Drawn in code: no assets, no licensing, crisp at any size, and every seed is a different person.
class OdPortraitPainter extends CustomPainter {
  OdPortraitPainter(this.seed, {this.background = true})
    : look = PortraitLook.fromSeed(seed);

  final int seed;
  final bool background;
  final PortraitLook look;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    canvas.save();
    canvas.translate((size.width - s) / 2, size.height - s);
    canvas.scale(s);
    final l = look;
    if (background) {
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 1, 1),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [l.backdrop, Color.lerp(l.backdrop, Colors.black, 0.25)!],
          ).createShader(const Rect.fromLTWH(0, 0, 1, 1)),
      );
    }
    final hair = Paint()..color = l.hair;
    final skinShade = Paint()..color = Color.lerp(l.skin, Colors.black, 0.16)!;

    // Hair that falls behind the head and shoulders.
    switch (l.hairStyle) {
      case HairStyle.long:
        canvas.drawRRect(
          RRect.fromLTRBR(0.27, 0.24, 0.73, 0.86, const Radius.circular(0.2)),
          hair,
        );
      case HairStyle.bob:
        canvas.drawRRect(
          RRect.fromLTRBR(0.26, 0.22, 0.74, 0.62, const Radius.circular(0.16)),
          hair,
        );
      case HairStyle.braid:
        canvas.drawRRect(
          RRect.fromLTRBR(0.29, 0.24, 0.71, 0.58, const Radius.circular(0.16)),
          hair,
        );
        for (var i = 0; i < 4; i++) {
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(0.7, 0.6 + i * 0.07),
              width: 0.08,
              height: 0.085,
            ),
            hair,
          );
        }
      default:
        break;
    }

    // Shoulders and top.
    final shirtRect = const Rect.fromLTRB(0.1, 0.74, 0.9, 1.08);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        shirtRect,
        topLeft: const Radius.circular(0.22),
        topRight: const Radius.circular(0.22),
      ),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [l.shirt, Color.lerp(l.shirt, Colors.black, 0.3)!],
        ).createShader(shirtRect),
    );
    // Neck and neckline.
    canvas.drawRRect(
      RRect.fromLTRBR(0.43, 0.56, 0.57, 0.8, const Radius.circular(0.05)),
      skinShade,
    );
    final neckline = Path()
      ..moveTo(0.41, 0.745)
      ..quadraticBezierTo(0.5, l.vNeck ? 0.88 : 0.83, 0.59, 0.745)
      ..close();
    canvas.drawPath(neckline, skinShade);

    // Ears and earrings.
    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(0.305, 0.45),
        width: 0.07,
        height: 0.1,
      ),
      skinShade,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(0.695, 0.45),
        width: 0.07,
        height: 0.1,
      ),
      skinShade,
    );
    if (l.earrings) {
      final gold = Paint()..color = const Color(0xFFF5C451);
      canvas.drawCircle(const Offset(0.305, 0.515), 0.018, gold);
      canvas.drawCircle(const Offset(0.695, 0.515), 0.018, gold);
    }

    // Head with soft light from the top left.
    final head = Rect.fromCenter(
      center: const Offset(0.5, 0.42),
      width: 0.38,
      height: 0.46,
    );
    canvas.drawOval(
      head,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          radius: 1.1,
          colors: [
            Color.lerp(l.skin, Colors.white, 0.1)!,
            l.skin,
            Color.lerp(l.skin, Colors.black, 0.08)!,
          ],
          stops: const [0, 0.6, 1],
        ).createShader(head),
    );

    if (l.beard) {
      final beard = Path()
        ..moveTo(0.315, 0.44)
        ..quadraticBezierTo(0.33, 0.66, 0.5, 0.67)
        ..quadraticBezierTo(0.67, 0.66, 0.685, 0.44)
        ..quadraticBezierTo(0.66, 0.55, 0.5, 0.56)
        ..quadraticBezierTo(0.34, 0.55, 0.315, 0.44)
        ..close();
      canvas.drawPath(beard, Paint()..color = l.hair.withValues(alpha: 0.9));
    }

    // Face.
    final ink = Paint()..color = const Color(0xFF2A1B17);
    for (final x in const [0.435, 0.565]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, 0.445), width: 0.034, height: 0.042),
        ink,
      );
      canvas.drawCircle(
        Offset(x + 0.007, 0.438),
        0.006,
        Paint()..color = Colors.white.withValues(alpha: 0.85),
      );
    }
    final brow = Paint()
      ..color = Color.lerp(l.hair, Colors.black, 0.2)!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.014
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(0.405, 0.4 - l.browLift),
      const Offset(0.465, 0.393),
      brow,
    );
    canvas.drawLine(
      const Offset(0.535, 0.393),
      Offset(0.595, 0.4 - l.browLift),
      brow,
    );
    final nose = Paint()
      ..color = Color.lerp(l.skin, Colors.black, 0.25)!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.01
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(0.5, 0.46)
        ..quadraticBezierTo(0.485, 0.505, 0.507, 0.508),
      nose,
    );
    final smile = Path()
      ..moveTo(0.455, 0.545)
      ..quadraticBezierTo(0.5, 0.545 + l.smile, 0.545, 0.545);
    if (l.smile > 0.035) {
      canvas.drawPath(smile..close(), Paint()..color = const Color(0xFF7A2E2E));
    } else {
      canvas.drawPath(
        smile,
        Paint()
          ..color = const Color(0xFF7A2E2E)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.012
          ..strokeCap = StrokeCap.round,
      );
    }
    final blush = Paint()
      ..color = const Color(0xFFFF6F7D).withValues(alpha: 0.18);
    canvas.drawCircle(const Offset(0.395, 0.505), 0.03, blush);
    canvas.drawCircle(const Offset(0.605, 0.505), 0.03, blush);
    if (l.bindi) {
      canvas.drawCircle(
        const Offset(0.5, 0.375),
        0.01,
        Paint()..color = const Color(0xFFD7263D),
      );
    }

    // Hair on top of the head.
    switch (l.hairStyle) {
      case HairStyle.curly:
        final rnd = math.Random(seed);
        for (var a = -math.pi; a <= 0.05; a += math.pi / 9) {
          final r = 0.055 + rnd.nextDouble() * 0.02;
          canvas.drawCircle(
            Offset(0.5 + math.cos(a) * 0.19, 0.4 + math.sin(a) * 0.21),
            r,
            hair,
          );
        }
        canvas.drawOval(
          Rect.fromCenter(
            center: const Offset(0.5, 0.25),
            width: 0.36,
            height: 0.14,
          ),
          hair,
        );
      case HairStyle.buzz:
        canvas.drawPath(_cap(0.32, low: 0.36), hair);
      case HairStyle.bun:
        canvas.drawCircle(const Offset(0.5, 0.15), 0.075, hair);
        canvas.drawPath(_cap(0.37, low: 0.4, part: true), hair);
      case HairStyle.short:
        canvas.drawPath(_cap(0.36, low: 0.4, fringe: true), hair);
      default:
        canvas.drawPath(_cap(0.37, low: 0.46, part: true), hair);
    }

    if (l.glasses) {
      final frame = Paint()
        ..color = const Color(0xFF1C1C22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.012;
      for (final x in const [0.435, 0.565]) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(x, 0.448), width: 0.1, height: 0.08),
            const Radius.circular(0.025),
          ),
          frame,
        );
      }
      canvas.drawLine(
        const Offset(0.485, 0.445),
        const Offset(0.515, 0.445),
        frame,
      );
    }
    canvas.restore();
  }

  /// The hair cap over the forehead: [top] is how high it starts, [low] how far down the sides it reaches.
  static Path _cap(
    double width, {
    required double low,
    bool fringe = false,
    bool part = false,
  }) {
    const cx = 0.5;
    final left = cx - width / 2 - 0.01;
    final right = cx + width / 2 + 0.01;
    final p = Path()..moveTo(left, low);
    p.cubicTo(left - 0.01, 0.2, right + 0.01, 0.2, right, low);
    if (fringe) {
      p.quadraticBezierTo(0.6, 0.29, 0.46, 0.33);
      p.quadraticBezierTo(0.37, 0.35, left, low);
    } else if (part) {
      p.quadraticBezierTo(0.66, 0.3, 0.55, 0.3);
      p.quadraticBezierTo(0.42, 0.29, left + 0.02, low);
    } else {
      p.quadraticBezierTo(0.5, 0.28, left, low);
    }
    return p..close();
  }

  @override
  bool shouldRepaint(OdPortraitPainter old) =>
      old.seed != seed || old.background != background;
}

enum HairStyle { short, long, bob, bun, curly, buzz, braid, side }

/// Everything that makes one illustrated person look like themselves, derived from a seed.
class PortraitLook {
  const PortraitLook({
    required this.skin,
    required this.hair,
    required this.shirt,
    required this.backdrop,
    required this.hairStyle,
    required this.glasses,
    required this.earrings,
    required this.beard,
    required this.bindi,
    required this.vNeck,
    required this.smile,
    required this.browLift,
  });

  factory PortraitLook.fromSeed(int seed) {
    final r = math.Random(seed * 7919 + 17);
    T pick<T>(List<T> xs) => xs[r.nextInt(xs.length)];
    final style = pick(HairStyle.values);
    final feminine = const {
      HairStyle.long,
      HairStyle.bob,
      HairStyle.bun,
      HairStyle.braid,
    }.contains(style);
    return PortraitLook(
      skin: pick(_skins),
      hair: pick(_hairs),
      shirt: pick(_shirts),
      backdrop: pick(_backdrops),
      hairStyle: style,
      glasses: r.nextDouble() < 0.25,
      earrings: feminine ? r.nextDouble() < 0.6 : r.nextDouble() < 0.1,
      beard: !feminine && r.nextDouble() < 0.45,
      bindi: feminine && r.nextDouble() < 0.3,
      vNeck: r.nextBool(),
      smile: 0.02 + r.nextDouble() * 0.03,
      browLift: r.nextDouble() * 0.012,
    );
  }

  final Color skin, hair, shirt, backdrop;
  final HairStyle hairStyle;
  final bool glasses, earrings, beard, bindi, vNeck;
  final double smile, browLift;

  static const _skins = [
    Color(0xFFF2C9A5),
    Color(0xFFE3AE86),
    Color(0xFFCF9468),
    Color(0xFFB97C51),
    Color(0xFF9A6240),
    Color(0xFF7A4A2E),
  ];
  static const _hairs = [
    Color(0xFF1B1412),
    Color(0xFF2E1F18),
    Color(0xFF4A2C1D),
    Color(0xFF6B3E26),
    Color(0xFF0F0F14),
    Color(0xFF7D4A6B),
  ];
  static const _shirts = [
    Color(0xFFFF6B5A),
    Color(0xFF3A86FF),
    Color(0xFF2EC4B6),
    Color(0xFFFFB547),
    Color(0xFF8A4DFF),
    Color(0xFFF2387F),
    Color(0xFFF4F1EA),
    Color(0xFF23262F),
  ];
  static const _backdrops = [
    Color(0xFFFFD6C9),
    Color(0xFFC9E4FF),
    Color(0xFFD9F5E5),
    Color(0xFFFFF0B8),
    Color(0xFFE6D9FF),
    Color(0xFFFFD1E3),
  ];
}
