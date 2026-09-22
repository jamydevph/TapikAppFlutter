import 'dart:convert';
import 'dart:typed_data';

import 'packet.dart';

class DecodeResult {
  const DecodeResult({required this.packets, required this.consumed});

  static const DecodeResult empty = DecodeResult(packets: [], consumed: 0);

  final List<Packet> packets;
  final int consumed;
}

class PacketCodec {
  const PacketCodec._();

  static const int moveLength = 5;
  static const int buttonLength = 3;
  static const int scrollLength = 5;
  static const int keyLength = 5;
  static const int textHeaderLength = 3;
  static const int pingLength = 1;

  static Uint8List encode(Packet packet) {
    switch (packet) {
      case MovePacket(:final dx, :final dy):
        return _encodeDeltas(PacketType.move, dx, dy);
      case ButtonPacket(:final button, :final down):
        final bytes = Uint8List(buttonLength);
        bytes[0] = PacketType.button.code;
        bytes[1] = button.code;
        bytes[2] = down ? 1 : 0;
        return bytes;
      case ScrollPacket(:final dx, :final dy):
        return _encodeDeltas(PacketType.scroll, dx, dy);
      case KeyPacket(:final keyCode, :final modifiers, :final down):
        final bytes = Uint8List(keyLength);
        final view = ByteData.view(bytes.buffer);
        bytes[0] = PacketType.key.code;
        view.setUint16(1, _clampKeyCode(keyCode), Endian.big);
        bytes[3] = modifiers.mask;
        bytes[4] = down ? 1 : 0;
        return bytes;
      case TextPacket(:final text):
        final payload = _truncateUtf8(utf8.encode(text));
        final bytes = Uint8List(textHeaderLength + payload.length);
        final view = ByteData.view(bytes.buffer);
        bytes[0] = PacketType.text.code;
        view.setUint16(1, payload.length, Endian.big);
        bytes.setRange(textHeaderLength, bytes.length, payload);
        return bytes;
      case PingPacket():
        return Uint8List.fromList([PacketType.ping.code]);
    }
  }

  static Packet? decodeOne(Uint8List bytes) {
    if (bytes.isEmpty) return null;
    final type = PacketType.fromCode(bytes[0]);
    if (type == null) return null;
    final view = _viewOf(bytes);
    if (_frameLength(type, view, 0, bytes.length) != bytes.length) return null;
    return _readPacket(type, bytes, view, 0);
  }

  static DecodeResult decode(Uint8List bytes) {
    if (bytes.isEmpty) return DecodeResult.empty;
    final packets = <Packet>[];
    var offset = 0;
    final view = _viewOf(bytes);
    while (offset < bytes.length) {
      final type = PacketType.fromCode(bytes[offset]);
      if (type == null) {
        offset += 1;
        continue;
      }
      final frame = _frameLength(type, view, offset, bytes.length);
      if (frame == null) {
        return DecodeResult(packets: packets, consumed: offset);
      }
      final packet = _readPacket(type, bytes, view, offset);
      if (packet != null) {
        packets.add(packet);
      }
      offset += frame;
    }
    return DecodeResult(packets: packets, consumed: offset);
  }

  static ByteData _viewOf(Uint8List bytes) {
    return ByteData.view(
      bytes.buffer,
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );
  }

  static int? _frameLength(
    PacketType type,
    ByteData view,
    int offset,
    int length,
  ) {
    final available = length - offset;
    final fixed = switch (type) {
      PacketType.move => moveLength,
      PacketType.button => buttonLength,
      PacketType.scroll => scrollLength,
      PacketType.key => keyLength,
      PacketType.ping => pingLength,
      PacketType.text => textHeaderLength,
    };
    if (available < fixed) return null;
    if (type != PacketType.text) return fixed;
    final payload = view.getUint16(offset + 1, Endian.big);
    final frame = textHeaderLength + payload;
    return available < frame ? null : frame;
  }

  static Packet? _readPacket(
    PacketType type,
    Uint8List bytes,
    ByteData view,
    int offset,
  ) {
    switch (type) {
      case PacketType.move:
        return MovePacket(
          dx: view.getInt16(offset + 1, Endian.big),
          dy: view.getInt16(offset + 3, Endian.big),
        );
      case PacketType.button:
        final button = PointerButton.fromCode(bytes[offset + 1]);
        return button == null
            ? null
            : ButtonPacket(button: button, down: bytes[offset + 2] != 0);
      case PacketType.scroll:
        return ScrollPacket(
          dx: view.getInt16(offset + 1, Endian.big),
          dy: view.getInt16(offset + 3, Endian.big),
        );
      case PacketType.key:
        return KeyPacket(
          keyCode: view.getUint16(offset + 1, Endian.big),
          modifiers: KeyModifiers.fromMask(bytes[offset + 3]),
          down: bytes[offset + 4] != 0,
        );
      case PacketType.text:
        final length = view.getUint16(offset + 1, Endian.big);
        final start = offset + textHeaderLength;
        try {
          return TextPacket(utf8.decode(bytes.sublist(start, start + length)));
        } on FormatException {
          return null;
        }
      case PacketType.ping:
        return const PingPacket();
    }
  }

  static Uint8List _encodeDeltas(PacketType type, int dx, int dy) {
    final bytes = Uint8List(moveLength);
    final view = ByteData.view(bytes.buffer);
    bytes[0] = type.code;
    view.setInt16(1, _clampDelta(dx), Endian.big);
    view.setInt16(3, _clampDelta(dy), Endian.big);
    return bytes;
  }

  static int _clampDelta(int value) {
    return value.clamp(Packet.minDelta, Packet.maxDelta);
  }

  static int _clampKeyCode(int value) {
    return value.clamp(Packet.minKeyCode, Packet.maxKeyCode);
  }

  static List<int> _truncateUtf8(List<int> payload) {
    if (payload.length <= Packet.maxTextBytes) return payload;
    var end = Packet.maxTextBytes;
    while (end > 0 && payload[end] & 0xC0 == 0x80) {
      end -= 1;
    }
    return payload.sublist(0, end);
  }
}
