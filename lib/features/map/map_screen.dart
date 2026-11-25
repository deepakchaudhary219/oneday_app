import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_error.dart';
import '../../core/providers.dart';
import '../../core/repositories.dart';
import '../../core/story_map.dart';
import '../../design_system/design_system.dart';

/// The Story Map (Snap Map's idea, OneDay's privacy): public stories as glowing, k-anonymous area clusters,
/// never a pin on a person. Lenses (Roots, language, activity, Today's Prompt) filter what lights up. The painter
/// stands in for the map SDK's dark style until it's wired.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

/// An area placed on the canvas: [at] is a fraction of the width and height.
class _Area {
  const _Area(this.area, this.at);

  final MapArea area;
  final Offset at;

  String get name => area.name;

  int get count => area.count;

  int get seed => area.seed;

  String? get activity => area.activity;
}

/// Lays the areas out inside the part of the screen the chrome leaves free, keeping their relative positions
/// (north is up). Areas without a centre are spread along a row.
List<_Area> _place(List<MapArea> areas) {
  const left = 0.18, right = 0.84, top = 0.26, bottom = 0.58;
  final located = [
    for (final a in areas)
      if (a.lat != null && a.lon != null) a,
  ];
  var minLat = double.infinity, maxLat = -double.infinity;
  var minLon = double.infinity, maxLon = -double.infinity;
  for (final a in located) {
    minLat = math.min(minLat, a.lat!);
    maxLat = math.max(maxLat, a.lat!);
    minLon = math.min(minLon, a.lon!);
    maxLon = math.max(maxLon, a.lon!);
  }
  final spanLat = maxLat - minLat, spanLon = maxLon - minLon;
  var unplaced = 0;
  return [
    for (final a in areas)
      if (a.lat != null && a.lon != null)
        _Area(
          a,
          Offset(
            spanLon < 1e-9
                ? 0.5
                : left + (right - left) * (a.lon! - minLon) / spanLon,
            spanLat < 1e-9
                ? 0.42
                : bottom - (bottom - top) * (a.lat! - minLat) / spanLat,
          ),
        )
      else
        _Area(a, Offset(left + 0.22 * (unplaced++ % 4), bottom)),
  ];
}

class _MapScreenState extends ConsumerState<MapScreen> {
  MapLens _lens = MapLens.everything;

  /// The last map that loaded, kept on screen while another lens loads.
  List<_Area> _areas = const [];

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final c = context.od;
    final map = ref.watch(storyMapProvider(_lens));
    final data = map.value;
    if (data != null) _areas = _place(data.areas);
    final error = map.hasError && data == null ? map.error : null;
    return LayoutBuilder(
      builder: (context, box) {
        final visible = error == null ? _areas : const <_Area>[];
        return Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(painter: _CityPainter()),
              ),
            ),
            // Heat: where the city is sharing right now.
            for (final a in visible)
              _Heat(
                center: Offset(a.at.dx * box.maxWidth, a.at.dy * box.maxHeight),
                radius: 70 + math.min(a.count, 30) * 4.0,
                on: true,
                color: a.area.busy || a.count > 12
                    ? const Color(0xFFFF3D7F)
                    : const Color(0xFFFF8A4C),
              ),
            // You: an area, not a dot.
            Positioned(
              left: box.maxWidth * 0.28 - 40,
              top: box.maxHeight * 0.41 - 40,
              child: const IgnorePointer(child: _You()),
            ),
            for (final a in visible)
              Positioned(
                left: a.at.dx * box.maxWidth - 40,
                top: a.at.dy * box.maxHeight - 40,
                child: _Cluster(area: a, onTap: () => _open(context, a)),
              ),
            if (error != null)
              Center(child: _MapProblem(error: error, lens: _lens))
            else if (data != null && visible.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(OdSpace.x4),
                  child: Text(
                    data.message ?? 'Quiet here right now. Try another lens.',
                    textAlign: TextAlign.center,
                    style: context.type.titleMedium?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            // Top: title, search, privacy promise, lenses.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      c.canvas.withValues(alpha: 0.92),
                      c.canvas.withValues(alpha: 0),
                    ],
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.only(
                    top: padding.top + OdSpace.x1,
                    bottom: OdSpace.x3,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: OdSpace.gutter,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Story Map',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.type.headlineSmall,
                              ),
                            ),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: box.maxWidth * 0.5,
                              ),
                              child: OdFrosted(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: OdSpace.x1_5,
                                  vertical: OdSpace.x1,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.shield_rounded,
                                      size: 15,
                                      color: c.safety,
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        'Areas, never pins',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: context.type.labelMedium
                                            ?.copyWith(color: Colors.white),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: OdSpace.x1),
                            OdIconButton(
                              icon: Icons.search_rounded,
                              semanticLabel: 'Search places',
                              onPressed: () {},
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: OdSpace.x1_5),
                      SizedBox(
                        height: MediaQuery.textScalerOf(context).scale(14) + 26,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                            horizontal: OdSpace.gutter,
                          ),
                          itemCount: MapLens.values.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(width: OdSpace.x1),
                          itemBuilder: (_, i) => Center(
                            child: OdChip(
                              label: MapLens.values[i].label,
                              selected: _lens == MapLens.values[i],
                              onTap: () =>
                                  setState(() => _lens = MapLens.values[i]),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Bottom: stories around you, the map's way in for people who don't explore maps.
            Positioned(
              left: 0,
              right: 0,
              bottom: padding.bottom + OdSpace.x1,
              child: SizedBox(
                height: 168,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: OdSpace.gutter,
                  ),
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const SizedBox(width: OdSpace.x1),
                  itemBuilder: (context, i) => _AreaCard(
                    area: visible[i],
                    onTap: () => _open(context, visible[i]),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _open(BuildContext context, _Area a) {
    showOdSheet<void>(
      context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(a.name, style: context.type.titleLarge),
          Text(
            '${a.count} stories in the last day',
            style: context.type.bodyMedium,
          ),
          const SizedBox(height: OdSpace.x2),
          SizedBox(
            height: 180,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: math.min(a.count, 6),
              separatorBuilder: (_, _) => const SizedBox(width: OdSpace.x1),
              itemBuilder: (_, i) => ClipRRect(
                borderRadius: BorderRadius.circular(OdRadius.md),
                child: SizedBox(
                  width: 112,
                  child: OdMedia(
                    url: i < a.area.stories.length
                        ? a.area.stories[i].previewUrl
                        : null,
                    seed: a.seed * 7 + i,
                    activity: i < a.area.stories.length
                        ? a.area.stories[i].activity
                        : (i.isEven ? a.activity : null),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Heat extends StatelessWidget {
  const _Heat({
    required this.center,
    required this.radius,
    required this.on,
    required this.color,
  });

  final Offset center;
  final double radius;
  final bool on;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: center.dx - radius,
      top: center.dy - radius,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: on ? 1 : 0,
          duration: OdMotion.of(context, OdMotion.standard),
          child: Container(
            width: radius * 2,
            height: radius * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  color.withValues(alpha: 0.45),
                  color.withValues(alpha: 0.12),
                  color.withValues(alpha: 0),
                ],
                stops: const [0, 0.45, 1],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _You extends StatelessWidget {
  const _You();

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF3A86FF);
    return SizedBox.square(
      dimension: 80,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: blue.withValues(alpha: 0.14),
              border: Border.all(color: blue.withValues(alpha: 0.5)),
            ),
          ),
          Semantics(
            label: 'Your area',
            child: const OdAvatar(name: 'You', seed: 2, size: 34),
          ),
        ],
      ),
    );
  }
}

/// The map couldn't load: usually because the area hasn't been shared yet.
class _MapProblem extends ConsumerWidget {
  const _MapProblem({required this.error, required this.lens});

  final Object error;
  final MapLens lens;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (error is LocationRequired) {
      return OdClosureCard(
        icon: Icons.near_me_rounded,
        title: 'See your city\'s stories',
        message:
            'Share your area while the app is open. The map shows areas with several people, never a pin on anyone.',
        actionLabel: 'Share my area',
        onAction: () async {
          final ok = await ref.read(locationShareProvider).share();
          if (!context.mounted) return;
          if (ok) {
            ref.invalidate(storyMapProvider);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Couldn\'t get your location. Check location permission.',
                ),
              ),
            );
          }
        },
      );
    }
    return OdClosureCard(
      icon: Icons.wifi_off_rounded,
      title: 'Couldn\'t load the map',
      message: error is ApiError
          ? (error as ApiError).detail
          : 'Check your connection and try again.',
      actionLabel: 'Try again',
      onAction: () => ref.invalidate(storyMapProvider(lens)),
    );
  }
}

class _Cluster extends StatelessWidget {
  const _Cluster({required this.area, required this.onTap});

  final _Area area;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final size = 48.0 + math.min(area.count, 24);
    return OdPressable(
      onTap: onTap,
      semanticLabel: '${area.name}, ${area.count} stories',
      child: SizedBox.square(
        dimension: 80,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x88000000),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: ClipOval(
                child: OdMediaArt(seed: area.seed, activity: area.activity),
              ),
            ),
            Positioned(
              right: 80 / 2 - size / 2 - 6,
              top: 80 / 2 - size / 2 - 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  gradient: context.od.brandGradient,
                  borderRadius: BorderRadius.circular(OdRadius.pill),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Text(
                  '${area.count}',
                  style: context.type.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -10,
              child: Text(
                area.name.toUpperCase(),
                maxLines: 1,
                style: context.type.labelSmall?.copyWith(
                  color: Colors.white,
                  letterSpacing: 0.8,
                  shadows: const [Shadow(color: Colors.black, blurRadius: 6)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AreaCard extends StatelessWidget {
  const _AreaCard({required this.area, required this.onTap});

  final _Area area;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OdPressable(
      onTap: onTap,
      pressedScale: 0.96,
      semanticLabel: 'Stories in ${area.name}',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(OdRadius.lg),
        child: SizedBox(
          width: 118,
          child: Stack(
            fit: StackFit.expand,
            children: [
              OdMediaArt(seed: area.seed + 50, activity: area.activity),
              const OdScrim(top: 0, bottom: 0.7),
              Positioned(
                left: OdSpace.x1,
                right: OdSpace.x1,
                bottom: OdSpace.x1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      area.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.type.labelLarge?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '${area.count} stories',
                      maxLines: 1,
                      style: context.type.labelSmall?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A night-mode city in the style of map SDK dark themes: land, a lake and a river, parks, a hierarchy of roads
/// (casing then fill) and a faint street grid. Deterministic so it never shimmers.
class _CityPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final h = s.height;
    canvas.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF12151F));

    // Neighbourhood tints.
    final r = math.Random(11);
    for (var i = 0; i < 9; i++) {
      final at = Offset(r.nextDouble() * w, r.nextDouble() * h);
      canvas.drawCircle(
        at,
        90 + r.nextDouble() * 80,
        Paint()..color = const Color(0xFF161A26),
      );
    }

    // Faint street grid, slightly rotated like a real city.
    canvas.save();
    canvas.translate(w / 2, h / 2);
    canvas.rotate(-0.18);
    final street = Paint()
      ..color = const Color(0xFF1D2231)
      ..strokeWidth = 1.4;
    for (double x = -w; x < w; x += 28 + r.nextDouble() * 18) {
      canvas.drawLine(Offset(x, -h), Offset(x, h), street);
    }
    for (double y = -h; y < h; y += 28 + r.nextDouble() * 18) {
      canvas.drawLine(Offset(-w, y), Offset(w, y), street);
    }
    canvas.restore();

    // Parks.
    final park = Paint()..color = const Color(0xFF16302A);
    canvas.drawPath(_blob(Offset(w * 0.36, h * 0.25), 70, 50, 3), park);
    canvas.drawPath(_blob(Offset(w * 0.2, h * 0.82), 60, 40, 5), park);
    canvas.drawPath(_blob(Offset(w * 0.86, h * 0.45), 44, 34, 8), park);

    // Water: a lake and a river.
    final water = Paint()..color = const Color(0xFF1A2E4F);
    canvas.drawPath(_blob(Offset(w * 0.78, h * 0.18), 52, 36, 2), water);
    final river = Path()
      ..moveTo(-20, h * 0.74)
      ..cubicTo(w * 0.25, h * 0.68, w * 0.45, h * 0.86, w * 0.7, h * 0.8)
      ..cubicTo(w * 0.85, h * 0.76, w * 0.95, h * 0.84, w + 20, h * 0.8);
    canvas.drawPath(
      river,
      Paint()
        ..color = const Color(0xFF1A2E4F)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 26
        ..strokeCap = StrokeCap.round,
    );

    // Roads: casing, then fill, so junctions read cleanly.
    final majors = [
      Path()
        ..moveTo(-10, h * 0.4)
        ..cubicTo(w * 0.3, h * 0.36, w * 0.6, h * 0.42, w + 10, h * 0.34),
      Path()
        ..moveTo(w * 0.46, -10)
        ..cubicTo(w * 0.5, h * 0.3, w * 0.42, h * 0.6, w * 0.56, h + 10),
      Path()
        ..moveTo(-10, h * 0.12)
        ..quadraticBezierTo(w * 0.4, h * 0.2, w * 0.95, h * 0.62)
        ..lineTo(w + 10, h * 0.7),
    ];
    final minors = [
      Path()
        ..moveTo(w * 0.15, -10)
        ..quadraticBezierTo(w * 0.22, h * 0.5, w * 0.1, h + 10),
      Path()
        ..moveTo(-10, h * 0.58)
        ..quadraticBezierTo(w * 0.5, h * 0.62, w + 10, h * 0.55),
      Path()
        ..moveTo(w * 0.78, -10)
        ..quadraticBezierTo(w * 0.7, h * 0.5, w * 0.85, h + 10),
    ];
    Paint stroke(Color color, double width) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final p in minors) {
      canvas.drawPath(p, stroke(const Color(0xFF0E1018), 7));
    }
    for (final p in minors) {
      canvas.drawPath(p, stroke(const Color(0xFF2B3144), 4));
    }
    for (final p in majors) {
      canvas.drawPath(p, stroke(const Color(0xFF0E1018), 11));
    }
    for (final p in majors) {
      canvas.drawPath(p, stroke(const Color(0xFF3D4560), 7));
    }
  }

  Path _blob(Offset c, double rx, double ry, int seed) {
    final r = math.Random(seed);
    final p = Path();
    const n = 9;
    final pts = [
      for (var i = 0; i < n; i++)
        c +
            Offset(
              math.cos(i / n * 2 * math.pi) *
                  rx *
                  (0.8 + r.nextDouble() * 0.35),
              math.sin(i / n * 2 * math.pi) *
                  ry *
                  (0.8 + r.nextDouble() * 0.35),
            ),
    ];
    p.moveTo((pts[0].dx + pts[1].dx) / 2, (pts[0].dy + pts[1].dy) / 2);
    for (var i = 1; i <= n; i++) {
      final a = pts[i % n];
      final b = pts[(i + 1) % n];
      p.quadraticBezierTo(a.dx, a.dy, (a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    }
    return p..close();
  }

  @override
  bool shouldRepaint(_CityPainter old) => false;
}
