import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';
import 'app_palette.dart';

class SnappyFadeTransitionsBuilder extends PageTransitionsBuilder {
  const SnappyFadeTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeIn,
      ),
      child: child,
    );
  }
}

class AppTheme {
  static ThemeData get darkTheme => _applyPalette(theme, AppPalette.dark);
  static ThemeData _applyPalette(ThemeData base, AppPalette palette) =>
      base.copyWith(
        brightness: palette.scheme.brightness,
        colorScheme: palette.scheme,
        scaffoldBackgroundColor: palette.surface,
        canvasColor: palette.surface,
        cardColor: palette.surfaceContainerLow,
        dividerColor: palette.outlineVariant,
        textTheme: base.textTheme.apply(
          bodyColor: palette.onSurface,
          displayColor: palette.onSurface,
        ),
        inputDecorationTheme: base.inputDecorationTheme.copyWith(
          fillColor: palette.surfaceContainerLow,
          hintStyle: base.inputDecorationTheme.hintStyle?.copyWith(
            color: palette.onSurfaceVariant,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: palette.primary,
            foregroundColor: palette.onPrimary,
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
  static ThemeData get theme {
    return _applyPalette(
      ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: AppColors.surface,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: SnappyFadeTransitionsBuilder(),
            TargetPlatform.iOS: SnappyFadeTransitionsBuilder(),
            TargetPlatform.windows: SnappyFadeTransitionsBuilder(),
            TargetPlatform.macOS: SnappyFadeTransitionsBuilder(),
            TargetPlatform.linux: SnappyFadeTransitionsBuilder(),
          },
        ),
        colorScheme: const ColorScheme.light(
          primary: AppColors.primary,
          primaryContainer: AppColors.primaryContainer,
          onPrimary: AppColors.onPrimary,
          onPrimaryContainer: AppColors.onPrimaryContainer,
          secondary: AppColors.secondary,
          secondaryContainer: AppColors.secondaryContainer,
          onSecondary: AppColors.onSecondary,
          onSecondaryContainer: AppColors.onSecondaryContainer,
          tertiary: AppColors.tertiary,
          tertiaryContainer: AppColors.tertiaryContainer,
          onTertiary: AppColors.onTertiary,
          onTertiaryContainer: AppColors.onTertiaryContainer,
          error: AppColors.error,
          errorContainer: AppColors.errorContainer,
          onError: AppColors.onError,
          onErrorContainer: AppColors.onErrorContainer,
          surface: AppColors.surface,
          onSurface: AppColors.onSurface,
          onSurfaceVariant: AppColors.onSurfaceVariant,
          outline: AppColors.outline,
          outlineVariant: AppColors.outlineVariant,
          inverseSurface: AppColors.inverseSurface,
          onInverseSurface: AppColors.inverseOnSurface,
          inversePrimary: AppColors.inversePrimary,
        ),
        textTheme: TextTheme(
          displayLarge: GoogleFonts.manrope(
            fontSize: 57,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.5,
            color: AppColors.onSurface,
          ),
          displayMedium: GoogleFonts.manrope(
            fontSize: 45,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: AppColors.onSurface,
          ),
          displaySmall: GoogleFonts.manrope(
            fontSize: 36,
            fontWeight: FontWeight.w800,
            color: AppColors.onSurface,
          ),
          headlineLarge: GoogleFonts.manrope(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: AppColors.onSurface,
          ),
          headlineMedium: GoogleFonts.manrope(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: AppColors.onSurface,
          ),
          headlineSmall: GoogleFonts.manrope(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: AppColors.onSurface,
          ),
          titleLarge: GoogleFonts.manrope(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: AppColors.onSurface,
          ),
          titleMedium: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.onSurface,
          ),
          titleSmall: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.onSurface,
          ),
          bodyLarge: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: AppColors.onSurface,
          ),
          bodyMedium: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: AppColors.onSurface,
          ),
          bodySmall: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: AppColors.onSurfaceVariant,
          ),
          labelLarge: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: AppColors.onSurface,
          ),
          labelMedium: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            color: AppColors.onSurfaceVariant,
          ),
          labelSmall: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.0,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surfaceContainerLow,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: AppColors.primary.withValues(alpha: 0.2),
              width: 2,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          hintStyle: GoogleFonts.inter(
            color: AppColors.outline,
            fontWeight: FontWeight.w400,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      AppPalette.light,
    );
  }
}
