import 'package:flutter/material.dart';

// Ventago 다크 네이비 + 골드 테마.
class AppColors {
  static const navy = Color(0xFF1A1A2E);
  static const navy2 = Color(0xFF16213E);
  static const panel = Color(0xFF1F2947);
  static const gold = Color(0xFFF5A623);
  static const cyan = Color(0xFF00B8D4);
  static const txt = Color(0xFFE8ECF5);
  static const dim = Color(0xFF9AA6C4);
  static const line = Color(0xFF2C3860);
  static const red = Color(0xFFFF5A5F);
  static const amber = Color(0xFFF5A623);
  static const green = Color(0xFF33D17A);
}

ThemeData buildAppTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.gold,
    secondary: AppColors.cyan,
    surface: AppColors.panel,
    error: AppColors.red,
    onPrimary: AppColors.navy,
    onSurface: AppColors.txt,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.navy,
    canvasColor: AppColors.navy2,
    dividerColor: AppColors.line,
    cardTheme: const CardThemeData(
      color: AppColors.panel,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: AppColors.line),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Color(0xFF0E1428),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: AppColors.line),
      ),
    ),
    textTheme: const TextTheme().apply(
      bodyColor: AppColors.txt,
      displayColor: AppColors.txt,
    ),
  );
}
