import 'package:flutter/material.dart';

/// 偏「多邻国」：高饱和主色、大圆角。
abstract final class AppTheme {
  static const Color duoGreen = Color(0xFF58CC02);
  static const Color duoGreenDark = Color(0xFF46A302);
  static const Color duoBlue = Color(0xFF1CB0F6);
  static const Color duoBlueDark = Color(0xFF1899D6);
  static const Color duoYellow = Color(0xFFFFC800);
  static const Color duoOrange = Color(0xFFFF9600);
  static const Color duoRed = Color(0xFFFF4B4B);
  static const Color duoBg = Color(0xFFF7F7F7);
  static const Color duoBgDark = Color(0xFF131920);

  static const Color textPrimary = Color(0xFF3C3C3C);
  static const Color textPrimaryDark = Color(0xFFE8EAED);

  static ThemeData get light {
    final seed = ColorScheme.fromSeed(
      seedColor: duoGreen,
      brightness: Brightness.light,
      primary: duoGreen,
      onPrimary: Colors.white,
      secondary: duoBlue,
      surface: Colors.white,
      error: duoRed,
    );
    final scheme = seed.copyWith(
      primaryContainer: const Color(0xFFE5F5D6),
      onPrimaryContainer: duoGreenDark,
      surfaceContainerHighest: const Color(0xFFE8E8E8),
    );
    return _buildLightThemeFromScheme(scheme, backgroundOverride: duoBg);
  }

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: duoGreen,
      brightness: Brightness.dark,
      primary: duoGreen,
      onPrimary: const Color(0xFF0D1A00),
      secondary: duoBlue,
      surface: const Color(0xFF1C242D),
      onSurface: textPrimaryDark,
      error: const Color(0xFFFF8A8A),
    );
    return _buildDarkThemeFromScheme(scheme, backgroundOverride: duoBgDark);
  }

  static ThemeData lightFromDynamic(ColorScheme scheme) {
    final lightScheme = scheme.brightness == Brightness.light
        ? scheme
        : ColorScheme.fromSeed(seedColor: scheme.primary, brightness: Brightness.light);
    return _buildLightThemeFromScheme(lightScheme);
  }

  static ThemeData darkFromDynamic(ColorScheme scheme) {
    final darkScheme = scheme.brightness == Brightness.dark
        ? scheme
        : ColorScheme.fromSeed(seedColor: scheme.primary, brightness: Brightness.dark);
    return _buildDarkThemeFromScheme(darkScheme);
  }

  static ThemeData lightFromSeed(Color seedColor) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
    );
    return _buildLightThemeFromScheme(scheme);
  }

  static ThemeData darkFromSeed(Color seedColor) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    );
    return _buildDarkThemeFromScheme(scheme);
  }

  static ThemeData _buildLightThemeFromScheme(
    ColorScheme scheme, {
    Color? backgroundOverride,
  }) {
    final base = ThemeData(brightness: Brightness.light, useMaterial3: true);
    final textTheme = _buildTextTheme(base, scheme.onSurface);
    return _buildTheme(
      base,
      scheme,
      textTheme,
      backgroundOverride ?? scheme.surface,
      scheme.onSurface,
    );
  }

  static ThemeData _buildDarkThemeFromScheme(
    ColorScheme scheme, {
    Color? backgroundOverride,
  }) {
    final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
    final textTheme = _buildTextTheme(base, scheme.onSurface);
    return _buildTheme(
      base,
      scheme,
      textTheme,
      backgroundOverride ?? scheme.surface,
      scheme.onSurface,
    );
  }

  static TextTheme _buildTextTheme(ThemeData base, Color textColor) {
    return base.textTheme.apply(bodyColor: textColor, displayColor: textColor).copyWith(
          titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          bodyLarge: base.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        );
  }

  static ThemeData _buildTheme(ThemeData base, ColorScheme scheme, TextTheme textTheme, Color bg, Color text) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: bg,
        foregroundColor: text,
        titleSpacing: 20,
        leadingWidth: 46,
        titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: text),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        color: scheme.surface,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.65)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.65)),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.35)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: scheme.primary, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: scheme.error.withValues(alpha: 0.85)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: scheme.error, width: 1.8),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
    );
  }
}

