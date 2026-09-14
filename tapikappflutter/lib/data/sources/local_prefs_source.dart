import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme_mode.dart';

class LocalPrefsSource {
  static const String _loggedInKey = 'logged_in';
  static const String _themeModeKey = 'theme_mode';

  Future<void> setLoggedIn(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_loggedInKey, value);
  }

  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_loggedInKey) ?? false;
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, mode.name);
  }

  Future<AppThemeMode> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return AppThemeMode.fromName(prefs.getString(_themeModeKey));
  }
}
