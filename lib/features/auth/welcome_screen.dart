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
          const OdMediaArt(seed: 3),
          const OdScrim(top: 0.1, bottom: 0.85),
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

/// Shown while the stored session is read (a few milliseconds); matches the launch screen so nothing flashes.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.od.canvas,
    body: Center(child: Text('OneDay', style: context.type.headlineSmall)),
  );
}
