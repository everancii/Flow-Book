// lib/resources/designs/themes.dart
import 'package:flutter/material.dart';
import 'app_colors.dart';

class Themes {
  // Light Theme
  static final ThemeData lightTheme = ThemeData.light().copyWith(
    scaffoldBackgroundColor: AppColors.scaffoldBackgroundColor,
    // Kill surface tint so grays don't get a blue cast
    colorScheme: ThemeData.light().colorScheme.copyWith(
          primary: AppColors.primaryColor,
          secondary: AppColors.primaryColor,
          surfaceTint: Colors.transparent,
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.scaffoldBackgroundColor,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.scaffoldBackgroundColor,
      elevation: 0,
      selectedItemColor: AppColors.primaryColor,
      unselectedItemColor: Colors.grey,
    ),
    cardTheme: const CardThemeData(
      color: AppColors.cardColorLight,
    ),
  );

  // Dark Theme
  static final ThemeData darkTheme = ThemeData.dark().copyWith(
    scaffoldBackgroundColor: AppColors.darkScaffoldBackgroundColor,
    colorScheme: ThemeData.dark().colorScheme.copyWith(
          primary: AppColors.primaryColor,
          secondary: AppColors.primaryColor,
          surfaceTint: Colors.transparent,
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.darkScaffoldBackgroundColor,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.darkScaffoldBackgroundColor,
      elevation: 0,
      selectedItemColor: AppColors.primaryColor,
      unselectedItemColor: Colors.grey,
    ),
  );

  // Blue Theme
  static final ThemeData blueTheme = ThemeData.light().copyWith(
    scaffoldBackgroundColor: AppColors.blueScaffoldBackground,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.bluePrimaryColor,
      primary: AppColors.bluePrimaryColor,
      secondary: AppColors.bluePrimaryColor,
      surface: AppColors.blueScaffoldBackground,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bluePrimaryColor,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    cardTheme: const CardThemeData(
      color: AppColors.blueCardColor,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.blueCardColor,
      selectedItemColor: AppColors.bluePrimaryColor,
      unselectedItemColor: Colors.blueGrey,
    ),
  );
}
