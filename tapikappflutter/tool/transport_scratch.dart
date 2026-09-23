import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:tapikappflutter/core/error/failure.dart';
import 'package:tapikappflutter/core/protocol/codec.dart';
import 'package:tapikappflutter/core/protocol/packet.dart';
import 'package:tapikappflutter/core/protocol/packet_buffer.dart';
import 'package:tapikappflutter/services/transport/network_transport.dart';
import 'package:tapikappflutter/services/transport/transport.dart';

Future<void> main() async {
  final checks = <_Check>[];
  final agent = await _LoopbackAgent.start();
  final transport = NetworkTransport();
  final seenStates = <TransportState>[];
  final stateLog = transport.states.listen(seenStates.add);
  final received = <Packet>[];
  final incoming = transport.incoming.listen(received.add);

  await transport.connect(
    TransportEndpoint(
      host: InternetAddress.loopbackIPv4.address,
      tcpPort: agent.tcpPort,
      udpPort: agent.udpPort,
    ),
  );
  await _settle();
  checks.add(
    _Check(
      'connect walks disconnected to connected',
      seenStates.toString() ==
              [
                TransportState.connecting,
                TransportState.connected,
              ].toString() &&
          transport.state == TransportState.connected,
      '$seenStates',
    ),
  );

  const reliable = <Packet>[
    ButtonPacket(button: PointerButton.left, down: true),
    ButtonPacket(button: PointerButton.left, down: false),
    KeyPacket(keyCode: 36, modifiers: KeyModifiers(command: true), down: true),
    TextPacket('tapik 👋🏽 ñ'),
    PingPacket(),
  ];
  const motion = <Packet>[
    MovePacket(dx: 12, dy: -4),
    MovePacket(dx: Packet.minDelta, dy: Packet.maxDelta),
    ScrollPacket(dx: 0, dy: -3),
  ];
  for (final packet in [...reliable, ...motion]) {
    transport.send(packet);
  }
  await _settle();
  checks.add(
    _Check(
      'keys and clicks go over TCP',
      agent.tcpPackets.toString() == reliable.toString(),
      '${agent.tcpPackets.length} of ${reliable.length}',
    ),
  );
  checks.add(
    _Check(
      'motion goes over UDP',
      agent.udpPackets.toString() == motion.toString(),
      '${agent.udpPackets.length} of ${motion.length}',
    ),
  );

  const replies = <Packet>[
    TextPacket('agent says 안녕'),
    ButtonPacket(button: PointerButton.right, down: true),
    PingPacket(),
  ];
  final stream = <int>[
    for (final packet in replies) ...PacketCodec.encode(packet),
  ];
  agent.writeRaw(stream.sublist(0, 2));
  await _settle();
  final midway = received.length;
  agent.writeRaw(stream.sublist(2));
  await _settle();
  checks.add(
    _Check(
      'incoming frames survive a write split inside a frame',
      midway == 0 && received.toString() == replies.toString(),
      'after a 2-byte chunk $midway, total ${received.length}',
    ),
  );

  agent.writeRaw([0xFF, 0x00, PacketType.ping.code]);
  await _settle();
  checks.add(
    _Check(
      'incoming stream resyncs past junk',
      received.length == replies.length + 1 &&
          received.last == const PingPacket(),
      'last ${received.last}',
    ),
  );

  await transport.disconnect();
  await _settle();
  transport.send(const PingPacket());
  await _settle();
  checks.add(
    _Check(
      'disconnect is idempotent and mutes sends',
      transport.state == TransportState.disconnected &&
          seenStates.last == TransportState.disconnected &&
          agent.tcpPackets.length == reliable.length,
      '$seenStates',
    ),
  );

  checks.add(await _refusedConnection(transport));
  checks.add(await _serverHangUp(agent.udpPort));
  checks.add(await _overlappingConnects());
  checks.add(await _disconnectDuringConnect());
  checks.add(await _disposeDuringConnect());
  checks.add(await _invalidEndpoint());
  checks.add(await _ipv6Motion());
  checks.add(_bufferCap());

  await incoming.cancel();
  await stateLog.cancel();
  await transport.dispose();
  await agent.close();
  checks.add(
    _Check(
      'dispose closes the streams',
      transport.state == TransportState.disconnected,
      'state ${transport.state}',
    ),
  );

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

Future<int> _openSocketCount() async {
  final result = await Process.run('lsof', ['-p', '$pid']);
  return '${result.stdout}'
      .split('\n')
      .where((line) => line.contains('TCP') || line.contains('UDP'))
      .length;
}

Future<_Check> _overlappingConnects() async {
  final first = await _LoopbackAgent.start();
  final second = await _LoopbackAgent.start();
  final transport = NetworkTransport();
  final before = await _openSocketCount();
  final attempts = [
    transport.connect(
      TransportEndpoint(
        host: InternetAddress.loopbackIPv4.address,
        tcpPort: first.tcpPort,
        udpPort: first.udpPort,
      ),
    ),
    transport.connect(
      TransportEndpoint(
        host: InternetAddress.loopbackIPv4.address,
        tcpPort: second.tcpPort,
        udpPort: second.udpPort,
      ),
    ),
  ];
  await Future.wait(attempts);
  await _settle();
  await first.close();
  await _settle(rounds: 6);
  final survived = transport.state == TransportState.connected;
  transport.send(const PingPacket());
  await _settle();
  final delivered = second.tcpPackets.length;
  await transport.dispose();
  await second.close();
  await _settle();
  final after = await _openSocketCount();
  return _Check(
    'the loser of two overlapping connects is discarded',
    survived && delivered == 1 && after <= before,
    'live after the stale peer hung up: $survived, delivered $delivered, '
        'sockets $before -> $after',
  );
}

Future<_Check> _disconnectDuringConnect() async {
  final agent = await _LoopbackAgent.start();
  final transport = NetworkTransport();
  final attempt = transport.connect(
    TransportEndpoint(
      host: InternetAddress.loopbackIPv4.address,
      tcpPort: agent.tcpPort,
      udpPort: agent.udpPort,
    ),
  );
  await transport.disconnect();
  await attempt;
  await _settle();
  transport.send(const PingPacket());
  await _settle();
  final ok =
      transport.state == TransportState.disconnected &&
      agent.tcpPackets.isEmpty;
  await transport.dispose();
  await agent.close();
  return _Check(
    'disconnect during an in-flight connect wins',
    ok,
    'state ${transport.state}, delivered ${agent.tcpPackets.length}',
  );
}

Future<_Check> _disposeDuringConnect() async {
  final agent = await _LoopbackAgent.start();
  final transport = NetworkTransport();
  final before = await _openSocketCount();
  final attempt = transport.connect(
    TransportEndpoint(
      host: InternetAddress.loopbackIPv4.address,
      tcpPort: agent.tcpPort,
      udpPort: agent.udpPort,
    ),
  );
  await transport.dispose();
  await attempt;
  await _settle(rounds: 6);
  final after = await _openSocketCount();
  await agent.close();
  return _Check(
    'dispose during an in-flight connect leaks nothing',
    transport.state == TransportState.disconnected && after <= before,
    'state ${transport.state}, sockets $before -> $after',
  );
}

Future<_Check> _invalidEndpoint() async {
  final transport = NetworkTransport();
  final states = <TransportState>[];
  final log = transport.states.listen(states.add);
  Object? thrown;
  try {
    await transport.connect(
      TransportEndpoint(
        host: InternetAddress.loopbackIPv4.address,
        tcpPort: 99999,
        udpPort: 99999,
      ),
    );
  } catch (error) {
    thrown = error;
  }
  await _settle();
  final ok =
      thrown is TransportFailure &&
      transport.state == TransportState.disconnected &&
      states.last == TransportState.disconnected;
  await log.cancel();
  await transport.dispose();
  return _Check(
    'an invalid port fails as a TransportFailure, not a stuck connecting',
    ok,
    '${thrown.runtimeType} -> $states',
  );
}

Future<_Check> _ipv6Motion() async {
  ServerSocket? server;
  try {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv6, 0);
  } catch (_) {
    return const _Check('motion reaches an IPv6 peer', true, 'no IPv6 here');
  }
  final datagrams = await RawDatagramSocket.bind(
    InternetAddress.loopbackIPv6,
    0,
  );
  final seen = <Packet>[];
  datagrams.listen((event) {
    if (event != RawSocketEvent.read) return;
    final datagram = datagrams.receive();
    if (datagram == null) return;
    final packet = PacketCodec.decodeOne(datagram.data);
    if (packet != null) seen.add(packet);
  });
  server.listen((socket) => socket.listen((_) {}, onError: (Object _) {}));
  final transport = NetworkTransport();
  await transport.connect(
    TransportEndpoint(
      host: InternetAddress.loopbackIPv6.address,
      tcpPort: server.port,
      udpPort: datagrams.port,
    ),
  );
  transport.send(const MovePacket(dx: 9, dy: -9));
  await _settle();
  final ok = seen.length == 1 && seen.first == const MovePacket(dx: 9, dy: -9);
  await transport.dispose();
  datagrams.close();
  await server.close();
  return _Check(
    'motion reaches an IPv6 peer',
    ok,
    '${seen.length} datagram(s) decoded',
  );
}

Future<_Check> _refusedConnection(NetworkTransport transport) async {
  final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final deadPort = probe.port;
  await probe.close();
  Object? thrown;
  try {
    await transport.connect(
      TransportEndpoint(
        host: InternetAddress.loopbackIPv4.address,
        tcpPort: deadPort,
        udpPort: deadPort,
      ),
    );
  } catch (error) {
    thrown = error;
  }
  return _Check(
    'a refused connection surfaces a TransportFailure',
    thrown is TransportFailure &&
        transport.state == TransportState.disconnected,
    thrown is Failure ? thrown.message : '$thrown',
  );
}

Future<_Check> _serverHangUp(int udpPort) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final transport = NetworkTransport();
  final states = <TransportState>[];
  final log = transport.states.listen(states.add);
  server.listen((socket) => socket.destroy());
  await transport.connect(
    TransportEndpoint(
      host: InternetAddress.loopbackIPv4.address,
      tcpPort: server.port,
      udpPort: udpPort,
    ),
  );
  await _settle(rounds: 6);
  final ok =
      transport.state == TransportState.disconnected &&
      states.last == TransportState.disconnected;
  await log.cancel();
  await transport.dispose();
  await server.close();
  return _Check('a dropped socket reports disconnected', ok, '$states');
}

_Check _bufferCap() {
  final buffer = PacketBuffer(capacity: 8);
  final header = Uint8List.fromList([PacketType.text.code, 0xFF, 0xFF]);
  buffer.add(header);
  final held = buffer.length;
  buffer.add(Uint8List(32));
  return _Check(
    'the framing buffer refuses to grow past its cap',
    held == header.length && buffer.isEmpty,
    'held $held then ${buffer.length}',
  );
}

Future<void> _settle({int rounds = 3}) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
}

class _LoopbackAgent {
  _LoopbackAgent._(this._server, this._datagrams);

  static Future<_LoopbackAgent> start() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final datagrams = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final agent = _LoopbackAgent._(server, datagrams);
    server.listen(agent._onSocket);
    datagrams.listen(agent._onDatagram);
    return agent;
  }

  final ServerSocket _server;
  final RawDatagramSocket _datagrams;
  final PacketBuffer _buffer = PacketBuffer();
  final List<Packet> tcpPackets = [];
  final List<Packet> udpPackets = [];
  Socket? _client;

  int get tcpPort => _server.port;

  int get udpPort => _datagrams.port;

  void writeRaw(List<int> bytes) {
    _client?.add(bytes);
  }

  void _onSocket(Socket socket) {
    socket.setOption(SocketOption.tcpNoDelay, true);
    unawaited(socket.done.catchError((Object _) => socket));
    _client = socket;
    socket.listen(
      (chunk) => tcpPackets.addAll(_buffer.add(chunk)),
      onError: (Object _) {},
      onDone: () => _client = null,
    );
  }

  void _onDatagram(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _datagrams.receive();
    if (datagram == null) return;
    final packet = PacketCodec.decodeOne(datagram.data);
    if (packet != null) udpPackets.add(packet);
  }

  Future<void> close() async {
    _client?.destroy();
    _datagrams.close();
    await _server.close();
  }
}

class _Check {
  const _Check(this.name, this.ok, this.detail);

  final String name;
  final bool ok;
  final String detail;
}
