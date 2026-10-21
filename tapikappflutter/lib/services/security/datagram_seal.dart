import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/macs/hmac.dart';

class DatagramSeal {
  DatagramSeal(Uint8List key)
    : _mac = HMac(SHA256Digest(), blockLength)..init(KeyParameter(key));

  static const int keyLength = 32;
  static const int counterLength = 4;
  static const int tagLength = 16;
  static const int overhead = counterLength + tagLength;
  static const int maxCounter = 0xFFFFFFFF;
  static const int blockLength = 64;
  static const int digestLength = 32;
  static const int replayWindow = 32;
  static const int _windowMask = 0xFFFFFFFF;

  final HMac _mac;
  final Uint8List _digest = Uint8List(digestLength);
  int _sent = 0;
  int _received = 0;
  int _seen = 0;

  static Uint8List newKey() {
    final random = Random.secure();
    return Uint8List.fromList([
      for (var i = 0; i < keyLength; i++) random.nextInt(256),
    ]);
  }

  static String encodeKey(Uint8List key) => base64Url.encode(key);

  static Uint8List? decodeKey(String text) {
    try {
      final key = base64Url.decode(text);
      return key.length == keyLength ? key : null;
    } on FormatException {
      return null;
    }
  }

  Uint8List? seal(Uint8List frame) {
    if (_sent >= maxCounter) return null;
    _sent += 1;
    final body = frame.length + counterLength;
    final sealed = Uint8List(body + tagLength)
      ..setRange(0, frame.length, frame);
    ByteData.sublistView(sealed).setUint32(frame.length, _sent);
    _sign(sealed, body);
    sealed.setRange(body, sealed.length, _digest);
    return sealed;
  }

  Uint8List? open(Uint8List datagram) {
    final body = datagram.length - tagLength;
    if (body <= counterLength) return null;
    _sign(datagram, body);
    var difference = 0;
    for (var i = 0; i < tagLength; i++) {
      difference |= _digest[i] ^ datagram[body + i];
    }
    if (difference != 0) return null;
    final counter = ByteData.sublistView(datagram)
        .getUint32(body - counterLength);
    if (!_admit(counter)) return null;
    return Uint8List.sublistView(datagram, 0, body - counterLength);
  }

  bool _admit(int counter) {
    if (counter == 0) return false;
    if (counter > _received) {
      final ahead = counter - _received;
      _seen = ahead >= replayWindow ? 1 : ((_seen << ahead) | 1) & _windowMask;
      _received = counter;
      return true;
    }
    final behind = _received - counter;
    if (behind >= replayWindow) return false;
    final bit = 1 << behind;
    if (_seen & bit != 0) return false;
    _seen |= bit;
    return true;
  }

  void _sign(Uint8List data, int length) {
    _mac
      ..reset()
      ..update(data, 0, length)
      ..doFinal(_digest, 0);
  }
}
