import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens/colors.dart';
import 'tokens/spacing.dart';
import 'tokens/typography.dart';

/// Builds Material themes from the tokens. Components read [OdColors] via `context.od`.
abstract final class OdTheme {
  static ThemeData dark() => _build(OdColors.dark, Brightness.dark);

  static ThemeData light() => _build(OdColors.light, Brightness.light);

  static ThemeData _build(OdColors c, Brightness brightness) {
    final text = OdType.textTheme(c.textPrimary, c.textSecondary);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: c.brand,
          brightness: brightness,
        ).copyWith(
          primary: c.brand,
          surface: c.surface,
          onSurface: c.textPrimary,
          error: c.danger,
          outline: c.outline,
        );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.canvas,
      textTheme: text,
      extensions: [c],
      splashFactory: NoSplash
          .splashFactory, // pressables give their own feedback (scale + haptic)
      highlightColor: Colors.transparent,
      appBarTheme: AppBarTheme(
        backgroundColor: c.canvas,
        foregroundColor: c.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        systemOverlayStyle: brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        showDragHandle: true,
        dragHandleColor: c.outline,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(OdRadius.xl),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceSunken,
        hintStyle: text.bodyMedium?.copyWith(color: c.textTertiary),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: OdSpace.x2,
          vertical: OdSpace.x1_5,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(OdRadius.lg),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(OdRadius.lg),
          borderSide: BorderSide(color: c.brand, width: 1.5),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.surfaceRaised,
        contentTextStyle: text.bodyMedium?.copyWith(color: c.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OdRadius.md),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}

extension OdThemeContext on BuildContext {
  OdColors get od => Theme.of(this).extension<OdColors>()!;

  TextTheme get type => Theme.of(this).textTheme;
}
