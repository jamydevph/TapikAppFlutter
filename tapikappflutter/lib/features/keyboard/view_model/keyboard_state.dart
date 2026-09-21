import 'package:equatable/equatable.dart';

enum KeyboardConnection { disconnected, connecting, connected }

enum KeyModifier { command, option, shift, control }

class KeyboardState extends Equatable {
  const KeyboardState({
    this.connection = KeyboardConnection.disconnected,
    this.deviceName,
    this.heldModifiers = const {},
  });

  final KeyboardConnection connection;
  final String? deviceName;
  final Set<KeyModifier> heldModifiers;

  bool isHeld(KeyModifier modifier) => heldModifiers.contains(modifier);

  KeyboardState copyWith({
    KeyboardConnection? connection,
    String? deviceName,
    Set<KeyModifier>? heldModifiers,
  }) {
    return KeyboardState(
      connection: connection ?? this.connection,
      deviceName: deviceName ?? this.deviceName,
      heldModifiers: heldModifiers ?? this.heldModifiers,
    );
  }

  @override
  List<Object?> get props => [connection, deviceName, heldModifiers];
}
