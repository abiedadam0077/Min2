import 'dart:ui' show FontVariation;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_tokens.dart';

/// Builds the single dark theme used by the app. Inter provides Latin glyphs and Cairo supplies
/// Arabic glyphs through fontFamilyFallback, so both languages share one type scale.
abstract final class AppTheme {
  static const String _latin = 'Inter';
  static const List<String> _fallback = <String>['Cairo'];

  static TextStyle _style(double size, int weight, {double? height, double? spacing, Color? color}) {
    return TextStyle(
      fontFamily: _latin,
      fontFamilyFallback: _fallback,
      fontSize: size,
      height: height,
      letterSpacing: spacing,
      color: color ?? AppColors.textPrimary,
      fontVariations: <FontVariation>[FontVariation('wght', weight.toDouble())],
    );
  }

  static TextTheme textTheme() {
    return TextTheme(
      displaySmall: _style(36, 700, height: 1.1, spacing: -0.5),
      headlineLarge: _style(30, 700, height: 1.15, spacing: -0.3),
      headlineMedium: _style(26, 700, height: 1.2, spacing: -0.2),
      headlineSmall: _style(22, 650, height: 1.25),
      titleLarge: _style(20, 650, height: 1.3),
      titleMedium: _style(17, 600, height: 1.3),
      titleSmall: _style(15, 600, height: 1.3),
      bodyLarge: _style(16, 400, height: 1.5),
      bodyMedium: _style(15, 400, height: 1.45, color: AppColors.textSecondary),
      bodySmall: _style(13, 400, height: 1.4, color: AppColors.textSecondary),
      labelLarge: _style(15, 600, spacing: 0.1),
      labelMedium: _style(13, 600, spacing: 0.2, color: AppColors.textSecondary),
      labelSmall: _style(11, 600, spacing: 0.4, color: AppColors.textMuted),
    );
  }

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: AppColors.primary,
      onPrimary: AppColors.ink,
      secondary: AppColors.violet,
      onSecondary: AppColors.textPrimary,
      tertiary: AppColors.cyan,
      onTertiary: AppColors.ink,
      error: AppColors.danger,
      onError: AppColors.ink,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      outline: AppColors.outline,
      outlineVariant: AppColors.outlineSoft,
      surfaceContainerLowest: AppColors.ink,
      surfaceContainerLow: AppColors.surfaceLow,
      surfaceContainer: AppColors.surface,
      surfaceContainerHigh: AppColors.surfaceHigh,
      surfaceContainerHighest: AppColors.surfaceHigh,
    );
    final text = textTheme();
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      fontFamily: _latin,
      fontFamilyFallback: _fallback,
      textTheme: text,
      primaryTextTheme: text,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      dividerColor: AppColors.outlineSoft,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: AppColors.ink,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.ink,
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.all(AppRadius.md)),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.outline),
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.all(AppRadius.md)),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: text.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.glassFill,
        labelStyle: text.bodyMedium,
        hintStyle: text.bodyMedium?.copyWith(color: AppColors.textMuted),
        helperStyle: text.bodySmall,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
        border: OutlineInputBorder(borderRadius: AppRadius.all(AppRadius.md), borderSide: const BorderSide(color: AppColors.outline)),
        enabledBorder: OutlineInputBorder(borderRadius: AppRadius.all(AppRadius.md), borderSide: const BorderSide(color: AppColors.outline)),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.all(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(borderRadius: AppRadius.all(AppRadius.md), borderSide: const BorderSide(color: AppColors.danger)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceHigh,
        contentTextStyle: text.bodyMedium?.copyWith(color: AppColors.textPrimary),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.all(AppRadius.md)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: AppColors.surface,
        showDragHandle: true,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? AppColors.ink : AppColors.textSecondary),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? AppColors.primary : AppColors.surfaceHigh),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.surfaceHigh,
        circularTrackColor: AppColors.surfaceHigh,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: _SlideFadeTransitionsBuilder(),
          TargetPlatform.iOS: _SlideFadeTransitionsBuilder(),
        },
      ),
    );
  }
}

/// Page transition: content rises 4% while fading in, which reads as a deliberate navigation step.
class _SlideFadeTransitionsBuilder extends PageTransitionsBuilder {
  const _SlideFadeTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(parent: animation, curve: AppMotion.enter, reverseCurve: AppMotion.exit);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(curved),
        child: child,
      ),
    );
  }
}
