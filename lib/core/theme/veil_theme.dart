import 'package:flutter/material.dart';

class VeilColors {
  static const Color background = Color(0xFF000000);
  static const Color surface = Color(0xFF0A0A0A);
  static const Color card = Color(0xFF111111);
  static const Color cardElevated = Color(0xFF1A1A1A);

  static const Color primaryText = Color(0xFFF3F4F6);
  static const Color secondaryText = Color(0xFF9CA3AF);
  static const Color mutedText = Color(0xFF6B7280);

  // Emerald Green is the default, can be replaced dynamically
  static const Color defaultAccent = Color(0xFF10B981);
  static const Color defaultAccentMuted = Color(0x2010B981);

  static const Color error = Color(0xFFEF4444);
}

/// Veil Motion System — unified animation language.
/// All interactive components reference these constants.
class VeilMotion {
  VeilMotion._();

  // Durations
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration standard = Duration(milliseconds: 200);
  static const Duration emphasized = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 400);

  // Curves
  static const Curve curve = Curves.easeOutCubic; // General interactions
  static const Curve curveIn = Curves.easeInCubic; // Dismiss/exit
  static const Curve curveSharp = Curves.easeOut; // Snappy press feedback
  static const Curve curveSpring = Curves.elasticOut; // Bounce (use sparingly)

  // Scale values for press feedback
  static const double scaleCard = 0.97;
  static const double scaleButton = 0.94;
  static const double scaleChip = 0.95;
}

class VeilTheme {
  final Color accentColor;
  final bool amoledPureBlack;
  final Brightness brightness;

  const VeilTheme({
    this.accentColor = VeilColors.defaultAccent,
    this.amoledPureBlack = true,
    this.brightness = Brightness.dark,
  });

  static Color getAccentColor(String name) {
    switch (name) {
      case 'Ruby Red':
        return const Color(0xFFEF4444);
      case 'Sapphire Blue':
        return const Color(0xFF3B82F6);
      case 'Amber Gold':
        return const Color(0xFFF59E0B);
      case 'Nothing Silver':
        return const Color(0xFFE5E7EB);
      case 'Emerald':
      default:
        return const Color(0xFF10B981);
    }
  }

  ThemeData get themeData {
    final isDark = brightness == Brightness.dark;

    final bgColor = isDark
        ? (amoledPureBlack ? const Color(0xFF000000) : const Color(0xFF0C0F0E))
        : const Color(0xFFF9FAFB);

    final surfaceColor = isDark
        ? (amoledPureBlack ? const Color(0xFF0A0A0A) : const Color(0xFF141816))
        : const Color(0xFFFFFFFF);

    final cardColor = isDark
        ? (amoledPureBlack ? const Color(0xFF111111) : const Color(0xFF1C211E))
        : const Color(0xFFF3F4F6);

    final cardElevatedColor = isDark
        ? (amoledPureBlack ? const Color(0xFF1A1A1A) : const Color(0xFF262C29))
        : const Color(0xFFE5E7EB);

    final primaryText = isDark
        ? const Color(0xFFF3F4F6)
        : const Color(0xFF111827);
    final secondaryText = isDark
        ? const Color(0xFF9CA3AF)
        : const Color(0xFF4B5563);
    final mutedText = isDark
        ? const Color(0xFF6B7280)
        : const Color(0xFF9CA3AF);

    final borderColor = isDark
        ? (amoledPureBlack ? const Color(0xFF1E1E1E) : const Color(0xFF2E3532))
        : const Color(0xFFE5E7EB);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: bgColor,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: primaryText),
        actionsIconTheme: IconThemeData(color: primaryText),
        titleTextStyle: TextStyle(
          color: primaryText,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: borderColor,
        thickness: 1,
        space: 1,
      ),
      colorScheme: isDark
          ? ColorScheme.dark(
              surface: surfaceColor,
              onSurface: primaryText,
              primary: accentColor,
              secondary: accentColor.withValues(alpha: 0.7),
              error: VeilColors.error,
            )
          : ColorScheme.light(
              surface: surfaceColor,
              onSurface: primaryText,
              primary: accentColor,
              secondary: accentColor.withValues(alpha: 0.7),
              error: VeilColors.error,
            ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: borderColor, width: 1),
        ),
      ),
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          color: primaryText,
          fontSize: 32,
          fontWeight: FontWeight.w300,
          letterSpacing: -0.5,
        ),
        headlineMedium: TextStyle(
          color: primaryText,
          fontSize: 24,
          fontWeight: FontWeight.w400,
          letterSpacing: -0.5,
        ),
        titleLarge: TextStyle(
          color: primaryText,
          fontSize: 20,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.2,
        ),
        titleMedium: TextStyle(
          color: primaryText,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        bodyLarge: TextStyle(
          color: primaryText,
          fontSize: 15,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.1,
        ),
        bodyMedium: TextStyle(
          color: secondaryText,
          fontSize: 13,
          fontWeight: FontWeight.w400,
        ),
        labelLarge: TextStyle(
          color: primaryText,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
        labelMedium: TextStyle(
          color: mutedText,
          fontSize: 11,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.5,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accentColor,
        inactiveTrackColor: isDark ? Colors.white12 : Colors.black12,
        thumbColor: accentColor,
        trackHeight: 2.0,
        overlayColor: accentColor.withValues(alpha: 0.12),
        valueIndicatorColor: cardElevatedColor,
        valueIndicatorTextStyle: TextStyle(color: primaryText),
      ),
    );
  }
}
