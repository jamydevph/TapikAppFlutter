import 'packet.dart';

class Keycodes {
  const Keycodes._();

  static const int usageA = 0x04;
  static const int usageReturn = 0x28;
  static const int usageEscape = 0x29;
  static const int usageBackspace = 0x2A;
  static const int usageTab = 0x2B;
  static const int usageSpace = 0x2C;
  static const int usageLeftControl = 0xE0;
  static const int usageLeftShift = 0xE1;
  static const int usageLeftOption = 0xE2;
  static const int usageLeftCommand = 0xE3;
  static const int usageRightGui = 0xE7;
  static const int usagePeriod = 0x37;
  static const int usageArrowRight = 0x4F;
  static const int usageArrowLeft = 0x50;
  static const int usageArrowDown = 0x51;
  static const int usageArrowUp = 0x52;

  static const Map<int, int> _macosVirtualKeys = <int, int>{
    0x04: 0, // a
    0x05: 11, // b
    0x06: 8, // c
    0x07: 2, // d
    0x08: 14, // e
    0x09: 3, // f
    0x0A: 5, // g
    0x0B: 4, // h
    0x0C: 34, // i
    0x0D: 38, // j
    0x0E: 40, // k
    0x0F: 37, // l
    0x10: 46, // m
    0x11: 45, // n
    0x12: 31, // o
    0x13: 35, // p
    0x14: 12, // q
    0x15: 15, // r
    0x16: 1, // s
    0x17: 17, // t
    0x18: 32, // u
    0x19: 9, // v
    0x1A: 13, // w
    0x1B: 7, // x
    0x1C: 16, // y
    0x1D: 6, // z
    0x1E: 18, // 1
    0x1F: 19, // 2
    0x20: 20, // 3
    0x21: 21, // 4
    0x22: 23, // 5
    0x23: 22, // 6
    0x24: 26, // 7
    0x25: 28, // 8
    0x26: 25, // 9
    0x27: 29, // 0
    0x28: 36, // return
    0x29: 53, // escape
    0x2A: 51, // backspace
    0x2B: 48, // tab
    0x2C: 49, // space
    0x2D: 27, // minus
    0x2E: 24, // equal
    0x2F: 33, // leftBracket
    0x30: 30, // rightBracket
    0x31: 42, // backslash
    0x33: 41, // semicolon
    0x34: 39, // quote
    0x35: 50, // grave
    0x36: 43, // comma
    0x37: 47, // period
    0x38: 44, // slash
    0x39: 57, // capsLock
    0x3A: 122, // f1
    0x3B: 120, // f2
    0x3C: 99, // f3
    0x3D: 118, // f4
    0x3E: 96, // f5
    0x3F: 97, // f6
    0x40: 98, // f7
    0x41: 100, // f8
    0x42: 101, // f9
    0x43: 109, // f10
    0x44: 103, // f11
    0x45: 111, // f12
    0x4A: 115, // home
    0x4B: 116, // pageUp
    0x4C: 117, // forwardDelete
    0x4D: 119, // end
    0x4E: 121, // pageDown
    0x4F: 124, // right
    0x50: 123, // left
    0x51: 125, // down
    0x52: 126, // up
    0xE0: 59, // leftControl
    0xE1: 56, // leftShift
    0xE2: 58, // leftOption
    0xE3: 55, // leftCommand
    0xE4: 62, // rightControl
    0xE5: 60, // rightShift
    0xE6: 61, // rightOption
    0xE7: 54, // rightCommand
  };

  static const Map<int, int> _windowsVirtualKeys = <int, int>{
    0x04: 0x41, // a
    0x05: 0x42, // b
    0x06: 0x43, // c
    0x07: 0x44, // d
    0x08: 0x45, // e
    0x09: 0x46, // f
    0x0A: 0x47, // g
    0x0B: 0x48, // h
    0x0C: 0x49, // i
    0x0D: 0x4A, // j
    0x0E: 0x4B, // k
    0x0F: 0x4C, // l
    0x10: 0x4D, // m
    0x11: 0x4E, // n
    0x12: 0x4F, // o
    0x13: 0x50, // p
    0x14: 0x51, // q
    0x15: 0x52, // r
    0x16: 0x53, // s
    0x17: 0x54, // t
    0x18: 0x55, // u
    0x19: 0x56, // v
    0x1A: 0x57, // w
    0x1B: 0x58, // x
    0x1C: 0x59, // y
    0x1D: 0x5A, // z
    0x1E: 0x31, // 1
    0x1F: 0x32, // 2
    0x20: 0x33, // 3
    0x21: 0x34, // 4
    0x22: 0x35, // 5
    0x23: 0x36, // 6
    0x24: 0x37, // 7
    0x25: 0x38, // 8
    0x26: 0x39, // 9
    0x27: 0x30, // 0
    0x28: 0x0D, // return
    0x29: 0x1B, // escape
    0x2A: 0x08, // backspace
    0x2B: 0x09, // tab
    0x2C: 0x20, // space
    0x2D: 0xBD, // minus
    0x2E: 0xBB, // equal
    0x2F: 0xDB, // leftBracket
    0x30: 0xDD, // rightBracket
    0x31: 0xDC, // backslash
    0x33: 0xBA, // semicolon
    0x34: 0xDE, // quote
    0x35: 0xC0, // grave
    0x36: 0xBC, // comma
    0x37: 0xBE, // period
    0x38: 0xBF, // slash
    0x39: 0x14, // capsLock
    0x3A: 0x70, // f1
    0x3B: 0x71, // f2
    0x3C: 0x72, // f3
    0x3D: 0x73, // f4
    0x3E: 0x74, // f5
    0x3F: 0x75, // f6
    0x40: 0x76, // f7
    0x41: 0x77, // f8
    0x42: 0x78, // f9
    0x43: 0x79, // f10
    0x44: 0x7A, // f11
    0x45: 0x7B, // f12
    0x4A: 0x24, // home
    0x4B: 0x21, // pageUp
    0x4C: 0x2E, // forwardDelete
    0x4D: 0x23, // end
    0x4E: 0x22, // pageDown
    0x4F: 0x27, // right
    0x50: 0x25, // left
    0x51: 0x28, // down
    0x52: 0x26, // up
    0xE0: 0xA2, // leftControl
    0xE1: 0xA0, // leftShift
    0xE2: 0xA4, // leftOption
    0xE3: 0x5B, // leftCommand
    0xE4: 0xA3, // rightControl
    0xE5: 0xA1, // rightShift
    0xE6: 0xA5, // rightOption
    0xE7: 0x5C, // rightCommand
  };

  static int? macos(int usage) => _macosVirtualKeys[usage];

  static int? windows(int usage) => _windowsVirtualKeys[usage];

  static int? letter(String character) {
    if (character.length != 1) return null;
    final code = character.toLowerCase().codeUnitAt(0);
    if (code < 0x61 || code > 0x7A) return null;
    return usageA + (code - 0x61);
  }

  static KeyModifiers primaryModifier(String? platform) {
    return platform != null && platform.toLowerCase() == 'macos'
        ? const KeyModifiers(command: true)
        : const KeyModifiers(control: true);
  }

  static bool isModifier(int usage) =>
      usage >= usageLeftControl && usage <= usageRightGui;

  static Iterable<int> get macosUsages => _macosVirtualKeys.keys;

  static Iterable<int> get windowsUsages => _windowsVirtualKeys.keys;
}
