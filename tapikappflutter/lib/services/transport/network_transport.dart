import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../core/error/failure.dart';
import '../../core/protocol/codec.dart';
import '../../core/protocol/packet.dart';
import '../../core/protocol/packet_buffer.dart';
import '../security/agent_certificate.dart';
import 'transport.dart';

class NetworkTransport implements Transport {
  NetworkTransport({
    this.connectTimeout = defaultConnectTimeout,
    this.keepaliveInterval = defaultKeepaliveInterval,
    this.peerTimeout = defaultPeerTimeout,
  });

  static const Duration defaultConnectTimeout = Duration(seconds: 5);
  static const Duration defaultKeepaliveInterval = Duration(seconds: 3);
  static const Duration defaultPeerTimeout = Duration(seconds: 8);
  static const Set<PacketType> motionTypes = {
    PacketType.move,
    PacketType.scroll,
  };

  final Duration connectTimeout;
  final Duration keepaliveInterval;
  final Duration peerTimeout;

  final StreamController<TransportState> _states =
      StreamController<TransportState>.broadcast();
  final StreamController<Packet> _incoming =
      StreamController<Packet>.broadcast();
  final PacketBuffer _buffer = PacketBuffer();
  final StreamController<Failure> _pairingErrors =
      StreamController<Failure>.broadcast();
  final StreamController<void> _codeRequests =
      StreamController<void>.broadcast();

  TransportState _state = TransportState.disconnected;
  TransportEndpoint? _endpoint;
  Socket? _socket;
  RawDatagramSocket? _datagrams;
  StreamSubscription<Uint8List>? _reader;
  StreamSubscription<RawSocketEvent>? _datagramReader;
  InternetAddress? _address;
  String? _peerFingerprint;
  bool _sawCodeRequest = false;
  Timer? _keepalive;
  DateTime _lastHeard = DateTime.fromMillisecondsSinceEpoch(0);
  int _udpPort = 0;
  int _generation = 0;
  bool _disposed = false;

  @override
  TransportState get state => _state;

  @override
  TransportEndpoint? get endpoint => _endpoint;

  @override
  Stream<TransportState> get states => _states.stream;

  @override
  Stream<Packet> get incoming => _incoming.stream;

  @override
  Future<void> connect(TransportEndpoint endpoint) async {
    if (_disposed) {
      throw const TransportFailure('The connection was already closed.');
    }
    final generation = ++_generation;
    await _teardown();
    if (_isStale(generation)) return;
    _endpoint = endpoint;
    _emit(TransportState.connecting);
    Socket? socket;
    RawDatagramSocket? datagrams;
    try {
      final expected = endpoint.fingerprint;
      var presented = '';
      try {
        socket = await SecureSocket.connect(
          endpoint.host,
          endpoint.tcpPort,
          timeout: connectTimeout,
          onBadCertificate: (certificate) {
            presented = AgentCertificate.fingerprintOfDer(certificate.der);
            return expected == null || expected == presented;
          },
        );
      } on HandshakeException {
        throw _handshakeFailure(expected, presented);
      }
      if (expected != null && expected != presented) {
        socket.destroy();
        throw _handshakeFailure(expected, presented);
      }
      if (_isStale(generation)) {
        socket.destroy();
        return;
      }
      socket.setOption(SocketOption.tcpNoDelay, true);
      unawaited(socket.done.catchError((Object _) => socket!));
      datagrams = await RawDatagramSocket.bind(
        socket.remoteAddress.type == InternetAddressType.IPv6
            ? InternetAddress.anyIPv6
            : InternetAddress.anyIPv4,
        0,
      );
      if (_isStale(generation)) {
        socket.destroy();
        datagrams.close();
        return;
      }
      _socket = socket;
      _datagrams = datagrams;
      _address = socket.remoteAddress;
      _peerFingerprint = presented.isEmpty ? expected : presented;
      _udpPort = endpoint.udpPort;
      _reader = socket.listen(
        _onBytes,
        onError: (Object _) => _dropConnection(generation),
        onDone: () => _dropConnection(generation),
        cancelOnError: true,
      );
      _datagramReader = datagrams.listen(
        _onDatagramEvent,
        onError: (Object _) => _dropConnection(generation),
      );
      _emit(TransportState.pairing);
      _sendDirect(PairPacket(PairStage.hello, endpoint.clientId));
    } catch (error) {
      socket?.destroy();
      datagrams?.close();
      if (!_isStale(generation)) {
        await _teardown();
        _emit(TransportState.disconnected);
      }
      throw _failureFor(error);
    }
  }

  @override
  void submitPairingCode(String code) {
    if (_state != TransportState.pairing) return;
    _sendDirect(PairPacket(PairStage.code, code));
  }

  @override
  Stream<Failure> get pairingErrors => _pairingErrors.stream;

  @override
  Stream<void> get codeRequests => _codeRequests.stream;

  @override
  String? get peerFingerprint => _peerFingerprint;

  void _sendDirect(Packet packet) {
    final socket = _socket;
    if (socket == null) return;
    try {
      socket.add(PacketCodec.encode(packet));
    } catch (_) {}
  }

  void _onPair(PairPacket packet) {
    switch (packet.stage) {
      case PairStage.accepted:
        if (_endpoint?.fingerprint == null && !_sawCodeRequest) {
          if (!_pairingErrors.isClosed) {
            _pairingErrors.add(
              const HandshakeFailure(
                'That laptop let you in without asking for its code. '
                'It may not be your laptop.',
              ),
            );
          }
          unawaited(disconnect());
          return;
        }
        _lastHeard = DateTime.now();
        _startKeepalive();
        _emit(TransportState.connected);
      case PairStage.rejected:
        if (!_pairingErrors.isClosed) {
          _pairingErrors.add(HandshakeFailure(packet.detail));
        }
      case PairStage.codeRequired:
        _sawCodeRequest = true;
        if (!_codeRequests.isClosed) _codeRequests.add(null);
      case PairStage.hello:
      case PairStage.code:
        return;
    }
  }

  @override
  void send(Packet packet) {
    if (_state != TransportState.connected) return;
    final bytes = PacketCodec.encode(packet);
    if (motionTypes.contains(packet.type)) {
      final datagrams = _datagrams;
      final address = _address;
      if (datagrams == null || address == null) return;
      datagrams.send(bytes, address, _udpPort);
      return;
    }
    final socket = _socket;
    if (socket == null) return;
    try {
      socket.add(bytes);
    } on StateError {
      _dropConnection(_generation);
    }
  }

  @override
  Future<void> disconnect() async {
    _generation++;
    await _teardown();
    _emit(TransportState.disconnected);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    await _teardown();
    _state = TransportState.disconnected;
    await _pairingErrors.close();
    await _codeRequests.close();
    await _states.close();
    await _incoming.close();
  }

  bool _isStale(int generation) => _disposed || generation != _generation;

  void _onBytes(Uint8List chunk) {
    _lastHeard = DateTime.now();
    for (final packet in _buffer.add(chunk)) {
      if (packet is PairPacket) {
        _onPair(packet);
        continue;
      }
      if (packet is PingPacket) continue;
      if (!_incoming.isClosed) _incoming.add(packet);
    }
  }

  void _startKeepalive() {
    _keepalive?.cancel();
    final generation = _generation;
    _keepalive = Timer.periodic(keepaliveInterval, (_) {
      if (_isStale(generation) || _state != TransportState.connected) return;
      if (DateTime.now().difference(_lastHeard) > peerTimeout) {
        _dropConnection(generation);
        return;
      }
      _sendDirect(const PingPacket());
    });
  }

  void _onDatagramEvent(RawSocketEvent event) {
    if (event == RawSocketEvent.read) _datagrams?.receive();
  }

  void _dropConnection(int generation) {
    if (_isStale(generation)) return;
    unawaited(disconnect());
  }

  Future<void> _teardown() async {
    final reader = _reader;
    final datagramReader = _datagramReader;
    final socket = _socket;
    final datagrams = _datagrams;
    _reader = null;
    _datagramReader = null;
    _socket = null;
    _datagrams = null;
    _address = null;
    _endpoint = null;
    _peerFingerprint = null;
    _sawCodeRequest = false;
    _keepalive?.cancel();
    _keepalive = null;
    _buffer.clear();
    await reader?.cancel();
    await datagramReader?.cancel();
    datagrams?.close();
    socket?.destroy();
  }

  void _emit(TransportState next) {
    if (_state == next || _states.isClosed) return;
    _state = next;
    _states.add(next);
  }

  static Failure _failureFor(Object error) {
    if (error is Failure) return error;
    if (error is SocketException) {
      return TransportFailure(_messageFor(error));
    }
    if (error is HandshakeException || error is TlsException) {
      return _handshakeFailure(null, '');
    }
    return const TransportFailure(
      'That laptop address is not valid. Pick it from the list again.',
    );
  }

  static Failure _handshakeFailure(String? expected, String presented) {
    if (expected != null && presented.isNotEmpty && expected != presented) {
      return const HandshakeFailure(
        'That laptop presented a different certificate than the one you '
        'paired with. Pair it again if you replaced or reinstalled it.',
      );
    }
    return const HandshakeFailure(
      'Tapikapp could not set up a private connection to that laptop.',
    );
  }

  static String _messageFor(SocketException error) {
    switch (error.osError?.errorCode) {
      case 110:
      case 60:
      case 10060:
        return 'The laptop did not answer. '
            'Check that Tapikapp is running on it.';
      case 61:
      case 111:
      case 10061:
        return 'The laptop refused the connection. Is Tapikapp running on it?';
      case 51:
      case 65:
      case 101:
      case 10051:
      case 10065:
        return 'That laptop is not reachable on this network.';
      default:
        return 'Could not reach the laptop. '
            'Check that both are on the same Wi-Fi.';
    }
  }
}
