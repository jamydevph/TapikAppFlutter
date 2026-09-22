import 'package:equatable/equatable.dart';

enum PacketType {
  move(0x01),
  button(0x02),
  scroll(0x03),
  key(0x04),
  text(0x05),
  ping(0x06);

  const PacketType(this.code);

  final int code;

  static PacketType? fromCode(int code) {
    for (final type in values) {
      if (type.code == code) return type;
    }
    return null;
  }
}

enum PointerButton {
  left(0x01),
  right(0x02),
  middle(0x03);

  const PointerButton(this.code);

  final int code;

  static PointerButton? fromCode(int code) {
    for (final button in values) {
      if (button.code == code) return button;
    }
    return null;
  }
}

class KeyModifiers extends Equatable {
  const KeyModifiers({
    this.command = false,
    this.option = false,
    this.shift = false,
    this.control = false,
  });

  static const int commandBit = 0x01;
  static const int optionBit = 0x02;
  static const int shiftBit = 0x04;
  static const int controlBit = 0x08;
  static const KeyModifiers none = KeyModifiers();

  final bool command;
  final bool option;
  final bool shift;
  final bool control;

  factory KeyModifiers.fromMask(int mask) {
    return KeyModifiers(
      command: mask & commandBit != 0,
      option: mask & optionBit != 0,
      shift: mask & shiftBit != 0,
      control: mask & controlBit != 0,
    );
  }

  int get mask {
    var mask = 0;
    if (command) mask |= commandBit;
    if (option) mask |= optionBit;
    if (shift) mask |= shiftBit;
    if (control) mask |= controlBit;
    return mask;
  }

  @override
  List<Object?> get props => [command, option, shift, control];
}

sealed class Packet extends Equatable {
  const Packet();

  static const int minDelta = -32768;
  static const int maxDelta = 32767;
  static const int minKeyCode = 0;
  static const int maxKeyCode = 65535;
  static const int maxTextBytes = 65535;

  PacketType get type;

  @override
  List<Object?> get props => [type];
}

class MovePacket extends Packet {
  const MovePacket({required this.dx, required this.dy});

  final int dx;
  final int dy;

  @override
  PacketType get type => PacketType.move;

  @override
  List<Object?> get props => [type, dx, dy];
}

class ButtonPacket extends Packet {
  const ButtonPacket({required this.button, required this.down});

  final PointerButton button;
  final bool down;

  @override
  PacketType get type => PacketType.button;

  @override
  List<Object?> get props => [type, button, down];
}

class ScrollPacket extends Packet {
  const ScrollPacket({required this.dx, required this.dy});

  final int dx;
  final int dy;

  @override
  PacketType get type => PacketType.scroll;

  @override
  List<Object?> get props => [type, dx, dy];
}

class KeyPacket extends Packet {
  const KeyPacket({
    required this.keyCode,
    this.modifiers = KeyModifiers.none,
    required this.down,
  });

  final int keyCode;
  final KeyModifiers modifiers;
  final bool down;

  @override
  PacketType get type => PacketType.key;

  @override
  List<Object?> get props => [type, keyCode, modifiers, down];
}

class TextPacket extends Packet {
  const TextPacket(this.text);

  final String text;

  @override
  PacketType get type => PacketType.text;

  @override
  List<Object?> get props => [type, text];
}

class PingPacket extends Packet {
  const PingPacket();

  @override
  PacketType get type => PacketType.ping;
}
