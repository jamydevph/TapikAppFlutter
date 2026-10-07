import 'dart:typed_data';

import '../../core/protocol/keycodes.dart';
import '../../core/protocol/packet.dart';

class HidReport {
  const HidReport(this.id, this.data);

  final int id;
  final Uint8List data;

  @override
  String toString() => 'HidReport($id, ${data.toList()})';
}

class HidReports {
  HidReports({this.pixelsPerDetent = defaultPixelsPerDetent});

  static const int keyboardId = 1;
  static const int mouseId = 2;
  static const int defaultPixelsPerDetent = 40;
  static const int axisLimit = 127;

  static const int _control = 0x01;
  static const int _shift = 0x02;
  static const int _option = 0x04;
  static const int _command = 0x08;

  static const List<int> descriptor = <int>[
    0x05, 0x01, 0x09, 0x06, 0xA1, 0x01, 0x85, keyboardId, //
    0x05, 0x07, 0x19, 0xE0, 0x29, 0xE7, 0x15, 0x00, 0x25, 0x01, //
    0x75, 0x01, 0x95, 0x08, 0x81, 0x02, //
    0x95, 0x01, 0x75, 0x08, 0x81, 0x01, //
    0x95, 0x05, 0x75, 0x01, 0x05, 0x08, 0x19, 0x01, 0x29, 0x05, 0x91, 0x02, //
    0x95, 0x01, 0x75, 0x03, 0x91, 0x01, //
    0x95, 0x06, 0x75, 0x08, 0x15, 0x00, 0x25, 0x65, //
    0x05, 0x07, 0x19, 0x00, 0x29, 0x65, 0x81, 0x00, //
    0xC0, //
    0x05, 0x01, 0x09, 0x02, 0xA1, 0x01, 0x85, mouseId, //
    0x09, 0x01, 0xA1, 0x00, //
    0x05, 0x09, 0x19, 0x01, 0x29, 0x03, 0x15, 0x00, 0x25, 0x01, //
    0x95, 0x03, 0x75, 0x01, 0x81, 0x02, //
    0x95, 0x01, 0x75, 0x05, 0x81, 0x01, //
    0x05, 0x01, 0x09, 0x30, 0x09, 0x31, 0x09, 0x38, //
    0x15, 0x81, 0x25, 0x7F, 0x75, 0x08, 0x95, 0x03, 0x81, 0x06, //
    0x05, 0x0C, 0x0A, 0x38, 0x02, //
    0x15, 0x81, 0x25, 0x7F, 0x75, 0x08, 0x95, 0x01, 0x81, 0x06, //
    0xC0, 0xC0, //
  ];

  static const Map<String, (int, bool)> _shiftedSymbols = {
    '!': (0x1E, true), '@': (0x1F, true), '#': (0x20, true), //
    r'$': (0x21, true), '%': (0x22, true), '^': (0x23, true), //
    '&': (0x24, true), '*': (0x25, true), '(': (0x26, true), //
    ')': (0x27, true), '-': (0x2D, false), '_': (0x2D, true), //
    '=': (0x2E, false), '+': (0x2E, true), '[': (0x2F, false), //
    '{': (0x2F, true), ']': (0x30, false), '}': (0x30, true), //
    r'\': (0x31, false), '|': (0x31, true), ';': (0x33, false), //
    ':': (0x33, true), "'": (0x34, false), '"': (0x34, true), //
    '`': (0x35, false), '~': (0x35, true), ',': (0x36, false), //
    '<': (0x36, true), '.': (0x37, false), '>': (0x37, true), //
    '/': (0x38, false), '?': (0x38, true), ' ': (0x2C, false), //
    '\n': (0x28, false), '\t': (0x2B, false), //
  };

  final int pixelsPerDetent;
  int _buttons = 0;
  int _wheelCarry = 0;
  int _panCarry = 0;
  int skippedCharacters = 0;

  int get heldButtons => _buttons;

  List<HidReport> encode(Packet packet) {
    switch (packet) {
      case MovePacket(:final dx, :final dy):
        return _motion(dx, dy);
      case ButtonPacket(:final button, :final down):
        final bit = buttonBit(button);
        _buttons = down ? _buttons | bit : _buttons & ~bit;
        return [_mouse(0, 0, 0, 0)];
      case ScrollPacket(:final dx, :final dy):
        return _scroll(dx, dy);
      case KeyPacket(:final keyCode, :final modifiers, :final down):
        return [_key(keyCode, modifiers, down)];
      case TextPacket(:final text):
        return _text(text);
      case PingPacket():
      case PairPacket():
        return const <HidReport>[];
    }
  }

  List<HidReport> releaseAll() {
    _buttons = 0;
    _wheelCarry = 0;
    _panCarry = 0;
    return [_keyboard(0, 0), _mouse(0, 0, 0, 0)];
  }

  static int buttonBit(PointerButton button) {
    return switch (button) {
      PointerButton.left => 1 << 0,
      PointerButton.right => 1 << 1,
      PointerButton.middle => 1 << 2,
    };
  }

  static int modifierByte(KeyModifiers modifiers) {
    var byte = 0;
    if (modifiers.control) byte |= _control;
    if (modifiers.shift) byte |= _shift;
    if (modifiers.option) byte |= _option;
    if (modifiers.command) byte |= _command;
    return byte;
  }

  static (int, bool)? usageFor(String character) {
    final letter = Keycodes.letter(character.toLowerCase());
    if (letter != null) {
      return (letter, character != character.toLowerCase());
    }
    final code = character.codeUnitAt(0);
    if (character.length == 1 && code >= 0x31 && code <= 0x39) {
      return (0x1E + code - 0x31, false);
    }
    if (character == '0') return (0x27, false);
    return _shiftedSymbols[character];
  }

  List<HidReport> _motion(int dx, int dy) {
    final reports = <HidReport>[];
    var x = dx;
    var y = dy;
    do {
      final stepX = x.clamp(-axisLimit, axisLimit);
      final stepY = y.clamp(-axisLimit, axisLimit);
      reports.add(_mouse(stepX, stepY, 0, 0));
      x -= stepX;
      y -= stepY;
    } while (x != 0 || y != 0);
    return reports;
  }

  List<HidReport> _scroll(int dx, int dy) {
    _wheelCarry += dy;
    _panCarry += dx;
    final wheel = _wheelCarry ~/ pixelsPerDetent;
    final pan = _panCarry ~/ pixelsPerDetent;
    _wheelCarry -= wheel * pixelsPerDetent;
    _panCarry -= pan * pixelsPerDetent;
    if (wheel == 0 && pan == 0) return const <HidReport>[];
    final reports = <HidReport>[];
    var w = wheel;
    var p = pan;
    do {
      final stepW = w.clamp(-axisLimit, axisLimit);
      final stepP = p.clamp(-axisLimit, axisLimit);
      reports.add(_mouse(0, 0, stepW, stepP));
      w -= stepW;
      p -= stepP;
    } while (w != 0 || p != 0);
    return reports;
  }

  HidReport _key(int keyCode, KeyModifiers modifiers, bool down) {
    if (!down) return _keyboard(0, 0);
    if (Keycodes.isModifier(keyCode)) {
      return _keyboard(modifierByte(modifiers) | _modifierBit(keyCode), 0);
    }
    return _keyboard(modifierByte(modifiers), keyCode);
  }

  List<HidReport> _text(String text) {
    final reports = <HidReport>[];
    for (final rune in text.runes) {
      final character = String.fromCharCode(rune);
      final usage = usageFor(character);
      if (usage == null) {
        skippedCharacters += 1;
        continue;
      }
      reports.add(_keyboard(usage.$2 ? _shift : 0, usage.$1));
      reports.add(_keyboard(0, 0));
    }
    return reports;
  }

  static int _modifierBit(int usage) =>
      1 << (usage - Keycodes.usageLeftControl);

  HidReport _keyboard(int modifiers, int usage) {
    final data = Uint8List(8)
      ..[0] = modifiers
      ..[2] = usage;
    return HidReport(keyboardId, data);
  }

  HidReport _mouse(int dx, int dy, int wheel, int pan) {
    final data = Uint8List(5)
      ..[0] = _buttons
      ..[1] = dx & 0xFF
      ..[2] = dy & 0xFF
      ..[3] = wheel & 0xFF
      ..[4] = pan & 0xFF;
    return HidReport(mouseId, data);
  }
}
