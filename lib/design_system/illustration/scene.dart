import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The kinds of places a moment can be: chosen from the activity when known, otherwise from the seed.
enum SceneKind {
  mountains,
  cityNight,
  beach,
  cafe,
  park,
  monsoon,
  concert;

  /// First match wins, so more specific places come first.
  static const _rules = [
    (
      SceneKind.mountains,
      ['trek', 'hike', 'mountain', 'sunrise', 'climb', 'nandi'],
    ),
    (
      SceneKind.cafe,
      [
        'coffee',
        'chai',
        'cafe',
        'café',
        'brunch',
        'food',
        'dinner',
        'book',
        'pottery',
      ],
    ),
    (SceneKind.beach, ['beach', 'sea', 'surf', 'swim', 'sunset', 'goa']),
    (
      SceneKind.concert,
      ['gig', 'concert', 'music', 'dj', 'party', 'dance', 'jam'],
    ),
    (
      SceneKind.park,
      ['run', 'cycl', 'park', 'walk', 'yoga', 'cricket', 'football'],
    ),
    (SceneKind.monsoon, ['rain', 'monsoon']),
    (SceneKind.cityNight, ['night', 'city', 'rooftop', 'drive', 'market']),
  ];

  /// Maps an activity or caption ("sunrise trek", "Coffee", "gig") to the place it most likely happened.
  static SceneKind of(String? activity, int seed) {
    final a = (activity ?? '').toLowerCase();
    for (final (kind, words) in _rules) {
      if (words.any(a.contains)) {
        return kind;
      }
    }
    return SceneKind.values[seed.abs() % SceneKind.values.length];
  }
}

/// A painted place: layered skies, silhouettes and light, deterministic per seed. Stands in for photos in demo
/// mode and behind loading images, so the app always looks inhabited.
class OdScenePainter extends CustomPainter {
  OdScenePainter({required this.kind, required this.seed});

  final SceneKind kind;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.Random(seed * 31 + kind.index);
    switch (kind) {
      case SceneKind.mountains:
        _mountains(canvas, size, r);
      case SceneKind.cityNight:
        _city(canvas, size, r);
      case SceneKind.beach:
        _beach(canvas, size, r);
      case SceneKind.cafe:
        _cafe(canvas, size, r);
      case SceneKind.park:
        _park(canvas, size, r);
      case SceneKind.monsoon:
        _monsoon(canvas, size, r);
      case SceneKind.concert:
        _concert(canvas, size, r);
    }
  }

  void _sky(Canvas c, Size s, List<Color> colors, [List<double>? stops]) {
    final rect = Offset.zero & s;
    c.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
          stops: stops,
        ).createShader(rect),
    );
  }

  void _glow(
    Canvas c,
    Offset at,
    double radius,
    Color color, [
    double strength = 0.7,
  ]) {
    c.drawCircle(
      at,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: strength),
            color.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: at, radius: radius)),
    );
  }

  /// A ridge line across the width: [base] is its average height (0 top, 1 bottom), [rough] the peak size.
  Path _ridge(
    Size s,
    math.Random r,
    double base,
    double rough, {
    int points = 7,
    bool smooth = false,
  }) {
    final p = Path()..moveTo(0, s.height);
    final ys = [
      for (var i = 0; i <= points; i++)
        (base + (r.nextDouble() - 0.5) * rough) * s.height,
    ];
    p.lineTo(0, ys.first);
    for (var i = 1; i <= points; i++) {
      final x = s.width * i / points;
      if (smooth) {
        final px = s.width * (i - 0.5) / points;
        p.quadraticBezierTo(px, ys[i - 1] - rough * s.height * 0.3, x, ys[i]);
      } else {
        final mx = s.width * (i - 0.5) / points;
        p.lineTo(
          mx,
          math.min(ys[i - 1], ys[i]) - r.nextDouble() * rough * s.height,
        );
        p.lineTo(x, ys[i]);
      }
    }
    return p
      ..lineTo(s.width, s.height)
      ..close();
  }

  void _mountains(Canvas c, Size s, math.Random r) {
    _sky(
      c,
      s,
      const [
        Color(0xFF2B2A5C),
        Color(0xFFB8578A),
        Color(0xFFFFA47A),
        Color(0xFFFFD6A0),
      ],
      const [0, 0.42, 0.7, 0.85],
    );
    final sun = Offset(s.width * (0.3 + r.nextDouble() * 0.4), s.height * 0.58);
    _glow(c, sun, s.width * 0.55, const Color(0xFFFFE3A3), 0.8);
    c.drawCircle(sun, s.width * 0.07, Paint()..color = const Color(0xFFFFF4D6));
    const layers = [
      Color(0xFF8E5C8F),
      Color(0xFF5E3D6E),
      Color(0xFF3A2650),
      Color(0xFF1E1530),
    ];
    for (var i = 0; i < layers.length; i++) {
      c.drawPath(
        _ridge(s, r, 0.58 + i * 0.09, 0.12 - i * 0.015, points: 5 + i),
        Paint()..color = layers[i],
      );
      if (i < layers.length - 1) {
        final mist = Rect.fromLTWH(
          0,
          s.height * (0.6 + i * 0.09),
          s.width,
          s.height * 0.08,
        );
        c.drawRect(
          mist,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0),
                Colors.white.withValues(alpha: 0.08),
                Colors.white.withValues(alpha: 0),
              ],
            ).createShader(mist),
        );
      }
    }
  }

  void _city(Canvas c, Size s, math.Random r) {
    _sky(
      c,
      s,
      const [
        Color(0xFF0B0E2A),
        Color(0xFF2A1C5C),
        Color(0xFF6B2C70),
        Color(0xFFE0607E),
      ],
      const [0, 0.45, 0.72, 0.9],
    );
    final stars = Paint()..color = Colors.white.withValues(alpha: 0.7);
    for (var i = 0; i < 40; i++) {
      c.drawCircle(
        Offset(r.nextDouble() * s.width, r.nextDouble() * s.height * 0.4),
        r.nextDouble() * 1.2 + 0.3,
        stars,
      );
    }
    final moon = Offset(s.width * 0.78, s.height * 0.16);
    _glow(c, moon, s.width * 0.25, const Color(0xFFBFC8FF), 0.35);
    c.drawCircle(
      moon,
      s.width * 0.045,
      Paint()..color = const Color(0xFFF2F0FF),
    );
    for (var layer = 0; layer < 2; layer++) {
      final base = Color.lerp(
        const Color(0xFF2A1F4D),
        const Color(0xFF0C0A1C),
        layer.toDouble(),
      )!;
      var x = -r.nextDouble() * 20;
      while (x < s.width) {
        final w = s.width * (0.08 + r.nextDouble() * 0.1);
        final h =
            s.height *
            (layer == 0
                ? 0.25 + r.nextDouble() * 0.3
                : 0.15 + r.nextDouble() * 0.22);
        final top = s.height * 0.86 - h;
        c.drawRect(
          Rect.fromLTWH(x, top, w - 2, h + s.height),
          Paint()..color = base,
        );
        if (layer == 1) {
          final lit = Paint()
            ..color = const Color(0xFFFFD27A).withValues(alpha: 0.85);
          for (var wy = top + 8; wy < s.height * 0.84; wy += 12) {
            for (var wx = x + 5; wx < x + w - 8; wx += 9) {
              if (r.nextDouble() < 0.28) {
                c.drawRect(Rect.fromLTWH(wx, wy, 4, 5), lit);
              }
            }
          }
        }
        x += w;
      }
    }
    final road = Rect.fromLTWH(0, s.height * 0.84, s.width, s.height * 0.16);
    c.drawRect(road, Paint()..color = const Color(0xFF07060F));
    for (var i = 0; i < 14; i++) {
      final color = i.isEven
          ? const Color(0xFFFF4D6D)
          : const Color(0xFFFFE1A8);
      _glow(
        c,
        Offset(
          r.nextDouble() * s.width,
          s.height * (0.87 + r.nextDouble() * 0.08),
        ),
        10 + r.nextDouble() * 14,
        color,
        0.6,
      );
    }
  }

  void _beach(Canvas c, Size s, math.Random r) {
    _sky(
      c,
      s,
      const [Color(0xFF3B3D8F), Color(0xFFE86A8A), Color(0xFFFFB36B)],
      const [0, 0.4, 0.58],
    );
    final horizon = s.height * 0.58;
    final sun = Offset(s.width * (0.35 + r.nextDouble() * 0.3), horizon);
    _glow(c, sun, s.width * 0.6, const Color(0xFFFFD08A), 0.7);
    c.save();
    c.clipRect(Rect.fromLTWH(0, 0, s.width, horizon));
    c.drawCircle(sun, s.width * 0.11, Paint()..color = const Color(0xFFFFE9B8));
    c.restore();
    final sea = Rect.fromLTWH(0, horizon, s.width, s.height * 0.27);
    c.drawRect(
      sea,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFB55A86), Color(0xFF3B3570)],
        ).createShader(sea),
    );
    final shimmer = Paint()
      ..color = const Color(0xFFFFE2B0).withValues(alpha: 0.6);
    for (var i = 0; i < 18; i++) {
      final y = horizon + 4 + i * (s.height * 0.012);
      final w = s.width * (0.2 - i * 0.008) * (0.6 + r.nextDouble() * 0.6);
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(sun.dx + (r.nextDouble() - 0.5) * 20, y),
            width: w.abs(),
            height: 2,
          ),
          const Radius.circular(1),
        ),
        shimmer,
      );
    }
    final sand = _ridge(s, r, 0.88, 0.04, points: 3, smooth: true);
    c.drawPath(sand, Paint()..color = const Color(0xFF2A1E3A));
    // A palm on one side.
    final left = r.nextBool();
    final trunkX = left ? s.width * 0.12 : s.width * 0.88;
    final trunk = Paint()
      ..color = const Color(0xFF1A1226)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.width * 0.025
      ..strokeCap = StrokeCap.round;
    final top = Offset(
      trunkX + (left ? 1 : -1) * s.width * 0.08,
      s.height * 0.42,
    );
    c.drawPath(
      Path()
        ..moveTo(trunkX, s.height * 0.92)
        ..quadraticBezierTo(trunkX, s.height * 0.6, top.dx, top.dy),
      trunk,
    );
    final leaf = Paint()..color = const Color(0xFF1A1226);
    for (var i = 0; i < 6; i++) {
      final a = -math.pi + i * math.pi / 5;
      final end =
          top + Offset(math.cos(a), math.sin(a) * 0.5 + 0.35) * s.width * 0.16;
      c.drawPath(
        Path()
          ..moveTo(top.dx, top.dy)
          ..quadraticBezierTo(
            (top.dx + end.dx) / 2,
            top.dy - s.width * 0.05,
            end.dx,
            end.dy,
          )
          ..quadraticBezierTo(
            (top.dx + end.dx) / 2,
            top.dy + s.width * 0.01,
            top.dx,
            top.dy,
          ),
        leaf,
      );
    }
  }

  void _cafe(Canvas c, Size s, math.Random r) {
    _sky(c, s, const [Color(0xFF2B1A14), Color(0xFF5A3424), Color(0xFF8A5236)]);
    const warm = [
      Color(0xFFFFC46B),
      Color(0xFFFF9A5A),
      Color(0xFFFFE3A8),
      Color(0xFFFF7A6B),
    ];
    for (var i = 0; i < 22; i++) {
      final at = Offset(
        r.nextDouble() * s.width,
        r.nextDouble() * s.height * 0.65,
      );
      final rad = s.width * (0.03 + r.nextDouble() * 0.09);
      c.drawCircle(
        at,
        rad,
        Paint()
          ..color = warm[r.nextInt(warm.length)].withValues(
            alpha: 0.18 + r.nextDouble() * 0.3,
          )
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, rad * 0.25),
      );
    }
    // Pendant lamps.
    for (final fx in [0.25, 0.75]) {
      final x = s.width * fx;
      c.drawLine(
        Offset(x, 0),
        Offset(x, s.height * 0.22),
        Paint()
          ..color = const Color(0xFF140C08)
          ..strokeWidth = 2,
      );
      _glow(
        c,
        Offset(x, s.height * 0.26),
        s.width * 0.28,
        const Color(0xFFFFC879),
        0.55,
      );
      c.drawPath(
        Path()
          ..moveTo(x - s.width * 0.07, s.height * 0.27)
          ..lineTo(x - s.width * 0.03, s.height * 0.22)
          ..lineTo(x + s.width * 0.03, s.height * 0.22)
          ..lineTo(x + s.width * 0.07, s.height * 0.27)
          ..close(),
        Paint()..color = const Color(0xFF1A100B),
      );
    }
    final table = Rect.fromLTWH(0, s.height * 0.74, s.width, s.height * 0.26);
    c.drawRect(
      table,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF6B3F27), Color(0xFF2A160D)],
        ).createShader(table),
    );
    // A cup with steam.
    final cx = s.width * (0.3 + r.nextDouble() * 0.4);
    final cupTop = s.height * 0.66;
    final cup = Path()
      ..moveTo(cx - s.width * 0.09, cupTop)
      ..lineTo(cx + s.width * 0.09, cupTop)
      ..quadraticBezierTo(
        cx + s.width * 0.085,
        cupTop + s.height * 0.1,
        cx,
        cupTop + s.height * 0.1,
      )
      ..quadraticBezierTo(
        cx - s.width * 0.085,
        cupTop + s.height * 0.1,
        cx - s.width * 0.09,
        cupTop,
      )
      ..close();
    c.drawOval(
      Rect.fromCenter(
        center: Offset(cx, cupTop + s.height * 0.1),
        width: s.width * 0.3,
        height: s.height * 0.025,
      ),
      Paint()..color = const Color(0xFFF1E6DA),
    );
    c.drawPath(cup, Paint()..color = const Color(0xFFF7EFE6));
    c.drawOval(
      Rect.fromCenter(
        center: Offset(cx, cupTop),
        width: s.width * 0.18,
        height: s.height * 0.022,
      ),
      Paint()..color = const Color(0xFF6B3B1F),
    );
    c.drawCircle(
      Offset(cx + s.width * 0.1, cupTop + s.height * 0.03),
      s.width * 0.025,
      Paint()
        ..color = const Color(0xFFF7EFE6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s.width * 0.012,
    );
    final steam = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (final dx in [-0.03, 0.0, 0.03]) {
      final x = cx + s.width * dx;
      c.drawPath(
        Path()
          ..moveTo(x, cupTop - 6)
          ..cubicTo(x - 10, cupTop - 30, x + 10, cupTop - 45, x, cupTop - 70),
        steam,
      );
    }
  }

  void _park(Canvas c, Size s, math.Random r) {
    _sky(
      c,
      s,
      const [Color(0xFF6EC3F4), Color(0xFFBFE6F7), Color(0xFFFFF1C9)],
      const [0, 0.5, 0.7],
    );
    _glow(
      c,
      Offset(s.width * 0.8, s.height * 0.15),
      s.width * 0.4,
      const Color(0xFFFFF6C9),
      0.8,
    );
    final cloud = Paint()..color = Colors.white.withValues(alpha: 0.85);
    for (var i = 0; i < 3; i++) {
      final at = Offset(
        r.nextDouble() * s.width,
        s.height * (0.1 + r.nextDouble() * 0.25),
      );
      for (var j = 0; j < 4; j++) {
        c.drawCircle(
          at + Offset(j * s.width * 0.05, (j.isOdd ? -1 : 0) * s.width * 0.02),
          s.width * 0.045,
          cloud,
        );
      }
    }
    const hills = [
      Color(0xFF9ED67A),
      Color(0xFF6DBE5C),
      Color(0xFF3E9A4D),
      Color(0xFF256F3C),
    ];
    for (var i = 0; i < hills.length; i++) {
      c.drawPath(
        _ridge(s, r, 0.6 + i * 0.09, 0.08, points: 3, smooth: true),
        Paint()..color = hills[i],
      );
      if (i == 1 || i == 2) {
        for (var t = 0; t < 4; t++) {
          final x = r.nextDouble() * s.width;
          final y = s.height * (0.58 + i * 0.09);
          final h = s.height * (0.06 + i * 0.03);
          c.drawRect(
            Rect.fromLTWH(x - 2, y - h * 0.4, 4 + i.toDouble(), h * 0.5),
            Paint()..color = const Color(0xFF4A3426),
          );
          c.drawCircle(
            Offset(x, y - h * 0.55),
            h * 0.38,
            Paint()..color = Color.lerp(hills[i], Colors.black, 0.25)!,
          );
        }
      }
    }
    final path = Path()
      ..moveTo(s.width * 0.45, s.height)
      ..quadraticBezierTo(
        s.width * 0.6,
        s.height * 0.85,
        s.width * 0.52,
        s.height * 0.72,
      )
      ..lineTo(s.width * 0.55, s.height * 0.72)
      ..quadraticBezierTo(
        s.width * 0.7,
        s.height * 0.86,
        s.width * 0.62,
        s.height,
      )
      ..close();
    c.drawPath(
      path,
      Paint()..color = const Color(0xFFE9D7A8).withValues(alpha: 0.8),
    );
  }

  void _monsoon(Canvas c, Size s, math.Random r) {
    _sky(c, s, const [Color(0xFF3A4A5C), Color(0xFF6C8291), Color(0xFF9FB2AE)]);
    const hills = [
      Color(0xFF5E7F6E),
      Color(0xFF3F6553),
      Color(0xFF274A3B),
      Color(0xFF173226),
    ];
    for (var i = 0; i < hills.length; i++) {
      c.drawPath(
        _ridge(s, r, 0.5 + i * 0.12, 0.14, points: 4, smooth: true),
        Paint()..color = hills[i],
      );
    }
    final rain = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 160; i++) {
      final x = r.nextDouble() * s.width;
      final y = r.nextDouble() * s.height;
      final len = 10 + r.nextDouble() * 18;
      c.drawLine(Offset(x, y), Offset(x - len * 0.25, y + len), rain);
    }
  }

  void _concert(Canvas c, Size s, math.Random r) {
    _sky(c, s, const [Color(0xFF07040F), Color(0xFF1A0B2E), Color(0xFF2B0F3A)]);
    const beams = [
      Color(0xFFFF3D7F),
      Color(0xFF7B5CFF),
      Color(0xFF2EE6D6),
      Color(0xFFFFC94D),
    ];
    for (var i = 0; i < 6; i++) {
      final origin = Offset(s.width * (0.1 + i * 0.16), s.height * 0.02);
      final spread = s.width * 0.18;
      final target = Offset(
        origin.dx + (r.nextDouble() - 0.5) * s.width * 0.9,
        s.height * 0.85,
      );
      final beam = Path()
        ..moveTo(origin.dx, origin.dy)
        ..lineTo(target.dx - spread, target.dy)
        ..lineTo(target.dx + spread, target.dy)
        ..close();
      final color = beams[i % beams.length];
      c.drawPath(
        beam,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.linear(origin, target, [
            color.withValues(alpha: 0.55),
            color.withValues(alpha: 0),
          ]),
      );
      _glow(c, origin, 18, color, 0.9);
    }
    final crowd = Paint()..color = const Color(0xFF05030A);
    var x = -10.0;
    while (x < s.width + 10) {
      final hr = s.width * (0.035 + r.nextDouble() * 0.02);
      final y = s.height * (0.84 + r.nextDouble() * 0.04);
      c.drawCircle(Offset(x, y), hr, crowd);
      c.drawRRect(
        RRect.fromLTRBR(
          x - hr * 1.6,
          y + hr * 0.6,
          x + hr * 1.6,
          s.height,
          Radius.circular(hr),
        ),
        crowd,
      );
      if (r.nextDouble() < 0.18) {
        c.drawLine(
          Offset(x + hr, y),
          Offset(x + hr * 2.2, y - hr * 3.5),
          crowd..strokeWidth = hr * 0.5,
        );
        c.drawCircle(
          Offset(x + hr * 2.2, y - hr * 3.6),
          hr * 0.35,
          Paint()..color = const Color(0xFFFFF3C4),
        );
      }
      x += hr * 2.4;
    }
  }

  @override
  bool shouldRepaint(OdScenePainter old) =>
      old.kind != kind || old.seed != seed;
}
