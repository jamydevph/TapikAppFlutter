import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/protocol/keycodes.dart';
import '../../../core/protocol/packet.dart';
import '../../../services/transport/transport.dart';
import 'keyboard_state.dart';

class KeyboardCubit extends Cubit<KeyboardState> {
  KeyboardCubit(this._transport) : super(const KeyboardState());

  final Transport _transport;
  StreamSubscription<TransportState>? _link;

  void start() {
    _link ??= _transport.states.listen(_onTransport);
    _onTransport(_transport.state);
  }

  void toggleModifier(KeyModifier modifier) {
    final held = Set<KeyModifier>.of(state.heldModifiers);
    if (!held.remove(modifier)) {
      held.add(modifier);
    }
    emit(state.copyWith(heldModifiers: held));
  }

  void releaseAll() {
    if (state.heldModifiers.isEmpty) return;
    emit(state.copyWith(heldModifiers: const {}));
  }

  void tapKey(int usage) {
    if (state.connection != KeyboardConnection.connected) return;
    final modifiers = _mask();
    _transport.send(
      KeyPacket(keyCode: usage, modifiers: modifiers, down: true),
    );
    _transport.send(
      KeyPacket(keyCode: usage, modifiers: modifiers, down: false),
    );
  }

  void tapLetter(String character) {
    final usage = Keycodes.letter(character);
    if (usage == null) return;
    tapKey(usage);
  }

  void sendText(String text) {
    if (text.isEmpty) return;
    if (state.connection != KeyboardConnection.connected) return;
    _transport.send(TextPacket(text));
  }

  KeyModifiers _mask() {
    final held = state.heldModifiers;
    return KeyModifiers(
      command: held.contains(KeyModifier.command),
      option: held.contains(KeyModifier.option),
      shift: held.contains(KeyModifier.shift),
      control: held.contains(KeyModifier.control),
    );
  }

  void _onTransport(TransportState transport) {
    final endpoint = _transport.endpoint;
    final connected = transport == TransportState.connected;
    emit(
      state.copyWith(
        connection: switch (transport) {
          TransportState.connected => KeyboardConnection.connected,
          TransportState.connecting => KeyboardConnection.connecting,
          TransportState.disconnected => KeyboardConnection.disconnected,
        },
        deviceName: () => endpoint?.label ?? endpoint?.host,
        heldModifiers: connected ? state.heldModifiers : const {},
      ),
    );
  }

  @override
  Future<void> close() async {
    await _link?.cancel();
    return super.close();
  }
}
