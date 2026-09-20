import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/error/failure.dart';
import '../../../data/models/settings_model.dart';
import '../../../data/repositories/settings_repository.dart';
import 'trackpad_state.dart';

class TrackpadCubit extends Cubit<TrackpadState> {
  TrackpadCubit(this._settings) : super(const TrackpadState());

  static const double minSensitivity = SettingsModel.minSensitivity;
  static const double maxSensitivity = SettingsModel.maxSensitivity;

  final SettingsRepository _settings;
  StreamSubscription<SettingsModel>? _subscription;

  void start() {
    _subscription?.cancel();
    _subscription = _settings.watch().listen(
      _onSettings,
      onError: (Object _) {},
    );
  }

  void setSensitivity(double value) {
    final clamped = value.clamp(minSensitivity, maxSensitivity).toDouble();
    if (clamped == state.sensitivity) return;
    emit(state.copyWith(sensitivity: clamped));
    try {
      _settings.update(_settings.current.copyWith(sensitivity: clamped));
    } on Failure {
      return;
    }
  }

  void _onSettings(SettingsModel settings) {
    emit(
      state.copyWith(
        sensitivity: settings.sensitivity,
        naturalScrolling: settings.naturalScrolling,
      ),
    );
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
