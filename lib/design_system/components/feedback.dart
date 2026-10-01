import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens/motion.dart';
import '../tokens/spacing.dart';
import 'button.dart';

/// Shimmer skeleton: shows the shape of what's loading, so the layout never jumps when data arrives.
class OdSkeleton extends StatefulWidget {
  const OdSkeleton({
    super.key,
    this.width,
    this.height = 16,
    this.radius = OdRadius.sm,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<OdSkeleton> createState() => _OdSkeletonState();
}

class _OdSkeletonState extends State<OdSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.od;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final base = c.surfaceRaised;
    final shine = Color.lerp(base, c.textPrimary, 0.08)!;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _shimmer,
        builder: (context, _) {
          final t = reduce ? 0.5 : _shimmer.value;
          return Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              gradient: LinearGradient(
                begin: Alignment(-1 + 3 * t - 1, 0),
                end: Alignment(-1 + 3 * t, 0),
                colors: [base, shine, base],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The end of a bounded list: a deliberate stopping cue with a suggestion to do something real. This is the
/// anti-infinite-scroll pattern.
class OdClosureCard extends StatelessWidget {
  const OdClosureCard({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.icon = Icons.check_circle_rounded,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.od;
    return Padding(
      padding: const EdgeInsets.all(OdSpace.x3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: c.brandGradient,
            ),
            child: Icon(icon, color: c.onBrand, size: 36),
          ),
          const SizedBox(height: OdSpace.x2),
          Text(
            title,
            textAlign: TextAlign.center,
            style: context.type.headlineSmall,
          ),
          const SizedBox(height: OdSpace.x1),
          Text(
            message,
            textAlign: TextAlign.center,
            style: context.type.bodyMedium,
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: OdSpace.x3),
            OdButton(
              label: actionLabel!,
              onPressed: onAction,
              variant: OdButtonVariant.secondary,
            ),
          ],
        ],
      ),
    );
  }
}

/// Connection Warmth: a glow that grows with two-way exchange. It never counts down and never breaks, so
/// there is nothing to lose and nothing to "keep up".
class OdWarmthGlow extends StatelessWidget {
  const OdWarmthGlow({super.key, required this.level, required this.child});

  /// 0 (new) to 3 (flowing).
  final int level;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final warmth = context.od.warmth;
    final strength = (level.clamp(0, 3)) / 3;
    return AnimatedContainer(
      duration: OdMotion.of(context, OdMotion.emphasized),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: strength == 0
            ? const []
            : [
                BoxShadow(
                  color: warmth.withValues(alpha: 0.25 + 0.35 * strength),
                  blurRadius: 8 + 14 * strength,
                ),
              ],
      ),
      child: child,
    );
  }
}

/// Bottom sheet with the house style: drag handle, safe-area padding, keyboard-aware.
Future<T?> showOdSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        left: OdSpace.gutter,
        right: OdSpace.gutter,
        bottom: MediaQuery.viewInsetsOf(context).bottom + OdSpace.x3,
      ),
      child: builder(context),
    ),
  );
}
