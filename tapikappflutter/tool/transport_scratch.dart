import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:tapikappflutter/core/error/failure.dart';
import 'package:tapikappflutter/core/protocol/codec.dart';
import 'package:tapikappflutter/core/protocol/packet.dart';
import 'package:tapikappflutter/core/protocol/packet_buffer.dart';
import 'package:tapikappflutter/services/input/pointer_pump.dart';
import 'package:tapikappflutter/services/security/agent_certificate.dart';
import 'package:tapikappflutter/services/security/datagram_seal.dart';
import 'package:tapikappflutter/services/transport/network_transport.dart';
import 'package:tapikappflutter/services/transport/transport.dart';

const String _toolClient = 'tapikapp-dev-tool';
const String _toolCode = '424242';

late final AgentCertificate _certificate;
DatagramSeal? _toolSeal;

NetworkTransport _phone() {
  final transport = NetworkTransport();
  transport.codeRequests.listen((_) => transport.submitPairingCode(_toolCode));
  return transport;
}

void _answerPairing(Socket socket, PairPacket packet) {
  if (packet.stage == PairStage.introduce || packet.stage == PairStage.resume) {
    socket.add(PacketCodec.encode(const PairPacket(PairStage.codeRequired)));
  } else if (packet.stage == PairStage.code && packet.detail == _toolCode) {
    final key = DatagramSeal.newKey();
    _toolSeal = DatagramSeal(key);
    socket.add(
      PacketCodec.encode(
        PairPacket(PairStage.accepted, DatagramSeal.encodeKey(key)),
      ),
    );
  }
}

Packet? _openDatagram(Uint8List data) {
  final frame = _toolSeal?.open(data);
  return frame == null ? null : PacketCodec.decodeOne(frame);
}

Future<void> main() async {
  await runZonedGuarded(_run, (error, _) {
    if (error is SocketException) return;
    stdout.writeln('UNEXPECTED  $error');
    exitCode = 1;
  });
}

Future<void> _run() async {
  stdout.writeln('generating a loopback certificate…');
  _certificate = await AgentCertificate.generate('tapikapp-loopback');
  final checks = <_Check>[];
  final agent = await _LoopbackAgent.start();
  final transport = _phone();
  final seenStates = <TransportState>[];
  final stateLog = transport.states.listen(seenStates.add);
  final received = <Packet>[];
  final incoming = transport.incoming.listen(received.add);

  await transport.connect(
    TransportEndpoint(
      clientId: _toolClient,
      host: InternetAddress.loopbackIPv4.address,
      tcpPort: agent.tcpPort,
      udpPort: agent.udpPort,
    ),
  );
  await _settle();
  checks.add(
    _Check(
      'connect walks connecting -> pairing -> connected',
      seenStates.toString() ==
              [
                TransportState.connecting,
                TransportState.pairing,
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
    ButtonPacket(button: PointerButton.middle, down: true),
  ];
  const motion = <Packet>[
    MovePacket(dx: 12, dy: -4),
    MovePacket(dx: Packet.minDelta, dy: Packet.maxDelta),
    ScrollPacket(dx: 0, dy: -3),
  ];
  for (final packet in reliable) {
    transport.send(packet);
  }
  for (final packet in motion) {
    transport.send(packet);
    await Future<void>.delayed(PointerPump.nominalFrame);
  }
  await _settle();
  checks.add(
    _Check(
      'keys and clicks go over TCP',
      _samePackets(agent.tcpPackets, reliable),
      '${agent.tcpPackets.length} of ${reliable.length}',
    ),
  );
  checks.add(
    _Check(
      'motion goes over UDP',
      _samePackets(agent.udpPackets, motion),
      '${agent.udpPackets.length} of ${motion.length}',
    ),
  );

  const replies = <Packet>[
    TextPacket('agent says 안녕'),
    ButtonPacket(button: PointerButton.right, down: true),
    ButtonPacket(button: PointerButton.middle, down: false),
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
      midway == 0 && _samePackets(received, replies),
      'after a 2-byte chunk $midway, total ${received.length}',
    ),
  );

  agent.writeRaw([
    0xFF,
    0x00,
    ...PacketCodec.encode(
      const ButtonPacket(button: PointerButton.middle, down: true),
    ),
  ]);
  await _settle();
  checks.add(
    _Check(
      'incoming stream resyncs past junk',
      received.length == replies.length + 1 &&
          received.last ==
              const ButtonPacket(button: PointerButton.middle, down: true),
      'last ${received.last}',
    ),
  );

  await transport.disconnect();
  await _settle();
  transport.send(const ButtonPacket(button: PointerButton.middle, down: true));
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
  checks.addAll(await _overlappingConnects());
  checks.add(await _disconnectDuringConnect());
  checks.addAll(await _disposeDuringConnect());
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
  var skipped = 0;
  for (final check in checks) {
    final status = check.skipped ? 'SKIP' : (check.ok ? 'PASS' : 'FAIL');
    stdout.writeln('$status  ${check.name}  ${check.detail}');
    if (check.skipped) {
      skipped += 1;
    } else if (!check.ok) {
      failed += 1;
    }
  }
  stdout.writeln(
    '${checks.length - failed - skipped}/${checks.length} checks passed'
    '${skipped == 0 ? '' : ', $skipped skipped'}',
  );
  if (failed > 0) exitCode = 1;
  await _settle(rounds: 3);
}

Future<int?> _openSocketCount() async {
  final ProcessResult result;
  try {
    result = Platform.isWindows
        ? await Process.run('netstat', ['-ano'])
        : await Process.run('lsof', ['-p', '$pid']);
  } on ProcessException {
    return null;
  }
  if (result.exitCode != 0) return null;
  final lines = '${result.stdout}'.split('\n');
  if (!Platform.isWindows) {
    return lines
        .where((line) => line.contains('TCP') || line.contains('UDP'))
        .length;
  }
  return lines.where((line) {
    final fields = line.trim().split(RegExp(r'\s+'));
    return (fields.first == 'TCP' || fields.first == 'UDP') &&
        fields.last == '$pid';
  }).length;
}

_Check _leakCheck(String name, int? before, int? after) {
  if (before == null || after == null) {
    return _Check(
      name,
      false,
      'no lsof or netstat to count sockets on ${Platform.operatingSystem}',
      skipped: true,
    );
  }
  return _Check(name, after <= before, 'sockets $before -> $after');
}

Future<List<_Check>> _overlappingConnects() async {
  final first = await _LoopbackAgent.start();
  final second = await _LoopbackAgent.start();
  final transport = _phone();
  final before = await _openSocketCount();
  final attempts = [
    transport.connect(
      TransportEndpoint(
        clientId: _toolClient,
        host: InternetAddress.loopbackIPv4.address,
        tcpPort: first.tcpPort,
        udpPort: first.udpPort,
      ),
    ),
    transport.connect(
      TransportEndpoint(
        clientId: _toolClient,
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
  transport.send(const ButtonPacket(button: PointerButton.middle, down: true));
  await _settle();
  final delivered = second.tcpPackets.length;
  await transport.dispose();
  await second.close();
  await _settle();
  final after = await _openSocketCount();
  return [
    _Check(
      'the loser of two overlapping connects is discarded',
      survived && delivered == 1,
      'live after the stale peer hung up: $survived, delivered $delivered',
    ),
    _leakCheck('overlapping connects leak no sockets', before, after),
  ];
}

Future<_Check> _disconnectDuringConnect() async {
  final agent = await _LoopbackAgent.start();
  final transport = _phone();
  final attempt = transport.connect(
    TransportEndpoint(
      clientId: _toolClient,
      host: InternetAddress.loopbackIPv4.address,
      tcpPort: agent.tcpPort,
      udpPort: agent.udpPort,
    ),
  );
  await transport.disconnect();
  await attempt;
  await _settle();
  transport.send(const ButtonPacket(button: PointerButton.middle, down: true));
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

Future<List<_Check>> _disposeDuringConnect() async {
  final agent = await _LoopbackAgent.start();
  final transport = _phone();
  final before = await _openSocketCount();
  final attempt = transport.connect(
    TransportEndpoint(
      clientId: _toolClient,
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
  return [
    _Check(
      'dispose during an in-flight connect ends disconnected',
      transport.state == TransportState.disconnected,
      'state ${transport.state}',
    ),
    _leakCheck(
      'dispose during an in-flight connect leaks nothing',
      before,
      after,
    ),
  ];
}

Future<_Check> _invalidEndpoint() async {
  final transport = _phone();
  final states = <TransportState>[];
  final log = transport.states.listen(states.add);
  Object? thrown;
  try {
    await transport.connect(
      TransportEndpoint(
        clientId: _toolClient,
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
  SecureServerSocket? server;
  try {
    server = await SecureServerSocket.bind(
      InternetAddress.loopbackIPv6,
      0,
      _LoopbackAgent._context(),
    );
  } catch (_) {
    return const _Check(
      'motion reaches an IPv6 peer',
      false,
      'no IPv6 here',
      skipped: true,
    );
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
    final packet = _openDatagram(datagram.data);
    if (packet != null) seen.add(packet);
  });
  final handshake = PacketBuffer();
  server.listen(
    (socket) => socket.listen(
      (chunk) {
        for (final packet in handshake.add(chunk)) {
          if (packet is PairPacket) _answerPairing(socket, packet);
        }
      },
      onError: (Object _) => socket.destroy(),
      onDone: socket.destroy,
    ),
  );
  final transport = _phone();
  await transport.connect(
    TransportEndpoint(
      clientId: _toolClient,
      host: InternetAddress.loopbackIPv6.address,
      tcpPort: server.port,
      udpPort: datagrams.port,
    ),
  );
  await _settle();
  transport.send(const MovePacket(dx: 9, dy: -9));
  await _settle();
  final ok = seen.length == 1 && seen.first == const MovePacket(dx: 9, dy: -9);
  await transport.dispose();
  await _settle(rounds: 2);
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
        clientId: _toolClient,
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
  final server = await SecureServerSocket.bind(
    InternetAddress.loopbackIPv4,
    0,
    _LoopbackAgent._context(),
  );
  final transport = _phone();
  final states = <TransportState>[];
  final log = transport.states.listen(states.add);
  server.listen((socket) => socket.destroy());
  Failure? refused;
  try {
    await transport.connect(
      TransportEndpoint(
        clientId: _toolClient,
        host: InternetAddress.loopbackIPv4.address,
        tcpPort: server.port,
        udpPort: udpPort,
      ),
    );
  } on Failure catch (failure) {
    refused = failure;
  }
  await _settle(rounds: 6);
  final ok =
      transport.state == TransportState.disconnected &&
      states.last == TransportState.disconnected;
  await log.cancel();
  await transport.dispose();
  await server.close();
  return _Check(
    'a dropped socket reports disconnected',
    ok,
    '$states${refused == null ? '' : ' after ${refused.message}'}',
  );
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
    final server = await SecureServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      _context(),
    );
    final datagrams = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final agent = _LoopbackAgent._(server, datagrams);
    server.listen(agent._onSocket);
    datagrams.listen(agent._onDatagram);
    return agent;
  }

  final SecureServerSocket _server;
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
      (chunk) {
        for (final packet in _buffer.add(chunk)) {
          if (packet is PairPacket) {
            _answerPairing(socket, packet);
            continue;
          }
          tcpPackets.add(packet);
        }
      },
      onError: (Object _) => socket.destroy(),
      onDone: () {
        socket.destroy();
        _client = null;
      },
    );
  }

  static SecurityContext _context() {
    return SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(utf8.encode(_certificate.certificatePem))
      ..usePrivateKeyBytes(utf8.encode(_certificate.privateKeyPem));
  }

  void _onDatagram(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _datagrams.receive();
    if (datagram == null) return;
    final packet = _openDatagram(datagram.data);
    if (packet != null) udpPackets.add(packet);
  }

  Future<void> close() async {
    _client?.destroy();
    _datagrams.close();
    await _server.close();
  }
}

class _Check {
  const _Check(this.name, this.ok, this.detail, {this.skipped = false});

  final String name;
  final bool ok;
  final String detail;
  final bool skipped;
}

bool _samePackets(List<Packet> actual, List<Packet> expected) {
  if (actual.length != expected.length) return false;
  for (var i = 0; i < actual.length; i++) {
    if (actual[i] != expected[i]) return false;
  }
  return true;
}
