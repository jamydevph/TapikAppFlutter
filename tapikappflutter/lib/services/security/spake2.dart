import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256r1.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/hkdf.dart';
import 'package:pointycastle/macs/hmac.dart';

import '../../core/resources/constants.dart';

class Spake2Session {
  Spake2Session._(this.transcript, this._confirmA, this._confirmB);

  final Uint8List transcript;
  final Uint8List _confirmA;
  final Uint8List _confirmB;

  Uint8List get confirmA => Uint8List.fromList(_confirmA);

  Uint8List get confirmB => Uint8List.fromList(_confirmB);

  bool acceptsA(List<int> tag) => Spake2.sameBytes(tag, _confirmA);

  bool acceptsB(List<int> tag) => Spake2.sameBytes(tag, _confirmB);
}

class Spake2 {
  Spake2._(
    this.isA,
    this._w,
    this._scalar,
    this._idA,
    this._idB,
    this._aad,
    this._random,
  );

  factory Spake2.phone({
    required String code,
    required String phoneId,
    required String laptopFingerprint,
    Random? random,
  }) => Spake2._forPairing(
    isA: true,
    code: code,
    phoneId: phoneId,
    laptopFingerprint: laptopFingerprint,
    random: random,
  );

  factory Spake2.laptop({
    required String code,
    required String phoneId,
    required String laptopFingerprint,
    Random? random,
  }) => Spake2._forPairing(
    isA: false,
    code: code,
    phoneId: phoneId,
    laptopFingerprint: laptopFingerprint,
    random: random,
  );

  factory Spake2._forPairing({
    required bool isA,
    required String code,
    required String phoneId,
    required String laptopFingerprint,
    Random? random,
  }) {
    final source = random ?? Random.secure();
    return Spake2._(
      isA,
      passwordScalar(code, laptopFingerprint),
      _randomScalar(source),
      _utf8('$phoneIdentity$phoneId'),
      _utf8('$laptopIdentity$laptopFingerprint'),
      _utf8('$aadPrefix${TapikappConstants.protocolVersion}'),
      source,
    );
  }

  factory Spake2.withScalars({
    required bool isA,
    required BigInt w,
    required BigInt scalar,
    required List<int> idA,
    required List<int> idB,
    List<int> aad = const [],
  }) => Spake2._(
    isA,
    w,
    scalar,
    Uint8List.fromList(idA),
    Uint8List.fromList(idB),
    Uint8List.fromList(aad),
    Random.secure(),
  );

  static const String phoneIdentity = 'tapikapp-phone:';
  static const String laptopIdentity = 'tapikapp-laptop:';
  static const String aadPrefix = 'tapikapp v';
  static const String passwordInfo = 'tapikapp-w';
  static const String confirmationInfo = 'ConfirmationKeys';
  static const int shareLength = 33;
  static const int confirmLength = 32;
  static const int scalarLength = 32;
  static const int passwordBytes = 40;
  static const int randomBytes = 48;
  static const int blindBits = 64;
  static const int keyLength = 16;

  static final ECDomainParameters _group = ECCurve_secp256r1();
  static final BigInt _order = _group.n;
  static final BigInt _fieldPrime = BigInt.parse(
    'ffffffff00000001000000000000000000000000ffffffffffffffffffffffff',
    radix: 16,
  );
  static final ECPoint _m = _group.curve.decodePoint(
    _hex('02886e2f97ace46e55ba9dd7242579f2993b64e16ef3dcab95afd497333d8fa12f'),
  )!;
  static final ECPoint _n = _group.curve.decodePoint(
    _hex('03d8bbd6c639c62937b04d997f38c3770719c629d7014d49a24b4f98baa1292b49'),
  )!;

  final bool isA;
  final BigInt _w;
  final BigInt _scalar;
  final Uint8List _idA;
  final Uint8List _idB;
  final Uint8List _aad;
  final Random _random;

  late final ECPoint _share = ((_group.G * _scalar)! + _blinded(_own, _w))!;

  ECPoint get _own => isA ? _m : _n;

  ECPoint get _other => isA ? _n : _m;

  Uint8List get share => _share.getEncoded(true);

  Uint8List get uncompressedShare => _share.getEncoded(false);

  Spake2Session? finish(List<int> peerShare) {
    final peer = decodeShare(peerShare);
    if (peer == null) return null;
    final unmasked = peer - _blinded(_other, _w)!;
    if (unmasked == null || unmasked.isInfinity) return null;
    final shared = unmasked * _scalar;
    if (shared == null || shared.isInfinity) return null;
    final ownShare = _share.getEncoded(false);
    final otherShare = peer.getEncoded(false);
    final transcript = _transcript([
      _idA,
      _idB,
      isA ? ownShare : otherShare,
      isA ? otherShare : ownShare,
      shared.getEncoded(false),
      _fixed(_w, scalarLength),
    ]);
    final digest = SHA256Digest().process(transcript);
    final ka = Uint8List.sublistView(digest, keyLength);
    final confirmation = HKDFKeyDerivator(SHA256Digest())
      ..init(
        HkdfParameters(
          ka,
          keyLength * 2,
          null,
          Uint8List.fromList([..._utf8(confirmationInfo), ..._aad]),
        ),
      );
    final keys = confirmation.process(Uint8List(0));
    return Spake2Session._(
      transcript,
      _mac(Uint8List.sublistView(keys, 0, keyLength), transcript),
      _mac(Uint8List.sublistView(keys, keyLength), transcript),
    );
  }

  ECPoint? _blinded(ECPoint point, BigInt scalar) {
    var blind = BigInt.zero;
    for (var i = 0; i < blindBits ~/ 16; i++) {
      blind = (blind << 16) | BigInt.from(_random.nextInt(1 << 16));
    }
    return point * (scalar + blind * _order);
  }

  static ECPoint? decodeShare(List<int> bytes) {
    if (bytes.length != shareLength) return null;
    if (bytes.first != 0x02 && bytes.first != 0x03) return null;
    if (_toBigInt(bytes.sublist(1)) >= _fieldPrime) return null;
    try {
      final point = _group.curve.decodePoint(bytes);
      if (point == null || point.isInfinity) return null;
      return point;
    } on ArgumentError {
      return null;
    }
  }

  static BigInt passwordScalar(String code, String laptopFingerprint) {
    final digits = code.replaceAll(RegExp(r'[^0-9]'), '');
    final derivator = HKDFKeyDerivator(SHA256Digest())
      ..init(
        HkdfParameters(
          _utf8(digits),
          passwordBytes,
          _utf8(laptopFingerprint),
          _utf8(passwordInfo),
        ),
      );
    return _toBigInt(derivator.process(Uint8List(0))) % _order;
  }

  static String encode(List<int> bytes) => base64Url.encode(bytes);

  static Uint8List? decode(String text, int length) {
    try {
      final bytes = base64Url.decode(text);
      return bytes.length == length ? bytes : null;
    } on FormatException {
      return null;
    }
  }

  static bool sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }

  static BigInt _randomScalar(Random random) {
    final bytes = [for (var i = 0; i < randomBytes; i++) random.nextInt(256)];
    return _toBigInt(bytes) % (_order - BigInt.one) + BigInt.one;
  }

  static Uint8List _mac(Uint8List key, Uint8List message) {
    final mac = HMac(SHA256Digest(), 64)..init(KeyParameter(key));
    return mac.process(message);
  }

  static Uint8List _transcript(List<Uint8List> fields) {
    final builder = BytesBuilder(copy: false);
    for (final field in fields) {
      final length = ByteData(8)..setUint32(0, field.length, Endian.little);
      builder
        ..add(length.buffer.asUint8List())
        ..add(field);
    }
    return builder.toBytes();
  }

  static Uint8List _fixed(BigInt value, int length) {
    final out = Uint8List(length);
    var rest = value;
    for (var i = length - 1; i >= 0; i--) {
      out[i] = (rest & BigInt.from(0xff)).toInt();
      rest = rest >> 8;
    }
    return out;
  }

  static BigInt _toBigInt(List<int> bytes) {
    var value = BigInt.zero;
    for (final byte in bytes) {
      value = (value << 8) | BigInt.from(byte);
    }
    return value;
  }

  static Uint8List _utf8(String text) => Uint8List.fromList(utf8.encode(text));

  static Uint8List _hex(String text) => Uint8List.fromList([
    for (var i = 0; i < text.length; i += 2)
      int.parse(text.substring(i, i + 2), radix: 16),
  ]);
}
