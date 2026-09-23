import '../../core/protocol/packet.dart';
import '../../core/resources/constants.dart';

enum TransportState { disconnected, connecting, connected }

class TransportEndpoint {
  const TransportEndpoint({
    required this.host,
    this.tcpPort = TapikappConstants.tcpPort,
    this.udpPort = TapikappConstants.udpPort,
  });

  final String host;
  final int tcpPort;
  final int udpPort;
}

abstract class Transport {
  TransportState get state;

  Stream<TransportState> get states;

  Stream<Packet> get incoming;

  Future<void> connect(TransportEndpoint endpoint);

  void send(Packet packet);

  Future<void> disconnect();

  Future<void> dispose();
}
