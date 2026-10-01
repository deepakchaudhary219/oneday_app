import 'package:flutter/material.dart';

/// Colour tokens. Screens use [OdColors] through `context.od`, never raw hex values, so the brand can change in
/// one place and light/dark stay consistent.
@immutable
class OdColors extends ThemeExtension<OdColors> {
  const OdColors({
    required this.canvas,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceSunken,
    required this.outline,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.onBrand,
    required this.brand,
    required this.brandGradient,
    required this.live,
    required this.safety,
    required this.warning,
    required this.danger,
    required this.warmth,
    required this.scrim,
  });

  /// The app background behind everything.
  final Color canvas;

  /// Cards, sheets and bars.
  final Color surface;

  /// Things that sit above surfaces: menus, toasts.
  final Color surfaceRaised;

  /// Inputs and wells.
  final Color surfaceSunken;
  final Color outline;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  /// Text and icons on the brand gradient.
  final Color onBrand;

  /// The single brand accent for small things (a selected icon, a focus ring).
  final Color brand;

  /// "Dusk": primary actions and live states only. Using it sparingly is what keeps it meaningful.
  final Gradient brandGradient;

  /// A story ring or live badge: something new right now.
  final Color live;

  /// Safety surfaces (Date Mode, trusted contact): calm, never alarming.
  final Color safety;
  final Color warning;
  final Color danger;

  /// Connection Warmth glow (replaces streaks).
  final Color warmth;

  /// Gradient scrims that keep text legible over any photo.
  final Color scrim;

  static const _dusk = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF6B5A), Color(0xFFF2387F), Color(0xFF8A4DFF)],
    stops: [0, .5, 1],
  );

  static const dark = OdColors(
    canvas: Color(0xFF07070B),
    surface: Color(0xFF121219),
    surfaceRaised: Color(0xFF1C1C26),
    surfaceSunken: Color(0xFF0D0D13),
    outline: Color(0xFF2A2A36),
    textPrimary: Color(0xFFF5F5FA),
    textSecondary: Color(0xFFB3B3C2),
    textTertiary: Color(0xFF7B7B8E),
    onBrand: Color(0xFFFFFFFF),
    brand: Color(0xFFF2387F),
    brandGradient: _dusk,
    live: Color(0xFFFF4F7B),
    safety: Color(0xFF2EC4B6),
    warning: Color(0xFFFFB547),
    danger: Color(0xFFFF5A5F),
    warmth: Color(0xFFFF9F43),
    scrim: Color(0xCC000000),
  );

  static const light = OdColors(
    canvas: Color(0xFFF7F6FB),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFEFEEF5),
    outline: Color(0xFFE2E0EB),
    textPrimary: Color(0xFF111118),
    textSecondary: Color(0xFF55556A),
    textTertiary: Color(0xFF8A8A9C),
    onBrand: Color(0xFFFFFFFF),
    brand: Color(0xFFD81B67),
    brandGradient: _dusk,
    live: Color(0xFFE11D5A),
    safety: Color(0xFF0E9F92),
    warning: Color(0xFFB86E00),
    danger: Color(0xFFD62F35),
    warmth: Color(0xFFE07A00),
    scrim: Color(0x99000000),
  );

  @override
  OdColors copyWith({Color? brand}) => OdColors(
    canvas: canvas,
    surface: surface,
    surfaceRaised: surfaceRaised,
    surfaceSunken: surfaceSunken,
    outline: outline,
    textPrimary: textPrimary,
    textSecondary: textSecondary,
    textTertiary: textTertiary,
    onBrand: onBrand,
    brand: brand ?? this.brand,
    brandGradient: brandGradient,
    live: live,
    safety: safety,
    warning: warning,
    danger: danger,
    warmth: warmth,
    scrim: scrim,
  );

  @override
  OdColors lerp(OdColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return OdColors(
      canvas: l(canvas, other.canvas),
      surface: l(surface, other.surface),
      surfaceRaised: l(surfaceRaised, other.surfaceRaised),
      surfaceSunken: l(surfaceSunken, other.surfaceSunken),
      outline: l(outline, other.outline),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textTertiary: l(textTertiary, other.textTertiary),
      onBrand: l(onBrand, other.onBrand),
      brand: l(brand, other.brand),
      brandGradient: t < .5 ? brandGradient : other.brandGradient,
      live: l(live, other.live),
      safety: l(safety, other.safety),
      warning: l(warning, other.warning),
      danger: l(danger, other.danger),
      warmth: l(warmth, other.warmth),
      scrim: l(scrim, other.scrim),
    );
  }
}
