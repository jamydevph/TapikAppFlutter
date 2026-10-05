import '../../core/error/failure.dart';
import '../../core/protocol/packet.dart';
import '../../core/resources/constants.dart';

enum TransportState { disconnected, connecting, pairing, connected }

class TransportEndpoint {
  const TransportEndpoint({
    required this.host,
    this.label,
    this.platform,
    this.fingerprint,
    required this.clientId,
    this.tcpPort = TapikappConstants.tcpPort,
    this.udpPort = TapikappConstants.udpPort,
  });

  final String host;
  final String? label;
  final String? platform;
  final String? fingerprint;
  final String clientId;
  final int tcpPort;
  final int udpPort;
}

abstract class Transport {
  TransportState get state;

  TransportEndpoint? get endpoint;

  Stream<TransportState> get states;

  Stream<Packet> get incoming;

  Future<void> connect(TransportEndpoint endpoint);

  void submitPairingCode(String code);

  Stream<Failure> get pairingErrors;

  Stream<void> get codeRequests;

  String? get peerFingerprint;

  void send(Packet packet);

  Future<void> disconnect();

  Future<void> dispose();
}
