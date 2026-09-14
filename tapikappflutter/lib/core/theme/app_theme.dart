import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_tokens.dart';
import 'app_typography.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData get light => _build(AppColors.light, Brightness.light);
  static ThemeData get dark => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors colors, Brightness brightness) {
    final textTheme = AppTextStyles.textTheme(colors);
    final scheme = ColorScheme(
      brightness: brightness,
      primary: colors.primary,
      onPrimary: colors.onPrimary,
      primaryContainer: colors.primarySubtle,
      onPrimaryContainer: colors.accent,
      secondary: colors.primary,
      onSecondary: colors.onPrimary,
      secondaryContainer: colors.primarySubtle,
      onSecondaryContainer: colors.accent,
      tertiary: colors.success,
      onTertiary: colors.onAccent,
      error: colors.textDanger,
      onError: colors.onPrimary,
      errorContainer: colors.danger,
      onErrorContainer: colors.onAccent,
      surface: colors.canvas,
      onSurface: colors.textPrimary,
      onSurfaceVariant: colors.textSecondary,
      surfaceContainerLowest: colors.canvas,
      surfaceContainerLow: colors.elevated,
      surfaceContainer: colors.surface,
      surfaceContainerHigh: colors.surface,
      surfaceContainerHighest: colors.surfaceAlt,
      outline: colors.borderStrong,
      outlineVariant: colors.borderDefault,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: colors.textPrimary,
      onInverseSurface: colors.canvas,
      inversePrimary: colors.primarySubtle,
    );
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: AppFonts.poppins,
      textTheme: textTheme,
      extensions: [colors],
      scaffoldBackgroundColor: colors.canvas,
      canvasColor: colors.canvas,
      cardColor: colors.elevated,
      dividerColor: colors.borderDefault,
      appBarTheme: AppBarTheme(
        backgroundColor: colors.canvas,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: AppTextStyles.headingM.copyWith(color: colors.textPrimary),
      ),
      dividerTheme: DividerThemeData(
        color: colors.borderDefault,
        thickness: 1,
        space: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          disabledBackgroundColor: colors.surfaceAlt,
          disabledForegroundColor: colors.textTertiary,
          minimumSize: const Size(64, AppComponentSizes.buttonHeight),
          shape: buttonShape,
          textStyle: AppTextStyles.labelL,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.textPrimary,
          backgroundColor: colors.surface,
          disabledForegroundColor: colors.textTertiary,
          side: BorderSide(color: colors.borderDefault),
          minimumSize: const Size(64, AppComponentSizes.buttonHeight),
          shape: buttonShape,
          textStyle: AppTextStyles.labelL,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.accent,
          disabledForegroundColor: colors.textTertiary,
          minimumSize: const Size(64, AppComponentSizes.buttonHeight),
          shape: buttonShape,
          textStyle: AppTextStyles.labelL,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceAlt,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        hintStyle: AppTextStyles.bodyL.copyWith(color: colors.textTertiary),
        labelStyle: AppTextStyles.labelM.copyWith(color: colors.textSecondary),
        helperStyle: AppTextStyles.caption.copyWith(color: colors.textTertiary),
        errorStyle: AppTextStyles.caption.copyWith(color: colors.textDanger),
        border: _fieldBorder(colors.borderDefault),
        enabledBorder: _fieldBorder(colors.borderDefault),
        focusedBorder: _fieldBorder(colors.borderFocus, width: 2),
        errorBorder: _fieldBorder(colors.borderDanger),
        focusedErrorBorder: _fieldBorder(colors.borderDanger, width: 2),
        disabledBorder: _fieldBorder(colors.borderDefault),
      ),
    );
  }

  static OutlineInputBorder _fieldBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}
