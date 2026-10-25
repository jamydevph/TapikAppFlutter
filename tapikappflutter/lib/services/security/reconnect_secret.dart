import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';

class ReconnectSecret {
  const ReconnectSecret._();

  static const int byteLength = 32;
  static const int idByteLength = 16;
  static const int maxTokenLength = 64;

  static final RegExp _token = RegExp('^[A-Za-z0-9_-]{1,$maxTokenLength}\$');

  static String generate([Random? random]) =>
      _encode(_randomBytes(byteLength, random));

  static String newClientId([Random? random]) =>
      _encode(_randomBytes(idByteLength, random));

  static bool isToken(String text) => _token.hasMatch(text);

  static String hash(String secret) {
    final digest = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(secret)),
    );
    final buffer = StringBuffer();
    for (final byte in digest) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  static bool matches(String secret, String expectedHash) {
    final actual = hash(secret);
    if (actual.length != expectedHash.length) return false;
    var difference = 0;
    for (var i = 0; i < actual.length; i++) {
      difference |= actual.codeUnitAt(i) ^ expectedHash.codeUnitAt(i);
    }
    return difference == 0;
  }

  static Uint8List _randomBytes(int length, Random? random) {
    final source = random ?? Random.secure();
    return Uint8List.fromList([
      for (var i = 0; i < length; i++) source.nextInt(256),
    ]);
  }

  static String _encode(Uint8List bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');
}
