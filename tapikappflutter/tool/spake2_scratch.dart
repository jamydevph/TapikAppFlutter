import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/ecc/curves/secp256r1.dart';
import 'package:tapikappflutter/services/security/spake2.dart';

final _group = ECCurve_secp256r1();
const _fieldPrime =
    'ffffffff00000001000000000000000000000000ffffffffffffffffffffffff';
const _nPoint =
    '03d8bbd6c639c62937b04d997f38c3770719c629d7014d49a24b4f98baa1292b49';
const _fingerprint = 'AB:CD:EF:01';
const _phoneId = 'phone-id-for-checks';

const _vectors = [
  _Vector(
    a: 'server',
    b: 'client',
    w: '2ee57912099d31560b3a44b1184b9b4866e904c49d12ac5042c97dca461b1a5f',
    x: '43dd0fd7215bdcb482879fca3220c6a968e66d70b1356cac18bb26c84a78d729',
    y: 'dcb60106f276b02606d8ef0a328c02e4b629f84f89786af5befb0bc75b6e66be',
    pA: '04a56fa807caaa53a4d28dbb9853b9815c61a411118a6fe516a8798434751470f9010153ac33d0d5f2047ffdb1a3e42c9b4e6be662766e1eeb4116988ede5f912c',
    pB: '0406557e482bd03097ad0cbaa5df82115460d951e3451962f1eaf4367a420676d09857ccbc522686c83d1852abfa8ed6e4a1155cf8f1543ceca528afb591a1e0b7',
    k: '0412af7e89717850671913e6b469ace67bd90a4df8ce45c2af19010175e37eed69f75897996d539356e2fa6a406d528501f907e04d97515fbe83db277b715d3325',
    tt: '06000000000000007365727665720600000000000000636c69656e74410000000000000004a56fa807caaa53a4d28dbb9853b9815c61a411118a6fe516a8798434751470f9010153ac33d0d5f2047ffdb1a3e42c9b4e6be662766e1eeb4116988ede5f912c41000000000000000406557e482bd03097ad0cbaa5df82115460d951e3451962f1eaf4367a420676d09857ccbc522686c83d1852abfa8ed6e4a1155cf8f1543ceca528afb591a1e0b741000000000000000412af7e89717850671913e6b469ace67bd90a4df8ce45c2af19010175e37eed69f75897996d539356e2fa6a406d528501f907e04d97515fbe83db277b715d332520000000000000002ee57912099d31560b3a44b1184b9b4866e904c49d12ac5042c97dca461b1a5f',
    confirmA:
        '58ad4aa88e0b60d5061eb6b5dd93e80d9c4f00d127c65b3b35b1b5281fee38f0',
    confirmB:
        'd3e2e547f1ae04f2dbdbf0fc4b79f8ecff2dff314b5d32fe9fcef2fb26dc459b',
  ),
  _Vector(
    a: '',
    b: 'client',
    w: '0548d8729f730589e579b0475a582c1608138ddf7054b73b5381c7e883e2efae',
    x: '403abbe3b1b4b9ba17e3032849759d723939a27a27b9d921c500edde18ed654b',
    y: '903023b6598908936ea7c929bd761af6039577a9c3f9581064187c3049d87065',
    pA: '04a897b769e681c62ac1c2357319a3d363f610839c4477720d24cbe32f5fd85f44fb92ba966578c1b712be6962498834078262caa5b441ecfa9d4a9485720e918a',
    pB: '04e0f816fd1c35e22065d5556215c097e799390d16661c386e0ecc84593974a61b881a8c82327687d0501862970c64565560cb5671f696048050ca66ca5f8cc7fc',
    k: '048f83ec9f6e4f87cc6f9dc740bdc2769725f923364f01c84148c049a39a735ebda82eac03e00112fd6a5710682767cff5361f7e819e53d8d3c3a2922e0d837aa6',
    tt: '00000000000000000600000000000000636c69656e74410000000000000004a897b769e681c62ac1c2357319a3d363f610839c4477720d24cbe32f5fd85f44fb92ba966578c1b712be6962498834078262caa5b441ecfa9d4a9485720e918a410000000000000004e0f816fd1c35e22065d5556215c097e799390d16661c386e0ecc84593974a61b881a8c82327687d0501862970c64565560cb5671f696048050ca66ca5f8cc7fc4100000000000000048f83ec9f6e4f87cc6f9dc740bdc2769725f923364f01c84148c049a39a735ebda82eac03e00112fd6a5710682767cff5361f7e819e53d8d3c3a2922e0d837aa620000000000000000548d8729f730589e579b0475a582c1608138ddf7054b73b5381c7e883e2efae',
    confirmA:
        '47d29e6666af1b7dd450d571233085d7a9866e4d49d2645e2df975489521232b',
    confirmB:
        '3313c5cefc361d27fb16847a91c2a73b766ffa90a4839122a9b70a2f6bd1d6df',
  ),
  _Vector(
    a: 'server',
    b: '',
    w: '626e0cdc7b14c9db3e52a0b1b3a768c98e37852d5db30febe0497b14eae8c254',
    x: '07adb3db6bc623d3399726bfdbfd3d15a58ea776ab8a308b00392621291f9633',
    y: 'b6a4fc8dbb629d4ba51d6f91ed1532cf87adec98f25dd153a75accafafedec16',
    pA: '04f88fb71c99bfffaea370966b7eb99cd4be0ff1a7d335caac4211c4afd855e2e15a873b298503ad8ba1d9cbb9a392d2ba309b48bfd7879aefd0f2cea6009763b0',
    pB: '040c269d6be017dccb15182ac6bfcd9e2a14de019dd587eaf4bdfd353f031101e7cca177f8eb362a6e83e7d5e729c0732e1b528879c086f39ba0f31a9661bd34db',
    k: '0445ee233b8ecb51ebd6e7da3f307e88a1616bae2166121221fdc0dadb986afaf3ec8a988dc9c626fa3b99f58a7ca7c9b844bb3e8dd9554aafc5b53813504c1cbe',
    tt: '06000000000000007365727665720000000000000000410000000000000004f88fb71c99bfffaea370966b7eb99cd4be0ff1a7d335caac4211c4afd855e2e15a873b298503ad8ba1d9cbb9a392d2ba309b48bfd7879aefd0f2cea6009763b04100000000000000040c269d6be017dccb15182ac6bfcd9e2a14de019dd587eaf4bdfd353f031101e7cca177f8eb362a6e83e7d5e729c0732e1b528879c086f39ba0f31a9661bd34db41000000000000000445ee233b8ecb51ebd6e7da3f307e88a1616bae2166121221fdc0dadb986afaf3ec8a988dc9c626fa3b99f58a7ca7c9b844bb3e8dd9554aafc5b53813504c1cbe2000000000000000626e0cdc7b14c9db3e52a0b1b3a768c98e37852d5db30febe0497b14eae8c254',
    confirmA:
        'bc9f9bbe99f26d0b2260e6456e05a86196a3307ec6663a18bf6ac825736533b2',
    confirmB:
        'c2370e1bf813b086dff0d834e74425a06e6390f48f5411900276dcccc5a297ec',
  ),
  _Vector(
    a: '',
    b: '',
    w: '7bf46c454b4c1b25799527d896508afd5fc62ef4ec59db1efb49113063d70cca',
    x: '8cef65df64bb2d0f83540c53632de911b5b24b3eab6cc74a97609fd659e95473',
    y: 'd7a66f64074a84652d8d623a92e20c9675c61cb5b4f6a0063e4648a2fdc02d53',
    pA: '04a65b367a3f613cf9f0654b1b28a1e3a8a40387956c8ba6063e8658563890f46ca1ef6a676598889fc28de2950ab8120b79a5ef1ea4c9f44bc98f585634b46d66',
    pB: '04589f13218822710d98d8b2123a079041052d9941b9cf88c6617ddb2fcc0494662eea8ba6b64692dc318250030c6af045cb738bc81ba35b043c3dcb46adf6f58d',
    k: '041a3c03d51b452537ca2a1fea6110353c6d5ed483c4f0f86f4492ca3f378d40a994b4477f93c64d928edbbcd3e85a7c709b7ea73ee97986ce3d1438e135543772',
    tt: '00000000000000000000000000000000410000000000000004a65b367a3f613cf9f0654b1b28a1e3a8a40387956c8ba6063e8658563890f46ca1ef6a676598889fc28de2950ab8120b79a5ef1ea4c9f44bc98f585634b46d66410000000000000004589f13218822710d98d8b2123a079041052d9941b9cf88c6617ddb2fcc0494662eea8ba6b64692dc318250030c6af045cb738bc81ba35b043c3dcb46adf6f58d4100000000000000041a3c03d51b452537ca2a1fea6110353c6d5ed483c4f0f86f4492ca3f378d40a994b4477f93c64d928edbbcd3e85a7c709b7ea73ee97986ce3d1438e13554377220000000000000007bf46c454b4c1b25799527d896508afd5fc62ef4ec59db1efb49113063d70cca',
    confirmA:
        'dfb4db8d48ae5a675963ea5e6c19d98d4ea028d8e898dad96ea19a80ade95dca',
    confirmB:
        'd0f0609d1613138d354f7e95f19fb556bf52d751947241e8c7118df5ef0ae175',
  ),
];

void main() {
  final checks = <_Check>[
    for (final vector in _vectors) ..._vectorChecks(vector),
    ..._encodingChecks(),
    ..._pairingChecks(),
  ];

  var failed = 0;
  for (final check in checks) {
    stdout.writeln(
      '${check.ok ? 'PASS' : 'FAIL'}  ${check.name}  ${check.detail}',
    );
    if (!check.ok) failed += 1;
  }
  stdout.writeln('${checks.length - failed}/${checks.length} checks passed');
  if (failed > 0) exitCode = 1;
}

List<_Check> _vectorChecks(_Vector vector) {
  final label = 'RFC 9382 A="${vector.a}" B="${vector.b}"';
  final w = BigInt.parse(vector.w, radix: 16);
  Spake2 party(bool isA) => Spake2.withScalars(
    isA: isA,
    w: w,
    scalar: BigInt.parse(isA ? vector.x : vector.y, radix: 16),
    idA: utf8.encode(vector.a),
    idB: utf8.encode(vector.b),
  );
  final a = party(true);
  final b = party(false);
  final fromA = a.finish(_compress(vector.pB));
  final fromB = b.finish(_compress(vector.pA));
  final confirmA = _bytes(vector.confirmA);
  final confirmB = _bytes(vector.confirmB);
  return [
    _Check(
      name: '$label pA',
      ok: _hex(a.uncompressedShare) == vector.pA,
      detail: 'A share matches byte for byte',
    ),
    _Check(
      name: '$label pB',
      ok: _hex(b.uncompressedShare) == vector.pB,
      detail: 'B share matches byte for byte',
    ),
    _Check(
      name: '$label TT',
      ok:
          fromA != null &&
          fromB != null &&
          _hex(fromA.transcript) == vector.tt &&
          _hex(fromB.transcript) == vector.tt,
      detail: 'both sides build the RFC transcript, K included',
    ),
    _Check(
      name: '$label confirmations',
      ok:
          fromA != null &&
          fromB != null &&
          _hex(fromA.confirmA) == vector.confirmA &&
          _hex(fromB.confirmB) == vector.confirmB &&
          fromB.acceptsA(confirmA) &&
          fromA.acceptsB(confirmB) &&
          !fromA.acceptsB(confirmA),
      detail: 'A conf and B conf match, and each side checks the other',
    ),
  ];
}

List<_Check> _encodingChecks() {
  final vector = _vectors.first;
  Spake2 phone() => Spake2.withScalars(
    isA: true,
    w: BigInt.parse(vector.w, radix: 16),
    scalar: BigInt.parse(vector.x, radix: 16),
    idA: utf8.encode(vector.a),
    idB: utf8.encode(vector.b),
  );
  final uncompressed = _bytes(vector.pB);
  final hybrid = Uint8List.fromList(uncompressed)
    ..[0] = 0x06 | (uncompressed.last & 1);
  final offCurve = _offCurve();
  final tooBig = _bytes('02$_fieldPrime');
  final masked = _maskOnly(BigInt.parse(vector.w, radix: 16));
  return [
    _Check(
      name: 'uncompressed share refused',
      ok: phone().finish(uncompressed) == null,
      detail: '0x04 points are never decoded, so no off-curve point gets in',
    ),
    _Check(
      name: 'hybrid share refused',
      ok: phone().finish(hybrid) == null,
      detail: '0x06/0x07 refused',
    ),
    _Check(
      name: 'off-curve share refused',
      ok: offCurve != null && phone().finish(offCurve) == null,
      detail: 'an x with no square root is refused',
    ),
    _Check(
      name: 'x at or above p refused',
      ok: Spake2.decodeShare(tooBig) == null,
      detail: 'x = p is not reduced into a valid point',
    ),
    _Check(
      name: 'identity and odd lengths refused',
      ok:
          Spake2.decodeShare([0x00]) == null &&
          Spake2.decodeShare(const []) == null &&
          Spake2.decodeShare(_bytes(vector.pA).sublist(0, 32)) == null,
      detail: 'infinity, empty and short encodings',
    ),
    _Check(
      name: 'a share that unmasks to the identity is refused',
      ok: phone().finish(masked) == null,
      detail: 'pB = w·N would make K the identity',
    ),
  ];
}

List<_Check> _pairingChecks() {
  Spake2 phone(String code, {String fingerprint = _fingerprint}) =>
      Spake2.phone(
        code: code,
        phoneId: _phoneId,
        laptopFingerprint: fingerprint,
      );
  Spake2 laptop(String code, {String phoneId = _phoneId}) => Spake2.laptop(
    code: code,
    phoneId: phoneId,
    laptopFingerprint: _fingerprint,
  );
  bool pairs(Spake2 a, Spake2 b) {
    final onLaptop = b.finish(a.share);
    final onPhone = a.finish(b.share);
    if (onLaptop == null || onPhone == null) return false;
    return onPhone.acceptsB(onLaptop.confirmB) &&
        onLaptop.acceptsA(onPhone.confirmA);
  }

  final first = laptop('482913');
  final second = laptop('482913');
  return [
    _Check(
      name: 'same code pairs',
      ok: pairs(phone('482913'), laptop('482913')),
      detail: 'both confirmations check out',
    ),
    _Check(
      name: 'wrong code fails',
      ok: !pairs(phone('482914'), laptop('482913')),
      detail: 'one digit off',
    ),
    _Check(
      name: 'relaying laptop fails',
      ok: !pairs(phone('482913', fingerprint: 'FA:KE:00:01'), laptop('482913')),
      detail: 'the phone sees another certificate than the real laptop',
    ),
    _Check(
      name: 'another phone id fails',
      ok: !pairs(phone('482913'), laptop('482913', phoneId: 'someone-else')),
      detail: 'the transcript names the phone',
    ),
    _Check(
      name: 'code is normalised to digits',
      ok:
          Spake2.passwordScalar('482 913', _fingerprint) ==
              Spake2.passwordScalar('482913', _fingerprint) &&
          Spake2.passwordScalar('482913', _fingerprint) !=
              Spake2.passwordScalar('482913', 'FA:KE:00:01'),
      detail: 'spaces drop out; the certificate salts w',
    ),
    _Check(
      name: 'every session has a fresh share',
      ok: _hex(first.share) != _hex(second.share) && first.share.length == 33,
      detail: 'a new random scalar each time, 33-byte compressed',
    ),
    _Check(
      name: 'wire encoding round-trips',
      ok:
          Spake2.decode(Spake2.encode(first.share), Spake2.shareLength) !=
              null &&
          Spake2.decode('not base64!', Spake2.shareLength) == null &&
          Spake2.decode(Spake2.encode([1, 2, 3]), Spake2.shareLength) == null,
      detail: 'base64url, exact length',
    ),
  ];
}

Uint8List? _offCurve() {
  for (var x = 1; x < 64; x++) {
    final candidate = Uint8List(33)
      ..[0] = 0x02
      ..[32] = x;
    try {
      _group.curve.decodePoint(candidate);
    } on ArgumentError {
      return candidate;
    }
  }
  return null;
}

Uint8List _maskOnly(BigInt w) {
  final n = _group.curve.decodePoint(_bytes(_nPoint))!;
  return (n * w)!.getEncoded(true);
}

Uint8List _compress(String uncompressed) =>
    _group.curve.decodePoint(_bytes(uncompressed))!.getEncoded(true);

Uint8List _bytes(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

class _Vector {
  const _Vector({
    required this.a,
    required this.b,
    required this.w,
    required this.x,
    required this.y,
    required this.pA,
    required this.pB,
    required this.k,
    required this.tt,
    required this.confirmA,
    required this.confirmB,
  });

  final String a;
  final String b;
  final String w;
  final String x;
  final String y;
  final String pA;
  final String pB;
  final String k;
  final String tt;
  final String confirmA;
  final String confirmB;
}

class _Check {
  const _Check({required this.name, required this.ok, required this.detail});

  final String name;
  final bool ok;
  final String detail;
}
