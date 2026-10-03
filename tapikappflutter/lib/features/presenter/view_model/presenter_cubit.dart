import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/protocol/keycodes.dart';
import '../../../core/protocol/packet.dart';
import '../../../services/transport/transport.dart';
import 'presenter_state.dart';

class PresenterCubit extends Cubit<PresenterState> {
  PresenterCubit(this._transport) : super(const PresenterState());

  static const int blackScreenUsage = 0x05;

  final Transport _transport;
  StreamSubscription<TransportState>? _link;

  void start() {
    _link ??= _transport.states.listen(_onTransport);
    _onTransport(_transport.state);
  }

  void next() => _tap(Keycodes.usageArrowRight);

  void previous() => _tap(Keycodes.usageArrowLeft);

  void toggleBlackScreen() {
    if (!_connected) return;
    _tap(blackScreenUsage);
    emit(state.copyWith(screenBlanked: !state.screenBlanked));
  }

  bool get _connected => state.connection == PresenterConnection.connected;

  void _tap(int usage) {
    if (!_connected) return;
    _transport.send(
      KeyPacket(keyCode: usage, modifiers: KeyModifiers.none, down: true),
    );
    _transport.send(
      KeyPacket(keyCode: usage, modifiers: KeyModifiers.none, down: false),
    );
  }

  void _onTransport(TransportState transport) {
    final endpoint = _transport.endpoint;
    final connected = transport == TransportState.connected;
    emit(
      state.copyWith(
        connection: switch (transport) {
          TransportState.connected => PresenterConnection.connected,
          TransportState.connecting => PresenterConnection.connecting,
          TransportState.disconnected => PresenterConnection.disconnected,
        },
        deviceName: () => endpoint?.label ?? endpoint?.host,
        screenBlanked: connected && state.screenBlanked,
      ),
    );
  }

  @override
  Future<void> close() async {
    await _link?.cancel();
    return super.close();
  }
}
