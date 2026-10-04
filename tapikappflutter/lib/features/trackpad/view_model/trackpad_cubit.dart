import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/error/failure.dart';
import '../../../data/models/settings_model.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../services/transport/transport.dart';
import 'trackpad_state.dart';

class TrackpadCubit extends Cubit<TrackpadState> {
  TrackpadCubit(this._settings, this._transport) : super(const TrackpadState());

  static const double minSensitivity = SettingsModel.minSensitivity;
  static const double maxSensitivity = SettingsModel.maxSensitivity;

  final SettingsRepository _settings;
  final Transport _transport;
  StreamSubscription<SettingsModel>? _subscription;
  StreamSubscription<TransportState>? _link;

  void start() {
    _subscription?.cancel();
    _subscription = _settings.watch().listen(
      _onSettings,
      onError: (Object _) {},
    );
    _link ??= _transport.states.listen(_onTransport);
    _onTransport(_transport.state);
  }

  void _onTransport(TransportState transport) {
    final endpoint = _transport.endpoint;
    emit(
      state.copyWith(
        connection: switch (transport) {
          TransportState.connected => TrackpadConnection.connected,
          TransportState.connecting => TrackpadConnection.connecting,
          TransportState.pairing => TrackpadConnection.connecting,
          TransportState.disconnected => TrackpadConnection.disconnected,
        },
        deviceName: () => endpoint?.label ?? endpoint?.host,
      ),
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
    await _link?.cancel();
    return super.close();
  }
}
