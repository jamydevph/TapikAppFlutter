import 'package:equatable/equatable.dart';

enum KeyboardConnection { disconnected, connecting, connected }

enum KeyModifier { command, option, shift, control }

enum KeyboardShortcut { cut, copy, paste, undo, switchApp }

class KeyboardState extends Equatable {
  const KeyboardState({
    this.connection = KeyboardConnection.disconnected,
    this.deviceName,
    this.heldModifiers = const {},
    this.macHost = false,
  });

  final KeyboardConnection connection;
  final String? deviceName;
  final Set<KeyModifier> heldModifiers;
  final bool macHost;

  bool isHeld(KeyModifier modifier) => heldModifiers.contains(modifier);

  KeyboardState copyWith({
    KeyboardConnection? connection,
    String? Function()? deviceName,
    Set<KeyModifier>? heldModifiers,
    bool? macHost,
  }) {
    return KeyboardState(
      connection: connection ?? this.connection,
      deviceName: deviceName == null ? this.deviceName : deviceName(),
      heldModifiers: heldModifiers ?? this.heldModifiers,
      macHost: macHost ?? this.macHost,
    );
  }

  @override
  List<Object?> get props => [connection, deviceName, heldModifiers, macHost];
}
