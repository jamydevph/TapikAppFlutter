import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_theme_mode.dart';
import '../../../data/sources/local_prefs_source.dart';

class ThemeCubit extends Cubit<AppThemeMode> {
  ThemeCubit({LocalPrefsSource? prefs})
      : _prefs = prefs ?? LocalPrefsSource(),
        super(AppThemeMode.system);

  final LocalPrefsSource _prefs;

  Future<void> load() async {
    emit(await _prefs.getThemeMode().catchError((Object _) => AppThemeMode.system));
  }

  void setMode(AppThemeMode mode) {
    if (mode == state) return;
    emit(mode);
    _prefs.setThemeMode(mode).ignore();
  }
}
