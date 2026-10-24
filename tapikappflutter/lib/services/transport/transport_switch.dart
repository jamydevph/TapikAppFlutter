import 'dart:async';

import '../../core/error/failure.dart';
import '../../core/protocol/packet.dart';
import 'bt_hid_transport.dart';
import 'transport.dart';

class TransportSwitch implements Transport {
  TransportSwitch({required this.network, this.bluetooth}) : _active = network {
    for (final transport in [network, ?bluetooth]) {
      _links
        ..add(transport.states.listen((state) => _forward(transport, state)))
        ..add(
          transport.incoming.listen((packet) {
            if (transport == _active) _incoming.add(packet);
          }),
        );
    }
  }

  final Transport network;
  final BtHidTransport? bluetooth;

  final StreamController<TransportState> _states =
      StreamController<TransportState>.broadcast();
  final StreamController<Packet> _incoming =
      StreamController<Packet>.broadcast();
  final List<StreamSubscription<Object?>> _links = [];

  Transport _active;

  Transport get active => _active;

  void use(Transport transport) {
    if (transport != network && transport != bluetooth) return;
    if (transport == _active) return;
    _active = transport;
    if (!_states.isClosed) _states.add(transport.state);
  }

  @override
  TransportState get state => _active.state;

  @override
  TransportEndpoint? get endpoint => _active.endpoint;

  @override
  Stream<TransportState> get states => _states.stream;

  @override
  Stream<Packet> get incoming => _incoming.stream;

  @override
  Stream<Failure> get pairingErrors => network.pairingErrors;

  @override
  Stream<void> get codeRequests => network.codeRequests;

  @override
  String? get peerFingerprint => _active.peerFingerprint;

  @override
  Future<void> connect(TransportEndpoint endpoint) => _active.connect(endpoint);

  @override
  void submitPairingCode(String code) => _active.submitPairingCode(code);

  @override
  void send(Packet packet) => _active.send(packet);

  @override
  Future<void> disconnect() async {
    if (_active == network || network.state != TransportState.disconnected) {
      await network.disconnect();
    }
    await bluetooth?.release();
  }

  @override
  Future<void> forget() async {
    await network.forget();
    await bluetooth?.release();
  }

  @override
  Future<void> dispose() async {
    for (final link in _links) {
      await link.cancel();
    }
    await network.dispose();
    await bluetooth?.dispose();
    await _states.close();
    await _incoming.close();
  }

  void _forward(Transport source, TransportState state) {
    if (source == _active && !_states.isClosed) _states.add(state);
  }
}
