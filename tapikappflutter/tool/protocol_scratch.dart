import 'dart:io';
import 'dart:typed_data';

import 'package:tapikappflutter/core/protocol/codec.dart';
import 'package:tapikappflutter/core/protocol/packet.dart';

void main() {
  final checks = <_Check>[
    _roundTrip('move zero', const MovePacket(dx: 0, dy: 0)),
    _roundTrip('move negative', const MovePacket(dx: -7, dy: -1)),
    _roundTrip(
      'move i16 bounds',
      const MovePacket(dx: Packet.minDelta, dy: Packet.maxDelta),
    ),
    _roundTrip(
      'button left down',
      const ButtonPacket(button: PointerButton.left, down: true),
    ),
    _roundTrip(
      'button right up',
      const ButtonPacket(button: PointerButton.right, down: false),
    ),
    _roundTrip(
      'button middle down',
      const ButtonPacket(button: PointerButton.middle, down: true),
    ),
    _roundTrip('scroll', const ScrollPacket(dx: 3, dy: -120)),
    _roundTrip(
      'key with modifiers',
      const KeyPacket(
        keyCode: 8,
        modifiers: KeyModifiers(command: true, shift: true),
        down: true,
      ),
    ),
    _roundTrip(
      'key u16 max',
      const KeyPacket(keyCode: Packet.maxKeyCode, down: false),
    ),
    _roundTrip('text ascii', const TextPacket('hello')),
    _roundTrip('text empty', const TextPacket('')),
    _roundTrip('text multi-byte', const TextPacket('añ日本語')),
    _roundTrip('text emoji', const TextPacket('tap 👉🏽 tapik 🇵🇭')),
    _roundTrip('ping', const PingPacket()),
    _sizes(),
    _clamping(),
    _textTruncation(),
    _stream(),
    _garbage(),
    _strictDatagrams(),
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

_Check _roundTrip(String name, Packet packet) {
  final bytes = PacketCodec.encode(packet);
  final decoded = PacketCodec.decodeOne(bytes);
  return _Check(
    name: name,
    ok: decoded == packet,
    detail: '${bytes.length} bytes → ${decoded ?? 'null'}',
  );
}

_Check _sizes() {
  final sizes = {
    'move': PacketCodec.encode(const MovePacket(dx: 1, dy: 1)).length,
    'button': PacketCodec.encode(
      const ButtonPacket(button: PointerButton.left, down: true),
    ).length,
    'scroll': PacketCodec.encode(const ScrollPacket(dx: 1, dy: 1)).length,
    'key': PacketCodec.encode(const KeyPacket(keyCode: 1, down: true)).length,
    'ping': PacketCodec.encode(const PingPacket()).length,
    'text': PacketCodec.encode(const TextPacket('abc')).length,
  };
  final expected = {
    'move': 5,
    'button': 3,
    'scroll': 5,
    'key': 5,
    'ping': 1,
    'text': 6,
  };
  return _Check(
    name: 'wire sizes',
    ok: sizes.toString() == expected.toString(),
    detail: '$sizes',
  );
}

_Check _clamping() {
  final move = PacketCodec.decodeOne(
    PacketCodec.encode(const MovePacket(dx: 40000, dy: -40000)),
  );
  final key = PacketCodec.decodeOne(
    PacketCodec.encode(const KeyPacket(keyCode: 70000, down: true)),
  );
  final ok =
      move == const MovePacket(dx: Packet.maxDelta, dy: Packet.minDelta) &&
      key == const KeyPacket(keyCode: Packet.maxKeyCode, down: true);
  return _Check(name: 'out-of-range clamping', ok: ok, detail: '$move · $key');
}

_Check _textTruncation() {
  final decoded = PacketCodec.decodeOne(
    PacketCodec.encode(TextPacket('é' * 40000)),
  ) as TextPacket?;
  final bytes = decoded == null ? -1 : PacketCodec.encode(decoded).length - 3;
  return _Check(
    name: 'text truncated on a rune boundary',
    ok: decoded != null && bytes <= Packet.maxTextBytes && bytes.isEven,
    detail: '$bytes payload bytes',
  );
}

_Check _stream() {
  final packets = <Packet>[
    const MovePacket(dx: 2, dy: -2),
    const TextPacket('héllo 👋'),
    const PingPacket(),
    const ButtonPacket(button: PointerButton.right, down: false),
  ];
  final buffer = <int>[
    for (final packet in packets) ...PacketCodec.encode(packet),
  ];
  final whole = PacketCodec.decode(Uint8List.fromList(buffer));
  final split = buffer.length - 2;
  final partial = PacketCodec.decode(
    Uint8List.fromList(buffer.sublist(0, split)),
  );
  final rest = PacketCodec.decode(
    Uint8List.fromList(buffer.sublist(partial.consumed)),
  );
  final ok =
      whole.packets.length == packets.length &&
      whole.consumed == buffer.length &&
      partial.packets.length == packets.length - 1 &&
      partial.consumed < split &&
      rest.packets.length == 1;
  return _Check(
    name: 'stream framing and partial frames',
    ok: ok,
    detail:
        'whole ${whole.packets.length}/${whole.consumed}B · '
        'partial ${partial.packets.length}/${partial.consumed}B · '
        'rest ${rest.packets.length}',
  );
}

_Check _garbage() {
  final samples = <String, Uint8List>{
    'empty': Uint8List(0),
    'unknown type bytes': Uint8List.fromList([0x00, 0xFF, 0x7E]),
    'truncated move': Uint8List.fromList([0x01, 0x00]),
    'text length lies': Uint8List.fromList([0x05, 0xFF, 0xFF, 0x41]),
    'invalid utf8 payload': Uint8List.fromList([0x05, 0x00, 0x02, 0xC3, 0x28]),
    'unknown button code': Uint8List.fromList([0x02, 0x09, 0x01]),
    'random noise': Uint8List.fromList(
      List<int>.generate(64, (i) => (i * 37 + 11) & 0xFF),
    ),
  };
  final details = <String>[];
  var ok = true;
  for (final entry in samples.entries) {
    try {
      final result = PacketCodec.decode(entry.value);
      details.add('${entry.key}:${result.packets.length}');
    } catch (error) {
      ok = false;
      details.add('${entry.key}:THREW $error');
    }
  }
  return _Check(
    name: 'decode never throws on garbage',
    ok: ok,
    detail: details.join(' · '),
  );
}

_Check _strictDatagrams() {
  final move = PacketCodec.encode(const MovePacket(dx: 5, dy: 6));
  final rejected = <String, Uint8List>{
    'leading junk': Uint8List.fromList([0xFF, PacketType.ping.code]),
    'trailing junk': Uint8List.fromList([PacketType.ping.code, 0xFF]),
    'junk both sides': Uint8List.fromList([0x00, PacketType.ping.code, 0xFF]),
    'trailing bytes after a frame': Uint8List.fromList([...move, 0x00, 0xFE]),
    'two frames in one datagram': Uint8List.fromList([
      ...move,
      PacketType.ping.code,
    ]),
    'truncated frame': Uint8List.fromList(move.sublist(0, 3)),
    'unknown button code': Uint8List.fromList([
      PacketType.button.code,
      0x09,
      1,
    ]),
  };
  final leaked = <String>[];
  for (final entry in rejected.entries) {
    if (PacketCodec.decodeOne(entry.value) != null) leaked.add(entry.key);
  }
  final accepted =
      PacketCodec.decodeOne(move) == const MovePacket(dx: 5, dy: 6) &&
      PacketCodec.decodeOne(PacketCodec.encode(const TextPacket('ok 👍'))) ==
          const TextPacket('ok 👍');
  return _Check(
    name: 'decodeOne accepts only one exact frame',
    ok: leaked.isEmpty && accepted,
    detail: leaked.isEmpty
        ? '${rejected.length} malformed datagrams rejected'
        : 'accepted ${leaked.join(', ')}',
  );
}

class _Check {
  const _Check({required this.name, required this.ok, required this.detail});

  final String name;
  final bool ok;
  final String detail;
}
