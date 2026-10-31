import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../core/error/failure.dart';
import '../../core/protocol/codec.dart';
import '../../core/protocol/packet.dart';
import '../../core/protocol/packet_buffer.dart';
import '../../core/protocol/pair_detail.dart';
import '../security/agent_certificate.dart';
import '../security/datagram_seal.dart';
import '../security/reconnect_secret.dart';
import '../security/spake2.dart';
import 'transport.dart';

class NetworkTransport implements Transport {
  NetworkTransport({
    this.connectTimeout = defaultConnectTimeout,
    this.keepaliveInterval = defaultKeepaliveInterval,
    this.peerTimeout = defaultPeerTimeout,
    this.replyTimeout = defaultReplyTimeout,
  });

  static const Duration defaultConnectTimeout = Duration(seconds: 5);
  static const Duration defaultKeepaliveInterval = Duration(seconds: 3);
  static const Duration defaultPeerTimeout = Duration(seconds: 8);
  static const Duration forgetFlushTimeout = Duration(seconds: 1);
  static const Duration defaultReplyTimeout = Duration(seconds: 10);
  static const String laptopNotConfirmed =
      'That code didn’t work, or that isn’t the laptop showing it.';
  static const Set<PacketType> motionTypes = {
    PacketType.move,
    PacketType.scroll,
  };

  final Duration connectTimeout;
  final Duration keepaliveInterval;
  final Duration peerTimeout;
  final Duration replyTimeout;

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
  String? _issuedSecret;
  DatagramSeal? _seal;
  Spake2? _spake;
  bool _laptopConfirmed = false;
  Timer? _keepalive;
  Timer? _replyTimer;
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
    SecureSocket? socket;
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
      final certificate = socket.peerCertificate;
      if (certificate == null) {
        socket.destroy();
        throw _handshakeFailure(expected, '');
      }
      presented = AgentCertificate.fingerprintOfDer(certificate.der);
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
      _peerFingerprint = presented;
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
      _replyTimer = Timer(replyTimeout, () => _dropConnection(generation));
      final secret = endpoint.secret;
      _sendDirect(
        expected != null && secret != null
            ? PairPacket(
                PairStage.resume,
                PairDetail.resume(endpoint.clientId, secret),
              )
            : PairPacket(
                PairStage.introduce,
                PairDetail.introduce(endpoint.clientId),
              ),
      );
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
    final endpoint = _endpoint;
    final fingerprint = _peerFingerprint;
    if (_state != TransportState.pairing) return;
    if (endpoint == null || fingerprint == null) return;
    final spake = Spake2.phone(
      code: code,
      phoneId: endpoint.clientId,
      laptopFingerprint: fingerprint,
    );
    _spake = spake;
    _sendDirect(PairPacket(PairStage.spakeShare, Spake2.encode(spake.share)));
  }

  void _onLaptopShare(String detail) {
    final spake = _spake;
    _spake = null;
    if (spake == null || _state != TransportState.pairing) return;
    final parts = PairDetail.parts(detail);
    final wellFormed = parts.length == 2;
    final share = wellFormed
        ? Spake2.decode(parts.first, Spake2.shareLength)
        : null;
    final tag = wellFormed
        ? Spake2.decode(parts.last, Spake2.confirmLength)
        : null;
    final session = share == null ? null : spake.finish(share);
    if (session == null || tag == null || !session.acceptsB(tag)) {
      if (!_pairingErrors.isClosed) {
        _pairingErrors.add(const HandshakeFailure(laptopNotConfirmed));
      }
      _sendDirect(const PairPacket(PairStage.spakeConfirm));
      return;
    }
    _laptopConfirmed = true;
    _sendDirect(
      PairPacket(PairStage.spakeConfirm, Spake2.encode(session.confirmA)),
    );
  }

  @override
  Stream<Failure> get pairingErrors => _pairingErrors.stream;

  @override
  Stream<void> get codeRequests => _codeRequests.stream;

  @override
  String? get peerFingerprint => _peerFingerprint;

  @override
  String? get issuedSecret => _issuedSecret;

  void _sendDirect(Packet packet) {
    final socket = _socket;
    if (socket == null) return;
    try {
      socket.add(PacketCodec.encode(packet));
    } catch (_) {}
  }

  void _onPair(PairPacket packet) {
    _replyTimer?.cancel();
    _replyTimer = null;
    switch (packet.stage) {
      case PairStage.accepted:
        if (_state != TransportState.pairing) return;
        if (_endpoint?.fingerprint == null && !_laptopConfirmed) {
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
        final parts = PairDetail.parts(packet.detail);
        final wellFormed =
            parts.length == 1 ||
            parts.length == 2 && ReconnectSecret.isToken(parts.last);
        final key = wellFormed ? DatagramSeal.decodeKey(parts.first) : null;
        if (key == null) {
          if (!_pairingErrors.isClosed) {
            _pairingErrors.add(
              const VersionFailure(
                'That laptop is running an older Tapikapp. '
                'Update it, then try again.',
              ),
            );
          }
          unawaited(disconnect());
          return;
        }
        _seal = DatagramSeal(key);
        if (parts.length == 2) _issuedSecret = parts.last;
        _lastHeard = DateTime.now();
        _startKeepalive();
        _emit(TransportState.connected);
      case PairStage.rejected:
        if (!_pairingErrors.isClosed) {
          _pairingErrors.add(HandshakeFailure(packet.detail));
        }
      case PairStage.busy:
        if (!_pairingErrors.isClosed) {
          _pairingErrors.add(TransportFailure(packet.detail));
        }
      case PairStage.codeRequired:
        if (!_codeRequests.isClosed) _codeRequests.add(null);
      case PairStage.spakeShare:
        _onLaptopShare(packet.detail);
      case PairStage.hello:
      case PairStage.spakeConfirm:
      case PairStage.code:
      case PairStage.introduce:
      case PairStage.resume:
      case PairStage.forget:
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
      final sealed = _seal?.seal(bytes);
      if (datagrams == null || address == null || sealed == null) return;
      datagrams.send(sealed, address, _udpPort);
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
  Future<void> forget() async {
    final generation = _generation;
    final socket = _socket;
    if (_state == TransportState.connected && socket != null) {
      try {
        socket.add(PacketCodec.encode(const PairPacket(PairStage.forget)));
        await socket.flush().timeout(forgetFlushTimeout);
      } catch (_) {}
    }
    if (_isStale(generation)) return;
    await disconnect();
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
    _issuedSecret = null;
    _seal = null;
    _spake = null;
    _laptopConfirmed = false;
    _keepalive?.cancel();
    _keepalive = null;
    _replyTimer?.cancel();
    _replyTimer = null;
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
