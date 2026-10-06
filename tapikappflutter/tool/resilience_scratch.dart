import 'dart:async';
import 'dart:io';

import 'package:tapikappflutter/core/protocol/codec.dart';
import 'package:tapikappflutter/core/protocol/packet.dart';
import 'package:tapikappflutter/services/security/agent_certificate.dart';
import 'package:tapikappflutter/services/security/pairing_guard.dart';
import 'package:tapikappflutter/services/server/agent_server.dart';
import 'package:tapikappflutter/services/transport/network_transport.dart';
import 'package:tapikappflutter/services/transport/transport.dart';

const String _phone = 'resilience-scratch-phone';

var _passed = 0;
var _failed = 0;

void _check(String label, Object? actual, Object? expected) {
  final ok = '$actual' == '$expected';
  ok ? _passed += 1 : _failed += 1;
  stdout.writeln('${ok ? 'PASS' : 'FAIL'}  $label');
  if (!ok) stdout.writeln('        expected $expected, got $actual');
}

Future<(int, int)> _freePorts() async {
  final a = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final b = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  final ports = (a.port, b.port);
  await a.close();
  b.close();
  return ports;
}

Future<void> main() async {
  stdout.writeln('generating the agent certificate…');
  final certificate = await AgentCertificate.generate('tapikapp-resilience');

  stdout.writeln('');
  stdout.writeln(
    'the laptop answers a keepalive and does not mistake it for input',
  );
  final ports = await _freePorts();
  final agent = AgentServer(
    certificate: certificate,
    guard: PairingGuard(trustedClients: const {_phone}),
    peerTimeout: const Duration(seconds: 1),
    tcpPort: ports.$1,
    udpPort: ports.$2,
  );
  final delivered = <Packet>[];
  agent.packets.listen(delivered.add);
  await agent.start();

  final phone = NetworkTransport(
    keepaliveInterval: const Duration(milliseconds: 200),
    peerTimeout: const Duration(seconds: 1),
  );
  await phone.connect(
    TransportEndpoint(
      clientId: _phone,
      host: InternetAddress.loopbackIPv4.address,
      tcpPort: ports.$1,
      udpPort: ports.$2,
      fingerprint: certificate.fingerprint,
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 400));
  _check('the phone is connected', phone.state, TransportState.connected);

  await Future<void>.delayed(const Duration(milliseconds: 1500));
  _check(
    'a quiet phone that keeps pinging is not dropped',
    phone.state,
    TransportState.connected,
  );
  _check('and its pings never reach the injector', delivered.length, 0);
  _check(
    'the laptop still reports it as connected',
    agent.state.hasClient,
    true,
  );

  phone.send(
    const KeyPacket(keyCode: 0x04, modifiers: KeyModifiers.none, down: true),
  );
  await Future<void>.delayed(const Duration(milliseconds: 300));
  _check('real input still arrives', delivered.length, 1);

  await phone.dispose();
  await agent.dispose();

  stdout.writeln('');
  stdout.writeln('a phone that vanishes is dropped, so nothing is left held');
  final deadPorts = await _freePorts();
  final lonely = AgentServer(
    certificate: certificate,
    guard: PairingGuard(trustedClients: const {_phone}),
    peerTimeout: const Duration(seconds: 1),
    tcpPort: deadPorts.$1,
    udpPort: deadPorts.$2,
  );
  final states = <AgentServerState>[];
  lonely.states.listen(states.add);
  await lonely.start();

  final socket = await SecureSocket.connect(
    InternetAddress.loopbackIPv4.address,
    deadPorts.$1,
    onBadCertificate: (_) => true,
  );
  socket.add(PacketCodec.encode(const PairPacket(PairStage.hello, _phone)));
  await socket.flush();
  await Future<void>.delayed(const Duration(milliseconds: 400));
  _check('the laptop has a paired phone', lonely.state.hasClient, true);

  await Future<void>.delayed(const Duration(milliseconds: 1800));
  _check(
    'a phone that stops talking is dropped',
    lonely.state.hasClient,
    false,
  );
  _check(
    'and the laptop is still listening for the next one',
    lonely.state.listening,
    true,
  );
  _check(
    'the drop is published, which is what releases held keys',
    states.any((s) => s.listening && !s.hasClient),
    true,
  );
  socket.destroy();
  await lonely.dispose();

  stdout.writeln('');
  stdout.writeln('a laptop that goes silent is given up on by the phone');
  final mutePorts = await _freePorts();
  final mute = await SecureServerSocket.bind(
    InternetAddress.loopbackIPv4,
    mutePorts.$1,
    SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(certificate.certificatePem.codeUnits)
      ..usePrivateKeyBytes(certificate.privateKeyPem.codeUnits),
  );
  mute.listen((socket) {
    unawaited(socket.done.catchError((Object _) => socket));
    socket.listen((_) {}, onError: (Object _) {});
    try {
      socket.add(PacketCodec.encode(const PairPacket(PairStage.codeRequired)));
      socket.add(PacketCodec.encode(const PairPacket(PairStage.accepted)));
    } catch (_) {}
  }, onError: (Object _) {});
  final patient = NetworkTransport(
    keepaliveInterval: const Duration(milliseconds: 200),
    peerTimeout: const Duration(milliseconds: 800),
  );
  final seen = <TransportState>[];
  patient.states.listen(seen.add);
  await patient.connect(
    TransportEndpoint(
      clientId: _phone,
      host: InternetAddress.loopbackIPv4.address,
      tcpPort: mutePorts.$1,
      udpPort: mutePorts.$2,
      fingerprint: certificate.fingerprint,
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 400));
  _check('the phone connects', patient.state, TransportState.connected);
  await Future<void>.delayed(const Duration(milliseconds: 1600));
  _check(
    'then gives up when the laptop never answers',
    patient.state,
    TransportState.disconnected,
  );
  _check(
    'and says so, so the UI can react',
    seen.last,
    TransportState.disconnected,
  );
  await patient.dispose();
  await mute.close();

  stdout.writeln('');
  stdout.writeln('$_passed passed, $_failed failed');
  if (_failed > 0) exitCode = 1;
}
