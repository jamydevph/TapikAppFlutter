import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/error/failure.dart';
import '../../../data/models/device_model.dart';
import '../../../data/repositories/device_repository.dart';
import 'connect_state.dart';

class ConnectCubit extends Cubit<ConnectState> {
  ConnectCubit(this._devices) : super(const ConnectLoading());

  final DeviceRepository _devices;
  StreamSubscription<List<DeviceModel>>? _subscription;

  void start() {
    _subscription?.cancel();
    try {
      _subscription = _devices.watchDevices().listen(
        _onRegistry,
        onError: _onError,
      );
    } on Failure catch (failure) {
      emit(ConnectError(failure.message));
    }
  }

  void _onRegistry(List<DeviceModel> registry) {
    final offline =
        registry
            .map(
              (device) => ConnectDevice(
                id: device.id,
                name: device.name,
                platform: device.platform,
                status: ConnectDeviceStatus.offline,
                lastSeenAt: device.lastSeenAt,
              ),
            )
            .toList()
          ..sort(_byLastSeen);
    emit(ConnectReady(nearby: const [], offline: offline));
  }

  void _onError(Object error) {
    emit(
      ConnectError(
        error is Failure
            ? error.message
            : 'Something went wrong. Please try again.',
      ),
    );
  }

  static int _byLastSeen(ConnectDevice a, ConnectDevice b) {
    final left = a.lastSeenAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final right = b.lastSeenAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return right.compareTo(left);
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
