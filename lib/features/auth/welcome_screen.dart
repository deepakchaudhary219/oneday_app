import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../design_system/design_system.dart';

/// The front door: one promise, one obvious action. Phone first because that's how most people in India sign
/// in; email stays one tap away for everyone else.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: context.od.canvas),
          const _FloatingMoments(),
          const OdScrim(top: 0, bottom: 0.7),
          SafeArea(
            // Bottom-anchored, but scrolls instead of overflowing on a small phone with large text.
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                reverse:
                    true, // the actions stay in view; the headline scrolls up
                padding: const EdgeInsets.all(OdSpace.gutter),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 2 * OdSpace.gutter,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'OneDay',
                        style: context.type.displaySmall?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: OdSpace.x1),
                      Text(
                        'Real moments from people near you. Today, not forever.',
                        style: context.type.titleMedium?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: OdSpace.x4),
                      OdButton(
                        label: 'Continue with phone',
                        icon: Icons.phone_iphone_rounded,
                        expand: true,
                        onPressed: () => context.push('/auth/phone'),
                      ),
                      const SizedBox(height: OdSpace.x1),
                      OdButton(
                        label: 'Use email instead',
                        variant: OdButtonVariant.ghost,
                        expand: true,
                        onPressed: () => context.push('/auth/email'),
                      ),
                      const SizedBox(height: OdSpace.x2),
                      SizedBox(
                        width: double.infinity,
                        child: Text(
                          'OneDay is for adults 18+. We never show your exact location.',
                          textAlign: TextAlign.center,
                          style: context.type.labelSmall?.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                      ),
                      const SizedBox(height: OdSpace.x1),
                    ],
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

/// Three moments drifting in the upper half: real-looking people doing real things nearby, which says what
/// OneDay is faster than any sentence. The drift stops when the system asks for reduced motion.
class _FloatingMoments extends StatefulWidget {
  const _FloatingMoments();

  @override
  State<_FloatingMoments> createState() => _FloatingMomentsState();
}

class _FloatingMomentsState extends State<_FloatingMoments>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  );

  static const _cards = [
    // name, person seed, scene seed, activity, x, y, angle
    ('Riya', 25, 1, 'sunrise trek', 0.03, 0.04, -0.13),
    ('Arjun', 9, 2, 'chess at a café', 0.5, 0.03, 0.09),
    ('Zoya', 7, 12, 'rooftop gig', 0.27, 0.37, -0.03),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _drift.stop();
    } else if (!_drift.isAnimating) {
      _drift.repeat();
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = math.min(box.maxWidth * 0.46, 220.0);
        return AnimatedBuilder(
          animation: _drift,
          builder: (context, _) => Stack(
            children: [
              for (var i = 0; i < _cards.length; i++)
                Positioned(
                  left: box.maxWidth * _cards[i].$5,
                  top:
                      box.maxHeight * _cards[i].$6 +
                      MediaQuery.paddingOf(context).top +
                      math.sin((_drift.value + i / 3) * 2 * math.pi) * 8,
                  child: Transform.rotate(
                    angle: _cards[i].$7,
                    child: _MomentPreview(
                      width: w,
                      name: _cards[i].$1,
                      person: _cards[i].$2,
                      scene: _cards[i].$3,
                      activity: _cards[i].$4,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _MomentPreview extends StatelessWidget {
  const _MomentPreview({
    required this.width,
    required this.name,
    required this.person,
    required this.scene,
    required this.activity,
  });

  final double width;
  final String name;
  final int person;
  final int scene;
  final String activity;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: width,
        height: width * 1.4,
        decoration: ShapeDecoration(
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          shadows: const [
            BoxShadow(
              color: Color(0x99000000),
              blurRadius: 30,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: ClipRSuperellipse(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: [
              OdMediaArt(seed: scene, activity: activity),
              const OdScrim(top: 0, bottom: 0.6),
              const Positioned(top: 10, left: 10, child: OdLiveBadge()),
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Row(
                  children: [
                    OdAvatar(
                      name: name,
                      seed: person,
                      size: 30,
                      ring: OdRing.live,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            style: context.type.labelLarge?.copyWith(
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            activity,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown while the stored session is read (a few milliseconds); matches the launch screen so nothing flashes.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.od.canvas,
    body: Center(child: Text('OneDay', style: context.type.headlineSmall)),
  );
}
