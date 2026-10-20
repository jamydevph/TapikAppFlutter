class LaptopName {
  const LaptopName._();

  static const int maxLength = 40;
  static const String fallback = 'Laptop';

  static final RegExp _unsafeCharacters = RegExp(
    r'[\p{Cc}\p{Zl}\p{Zp}\p{Bidi_Control}]+',
    unicode: true,
  );
  static final String _maskedCharacters =
      '0-9A-Za-z${String.fromCharCodes(_hexLookalikes.keys)}'
      '${String.fromCharCode(0xFF10)}-${String.fromCharCode(0xFF19)}'
      '${String.fromCharCode(0xFF21)}-${String.fromCharCode(0xFF26)}'
      '${String.fromCharCode(0xFF41)}-${String.fromCharCode(0xFF46)}'
      r'\u{1D400}-\u{1D6A3}\u{1D7CE}-\u{1D7FF}\u{1FBF0}-\u{1FBF9}';
  static final RegExp _ignorableNearText = RegExp(
    '(?<=[$_maskedCharacters])'
    r'\p{Default_Ignorable_Code_Point}+'
    '|'
    r'\p{Default_Ignorable_Code_Point}+'
    '(?=[$_maskedCharacters])',
    unicode: true,
  );
  static final RegExp _idLike = RegExp(
    r'[0-9A-Fa-f]{4}(?:[^0-9A-Za-z]+[0-9A-Fa-f]{4})+'
    r'|(?:[0-9A-Fa-f]{2}[^0-9A-Za-z]+){3,}[0-9A-Fa-f]{2}'
    r'|[0-9A-Fa-f]{8,}',
  );
  static final RegExp _spaces = RegExp(r'\s+');
  static const Map<int, int> _hexLookalikes = {
    0x0391: 0x41,
    0x0392: 0x42,
    0x0395: 0x45,
    0x0399: 0x31,
    0x039F: 0x30,
    0x0406: 0x31,
    0x0410: 0x41,
    0x0412: 0x42,
    0x0415: 0x45,
    0x0421: 0x43,
    0x0430: 0x61,
    0x0435: 0x65,
    0x041E: 0x30,
    0x0441: 0x63,
    0x0501: 0x64,
    0x2102: 0x43,
    0x212C: 0x42,
    0x212D: 0x43,
    0x212F: 0x65,
    0x2130: 0x45,
    0x2131: 0x46,
    0x2145: 0x44,
    0x2146: 0x64,
    0x2147: 0x65,
    0x2160: 0x31,
    0x216D: 0x43,
    0x216E: 0x44,
    0x217D: 0x63,
    0x217E: 0x64,
    0x4F: 0x30,
    0x49: 0x31,
  };
  static const Map<int, int> _digitLookalikes = {0x6C: 0x31, 0x6F: 0x30};
  static final RegExp _digit = RegExp(r'\p{Nd}', unicode: true);
  static final RegExp _mark = RegExp(r'^\p{Mn}$', unicode: true);
  static final RegExp _lower = RegExp(r'^\p{Ll}$', unicode: true);

  static String? plain(String name) {
    final visible = name
        .replaceAll(_unsafeCharacters, ' ')
        .replaceAll(_ignorableNearText, '');
    final folded = StringBuffer();
    final origin = <int>[];
    var offset = 0;
    final runes = visible.runes.toList();
    for (var i = 0; i < runes.length; i++) {
      final rune = runes[i];
      final width = rune > 0xFFFF ? 2 : 1;
      if (i > 0 && _isMark(rune)) {
        offset += width;
        continue;
      }
      final text = String.fromCharCode(_foldAt(runes, i));
      for (var unit = 0; unit < text.length; unit++) {
        origin.add(offset);
      }
      folded.write(text);
      offset += width;
    }
    origin.add(offset);
    final masked = StringBuffer();
    var start = 0;
    for (final match in _idLike.allMatches(folded.toString())) {
      final source = visible.substring(origin[match.start], origin[match.end]);
      if (!_digit.hasMatch(source)) continue;
      masked
        ..write(visible.substring(start, origin[match.start]))
        ..write('…');
      start = origin[match.end];
    }
    masked.write(visible.substring(start));
    final flat = masked.toString().replaceAll(_spaces, ' ').trim();
    if (flat.isEmpty) return null;
    final shownRunes = flat.runes.toList();
    if (shownRunes.length <= maxLength) return flat;
    final kept = String.fromCharCodes(shownRunes.take(maxLength - 1));
    return '${kept.trimRight()}…';
  }

  static String shown(String name) => plain(name) ?? fallback;

  static bool _isMark(int rune) => _mark.hasMatch(String.fromCharCode(rune));

  static bool _isLower(List<int> runes, int i) =>
      i >= 0 &&
      i < runes.length &&
      _lower.hasMatch(String.fromCharCode(runes[i]));

  static int _foldAt(List<int> runes, int i) {
    final rune = runes[i];
    final digit = _digitLookalikes[rune];
    if (digit != null && !_isLower(runes, i - 1) && !_isLower(runes, i + 1)) {
      return digit;
    }
    return _fold(rune);
  }

  static int _fold(int rune) {
    if (rune >= 0xFF10 && rune <= 0xFF19) return rune - 0xFF10 + 0x30;
    if (rune >= 0xFF21 && rune <= 0xFF26) return rune - 0xFF21 + 0x41;
    if (rune >= 0xFF41 && rune <= 0xFF46) return rune - 0xFF41 + 0x61;
    if (rune >= 0x1D7CE && rune <= 0x1D7FF) return 0x30 + (rune - 0x1D7CE) % 10;
    if (rune >= 0x1FBF0 && rune <= 0x1FBF9) return 0x30 + rune - 0x1FBF0;
    if (rune >= 0x1D400 && rune <= 0x1D6A3) {
      final letter = (rune - 0x1D400) % 52;
      return letter < 26 ? 0x41 + letter : 0x61 + letter - 26;
    }
    return _hexLookalikes[rune] ?? rune;
  }
}
