import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';

import '../../core/error/failure.dart';
import '../../core/protocol/codec.dart';
import '../../core/protocol/packet.dart';
import '../../core/protocol/packet_buffer.dart';
import '../../core/resources/constants.dart';

class AgentServerState extends Equatable {
  const AgentServerState({this.listening = false, this.client});

  static const AgentServerState stopped = AgentServerState();

  final bool listening;
  final String? client;

  bool get hasClient => client != null;

  @override
  List<Object?> get props => [listening, client];
}

class AgentServer {
  AgentServer({
    this.tcpPort = TapikappConstants.tcpPort,
    this.udpPort = TapikappConstants.udpPort,
  });

  final int tcpPort;
  final int udpPort;

  final StreamController<AgentServerState> _states =
      StreamController<AgentServerState>.broadcast();
  final StreamController<Packet> _packets =
      StreamController<Packet>.broadcast();
  final PacketBuffer _buffer = PacketBuffer();

  AgentServerState _state = AgentServerState.stopped;
  String? _clientLabel;
  ServerSocket? _server;
  RawDatagramSocket? _datagrams;
  StreamSubscription<Socket>? _accepts;
  StreamSubscription<RawSocketEvent>? _datagramReader;
  StreamSubscription<Uint8List>? _reader;
  Socket? _client;
  int _packetCount = 0;
  int _generation = 0;
  bool _disposed = false;

  AgentServerState get state => _state;

  Stream<AgentServerState> get states => _states.stream;

  Stream<Packet> get packets => _packets.stream;

  int get packetCount => _packetCount;

  Future<void> start() async {
    if (_disposed) {
      throw const TransportFailure('The agent was already shut down.');
    }
    if (_state.listening) return;
    final generation = ++_generation;
    ServerSocket? server;
    RawDatagramSocket? datagrams;
    try {
      server = await ServerSocket.bind(InternetAddress.anyIPv6, tcpPort);
      if (_isStale(generation)) {
        await server.close();
        return;
      }
      datagrams = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        udpPort,
      );
      if (_isStale(generation)) {
        await server.close();
        datagrams.close();
        return;
      }
      _server = server;
      _datagrams = datagrams;
      _accepts = server.listen(_onClient, onError: (Object _) {});
      _datagramReader = datagrams.listen(
        _onDatagramEvent,
        onError: (Object _) {},
      );
      _emit(const AgentServerState(listening: true));
    } catch (error) {
      await server?.close();
      datagrams?.close();
      if (!_isStale(generation)) await stop();
      throw _failureFor(error, server == null ? tcpPort : udpPort);
    }
  }

  Future<void> stop() async {
    _generation++;
    await _dropClient();
    final accepts = _accepts;
    final datagramReader = _datagramReader;
    final server = _server;
    final datagrams = _datagrams;
    _accepts = null;
    _datagramReader = null;
    _server = null;
    _datagrams = null;
    await accepts?.cancel();
    await datagramReader?.cancel();
    datagrams?.close();
    await server?.close();
    _emit(AgentServerState.stopped);
  }

  Future<void> disconnectClient() async {
    await _dropClient();
    _emit(AgentServerState(listening: _state.listening));
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    await stop();
    await _states.close();
    await _packets.close();
  }

  void _onClient(Socket socket) {
    socket.setOption(SocketOption.tcpNoDelay, true);
    unawaited(socket.done.catchError((Object _) => socket));
    if (_client != null) {
      socket.destroy();
      return;
    }
    _client = socket;
    _clientLabel = _labelFor(socket.remoteAddress);
    _buffer.clear();
    _packetCount = 0;
    _reader = socket.listen(
      _onBytes,
      onError: (Object _) => unawaited(disconnectClient()),
      onDone: () => unawaited(disconnectClient()),
      cancelOnError: true,
    );
    _emit(AgentServerState(listening: true, client: _clientLabel));
  }

  void _onBytes(Uint8List chunk) {
    for (final packet in _buffer.add(chunk)) {
      _deliver(packet);
    }
  }

  void _onDatagramEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _datagrams?.receive();
    if (datagram == null) return;
    if (_labelFor(datagram.address) != _clientLabel) return;
    final packet = PacketCodec.decodeOne(datagram.data);
    if (packet != null) _deliver(packet);
  }

  void _deliver(Packet packet) {
    _packetCount += 1;
    if (!_packets.isClosed) _packets.add(packet);
  }

  Future<void> _dropClient() async {
    final reader = _reader;
    final client = _client;
    _reader = null;
    _client = null;
    _clientLabel = null;
    _buffer.clear();
    await reader?.cancel();
    client?.destroy();
  }

  bool _isStale(int generation) => _disposed || generation != _generation;

  void _emit(AgentServerState next) {
    if (_state == next || _states.isClosed) return;
    _state = next;
    _states.add(next);
  }

  static String _labelFor(InternetAddress address) {
    const mappedPrefix = '::ffff:';
    final text = address.address;
    return text.startsWith(mappedPrefix)
        ? text.substring(mappedPrefix.length)
        : text;
  }

  static Failure _failureFor(Object error, int port) {
    if (error is Failure) return error;
    if (error is! SocketException) {
      return const TransportFailure(
        'Tapikapp could not start listening on this network.',
      );
    }
    switch (error.osError?.errorCode) {
      case 48:
      case 98:
      case 10048:
        return TransportFailure(
          'Port $port is already in use. '
          'Is another copy of Tapikapp running?',
        );
      case 13:
      case 10013:
        return TransportFailure(
          'Tapikapp is not allowed to open port $port on this computer.',
        );
      default:
        return const TransportFailure(
          'Tapikapp could not start listening on this network.',
        );
    }
  }
}
