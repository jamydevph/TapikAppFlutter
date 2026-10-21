import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:tapikappflutter/core/error/failure.dart';
import 'package:tapikappflutter/core/protocol/codec.dart';
import 'package:tapikappflutter/core/protocol/packet.dart';
import 'package:tapikappflutter/core/protocol/packet_buffer.dart';
import 'package:tapikappflutter/services/security/agent_certificate.dart';
import 'package:tapikappflutter/services/security/datagram_seal.dart';
import 'package:tapikappflutter/services/security/laptop_id.dart';
import 'package:tapikappflutter/services/security/laptop_name.dart';
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

Future<SecureServerSocket> _lenientImpostor(
  AgentCertificate certificate, {
  bool askFirst = false,
  bool takeAnyCode = false,
}) async {
  final context = SecurityContext(withTrustedRoots: false)
    ..useCertificateChainBytes(utf8.encode(certificate.certificatePem))
    ..usePrivateKeyBytes(utf8.encode(certificate.privateKeyPem));
  final server = await SecureServerSocket.bind(
    InternetAddress.loopbackIPv4,
    0,
    context,
  );
  server.listen((socket) {
    unawaited(socket.done.catchError((Object _) => socket));
    final buffer = PacketBuffer();
    socket.listen(
      (chunk) {
        for (final packet in buffer.add(chunk)) {
          if (packet is PairPacket) {
            if (takeAnyCode) {
              socket.add(
                PacketCodec.encode(
                  PairPacket(
                    packet.stage == PairStage.code
                        ? PairStage.accepted
                        : PairStage.codeRequired,
                  ),
                ),
              );
              continue;
            }
            if (askFirst) {
              socket.add(
                PacketCodec.encode(const PairPacket(PairStage.codeRequired)),
              );
            }
            socket.add(
              PacketCodec.encode(const PairPacket(PairStage.accepted)),
            );
          }
        }
      },
      onError: (Object _) => socket.destroy(),
      onDone: socket.destroy,
    );
  }, onError: (Object _) {});
  return server;
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
  stdout.writeln('the laptop ID');
  final mineId = LaptopId.of(mine.fingerprint);
  _check(
    'it is four groups of four uppercase hex digits',
    RegExp(r'^[0-9A-F]{4}( [0-9A-F]{4}){3}$').hasMatch(mineId ?? ''),
    true,
  );
  _check(
    'it is the first 8 bytes of the fingerprint',
    mineId?.replaceAll(' ', '').toLowerCase(),
    mine.fingerprint.substring(0, 16),
  );
  _check(
    'another certificate gets another ID',
    LaptopId.of(other.fingerprint) == mineId,
    false,
  );
  _check('no fingerprint, no ID', LaptopId.of(null), null);
  _check(
    'a fingerprint too short for 8 bytes gives no ID',
    [LaptopId.of('4fa29c1b77e0d3'), LaptopId.of('')],
    [null, null],
  );
  _check(
    'a fingerprint that is not hex gives no ID',
    LaptopId.of('z' * 64),
    null,
  );

  stdout.writeln('');
  stdout.writeln('laptop names');
  String styled(String text, int digitBase, int letterBase) =>
      String.fromCharCodes([
        for (final unit in text.codeUnits)
          if (unit >= 0x30 && unit <= 0x39)
            digitBase + unit - 0x30
          else if (unit >= 0x41 && unit <= 0x5A)
            letterBase + unit - 0x41
          else
            unit,
      ]);
  const fakeId = '4FA2 9C1B 77E0 D35C';
  final note = String.fromCharCode(0x1F3B5);
  _check(
    'a plain name is kept as it is',
    LaptopName.plain("Diane's MacBook Pro"),
    "Diane's MacBook Pro",
  );
  _check(
    'an ID typed into the name is masked',
    LaptopName.plain('MacBook $fakeId'),
    'MacBook …',
  );
  _check(
    'an ID in bold math digits is masked',
    LaptopName.plain('MacBook ${styled(fakeId, 0x1D7CE, 0x41)}'),
    'MacBook …',
  );
  _check(
    'an ID in monospace digits and sans-serif letters is masked',
    LaptopName.plain('MacBook ${styled(fakeId, 0x1D7F6, 0x1D5A0)}'),
    'MacBook …',
  );
  _check(
    'an ID in segmented digits is masked',
    LaptopName.plain('MacBook ${styled(fakeId, 0x1FBF0, 0x41)}'),
    'MacBook …',
  );
  _check(
    'an ID with letterlike E and F is masked',
    LaptopName.plain(
      'MacBook 4${String.fromCharCode(0x2131)}A2 9C1B 77${String.fromCharCode(0x2130)}0 D35C',
    ),
    'MacBook …',
  );
  _check(
    'invisible characters between math digits do not hide an ID',
    LaptopName.plain(
      'MacBook ${styled(fakeId, 0x1D7CE, 0x41).replaceAll(' ', String.fromCharCode(0x200B))}',
    ),
    'MacBook …',
  );
  _check(
    'an emoji before an ID stays and the ID is masked',
    LaptopName.plain('$note MacBook $fakeId'),
    '$note MacBook …',
  );
  _check(
    'a lone math digit that is not an ID is kept',
    LaptopName.plain('Room ${styled('4', 0x1D7CE, 0x41)} $note'),
    'Room ${styled('4', 0x1D7CE, 0x41)} $note',
  );
  _check(
    'a name with nothing visible gives no name',
    LaptopName.plain(String.fromCharCodes([0x0007, 0x202E, 0x000A])),
    null,
  );
  _check(
    'an empty name is shown as the fallback',
    LaptopName.shown(String.fromCharCodes([0x0007, 0x202E])),
    LaptopName.fallback,
  );
  final long = LaptopName.plain('$note${'z' * 60}') ?? '';
  _check(
    'a long name is cut to the rune limit',
    [long.runes.length, long.endsWith('…'), long.startsWith(note)],
    [LaptopName.maxLength, true, true],
  );

  String swap(Map<String, int> letters) {
    var text = fakeId;
    letters.forEach((from, to) {
      text = text.replaceFirst(from, String.fromCharCode(to));
    });
    return text;
  }

  _check(
    'an ID with the letter O for zero is masked',
    LaptopName.plain('MacBook 4FA2 9C1B 77EO D35C'),
    'MacBook …',
  );
  _check(
    'an ID with a lowercase o for zero is masked',
    LaptopName.plain('MacBook 4FA2 9C1B 77Eo D35C'),
    'MacBook …',
  );
  _check(
    'an ID with I or l for one is masked',
    [
      LaptopName.plain('MacBook 4FA2 9CIB 77E0 D35C'),
      LaptopName.plain('MacBook 4FA2 9ClB 77E0 D35C'),
    ],
    ['MacBook …', 'MacBook …'],
  );
  _check(
    'an ID with Roman numeral C and D is masked',
    LaptopName.plain('MacBook ${swap({'C': 0x216D, 'D': 0x216E})}'),
    'MacBook …',
  );
  _check(
    'an ID with double-struck D, Cyrillic d or Greek O is masked',
    [
      LaptopName.plain('MacBook ${swap({'D': 0x2145})}'),
      LaptopName.plain('MacBook ${swap({'D': 0x0501})}'),
      LaptopName.plain('MacBook ${swap({'0': 0x039F})}'),
    ],
    ['MacBook …', 'MacBook …', 'MacBook …'],
  );
  _check(
    'a combining mark inside a group does not hide an ID',
    LaptopName.plain(
      'MacBook ${fakeId.replaceFirst('F', 'F${String.fromCharCode(0x0323)}')}',
    ),
    'MacBook …',
  );
  _check(
    'an emoji between groups does not hide an ID',
    LaptopName.plain('4FA2${note}9C1B tail'),
    '… tail',
  );
  _check(
    'ordinary words with l, o and I are kept',
    [
      LaptopName.plain('Dell Latitude'),
      LaptopName.plain('Official MacBook'),
      LaptopName.plain('Lobby iMac'),
    ],
    ['Dell Latitude', 'Official MacBook', 'Lobby iMac'],
  );
  _check(
    'all-caps words made of hex letters are kept when no real digit is in them',
    [
      LaptopName.plain('Office DEAD BEEF'),
      LaptopName.plain('CODE OFFICE'),
      LaptopName.plain('DADDIO DEBBIE'),
    ],
    ['Office DEAD BEEF', 'CODE OFFICE', 'DADDIO DEBBIE'],
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

  final lenient = await _lenientImpostor(other);
  final skipped = NetworkTransport();
  final skippedErrors = <Failure>[];
  skipped.pairingErrors.listen(skippedErrors.add);
  await skipped.connect(
    TransportEndpoint(
      clientId: _phone,
      host: InternetAddress.loopbackIPv4.address,
      tcpPort: lenient.port,
      udpPort: ports.$2,
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 500));
  _check(
    'a laptop that never asks for its code is refused on a first pairing',
    skipped.state,
    TransportState.disconnected,
  );
  _check(
    'and the phone is told why',
    skippedErrors.isNotEmpty &&
        skippedErrors.last.message.contains('without asking'),
    true,
  );
  await skipped.dispose();
  await lenient.close();

  final hasty = await _lenientImpostor(other, askFirst: true);
  final rushed = NetworkTransport();
  final rushedErrors = <Failure>[];
  final rushedStates = <TransportState>[];
  rushed.pairingErrors.listen(rushedErrors.add);
  rushed.states.listen(rushedStates.add);
  await rushed.connect(
    TransportEndpoint(
      clientId: _phone,
      host: InternetAddress.loopbackIPv4.address,
      tcpPort: hasty.port,
      udpPort: ports.$2,
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 500));
  _check(
    'a laptop that asks for its code then lets the phone in before it is '
    'typed is refused',
    rushed.state,
    TransportState.disconnected,
  );
  _check(
    'without ever reporting connected',
    rushedStates.contains(TransportState.connected),
    false,
  );
  _check(
    'and the phone is told why',
    rushedErrors.isNotEmpty &&
        rushedErrors.last.message.contains('without asking'),
    true,
  );
  await rushed.dispose();
  await hasty.close();

  final collector = await _lenientImpostor(other, takeAnyCode: true);
  final fooled = NetworkTransport();
  await fooled.connect(
    TransportEndpoint(
      clientId: _phone,
      host: InternetAddress.loopbackIPv4.address,
      tcpPort: collector.port,
      udpPort: ports.$2,
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 500));
  _check(
    'a fake laptop that asks for the code gets an unpinned phone to the '
    'code step',
    fooled.state,
    TransportState.pairing,
  );
  _check(
    'but the laptop ID the phone shows is not your laptop\'s',
    LaptopId.of(fooled.peerFingerprint) == mineId,
    false,
  );
  _check(
    'it is the ID of the certificate the fake presented',
    LaptopId.of(fooled.peerFingerprint),
    LaptopId.of(other.fingerprint),
  );
  await fooled.dispose();
  await collector.close();

  final chained = await _lenientImpostor(
    AgentCertificate(
      certificatePem:
          '''
${other.certificatePem.trim()}
${mine.certificatePem.trim()}
''',
      privateKeyPem: other.privateKeyPem,
    ),
    takeAnyCode: true,
  );
  final copied = NetworkTransport();
  await copied.connect(
    TransportEndpoint(
      clientId: _phone,
      host: InternetAddress.loopbackIPv4.address,
      tcpPort: chained.port,
      udpPort: ports.$2,
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 500));
  _check(
    'a fake that also sends your laptop\'s certificate in its chain still '
    'shows its own ID',
    LaptopId.of(copied.peerFingerprint),
    LaptopId.of(other.fingerprint),
  );
  await copied.dispose();
  final pinnedPhone = NetworkTransport();
  Object? chainRefusal;
  try {
    await pinnedPhone.connect(
      TransportEndpoint(
        clientId: _phone,
        host: InternetAddress.loopbackIPv4.address,
        tcpPort: chained.port,
        udpPort: ports.$2,
        fingerprint: mine.fingerprint,
      ),
    );
  } catch (error) {
    chainRefusal = error;
  }
  _check(
    'and a phone pinned to your laptop refuses it',
    [chainRefusal is Failure, pinnedPhone.state],
    [true, TransportState.disconnected],
  );
  await pinnedPhone.dispose();
  await chained.close();
  await agent.dispose();

  stdout.writeln('');
  stdout.writeln('a first pairing learns the certificate it was shown');
  final tofuPorts = await _freePorts();
  final tofuAgent = AgentServer(
    certificate: mine,
    guard: PairingGuard(trustedClients: const {}),
    tcpPort: tofuPorts.$1,
    udpPort: tofuPorts.$2,
  );
  await tofuAgent.start();
  final unpinned = NetworkTransport();
  await unpinned.connect(
    TransportEndpoint(
      clientId: _phone,
      host: InternetAddress.loopbackIPv4.address,
      tcpPort: tofuPorts.$1,
      udpPort: tofuPorts.$2,
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 400));
  _check(
    'an unpinned phone is asked for the code',
    unpinned.state,
    TransportState.pairing,
  );
  _check(
    'before the code is typed, the phone shows the same laptop ID as the '
    'laptop window',
    LaptopId.of(unpinned.peerFingerprint),
    LaptopId.of(tofuAgent.certificate.fingerprint),
  );
  unpinned.submitPairingCode(tofuAgent.guard.visibleCode!);
  await Future<void>.delayed(const Duration(milliseconds: 400));
  _check('typing it connects', unpinned.state, TransportState.connected);
  final captured = unpinned.peerFingerprint;
  _check(
    'and the phone learns the certificate it just trusted',
    captured,
    mine.fingerprint,
  );
  await unpinned.disconnect();
  _check(
    'which is forgotten when the link drops',
    unpinned.peerFingerprint,
    null,
  );
  await unpinned.dispose();

  final returning = NetworkTransport();
  await returning.connect(
    TransportEndpoint(
      clientId: _phone,
      host: InternetAddress.loopbackIPv4.address,
      tcpPort: tofuPorts.$1,
      udpPort: tofuPorts.$2,
      fingerprint: captured,
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 400));
  _check(
    'coming back with the learned fingerprint connects',
    returning.state,
    TransportState.connected,
  );
  await returning.disconnect();
  await returning.dispose();
  await tofuAgent.dispose();

  final impostor = AgentCertificate(
    certificatePem: other.certificatePem,
    privateKeyPem: other.privateKeyPem,
  );
  final swapPorts = await _freePorts();
  final swapped = AgentServer(
    certificate: impostor,
    guard: PairingGuard(trustedClients: const {_phone}),
    tcpPort: swapPorts.$1,
    udpPort: swapPorts.$2,
  );
  await swapped.start();
  final suspicious = NetworkTransport();
  Object? swapRefusal;
  try {
    await suspicious.connect(
      TransportEndpoint(
        clientId: _phone,
        host: InternetAddress.loopbackIPv4.address,
        tcpPort: swapPorts.$1,
        udpPort: swapPorts.$2,
        fingerprint: captured,
      ),
    );
  } catch (error) {
    swapRefusal = error;
  }
  _check(
    'a laptop that swapped certificates is refused',
    swapRefusal is Failure,
    true,
  );
  _check(
    'and no keystroke can be sent to it',
    suspicious.state,
    TransportState.disconnected,
  );
  await suspicious.dispose();
  await swapped.dispose();
  await agent.dispose();

  stdout.writeln('');
  stdout.writeln('revoking a laptop makes it forget the phone');
  final revokePorts = await _freePorts();
  var persisted = <String>{_phone};
  final revoked = AgentServer(
    certificate: mine,
    guard: PairingGuard(trustedClients: const {_phone}),
    rememberClients: (clients) async => persisted = clients,
    tcpPort: revokePorts.$1,
    udpPort: revokePorts.$2,
  );
  final revokedDelivered = <Packet>[];
  revoked.packets.listen(revokedDelivered.add);
  await revoked.start();
  final pinned = TransportEndpoint(
    clientId: _phone,
    host: InternetAddress.loopbackIPv4.address,
    tcpPort: revokePorts.$1,
    udpPort: revokePorts.$2,
    fingerprint: mine.fingerprint,
  );
  final leaving = NetworkTransport();
  await leaving.connect(pinned);
  await Future<void>.delayed(const Duration(milliseconds: 400));
  _check(
    'a trusted phone connects without a code',
    leaving.state,
    TransportState.connected,
  );
  await leaving.forget();
  await Future<void>.delayed(const Duration(milliseconds: 400));
  _check(
    'asking the laptop to forget it hangs up',
    leaving.state,
    TransportState.disconnected,
  );
  _check(
    'the laptop no longer trusts that phone',
    revoked.guard.trustedClients.contains(_phone),
    false,
  );
  _check('and saves that, so a restart keeps it', persisted.isEmpty, true);
  _check('the laptop drops the session too', revoked.state.client, null);
  _check(
    'the request to forget never reaches the injector',
    revokedDelivered.length,
    0,
  );
  await leaving.dispose();

  final back = NetworkTransport();
  await back.connect(pinned);
  await Future<void>.delayed(const Duration(milliseconds: 400));
  _check(
    'coming back after that needs the code again',
    back.state,
    TransportState.pairing,
  );
  await back.dispose();
  await revoked.dispose();

  stdout.writeln('');
  stdout.writeln(
    'a phone that lost its pin pairs again instead of being locked out',
  );
  final lostPorts = await _freePorts();
  var saved = <String>{_phone};
  final stale = AgentServer(
    certificate: mine,
    guard: PairingGuard(trustedClients: const {_phone}),
    rememberClients: (clients) async => saved = clients,
    tcpPort: lostPorts.$1,
    udpPort: lostPorts.$2,
  );
  await stale.start();
  final fresh = NetworkTransport();
  final freshErrors = <Failure>[];
  fresh.pairingErrors.listen(freshErrors.add);
  await fresh.connect(
    TransportEndpoint(
      clientId: _phone,
      host: InternetAddress.loopbackIPv4.address,
      tcpPort: lostPorts.$1,
      udpPort: lostPorts.$2,
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 400));
  _check(
    'a laptop that still trusts the phone asks for its code',
    fresh.state,
    TransportState.pairing,
  );
  _check('instead of letting it in and getting refused', freshErrors.length, 0);
  _check(
    'the laptop drops its old trust first',
    stale.guard.trustedClients.contains(_phone),
    false,
  );
  _check('and saves that', saved.isEmpty, true);
  fresh.submitPairingCode(stale.guard.visibleCode!);
  await Future<void>.delayed(const Duration(milliseconds: 400));
  _check(
    'typing the code pairs it again',
    fresh.state,
    TransportState.connected,
  );
  _check('and the laptop trusts it again', saved.contains(_phone), true);
  _check(
    'and the phone learns the certificate again',
    fresh.peerFingerprint,
    mine.fingerprint,
  );
  await fresh.dispose();
  await stale.dispose();

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
  _check(
    'unsigned motion from the phone\'s own address is dropped, since that '
    'address can be faked',
    delivered.length,
    paired,
  );
  final forger = DatagramSeal(DatagramSeal.newKey());
  raw.send(
    forger.seal(PacketCodec.encode(const MovePacket(dx: 2, dy: 2)))!,
    InternetAddress.loopbackIPv4,
    strictPorts.$2,
  );
  await Future<void>.delayed(const Duration(milliseconds: 300));
  _check(
    'motion signed with a key other than the session\'s is dropped',
    delivered.length,
    paired,
  );
  stranger.send(const MovePacket(dx: 3, dy: 3));
  await Future<void>.delayed(const Duration(milliseconds: 300));
  _check(
    'motion the paired phone signs with its session key arrives',
    delivered.length == paired + 1 &&
        delivered.last == const MovePacket(dx: 3, dy: 3),
    true,
  );
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
  stdout.writeln('signed motion datagrams');
  final sessionKey = DatagramSeal.newKey();
  final phoneSeal = DatagramSeal(sessionKey);
  final laptopSeal = DatagramSeal(sessionKey);
  final frame = PacketCodec.encode(const MovePacket(dx: 5, dy: -5));
  final first = phoneSeal.seal(frame)!;
  _check(
    'a signed datagram is the frame plus a 4-byte counter and a 16-byte tag',
    first.length,
    frame.length + DatagramSeal.overhead,
  );
  _check(
    'the laptop opens it back to the same frame',
    PacketCodec.decodeOne(laptopSeal.open(first)!),
    const MovePacket(dx: 5, dy: -5),
  );
  _check('the same datagram replayed is dropped', laptopSeal.open(first), null);
  final second = phoneSeal.seal(frame)!;
  final third = phoneSeal.seal(frame)!;
  _check('a newer one opens', laptopSeal.open(third) != null, true);
  _check(
    'an older one that arrives late is dropped',
    laptopSeal.open(second),
    null,
  );
  final tampered = Uint8List.fromList(phoneSeal.seal(frame)!);
  tampered[2] ^= 0x01;
  _check('a changed byte is dropped', laptopSeal.open(tampered), null);
  final counterBumped = Uint8List.fromList(phoneSeal.seal(frame)!);
  counterBumped[frame.length + 3] ^= 0x01;
  _check('a changed counter is dropped', laptopSeal.open(counterBumped), null);
  _check(
    'a datagram cut short is dropped',
    laptopSeal.open(Uint8List.sublistView(phoneSeal.seal(frame)!, 0, 10)),
    null,
  );
  _check(
    'another session\'s key cannot open it',
    DatagramSeal(DatagramSeal.newKey()).open(phoneSeal.seal(frame)!),
    null,
  );
  _check(
    'every session gets a fresh key',
    DatagramSeal.encodeKey(DatagramSeal.newKey()) ==
        DatagramSeal.encodeKey(DatagramSeal.newKey()),
    false,
  );
  _check(
    'the key survives the trip inside the accepted reply',
    DatagramSeal.decodeKey(DatagramSeal.encodeKey(sessionKey)),
    sessionKey,
  );
  _check(
    'a missing or short key is refused',
    [
      DatagramSeal.decodeKey(''),
      DatagramSeal.decodeKey('c2hvcnQ='),
      DatagramSeal.decodeKey('not base64!'),
    ],
    [null, null, null],
  );

  stdout.writeln('');
  stdout.writeln('$_passed passed, $_failed failed');
  if (_failed > 0) exitCode = 1;
}
