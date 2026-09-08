import 'package:flutter/material.dart';

/// Design tokens, lifted from `docs/design.pen` (INSTRUCTIONS.md section 10).
///
/// Dark only: a light theme is not designed. If one ships it should be derived
/// from [ColorScheme.fromSeed] rather than hand-picked here.
abstract final class AppColors {
  static const ground = Color(0xFF08090B);
  static const surface = Color(0xFF121418);
  static const surfaceRaised = Color(0xFF1A1D23);
  static const outline = Color(0xFF2A2E36);
  static const textPrimary = Color(0xFFF2F3F5);
  static const textSecondary = Color(0xFF9BA1AC);
  static const textTertiary = Color(0xFF6B7280);

  /// Used only for state — progress, selection, focus. Never decoration.
  static const accent = Color(0xFFFF5E5B);

  /// Verified / healthy. Not part of the core palette; used for trust signals.
  static const ok = Color(0xFF5FBF8F);
}

/// Four sizes in practice. Eight type sizes across twenty screens is how a
/// design drifts.
abstract final class AppText {
  static const screenTitle = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
  );
  static const sectionTitle = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
  );
  static const body = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 15,
    fontWeight: FontWeight.w500,
  );
  static const bodySecondary = TextStyle(
    color: AppColors.textSecondary,
    fontSize: 13,
    height: 1.5,
  );
  static const meta = TextStyle(color: AppColors.textTertiary, fontSize: 12);
  static const kicker = TextStyle(
    color: AppColors.textTertiary,
    fontSize: 10,
    fontWeight: FontWeight.w600,
    letterSpacing: 1,
  );
}

abstract final class AppSpace {
  static const gutter = 16.0;
  static const radiusCard = 12.0;
  static const radiusPoster = 8.0;

  /// Minimum touch target (section 10).
  static const touchTarget = 48.0;
}

ThemeData buildDarkTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    brightness: Brightness.dark,
  ).copyWith(
    surface: AppColors.surface,
    onSurface: AppColors.textPrimary,
    outline: AppColors.outline,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.ground,
    // No drop shadows anywhere: separation comes from surface steps plus
    // hairline outlines, which is what keeps a near-black UI from turning
    // muddy (section 10).
    cardTheme: const CardThemeData(elevation: 0, color: AppColors.surface),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.ground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.outline,
      thickness: 1,
      space: 1,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.accent.withValues(alpha: 0.16),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.surfaceRaised,
      contentTextStyle: TextStyle(color: AppColors.textPrimary, fontSize: 13),
      behavior: SnackBarBehavior.floating,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accent,
    ),
  );
}
