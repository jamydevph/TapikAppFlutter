import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/error/failure.dart';
import '../../../core/theme/app_theme_mode.dart';
import '../../../data/models/device_model.dart';
import '../../../data/models/settings_model.dart';
import '../../../data/repositories/device_repository.dart';
import '../../../data/repositories/settings_repository.dart';
import 'settings_state.dart';

class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit(this._settings, this._devices) : super(const SettingsState());

  static const double minSensitivity = SettingsModel.minSensitivity;
  static const double maxSensitivity = SettingsModel.maxSensitivity;
  static const String genericError = 'Something went wrong. Please try again.';

  final SettingsRepository _settings;
  final DeviceRepository _devices;
  StreamSubscription<SettingsModel>? _settingsSubscription;
  StreamSubscription<List<DeviceModel>>? _devicesSubscription;
  StreamSubscription<Failure>? _saveFailures;

  void start() {
    _settingsSubscription?.cancel();
    _devicesSubscription?.cancel();
    _saveFailures?.cancel();
    _settingsSubscription = _settings.watch().listen(
      _onSettings,
      onError: _onError,
    );
    _saveFailures = _settings.saveFailures.listen(_onError);
    try {
      _devicesSubscription = _devices.watchDevices().listen(
        _onRegistry,
        onError: _onError,
      );
    } on Failure catch (failure) {
      _onError(failure);
    }
  }

  void setSensitivity(double value) {
    final clamped = value.clamp(minSensitivity, maxSensitivity).toDouble();
    if (clamped == state.sensitivity) return;
    emit(state.copyWith(sensitivity: clamped));
    _update(_settings.current.copyWith(sensitivity: clamped));
  }

  void setNaturalScrolling(bool enabled) {
    if (enabled == state.naturalScrolling) return;
    emit(state.copyWith(naturalScrolling: enabled));
    _update(_settings.current.copyWith(naturalScrolling: enabled));
  }

  void setHapticFeedback(bool enabled) {
    if (enabled == state.hapticFeedback) return;
    emit(state.copyWith(hapticFeedback: enabled));
    _update(_settings.current.copyWith(hapticFeedback: enabled));
  }

  void setThemeMode(AppThemeMode mode) {
    if (mode == state.themeMode) return;
    emit(state.copyWith(themeMode: mode));
    _update(_settings.current.copyWith(themeMode: mode));
  }

  Future<void> flushPending() async {
    try {
      await _settings.flush();
    } on Failure catch (failure) {
      _onError(failure);
    }
  }

  Future<void> revoke(String deviceId) async {
    if (state.isRevoking(deviceId)) return;
    emit(state.copyWith(revokingIds: {...state.revokingIds, deviceId}));
    try {
      await _devices.revokeDevice(deviceId);
    } on Failure catch (failure) {
      _onError(failure);
    } finally {
      if (!isClosed) {
        emit(
          state.copyWith(revokingIds: {...state.revokingIds}..remove(deviceId)),
        );
      }
    }
  }

  void _update(SettingsModel settings) {
    try {
      _settings.update(settings);
    } on Failure catch (failure) {
      _onError(failure);
    }
  }

  void _onSettings(SettingsModel settings) {
    emit(
      state.copyWith(
        loaded: _settings.loaded,
        sensitivity: settings.sensitivity,
        naturalScrolling: settings.naturalScrolling,
        hapticFeedback: settings.hapticFeedback,
        themeMode: settings.themeMode,
      ),
    );
  }

  void _onRegistry(List<DeviceModel> registry) {
    final devices =
        registry
            .map(
              (device) => SettingsDevice(
                id: device.id,
                name: device.name,
                platform: device.platform,
                certFingerprint: device.certFingerprint,
                trustedAt: device.trustedAt,
                lastSeenAt: device.lastSeenAt,
              ),
            )
            .toList()
          ..sort(_byTrusted);
    emit(state.copyWith(devices: devices, devicesLoaded: true));
  }

  void _onError(Object error) {
    if (isClosed) return;
    emit(
      state.copyWith(
        error: error is Failure ? error.message : genericError,
        errorId: state.errorId + 1,
      ),
    );
  }

  static int _byTrusted(SettingsDevice a, SettingsDevice b) {
    final left = a.trustedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final right = b.trustedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return right.compareTo(left);
  }

  @override
  Future<void> close() async {
    await _settingsSubscription?.cancel();
    await _devicesSubscription?.cancel();
    await _saveFailures?.cancel();
    return super.close();
  }
}
