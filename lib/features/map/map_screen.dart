import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design_system/design_system.dart';

/// The Story Map: public stories as k-anonymous clusters (never a pin on a person), with lenses (Roots,
/// language, activity, Today's Prompt). The painter stands in for the map SDK until it's wired.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const _lenses = [
    'Everything',
    'Roots',
    'Malayalam',
    'Trek',
    'Today\'s prompt',
  ];
  String _lens = _lenses.first;

  static const _clusters = [
    (Offset(0.28, 0.32), 14, 'Indiranagar', 1),
    (Offset(0.62, 0.26), 6, 'Cubbon Park', 2),
    (Offset(0.45, 0.55), 23, 'Koramangala', 3),
    (Offset(0.72, 0.6), 5, 'HSR Layout', 4),
    (Offset(0.24, 0.7), 9, 'Jayanagar', 5),
  ];

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return LayoutBuilder(
      builder: (context, box) {
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _MapPainter(context.od)),
            ),
            for (final (pos, count, area, seed) in _clusters)
              Positioned(
                left: pos.dx * box.maxWidth - 34,
                top: pos.dy * box.maxHeight - 34,
                child: _Cluster(
                  count: count,
                  seed: seed,
                  onTap: () => _open(context, area, count, seed),
                ),
              ),
            Positioned(
              top: padding.top + OdSpace.x1,
              left: 0,
              right: 0,
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
                            style: context.type.titleLarge,
                          ),
                        ),
                        const SizedBox(width: OdSpace.x1),
                        // Natural width, capped so a large text size ellipsizes instead of crowding the title.
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.sizeOf(context).width * 0.6,
                          ),
                          child: OdFrosted(
                            padding: const EdgeInsets.symmetric(
                              horizontal: OdSpace.x1_5,
                              vertical: OdSpace.x1,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.shield_moon_rounded,
                                  size: 16,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'Areas, never pins',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.type.labelMedium?.copyWith(
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: OdSpace.x1_5),
                  SizedBox(
                    height: 40,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: OdSpace.gutter,
                      ),
                      itemCount: _lenses.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(width: OdSpace.x1),
                      itemBuilder: (_, i) => OdChip(
                        label: _lenses[i],
                        selected: _lens == _lenses[i],
                        onTap: () => setState(() => _lens = _lenses[i]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  void _open(BuildContext context, String area, int count, int seed) {
    showOdSheet<void>(
      context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(area, style: context.type.titleLarge),
          Text(
            '$count stories in the last day',
            style: context.type.bodyMedium,
          ),
          const SizedBox(height: OdSpace.x2),
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: math.min(count, 6),
              separatorBuilder: (_, _) => const SizedBox(width: OdSpace.x1),
              itemBuilder: (_, i) => ClipRRect(
                borderRadius: BorderRadius.circular(OdRadius.md),
                child: SizedBox(
                  width: 100,
                  child: OdMediaArt(seed: seed * 7 + i),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Cluster extends StatelessWidget {
  const _Cluster({
    required this.count,
    required this.seed,
    required this.onTap,
  });

  final int count;
  final int seed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final size = 48.0 + math.min(count, 25);
    return OdPressable(
      onTap: onTap,
      semanticLabel: '$count stories here',
      child: SizedBox.square(
        dimension: 68,
        child: Center(
          child: Container(
            width: size,
            height: size,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: context.od.brandGradient,
            ),
            child: ClipOval(
              child: OdMediaArt(
                seed: seed,
                child: Center(
                  child: Text(
                    '$count',
                    style: context.type.titleMedium?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A stylised night city: blocks on a slightly irregular street grid, arterial roads, a river and parks.
/// Deterministic, so it doesn't shimmer between frames. Replaced by the map SDK's dark style later.
class _MapPainter extends CustomPainter {
  _MapPainter(this.c);

  final OdColors c;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = c.surfaceSunken);
    final rnd = math.Random(7);
    const cell = 46.0;
    final block = Paint()..color = c.surface;
    for (double y = -cell; y < size.height + cell; y += cell) {
      final shift = rnd.nextDouble() * 12 - 6;
      for (double x = -cell; x < size.width + cell; x += cell) {
        final w = cell - 8 - rnd.nextDouble() * 6;
        final h = cell - 8 - rnd.nextDouble() * 6;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x + shift + 4, y + 4, w, h),
            const Radius.circular(5),
          ),
          block,
        );
      }
    }
    final park = Paint()..color = c.safety.withValues(alpha: 0.16);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * .52, size.height * .2, 130, 96),
        const Radius.circular(28),
      ),
      park,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * .08, size.height * .78, 110, 70),
        const Radius.circular(24),
      ),
      park,
    );
    final river = Path()
      ..moveTo(-20, size.height * .42)
      ..cubicTo(
        size.width * .3,
        size.height * .36,
        size.width * .55,
        size.height * .52,
        size.width + 20,
        size.height * .46,
      );
    canvas.drawPath(
      river,
      Paint()
        ..color = const Color(0xFF2A6FDB).withValues(alpha: 0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 22
        ..strokeCap = StrokeCap.round,
    );
    final arterial = Paint()
      ..color = c.outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * .18, 0),
      Offset(size.width * .34, size.height),
      arterial,
    );
    canvas.drawLine(
      Offset(0, size.height * .64),
      Offset(size.width, size.height * .58),
      arterial,
    );
  }

  @override
  bool shouldRepaint(_MapPainter old) => old.c != c;
}
