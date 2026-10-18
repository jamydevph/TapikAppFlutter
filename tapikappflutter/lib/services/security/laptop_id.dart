class LaptopId {
  const LaptopId._();

  static const int bytes = 8;
  static const int groupLength = 4;

  static final RegExp _hex = RegExp(r'^[0-9a-fA-F]+$');

  static String? of(String? fingerprint) {
    const digits = bytes * 2;
    if (fingerprint == null || fingerprint.length < digits) return null;
    if (!_hex.hasMatch(fingerprint)) return null;
    final head = fingerprint.substring(0, digits).toUpperCase();
    return [
      for (var i = 0; i < digits; i += groupLength)
        head.substring(i, i + groupLength),
    ].join(' ');
  }
}
