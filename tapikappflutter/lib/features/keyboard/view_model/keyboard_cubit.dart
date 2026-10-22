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
    _tap(usage, _mask());
  }

  void tapLetter(String character) {
    final usage = Keycodes.letter(character);
    if (usage == null) return;
    tapKey(usage);
  }

  void tapMedia(int usage) {
    if (state.connection != KeyboardConnection.connected) return;
    _transport.send(MediaPacket(usage));
  }

  void tapShortcut(KeyboardShortcut shortcut) {
    if (state.connection != KeyboardConnection.connected) return;
    final platform = _transport.endpoint?.platform;
    final primary = Keycodes.primaryModifier(platform);
    switch (shortcut) {
      case KeyboardShortcut.cut:
        _tap(Keycodes.letter('X')!, primary);
      case KeyboardShortcut.copy:
        _tap(Keycodes.letter('C')!, primary);
      case KeyboardShortcut.paste:
        _tap(Keycodes.letter('V')!, primary);
      case KeyboardShortcut.undo:
        _tap(Keycodes.letter('Z')!, primary);
      case KeyboardShortcut.switchApp:
        _switchApp(platform);
    }
  }

  // The app switcher only settles when the real modifier key is let go, so
  // hold it around the Tab instead of only flagging the Tab.
  void _switchApp(String? platform) {
    final hold = Keycodes.appSwitchKey(platform);
    final modifiers = Keycodes.appSwitchModifier(platform);
    _transport.send(KeyPacket(keyCode: hold, modifiers: modifiers, down: true));
    _tap(Keycodes.usageTab, modifiers);
    _transport.send(
      KeyPacket(keyCode: hold, modifiers: KeyModifiers.none, down: false),
    );
  }

  void _tap(int usage, KeyModifiers modifiers) {
    _transport.send(
      KeyPacket(keyCode: usage, modifiers: modifiers, down: true),
    );
    _transport.send(
      KeyPacket(keyCode: usage, modifiers: modifiers, down: false),
    );
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
          TransportState.pairing => KeyboardConnection.connecting,
          TransportState.disconnected => KeyboardConnection.disconnected,
        },
        deviceName: () => endpoint?.label ?? endpoint?.host,
        heldModifiers: connected ? state.heldModifiers : const {},
        macHost: endpoint == null
            ? state.macHost
            : Keycodes.isMac(endpoint.platform),
      ),
    );
  }

  @override
  Future<void> close() async {
    await _link?.cancel();
    return super.close();
  }
}
