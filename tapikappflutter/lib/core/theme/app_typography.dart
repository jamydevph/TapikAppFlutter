import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppFonts {
  const AppFonts._();

  static const String poppins = 'Poppins';
  static const String jetBrainsMono = 'JetBrainsMono';
}

class AppTextStyles {
  const AppTextStyles._();

  static const TextStyle displayXl = TextStyle(
    fontFamily: AppFonts.poppins,
    fontSize: 34,
    height: 42 / 34,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.6,
  );

  static const TextStyle displayL = TextStyle(
    fontFamily: AppFonts.poppins,
    fontSize: 28,
    height: 36 / 28,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
  );

  static const TextStyle headingXl = TextStyle(
    fontFamily: AppFonts.poppins,
    fontSize: 24,
    height: 32 / 24,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
  );

  static const TextStyle headingL = TextStyle(
    fontFamily: AppFonts.poppins,
    fontSize: 20,
    height: 28 / 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );

  static const TextStyle headingM = TextStyle(
    fontFamily: AppFonts.poppins,
    fontSize: 17,
    height: 24 / 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  );

  static const TextStyle bodyL = TextStyle(
    fontFamily: AppFonts.poppins,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
  );

  static const TextStyle bodyM = TextStyle(
    fontFamily: AppFonts.poppins,
    fontSize: 15,
    height: 22 / 15,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
  );

  static const TextStyle bodyS = TextStyle(
    fontFamily: AppFonts.poppins,
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
  );

  static const TextStyle labelL = TextStyle(
    fontFamily: AppFonts.poppins,
    fontSize: 16,
    height: 20 / 16,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
  );

  static const TextStyle labelM = TextStyle(
    fontFamily: AppFonts.poppins,
    fontSize: 14,
    height: 18 / 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
  );

  static const TextStyle labelS = TextStyle(
    fontFamily: AppFonts.poppins,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.3,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: AppFonts.poppins,
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.2,
  );

  static const TextStyle overline = TextStyle(
    fontFamily: AppFonts.poppins,
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.4,
  );

  static const TextStyle monoCode = TextStyle(
    fontFamily: AppFonts.jetBrainsMono,
    fontSize: 40,
    height: 48 / 40,
    fontWeight: FontWeight.w700,
    letterSpacing: 8,
  );

  static const TextStyle monoS = TextStyle(
    fontFamily: AppFonts.jetBrainsMono,
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
  );

  static TextTheme textTheme(AppColors colors) {
    const base = TextTheme(
      displayLarge: displayXl,
      displayMedium: displayL,
      displaySmall: headingXl,
      headlineLarge: headingXl,
      headlineMedium: headingL,
      headlineSmall: headingM,
      titleLarge: headingL,
      titleMedium: labelL,
      titleSmall: labelM,
      bodyLarge: bodyL,
      bodyMedium: bodyM,
      bodySmall: bodyS,
      labelLarge: labelL,
      labelMedium: labelM,
      labelSmall: labelS,
    );
    return base.apply(
      bodyColor: colors.textPrimary,
      displayColor: colors.textPrimary,
    );
  }
}
