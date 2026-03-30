import 'package:flutter/material.dart';

/// 偏「多邻国」：高饱和主色、大圆角。
/// 不使用 runtime 网络字体，避免二次冷启动后字体未就绪时整主题回退成「旧 Material」观感。
abstract final class AppTheme {
  static const Color duoGreen = Color(0xFF58CC02);
  static const Color duoGreenDark = Color(0xFF46A302);
  static const Color duoBlue = Color(0xFF1CB0F6);
  static const Color duoBlueDark = Color(0xFF1899D6);
  static const Color duoYellow = Color(0xFFFFC800);
  static const Color duoOrange = Color(0xFFFF9600);
  static const Color duoRed = Color(0xFFFF4B4B);
  static const Color duoBg = Color(0xFFF7F7F7);

  /// 深灰底，偏「多邻国」夜间：仍保留鲜绿主色，降低疲劳。
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

    final base = ThemeData(brightness: Brightness.light, useMaterial3: true);
    final textTheme = base.textTheme
        .apply(bodyColor: textPrimary, displayColor: textPrimary)
        .copyWith(
          titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          titleSmall: base.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          bodyLarge: base.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: duoBg,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: duoBg,
        foregroundColor: textPrimary,
        titleTextStyle: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        color: Colors.white,
        shadowColor: Colors.black26,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.35)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: duoBlue, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.25)),
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: textPrimary),
        backgroundColor: scheme.surfaceContainerLow,
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  static ThemeData get dark {
    final scheme = ColorScheme.dark(
      brightness: Brightness.dark,
      primary: duoGreen,
      onPrimary: const Color(0xFF0D1A00),
      primaryContainer: const Color(0xFF2D4A12),
      onPrimaryContainer: const Color(0xFFB8F08A),
      secondary: duoBlue,
      onSecondary: const Color(0xFF001520),
      surface: const Color(0xFF1C242D),
      onSurface: textPrimaryDark,
      surfaceContainerHigh: const Color(0xFF283038),
      surfaceContainerHighest: const Color(0xFF323B45),
      error: const Color(0xFFFF8A8A),
      onError: const Color(0xFF2D0A0A),
      outline: const Color(0xFF4A5563),
      outlineVariant: const Color(0xFF3D4754),
    );

    final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
    final textTheme = base.textTheme
        .apply(bodyColor: textPrimaryDark, displayColor: textPrimaryDark)
        .copyWith(
          titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          titleSmall: base.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          bodyLarge: base.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: duoBgDark,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: duoBgDark,
        foregroundColor: textPrimaryDark,
        titleTextStyle: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: textPrimaryDark,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        color: scheme.surface,
        shadowColor: Colors.black54,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.5)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.35)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: duoBlue, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.4)),
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: textPrimaryDark),
        backgroundColor: scheme.surfaceContainerHighest,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
