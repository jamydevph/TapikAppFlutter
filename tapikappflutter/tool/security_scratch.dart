import 'dart:io';

import 'package:tapikappflutter/core/error/failure.dart';
import 'package:tapikappflutter/core/protocol/codec.dart';
import 'package:tapikappflutter/core/protocol/packet.dart';
import 'package:tapikappflutter/services/security/agent_certificate.dart';
import 'package:tapikappflutter/services/security/pairing_guard.dart';
import 'package:tapikappflutter/services/server/agent_server.dart';
import 'package:tapikappflutter/services/transport/network_transport.dart';
import 'package:tapikappflutter/services/transport/transport.dart';

const String _phone = 'security-scratch-phone';

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
  stdout.writeln('generating two independent agent certificates…');
  final mine = await AgentCertificate.generate('tapikapp-agent');
  final other = await AgentCertificate.generate('tapikapp-impostor');

  stdout.writeln('');
  stdout.writeln('fingerprints');
  _check(
    'a fingerprint is 64 hex chars (SHA-256)',
    mine.fingerprint.length,
    64,
  );
  _check(
    'it is lowercase hex',
    RegExp(r'^[0-9a-f]{64}$').hasMatch(mine.fingerprint),
    true,
  );
  _check(
    'the same certificate always hashes the same',
    AgentCertificate.fingerprintOfPem(mine.certificatePem),
    mine.fingerprint,
  );
  _check(
    'two certificates never share a fingerprint',
    mine.fingerprint == other.fingerprint,
    false,
  );
  _check(
    'the key is not the certificate',
    mine.privateKeyPem == mine.certificatePem,
    false,
  );
  _check(
    'the certificate is PEM',
    mine.certificatePem.startsWith('-----BEGIN CERTIFICATE-----'),
    true,
  );

  stdout.writeln('');
  stdout.writeln('pinning against a live TLS agent');
  final ports = await _freePorts();
  final agent = AgentServer(
    certificate: mine,
    guard: PairingGuard(trustedClients: const {_phone}),
    tcpPort: ports.$1,
    udpPort: ports.$2,
  );
  await agent.start();

  final trusting = NetworkTransport();
  await trusting.connect(
    TransportEndpoint(
      clientId: _phone,
      host: InternetAddress.loopbackIPv4.address,
      tcpPort: ports.$1,
      udpPort: ports.$2,
      fingerprint: mine.fingerprint,
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 400));
  _check(
    'the right fingerprint connects',
    trusting.state,
    TransportState.connected,
  );
  trusting.send(const PingPacket());
  await Future<void>.delayed(const Duration(milliseconds: 300));
  await trusting.disconnect();
  await trusting.dispose();

  final wrong = NetworkTransport();
  Object? refusal;
  try {
    await wrong.connect(
      TransportEndpoint(
        clientId: _phone,
        host: InternetAddress.loopbackIPv4.address,
        tcpPort: ports.$1,
        udpPort: ports.$2,
        fingerprint: other.fingerprint,
      ),
    );
  } catch (error) {
    refusal = error;
  }
  _check('a mismatched fingerprint is refused', refusal is Failure, true);
  _check(
    'and the phone is told the certificate changed',
    refusal is Failure && refusal.message.contains('certificate'),
    true,
  );
  _check(
    'and the transport is left disconnected',
    wrong.state,
    TransportState.disconnected,
  );
  await wrong.dispose();

  final unpinned = NetworkTransport();
  await unpinned.connect(
    TransportEndpoint(
      clientId: _phone,
      host: InternetAddress.loopbackIPv4.address,
      tcpPort: ports.$1,
      udpPort: ports.$2,
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 400));
  _check(
    'an unpinned first pairing is allowed',
    unpinned.state,
    TransportState.connected,
  );
  await unpinned.disconnect();
  await unpinned.dispose();
  await agent.dispose();

  stdout.writeln('');
  stdout.writeln('an unpaired phone cannot send input');
  final strictPorts = await _freePorts();
  var remembered = const <String>{};
  final strict = AgentServer(
    certificate: mine,
    guard: PairingGuard(trustedClients: const {}),
    rememberClients: (clients) async => remembered = clients,
    tcpPort: strictPorts.$1,
    udpPort: strictPorts.$2,
  );
  final delivered = <Packet>[];
  strict.packets.listen(delivered.add);
  await strict.start();

  final stranger = NetworkTransport();
  final verdicts = <TransportState>[];
  stranger.states.listen(verdicts.add);
  await stranger.connect(
    TransportEndpoint(
      clientId: 'stranger',
      host: InternetAddress.loopbackIPv4.address,
      tcpPort: strictPorts.$1,
      udpPort: strictPorts.$2,
      fingerprint: mine.fingerprint,
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 400));
  _check(
    'an unknown phone is held at pairing, not connected',
    stranger.state,
    TransportState.pairing,
  );
  _check('the agent is showing a code', strict.guard.visibleCode != null, true);
  _check(
    'the window has a code to display',
    strict.state.pairingCode,
    strict.guard.visibleCode,
  );
  _check(
    'an unpaired phone is not reported as connected',
    strict.state.client,
    null,
  );

  stranger.send(
    const KeyPacket(keyCode: 0x04, modifiers: KeyModifiers.none, down: true),
  );
  await Future<void>.delayed(const Duration(milliseconds: 300));
  _check('its keystrokes never reach the injector', delivered.length, 0);

  stranger.submitPairingCode('000000');
  await Future<void>.delayed(const Duration(milliseconds: 300));
  _check(
    'a wrong code does not pair it',
    stranger.state,
    TransportState.pairing,
  );

  stranger.submitPairingCode(strict.guard.visibleCode!);
  await Future<void>.delayed(const Duration(milliseconds: 400));
  _check('the right code pairs it', stranger.state, TransportState.connected);

  stranger.send(
    const KeyPacket(keyCode: 0x04, modifiers: KeyModifiers.none, down: true),
  );
  await Future<void>.delayed(const Duration(milliseconds: 300));
  _check('and now its keystrokes arrive', delivered.length, 1);
  _check('the phone is remembered for next time', remembered, {'stranger'});
  _check(
    'and is now reported as the connected phone',
    strict.state.client != null,
    true,
  );
  _check('with no code left on screen', strict.state.pairingCode, null);

  stdout.writeln('');
  stdout.writeln('the datagram port is not a way around the handshake');
  final raw = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  final paired = delivered.length;
  raw.send(
    PacketCodec.encode(
      const KeyPacket(keyCode: 0x05, modifiers: KeyModifiers.none, down: true),
    ),
    InternetAddress.loopbackIPv4,
    strictPorts.$2,
  );
  raw.send(
    PacketCodec.encode(const TextPacket('typed over udp')),
    InternetAddress.loopbackIPv4,
    strictPorts.$2,
  );
  raw.send(
    PacketCodec.encode(const PairPacket(PairStage.hello, 'udp-impostor')),
    InternetAddress.loopbackIPv4,
    strictPorts.$2,
  );
  await Future<void>.delayed(const Duration(milliseconds: 300));
  _check('keys and text over udp are dropped', delivered.length, paired);
  raw.send(
    PacketCodec.encode(const MovePacket(dx: 1, dy: 1)),
    InternetAddress.loopbackIPv4,
    strictPorts.$2,
  );
  await Future<void>.delayed(const Duration(milliseconds: 300));
  _check('motion over udp still arrives', delivered.length, paired + 1);
  raw.close();

  await stranger.dispose();
  await strict.dispose();

  stdout.writeln('');
  stdout.writeln('a datagram before pairing is dropped');
  final earlyPorts = await _freePorts();
  final early = AgentServer(
    certificate: mine,
    guard: PairingGuard(trustedClients: const {}),
    tcpPort: earlyPorts.$1,
    udpPort: earlyPorts.$2,
  );
  final earlyDelivered = <Packet>[];
  early.packets.listen(earlyDelivered.add);
  await early.start();
  final shouter = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  shouter.send(
    PacketCodec.encode(const MovePacket(dx: 40, dy: 40)),
    InternetAddress.loopbackIPv4,
    earlyPorts.$2,
  );
  await Future<void>.delayed(const Duration(milliseconds: 300));
  _check('motion from nobody moves nothing', earlyDelivered.length, 0);
  shouter.close();
  await early.dispose();

  stdout.writeln('');
  stdout.writeln('$_passed passed, $_failed failed');
  if (_failed > 0) exitCode = 1;
}
