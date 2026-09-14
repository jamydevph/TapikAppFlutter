import 'package:flutter/material.dart';

enum AppThemeMode {
  light,
  dark,
  system;

  static AppThemeMode fromName(String? name) {
    return values.firstWhere(
      (mode) => mode.name == name,
      orElse: () => AppThemeMode.system,
    );
  }

  ThemeMode get material {
    return switch (this) {
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark => ThemeMode.dark,
      AppThemeMode.system => ThemeMode.system,
    };
  }
}
