import 'package:flutter/material.dart';

class AppTheme {
  // Dark theme colors (Mac-like)
  static const Color darkBg = Color(0xEC161616); // 92.5% opacity dark charcoal
  static const Color darkPanelBg = Color(0xFF222222);
  static const Color darkAccent = Color(0xFF0A84FF); // macOS Blue
  static const Color darkSecondaryText = Color(0xFF8E8E93);
  static const Color darkBorder = Color(0x28FFFFFF); // Light border for dark mode
  static const Color darkGlow = Color(0x1F0A84FF);
  
  // Light theme colors (Mac-like)
  static const Color lightBg = Color(0xF2F2F2F2); // 95% opacity light grey
  static const Color lightPanelBg = Color(0xFFFFFFFF);
  static const Color lightAccent = Color(0xFF007AFF);
  static const Color lightSecondaryText = Color(0xFF6C6C70);
  static const Color lightBorder = Color(0x1F000000);
  static const Color lightGlow = Color(0x14007AFF);

  // Common Layout Options
  static const double borderRadius = 12.0;
  static const double panelBorderRadius = 16.0;
  
  static BoxShadow getPanelShadow(bool isDark) {
    return BoxShadow(
      color: isDark ? Colors.black.withOpacity(0.4) : Colors.black.withOpacity(0.12),
      blurRadius: 18,
      spreadRadius: 2,
      offset: const Offset(0, 8),
    );
  }

  static BoxDecoration getFrostedDecoration({required bool isDark, double radius = panelBorderRadius}) {
    return BoxDecoration(
      color: isDark ? darkBg : lightBg,
      borderRadius: BorderRadius.only(
        bottomLeft: Radius.circular(radius),
        bottomRight: Radius.circular(radius),
      ),
      border: Border.all(
        color: isDark ? darkBorder : lightBorder,
        width: 1.0,
      ),
    );
  }

  static Color getAccentColor(String? colorName, bool isDark) {
    switch (colorName?.toLowerCase()) {
      case 'orange':
        return isDark ? const Color(0xFFFF9F0A) : const Color(0xFFFF9500);
      case 'green':
        return isDark ? const Color(0xFF30D158) : const Color(0xFF34C759);
      case 'purple':
        return isDark ? const Color(0xFFBF5AF2) : const Color(0xFFAF52DE);
      case 'red':
        return isDark ? const Color(0xFFFF453A) : const Color(0xFFFF3B30);
      case 'blue':
      default:
        return isDark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF);
    }
  }

  static ThemeData getThemeData(bool isDark, String colorName) {
    final baseColor = isDark ? Colors.white : Colors.black;
    final accent = getAccentColor(colorName, isDark);
    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      primaryColor: accent,
      scaffoldBackgroundColor: Colors.transparent,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: isDark ? Brightness.dark : Brightness.light,
        surface: isDark ? darkPanelBg : lightPanelBg,
      ),
      textTheme: const TextTheme(
        titleMedium: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        titleSmall: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        bodyMedium: TextStyle(fontSize: 13),
        bodySmall: TextStyle(fontSize: 11),
      ).apply(
        bodyColor: baseColor,
        displayColor: baseColor,
        fontFamily: 'Segoe UI', // Windows default modern sans-serif
      ),
      iconTheme: IconThemeData(
        color: isDark ? Colors.white.withOpacity(0.9) : Colors.black.withOpacity(0.8),
        size: 20,
      ),
    );
  }
}
