import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Context-bound colors prevent one screen's theme from changing another's.
class AppPalette {
  final ColorScheme scheme;
  const AppPalette(this.scheme);
  static AppPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
  static Color foregroundOn(Color background) =>
      background.computeLuminance() > 0.179 ? Colors.black : Colors.white;
  static const light = AppPalette(
    ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFF005AB6),
      onPrimaryContainer: Colors.white,
      secondary: Color(0xFF006E1C),
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFF91F78E),
      onSecondaryContainer: Color(0xFF005817),
      tertiary: Color(0xFFB81311),
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xFFB81311),
      onTertiaryContainer: Colors.white,
      error: Color(0xFFBA1A1A),
      onError: Colors.white,
      errorContainer: Color(0xFFFFDAD6),
      onErrorContainer: Color(0xFF93000A),
      surface: AppColors.surface,
      onSurface: AppColors.onSurface,
      onSurfaceVariant: AppColors.onSurfaceVariant,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: Color(0xFFF2F4F7),
      surfaceContainer: Color(0xFFECEEF1),
      surfaceContainerHigh: Color(0xFFE6E8EB),
      surfaceContainerHighest: Color(0xFFE0E3E6),
      outline: Color(0xFF626877),
      outlineVariant: Color(0xFFC1C6D5),
    ),
  );
  static const dark = AppPalette(
    ColorScheme.dark(
      primary: Color(0xFFABC7FF),
      onPrimary: Color(0xFF002F63),
      primaryContainer: Color(0xFF00458E),
      onPrimaryContainer: Color(0xFFD7E3FF),
      secondary: Color(0xFF94D88F),
      onSecondary: Color(0xFF00390B),
      secondaryContainer: Color(0xFF005313),
      onSecondaryContainer: Color(0xFFB0F5A7),
      tertiary: Color(0xFFFFB4A9),
      onTertiary: Color(0xFF690005),
      tertiaryContainer: Color(0xFF93000A),
      onTertiaryContainer: Color(0xFFFFDAD6),
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
      errorContainer: Color(0xFF93000A),
      onErrorContainer: Color(0xFFFFDAD6),
      surface: Color(0xFF101418),
      onSurface: Color(0xFFE0E3E7),
      onSurfaceVariant: Color(0xFFC1C6D5),
      surfaceContainerLowest: Color(0xFF0B0F12),
      surfaceContainerLow: Color(0xFF191D22),
      surfaceContainer: Color(0xFF1D2126),
      surfaceContainerHigh: Color(0xFF282C31),
      surfaceContainerHighest: Color(0xFF33373C),
      outline: Color(0xFFA0A6B5),
      outlineVariant: Color(0xFF414753),
    ),
  );
  bool get isDark => scheme.brightness == Brightness.dark;

  /// Pale dark-theme accents suit labels, but wash out filled action buttons.
  BoxDecoration primaryActionDecoration({
    double radius = 16,
    bool shadow = true,
  }) => BoxDecoration(
    color: isDark ? primaryContainer : null,
    gradient: isDark
        ? null
        : LinearGradient(colors: [primary, primaryContainer]),
    borderRadius: BorderRadius.circular(radius),
    boxShadow: isDark || !shadow
        ? null
        : [
            BoxShadow(
              color: primary.withValues(alpha: .2),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
  );
  Color get primary => scheme.primary;
  Color get onPrimary => scheme.onPrimary;
  Color get primaryContainer => scheme.primaryContainer;
  Color get onPrimaryContainer => scheme.onPrimaryContainer;
  Color get secondary => scheme.secondary;
  Color get onSecondary => scheme.onSecondary;
  Color get secondaryContainer => scheme.secondaryContainer;
  Color get onSecondaryContainer => scheme.onSecondaryContainer;
  Color get tertiary => scheme.tertiary;
  Color get onTertiary => scheme.onTertiary;
  Color get tertiaryContainer => scheme.tertiaryContainer;
  Color get onTertiaryContainer => scheme.onTertiaryContainer;
  Color get error => scheme.error;
  Color get onError => scheme.onError;
  Color get errorContainer => scheme.errorContainer;
  Color get onErrorContainer => scheme.onErrorContainer;
  Color get surface => scheme.surface;
  Color get background => scheme.surface;
  Color get onSurface => scheme.onSurface;
  Color get onBackground => scheme.onSurface;
  Color get onSurfaceVariant => scheme.onSurfaceVariant;
  Color get surfaceContainerLowest => scheme.surfaceContainerLowest;
  Color get surfaceContainerLow => scheme.surfaceContainerLow;
  Color get surfaceContainer => scheme.surfaceContainer;
  Color get surfaceContainerHigh => scheme.surfaceContainerHigh;
  Color get surfaceContainerHighest => scheme.surfaceContainerHighest;
  Color get surfaceVariant => scheme.surfaceContainerHighest;
  Color get surfaceDim => scheme.surfaceDim;
  Color get surfaceBright => scheme.surfaceBright;
  Color get outline => scheme.outline;
  Color get outlineVariant => scheme.outlineVariant;
  Color get inverseSurface => scheme.inverseSurface;
  Color get inverseOnSurface => scheme.onInverseSurface;
  Color get inversePrimary => scheme.inversePrimary;
  Color get primaryFixed => scheme.primaryFixed;
  Color get primaryFixedDim => scheme.primaryFixedDim;
  Color get onPrimaryFixed => scheme.onPrimaryFixed;
  Color get onPrimaryFixedVariant => scheme.onPrimaryFixedVariant;
  Color get secondaryFixed => scheme.secondaryFixed;
  Color get secondaryFixedDim => scheme.secondaryFixedDim;
  Color get tertiaryFixed => scheme.tertiaryFixed;
  Color get tertiaryFixedDim => scheme.tertiaryFixedDim;
  Color get passable =>
      isDark ? const Color(0xFF94D88F) : const Color(0xFF157035);
  Color get partial =>
      isDark ? const Color(0xFFFACC15) : const Color(0xFF805600);
  Color get warning => partial;
  Color get notPassable =>
      isDark ? const Color(0xFFFFB4A9) : const Color(0xFFB42318);
  Color get warningContainer =>
      isDark ? const Color(0xFF3A2D05) : const Color(0xFFFFF1D6);
  Color get onWarningContainer =>
      isDark ? const Color(0xFFFFE09A) : const Color(0xFF593B00);
}
