import 'dart:typed_data';

import 'codec.dart';
import 'packet.dart';

class PacketBuffer {
  PacketBuffer({this.capacity = maxFrameLength});

  static const int maxFrameLength =
      PacketCodec.textHeaderLength + Packet.maxTextBytes;

  final int capacity;
  final BytesBuilder _pending = BytesBuilder(copy: false);

  int get length => _pending.length;

  bool get isEmpty => _pending.isEmpty;

  List<Packet> add(Uint8List chunk) {
    _pending.add(chunk);
    final buffered = _pending.takeBytes();
    final result = PacketCodec.decode(buffered);
    final remaining = buffered.length - result.consumed;
    if (remaining > capacity) {
      return result.packets;
    }
    if (remaining > 0) {
      _pending.add(Uint8List.sublistView(buffered, result.consumed));
    }
    return result.packets;
  }

  void clear() {
    _pending.clear();
  }
}
