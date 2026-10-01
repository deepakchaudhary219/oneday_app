import 'package:flutter/widgets.dart';

/// Motion tokens: every duration and curve in the app comes from here.
abstract final class OdMotion {
  /// Press feedback, toggles.
  static const instant = Duration(milliseconds: 90);

  /// Small state changes: chips, icons, counters.
  static const quick = Duration(milliseconds: 160);

  /// Most transitions.
  static const standard = Duration(milliseconds: 240);

  /// Screen-level and hero moments.
  static const emphasized = Duration(milliseconds: 360);

  /// Things arriving: fast start, gentle landing.
  static const Curve enter = Cubic(0.05, 0.7, 0.1, 1.0);

  /// Things leaving: gentle start, fast exit.
  static const Curve exit = Cubic(0.3, 0.0, 0.8, 0.15);

  static const Curve standardCurve = Cubic(0.2, 0.0, 0, 1.0);

  /// Drags release into this: lively but never bouncy enough to feel toy-like.
  static const SpringDescription spring = SpringDescription(
    mass: 1,
    stiffness: 420,
    damping: 32,
  );

  /// Reduced motion: honour the OS setting by collapsing durations.
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false ? Duration.zero : d;
}
