/// 8-point grid with 4-point half steps. Use these, never literals, so rhythm stays consistent.
abstract final class OdSpace {
  static const double x0_5 = 4;
  static const double x1 = 8;
  static const double x1_5 = 12;
  static const double x2 = 16;
  static const double x3 = 24;
  static const double x4 = 32;
  static const double x5 = 40;
  static const double x6 = 48;
  static const double x8 = 64;

  /// Screen edge inset.
  static const double gutter = 16;

  /// Minimum touch target (Material and Apple HIG agree on ~44-48).
  static const double minTap = 48;
}

/// Corner radii. Larger surfaces get larger radii so nested corners look concentric.
abstract final class OdRadius {
  static const double sm = 8;
  static const double md = 14;
  static const double lg = 22;
  static const double xl = 32;
  static const double pill = 999;
}
