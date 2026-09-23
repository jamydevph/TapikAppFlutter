import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../core/error/failure.dart';
import '../../core/protocol/codec.dart';
import '../../core/protocol/packet.dart';
import '../../core/protocol/packet_buffer.dart';
import 'transport.dart';

class NetworkTransport implements Transport {
  NetworkTransport({this.connectTimeout = defaultConnectTimeout});

  static const Duration defaultConnectTimeout = Duration(seconds: 5);
  static const Set<PacketType> motionTypes = {
    PacketType.move,
    PacketType.scroll,
  };

  final Duration connectTimeout;

  final StreamController<TransportState> _states =
      StreamController<TransportState>.broadcast();
  final StreamController<Packet> _incoming =
      StreamController<Packet>.broadcast();
  final PacketBuffer _buffer = PacketBuffer();

  TransportState _state = TransportState.disconnected;
  Socket? _socket;
  RawDatagramSocket? _datagrams;
  StreamSubscription<Uint8List>? _reader;
  StreamSubscription<RawSocketEvent>? _datagramReader;
  InternetAddress? _address;
  int _udpPort = 0;
  int _generation = 0;
  bool _disposed = false;

  @override
  TransportState get state => _state;

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
    _emit(TransportState.connecting);
    Socket? socket;
    RawDatagramSocket? datagrams;
    try {
      socket = await Socket.connect(
        endpoint.host,
        endpoint.tcpPort,
        timeout: connectTimeout,
      );
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
      _emit(TransportState.connected);
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
    await _states.close();
    await _incoming.close();
  }

  bool _isStale(int generation) => _disposed || generation != _generation;

  void _onBytes(Uint8List chunk) {
    for (final packet in _buffer.add(chunk)) {
      if (!_incoming.isClosed) _incoming.add(packet);
    }
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
    return const TransportFailure(
      'That laptop address is not valid. Pick it from the list again.',
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
