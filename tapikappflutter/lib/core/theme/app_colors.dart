import 'package:flutter/material.dart';

import 'app_palette.dart';

class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.canvas,
    required this.elevated,
    required this.surface,
    required this.surfaceAlt,
    required this.primary,
    required this.primaryHover,
    required this.primaryPress,
    required this.primarySubtle,
    required this.buttonPrimary,
    required this.success,
    required this.warning,
    required this.danger,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.navInactive,
    required this.controlOff,
    required this.onPrimary,
    required this.onAccent,
    required this.accent,
    required this.textSuccess,
    required this.textWarning,
    required this.textDanger,
    required this.borderDefault,
    required this.borderStrong,
    required this.borderFocus,
    required this.borderDanger,
    required this.toastSuccess,
    required this.toastWarning,
    required this.toastDanger,
    required this.onToast,
  });

  static const AppColors light = AppColors(
    canvas: AppPalette.white,
    elevated: AppPalette.white,
    surface: AppPalette.ink50,
    surfaceAlt: AppPalette.ink100,
    primary: AppPalette.violet500,
    primaryHover: AppPalette.violet600,
    primaryPress: AppPalette.violet700,
    primarySubtle: AppPalette.violet50,
    buttonPrimary: AppPalette.violet600,
    success: AppPalette.lime400,
    warning: AppPalette.amber400,
    danger: AppPalette.red400,
    textPrimary: AppPalette.ink950,
    textSecondary: AppPalette.ink600,
    textTertiary: AppPalette.ink500,
    navInactive: AppPalette.ink400,
    controlOff: AppPalette.ink400,
    onPrimary: AppPalette.white,
    onAccent: AppPalette.ink950,
    accent: AppPalette.violet600,
    textSuccess: AppPalette.lime800,
    textWarning: AppPalette.amber700,
    textDanger: AppPalette.red700,
    borderDefault: AppPalette.ink100,
    borderStrong: AppPalette.ink300,
    borderFocus: AppPalette.violet500,
    borderDanger: AppPalette.red600,
    toastSuccess: AppPalette.lime800,
    toastWarning: AppPalette.amber700,
    toastDanger: AppPalette.red700,
    onToast: AppPalette.white,
  );

  static const AppColors dark = AppColors(
    canvas: AppPalette.ink950,
    elevated: AppPalette.ink900,
    surface: AppPalette.ink850,
    surfaceAlt: AppPalette.ink800,
    primary: AppPalette.violet500,
    primaryHover: AppPalette.violet400,
    primaryPress: AppPalette.violet600,
    primarySubtle: AppPalette.violet900,
    buttonPrimary: AppPalette.violet600,
    success: AppPalette.lime400,
    warning: AppPalette.amber400,
    danger: AppPalette.red400,
    textPrimary: AppPalette.ink50,
    textSecondary: AppPalette.ink300,
    textTertiary: AppPalette.ink350,
    navInactive: AppPalette.ink350,
    controlOff: AppPalette.ink400,
    onPrimary: AppPalette.white,
    onAccent: AppPalette.ink950,
    accent: AppPalette.violet400,
    textSuccess: AppPalette.lime400,
    textWarning: AppPalette.amber400,
    textDanger: AppPalette.red400,
    borderDefault: AppPalette.ink700,
    borderStrong: AppPalette.ink600,
    borderFocus: AppPalette.violet400,
    borderDanger: AppPalette.red400,
    toastSuccess: AppPalette.lime800,
    toastWarning: AppPalette.amber700,
    toastDanger: AppPalette.red700,
    onToast: AppPalette.white,
  );

  final Color canvas;
  final Color elevated;
  final Color surface;
  final Color surfaceAlt;
  final Color primary;
  final Color primaryHover;
  final Color primaryPress;
  final Color primarySubtle;
  final Color buttonPrimary;
  final Color success;
  final Color warning;
  final Color danger;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color navInactive;
  final Color controlOff;
  final Color onPrimary;
  final Color onAccent;
  final Color accent;
  final Color textSuccess;
  final Color textWarning;
  final Color textDanger;
  final Color borderDefault;
  final Color borderStrong;
  final Color borderFocus;
  final Color borderDanger;
  final Color toastSuccess;
  final Color toastWarning;
  final Color toastDanger;
  final Color onToast;

  static AppColors of(BuildContext context) {
    return Theme.of(context).extension<AppColors>() ?? light;
  }

  @override
  AppColors copyWith({
    Color? canvas,
    Color? elevated,
    Color? surface,
    Color? surfaceAlt,
    Color? primary,
    Color? primaryHover,
    Color? primaryPress,
    Color? primarySubtle,
    Color? buttonPrimary,
    Color? success,
    Color? warning,
    Color? danger,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? navInactive,
    Color? controlOff,
    Color? onPrimary,
    Color? onAccent,
    Color? accent,
    Color? textSuccess,
    Color? textWarning,
    Color? textDanger,
    Color? borderDefault,
    Color? borderStrong,
    Color? borderFocus,
    Color? borderDanger,
    Color? toastSuccess,
    Color? toastWarning,
    Color? toastDanger,
    Color? onToast,
  }) {
    return AppColors(
      canvas: canvas ?? this.canvas,
      elevated: elevated ?? this.elevated,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      primary: primary ?? this.primary,
      primaryHover: primaryHover ?? this.primaryHover,
      primaryPress: primaryPress ?? this.primaryPress,
      primarySubtle: primarySubtle ?? this.primarySubtle,
      buttonPrimary: buttonPrimary ?? this.buttonPrimary,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      navInactive: navInactive ?? this.navInactive,
      controlOff: controlOff ?? this.controlOff,
      onPrimary: onPrimary ?? this.onPrimary,
      onAccent: onAccent ?? this.onAccent,
      accent: accent ?? this.accent,
      textSuccess: textSuccess ?? this.textSuccess,
      textWarning: textWarning ?? this.textWarning,
      textDanger: textDanger ?? this.textDanger,
      borderDefault: borderDefault ?? this.borderDefault,
      borderStrong: borderStrong ?? this.borderStrong,
      borderFocus: borderFocus ?? this.borderFocus,
      borderDanger: borderDanger ?? this.borderDanger,
      toastSuccess: toastSuccess ?? this.toastSuccess,
      toastWarning: toastWarning ?? this.toastWarning,
      toastDanger: toastDanger ?? this.toastDanger,
      onToast: onToast ?? this.onToast,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      elevated: Color.lerp(elevated, other.elevated, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryHover: Color.lerp(primaryHover, other.primaryHover, t)!,
      primaryPress: Color.lerp(primaryPress, other.primaryPress, t)!,
      primarySubtle: Color.lerp(primarySubtle, other.primarySubtle, t)!,
      buttonPrimary: Color.lerp(buttonPrimary, other.buttonPrimary, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      navInactive: Color.lerp(navInactive, other.navInactive, t)!,
      controlOff: Color.lerp(controlOff, other.controlOff, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      textSuccess: Color.lerp(textSuccess, other.textSuccess, t)!,
      textWarning: Color.lerp(textWarning, other.textWarning, t)!,
      textDanger: Color.lerp(textDanger, other.textDanger, t)!,
      borderDefault: Color.lerp(borderDefault, other.borderDefault, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      borderFocus: Color.lerp(borderFocus, other.borderFocus, t)!,
      borderDanger: Color.lerp(borderDanger, other.borderDanger, t)!,
      toastSuccess: Color.lerp(toastSuccess, other.toastSuccess, t)!,
      toastWarning: Color.lerp(toastWarning, other.toastWarning, t)!,
      toastDanger: Color.lerp(toastDanger, other.toastDanger, t)!,
      onToast: Color.lerp(onToast, other.onToast, t)!,
    );
  }
}
