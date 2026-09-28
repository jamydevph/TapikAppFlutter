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

  static int? macos(int usage) => _macosVirtualKeys[usage];

  static bool isModifier(int usage) =>
      usage >= usageLeftControl && usage <= usageRightGui;

  static Iterable<int> get macosUsages => _macosVirtualKeys.keys;
}
