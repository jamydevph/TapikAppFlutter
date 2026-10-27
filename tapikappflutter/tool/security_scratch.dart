import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:tapikappflutter/core/error/failure.dart';
import 'package:tapikappflutter/core/protocol/codec.dart';
import 'package:tapikappflutter/core/protocol/packet.dart';
import 'package:tapikappflutter/core/protocol/packet_buffer.dart';
import 'package:tapikappflutter/core/protocol/pair_detail.dart';
import 'package:tapikappflutter/services/security/agent_certificate.dart';
import 'package:tapikappflutter/services/security/datagram_seal.dart';
import 'package:tapikappflutter/services/security/laptop_id.dart';
import 'package:tapikappflutter/services/security/laptop_name.dart';
import 'package:tapikappflutter/services/security/paired_phone.dart';
import 'package:tapikappflutter/services/security/pairing_guard.dart';
import 'package:tapikappflutter/services/security/reconnect_secret.dart';
import 'package:tapikappflutter/services/security/spake2.dart';
import 'package:tapikappflutter/services/server/agent_server.dart';
import 'package:tapikappflutter/services/transport/network_transport.dart';
import 'package:tapikappflutter/services/transport/transport.dart';

const String _phone = 'security-scratch-phone';
const String _secret = 'scratch-secret';

Map<String, String> _trust(Set<String> ids) => {
  for (final id in ids) id: ReconnectSecret.hash(_secret),
};

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
                    packet.stage == PairStage.spakeShare
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

Future<SecureServerSocket> _relayImpostor(
  AgentCertificate certificate,
  int realPort,
  List<PairPacket> overheard,
) async {
  final server = await SecureServerSocket.bind(
    InternetAddress.loopbackIPv4,
    0,
    SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(utf8.encode(certificate.certificatePem))
      ..usePrivateKeyBytes(utf8.encode(certificate.privateKeyPem)),
  );
  server.listen((phone) async {
    unawaited(phone.done.catchError((Object _) => phone));
    final laptop = await SecureSocket.connect(
      InternetAddress.loopbackIPv4,
      realPort,
      onBadCertificate: (_) => true,
    );
    unawaited(laptop.done.catchError((Object _) => laptop));
    final fromPhone = PacketBuffer();
    final fromLaptop = PacketBuffer();
    phone.listen(
      (chunk) {
        overheard.addAll(fromPhone.add(chunk).whereType<PairPacket>());
        laptop.add(chunk);
      },
      onError: (Object _) => laptop.destroy(),
      onDone: laptop.destroy,
    );
    laptop.listen(
      (chunk) {
        overheard.addAll(fromLaptop.add(chunk).whereType<PairPacket>());
        phone.add(chunk);
      },
      onError: (Object _) => phone.destroy(),
      onDone: phone.destroy,
    );
  }, onError: (Object _) {});
  return server;
}

Future<SecureServerSocket> _recordingImpostor(
  AgentCertificate certificate,
  List<PairPacket> heard,
) async {
  final server = await SecureServerSocket.bind(
    InternetAddress.loopbackIPv4,
    0,
    SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(utf8.encode(certificate.certificatePem))
      ..usePrivateKeyBytes(utf8.encode(certificate.privateKeyPem)),
  );
  server.listen((socket) {
    unawaited(socket.done.catchError((Object _) => socket));
    final buffer = PacketBuffer();
    socket.listen(
      (chunk) => heard.addAll(buffer.add(chunk).whereType<PairPacket>()),
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
    guard: PairingGuard(trustedClients: _trust({_phone})),
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
      secret: _secret,
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
  final fooledErrors = <String>[];
  fooled.pairingErrors.listen((failure) => fooledErrors.add(failure.message));
  fooled.submitPairingCode('123456');
  await Future<void>.delayed(const Duration(milliseconds: 400));
  _check(
    'a fake that skips the code check and just says accepted is refused',
    [fooled.state, fooled.issuedSecret, fooledErrors.isNotEmpty],
    [TransportState.disconnected, null, true],
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
        secret: _secret,
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
    guard: PairingGuard(trustedClients: _trust({})),
    tcpPort: tofuPorts.$1,
    udpPort: tofuPorts.$2,
  );
  await tofuAgent.start();
  tofuAgent.openPairing();
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
  final issued = unpinned.issuedSecret;
  _check(
    'and gets the reconnect secret the laptop now trusts',
    [
      issued != null,
      tofuAgent.guard.trustedClients[_phone] ==
          ReconnectSecret.hash(issued ?? ''),
    ],
    [true, true],
  );
  _check(
    'pairing on the laptop closes once the phone is in',
    tofuAgent.state.isPairingOpen,
    false,
  );
  await unpinned.disconnect();
  _check(
    'which are both forgotten when the link drops',
    [unpinned.peerFingerprint, unpinned.issuedSecret],
    [null, null],
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
      secret: issued,
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 400));
  _check(
    'coming back with the learned fingerprint and secret connects, '
    'with pairing closed',
    [returning.state, tofuAgent.state.isPairingOpen],
    [TransportState.connected, false],
  );
  await returning.disconnect();
  await returning.dispose();

  final replayer = NetworkTransport();
  final replayErrors = <Failure>[];
  replayer.pairingErrors.listen(replayErrors.add);
  await replayer.connect(
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
    'someone who learned only the phone id is not let in',
    [replayer.state, replayErrors.lastOrNull?.message],
    [TransportState.disconnected, PairingGuard.pairingClosed],
  );
  await replayer.dispose();

  final oldHello = await SecureSocket.connect(
    InternetAddress.loopbackIPv4.address,
    tofuPorts.$1,
    onBadCertificate: (_) => true,
  );
  final helloReplies = PacketBuffer();
  final helloSeen = <Packet>[];
  oldHello.listen(
    (bytes) => helloSeen.addAll(helloReplies.add(bytes)),
    onError: (Object _) {},
  );
  oldHello.add(PacketCodec.encode(const PairPacket(PairStage.hello, _phone)));
  await oldHello.flush();
  await Future<void>.delayed(const Duration(milliseconds: 400));
  _check(
    'and a v3 hello with that id is refused outright',
    [
      helloSeen.whereType<PairPacket>().map((p) => p.stage).toList(),
      tofuAgent.state.hasClient,
    ],
    [
      [PairStage.rejected],
      false,
    ],
  );
  oldHello.destroy();
  await tofuAgent.dispose();

  final impostor = AgentCertificate(
    certificatePem: other.certificatePem,
    privateKeyPem: other.privateKeyPem,
  );
  final swapPorts = await _freePorts();
  final swapped = AgentServer(
    certificate: impostor,
    guard: PairingGuard(trustedClients: _trust({_phone})),
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
  var persisted = _trust({_phone});
  final revoked = AgentServer(
    certificate: mine,
    guard: PairingGuard(trustedClients: _trust({_phone})),
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
    secret: _secret,
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
    revoked.guard.trustedClients.containsKey(_phone),
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

  final turnedAway = NetworkTransport();
  await turnedAway.connect(pinned);
  await Future<void>.delayed(const Duration(milliseconds: 400));
  _check(
    'coming back after that is turned away while pairing is closed',
    turnedAway.state,
    TransportState.disconnected,
  );
  await turnedAway.dispose();

  revoked.openPairing();
  final back = NetworkTransport();
  await back.connect(pinned);
  await Future<void>.delayed(const Duration(milliseconds: 400));
  _check(
    'and needs the code again once pairing is open',
    back.state,
    TransportState.pairing,
  );
  await back.dispose();
  await revoked.dispose();

  final unsavedRevoke = AgentServer(
    certificate: mine,
    guard: PairingGuard(trustedClients: _trust({_phone})),
    rememberClients: (_) async => throw const DataFailure('disk full'),
    tcpPort: revokePorts.$1,
    udpPort: revokePorts.$2,
  );
  await unsavedRevoke.start();
  final leavingAgain = NetworkTransport();
  await leavingAgain.connect(pinned);
  await Future<void>.delayed(const Duration(milliseconds: 400));
  _check(
    'before a phone asks to be forgotten, nothing is flagged as unsaved',
    [leavingAgain.state, unsavedRevoke.state.forgetUnsaved],
    [TransportState.connected, false],
  );
  await leavingAgain.forget();
  await Future<void>.delayed(const Duration(milliseconds: 400));
  _check(
    'if saving a phone’s own forget fails, the window warns instead of '
    'staying quiet',
    [
      unsavedRevoke.guard.trustedClients.containsKey(_phone),
      unsavedRevoke.state.forgetUnsaved,
    ],
    [false, true],
  );
  await leavingAgain.dispose();
  await unsavedRevoke.dispose();

  stdout.writeln('');
  stdout.writeln(
    'a phone that lost its pin pairs again instead of being locked out',
  );
  final lostPorts = await _freePorts();
  var saved = _trust({_phone});
  final stale = AgentServer(
    certificate: mine,
    guard: PairingGuard(trustedClients: _trust({_phone})),
    rememberClients: (clients) async => saved = clients,
    tcpPort: lostPorts.$1,
    udpPort: lostPorts.$2,
  );
  await stale.start();
  stale.openPairing();
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
    'the old trust stays until the code is typed, so introducing cannot '
    'un-pair a phone',
    [stale.guard.trustedClients[_phone], saved[_phone]],
    [ReconnectSecret.hash(_secret), ReconnectSecret.hash(_secret)],
  );
  fresh.submitPairingCode(stale.guard.visibleCode!);
  await Future<void>.delayed(const Duration(milliseconds: 400));
  _check(
    'typing the code pairs it again',
    fresh.state,
    TransportState.connected,
  );
  _check(
    'and the laptop saves the new secret in place of the old one',
    saved[_phone],
    ReconnectSecret.hash(fresh.issuedSecret ?? ''),
  );
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
  var remembered = const <String, String>{};
  final strict = AgentServer(
    certificate: mine,
    guard: PairingGuard(trustedClients: _trust({})),
    rememberClients: (clients) async => remembered = clients,
    tcpPort: strictPorts.$1,
    udpPort: strictPorts.$2,
  );
  final delivered = <Packet>[];
  strict.packets.listen(delivered.add);
  await strict.start();
  strict.openPairing();

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
      secret: _secret,
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
  _check('the phone is remembered for next time', remembered.keys.toList(), [
    'stranger',
  ]);
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
    guard: PairingGuard(trustedClients: _trust({})),
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
    PacketCodec.decodeOne(laptopSeal.open(first)!) ==
        const MovePacket(dx: 5, dy: -5),
    true,
  );
  _check('the same datagram replayed is dropped', laptopSeal.open(first), null);
  final second = phoneSeal.seal(frame)!;
  final third = phoneSeal.seal(frame)!;
  _check('a newer one opens', laptopSeal.open(third) != null, true);
  _check(
    'an older one that arrives late still opens, so its motion is kept',
    laptopSeal.open(second) != null,
    true,
  );
  _check(
    'but that late one replayed is dropped',
    laptopSeal.open(second),
    null,
  );
  final tooOld = phoneSeal.seal(frame)!;
  for (var i = 0; i < DatagramSeal.replayWindow; i++) {
    laptopSeal.open(phoneSeal.seal(frame)!);
  }
  _check(
    'one that falls more than ${DatagramSeal.replayWindow} behind is dropped',
    laptopSeal.open(tooOld),
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
  stdout.writeln('the laptop can forget every phone at once');
  final wipePorts = await _freePorts();
  var wipeSaved = _trust({_phone, 'second-phone'});
  var wipeSaves = 0;
  final wiping = AgentServer(
    certificate: mine,
    guard: PairingGuard(trustedClients: _trust({_phone, 'second-phone'})),
    rememberClients: (clients) async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      wipeSaves += 1;
      wipeSaved = clients;
    },
    tcpPort: wipePorts.$1,
    udpPort: wipePorts.$2,
  );
  await wiping.start();
  _check(
    'the laptop reports how many phones it trusts',
    wiping.state.pairedPhones,
    2,
  );
  final fromScratch = NetworkTransport();
  await fromScratch.connect(
    TransportEndpoint(
      clientId: 'second-phone',
      host: InternetAddress.loopbackIPv4.address,
      tcpPort: wipePorts.$1,
      udpPort: wipePorts.$2,
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 400));
  _check(
    'an introduction alone no longer drops a phone from the count',
    [wiping.state.pairedPhones, wipeSaves],
    [2, 0],
  );
  await fromScratch.dispose();
  await Future<void>.delayed(const Duration(milliseconds: 300));
  final wipeEndpoint = TransportEndpoint(
    clientId: _phone,
    host: InternetAddress.loopbackIPv4.address,
    tcpPort: wipePorts.$1,
    udpPort: wipePorts.$2,
    fingerprint: mine.fingerprint,
    secret: _secret,
  );
  final wipedPhone = NetworkTransport();
  await wipedPhone.connect(wipeEndpoint);
  await Future<void>.delayed(const Duration(milliseconds: 400));
  _check(
    'a trusted phone is connected without a code',
    wipedPhone.state,
    TransportState.connected,
  );
  await wiping.forgetAllPhones();
  _check(
    'forgetting all phones finishes only once the cleared list is saved',
    [wipeSaved.isEmpty, wipeSaves],
    [true, 1],
  );
  await Future<void>.delayed(const Duration(milliseconds: 400));
  _check(
    'it leaves none trusted, and the count says so',
    [wiping.guard.trustedClients.isEmpty, wiping.state.pairedPhones],
    [true, 0],
  );
  _check(
    'the connected phone is dropped on both ends',
    [wiping.state.hasClient, wipedPhone.state],
    [false, TransportState.disconnected],
  );
  await wipedPhone.dispose();
  wiping.openPairing();
  final returningPhone = NetworkTransport();
  await returningPhone.connect(wipeEndpoint);
  await Future<void>.delayed(const Duration(milliseconds: 400));
  final shownCode = wiping.guard.visibleCode;
  _check(
    'coming back, it is asked for the code instead of let in',
    [returningPhone.state, shownCode != null],
    [TransportState.pairing, true],
  );
  await wiping.forgetAllPhones();
  await Future<void>.delayed(const Duration(milliseconds: 300));
  _check(
    'forgetting again does not cut off a phone that is typing its code',
    [returningPhone.state, wiping.guard.visibleCode == shownCode],
    [TransportState.pairing, true],
  );
  _check('and saves again, so a save that failed can be retried', wipeSaves, 2);
  await returningPhone.dispose();
  await wiping.dispose();

  var unsavedAttempts = 0;
  final unsaved = AgentServer(
    certificate: mine,
    guard: PairingGuard(trustedClients: _trust({_phone})),
    rememberClients: (_) async {
      unsavedAttempts += 1;
      if (unsavedAttempts == 1) throw const DataFailure('disk full');
    },
    tcpPort: wipePorts.$1,
    udpPort: wipePorts.$2,
  );
  Object? saveError;
  try {
    await unsaved.forgetAllPhones();
  } catch (error) {
    saveError = error;
  }
  _check(
    'a save that fails is passed on, not swallowed',
    saveError is DataFailure,
    true,
  );
  _check(
    'and the laptop remembers it is unsaved, so the window keeps the button '
    'and a warning even with no phones trusted',
    [unsaved.state.forgetUnsaved, unsaved.state.pairedPhones],
    [true, 0],
  );
  await unsaved.forgetAllPhones();
  _check(
    'trying again clears the warning once the save works',
    [unsaved.state.forgetUnsaved, unsavedAttempts],
    [false, 2],
  );
  await unsaved.dispose();

  stdout.writeln('');
  stdout.writeln('the laptop can forget one phone and keep the rest');
  var oneSaved = _trust({_phone, 'second-phone'});
  var oneHistory = <PairedPhone>[];
  final single = AgentServer(
    certificate: mine,
    guard: PairingGuard(
      trustedClients: _trust({_phone, 'second-phone'}),
      history: [
        PairedPhone(
          id: 'second-phone',
          pairedAt: DateTime(2026, 10, 3),
          lastSeenAt: DateTime(2026, 10, 19),
        ),
      ],
    ),
    rememberClients: (clients) async => oneSaved = clients,
    rememberHistory: (phones) async => oneHistory = phones,
    tcpPort: wipePorts.$1,
    udpPort: wipePorts.$2,
  );
  await single.start();
  _check(
    'phones are listed newest pairing first, older pairings last',
    single.phones.map((phone) => phone.id).join(','),
    'second-phone,$_phone',
  );
  final keptPhone = NetworkTransport();
  await keptPhone.connect(wipeEndpoint);
  await Future<void>.delayed(const Duration(milliseconds: 400));
  _check(
    'the window learns which paired phone is the connected one',
    [keptPhone.state, single.state.phoneId],
    [TransportState.connected, _phone],
  );
  _check(
    'and connecting counts as seen, and is saved',
    [
      single.phones.firstWhere((phone) => phone.id == _phone).lastSeenAt !=
          null,
      oneHistory.any((phone) => phone.id == _phone && phone.lastSeenAt != null),
    ],
    [true, true],
  );
  await single.forgetPhone('second-phone');
  await Future<void>.delayed(const Duration(milliseconds: 300));
  _check(
    'forgetting another phone leaves the connected one alone',
    [keptPhone.state, single.state.hasClient],
    [TransportState.connected, true],
  );
  _check(
    'and saves the trust without it',
    [oneSaved.length, oneSaved.containsKey(_phone), single.state.pairedPhones],
    [1, true, 1],
  );
  _check(
    'its dates are dropped too',
    oneHistory.any((phone) => phone.id == 'second-phone'),
    false,
  );
  await single.forgetPhone('not-paired');
  _check(
    'forgetting a phone that is not paired changes nothing',
    [oneSaved.length, single.state.hasClient],
    [1, true],
  );
  await single.forgetPhone(_phone);
  await Future<void>.delayed(const Duration(milliseconds: 400));
  _check(
    'forgetting the connected phone drops it on both ends',
    [single.state.hasClient, keptPhone.state],
    [false, TransportState.disconnected],
  );
  _check(
    'and leaves none trusted',
    [oneSaved.isEmpty, single.state.pairedPhones, single.state.phoneId],
    [true, 0, null],
  );
  await keptPhone.dispose();
  await single.dispose();

  final stubborn = AgentServer(
    certificate: mine,
    guard: PairingGuard(
      trustedClients: _trust({_phone, 'second-phone'}),
      history: [PairedPhone(id: 'second-phone', pairedAt: DateTime(2026, 9))],
    ),
    rememberClients: (_) async => throw const DataFailure('disk full'),
    tcpPort: wipePorts.$1,
    udpPort: wipePorts.$2,
  );
  Object? oneError;
  try {
    await stubborn.forgetPhone('second-phone');
  } catch (error) {
    oneError = error;
  }
  _check(
    'a failed save for one phone is passed on, not swallowed',
    oneError is DataFailure,
    true,
  );
  _check(
    'and that phone stays paired with its dates, so its row and Forget stay',
    [
      stubborn.state.pairedPhones,
      stubborn.phones.first ==
          PairedPhone(id: 'second-phone', pairedAt: DateTime(2026, 9)),
    ],
    [2, true],
  );
  await stubborn.dispose();

  var raceSaves = 0;
  final racing = AgentServer(
    certificate: mine,
    guard: PairingGuard(trustedClients: _trust({_phone, 'second-phone'})),
    rememberClients: (_) async {
      raceSaves += 1;
      if (raceSaves > 1) return;
      await Future<void>.delayed(const Duration(milliseconds: 200));
      throw const DataFailure('disk full');
    },
    tcpPort: wipePorts.$1,
    udpPort: wipePorts.$2,
  );
  final slowForget = racing.forgetPhone('second-phone');
  await racing.forgetAllPhones();
  Object? lateError;
  try {
    await slowForget;
  } catch (error) {
    lateError = error;
  }
  _check(
    'a forget whose save fails after Forget all phones worked does not '
    'bring that phone back',
    [
      lateError is DataFailure,
      racing.guard.trustedClients.isEmpty,
      racing.state.pairedPhones,
    ],
    [true, true, 0],
  );
  await racing.dispose();

  Future<AgentServer> overlap({required bool laterSaveWorks}) async {
    var saves = 0;
    final server = AgentServer(
      certificate: mine,
      guard: PairingGuard(trustedClients: _trust({_phone, 'b', 'c'})),
      rememberClients: (_) async {
        saves += 1;
        final first = saves == 1;
        await Future<void>.delayed(Duration(milliseconds: first ? 200 : 50));
        if (first || !laterSaveWorks) throw const DataFailure('disk full');
      },
      tcpPort: wipePorts.$1,
      udpPort: wipePorts.$2,
    );
    final forgetB = server.forgetPhone('b');
    final forgetC = server.forgetPhone('c');
    for (final pending in [forgetC, forgetB]) {
      try {
        await pending;
      } catch (_) {}
    }
    return server;
  }

  final bothFail = await overlap(laterSaveWorks: false);
  _check(
    'when two forgets overlap and both saves fail, the window warns that '
    'they were not saved instead of quietly dropping one',
    [
      bothFail.state.forgetUnsaved,
      bothFail.guard.trustedClients.containsKey('b'),
      bothFail.guard.trustedClients.containsKey('c'),
    ],
    [true, false, true],
  );
  await bothFail.dispose();
  final laterWorks = await overlap(laterSaveWorks: true);
  _check(
    'but no warning shows once a later save without that phone has worked',
    [laterWorks.state.forgetUnsaved, laterWorks.guard.trustedClients.length],
    [false, 1],
  );
  await laterWorks.dispose();

  stdout.writeln('');
  stdout.writeln('each session gets its own key from the laptop');
  final keyPorts = await _freePorts();
  final keyed = AgentServer(
    certificate: mine,
    guard: PairingGuard(trustedClients: _trust({_phone})),
    peerTimeout: const Duration(seconds: 1),
    tcpPort: keyPorts.$1,
    udpPort: keyPorts.$2,
  );
  final keyedDelivered = <Packet>[];
  keyed.packets.listen(keyedDelivered.add);
  await keyed.start();
  final motion = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  void sendMotion(Uint8List datagram) {
    motion.send(datagram, InternetAddress.loopbackIPv4, keyPorts.$2);
  }

  final firstSession = await _rawPhone(keyPorts.$1);
  final firstSeal = DatagramSeal(firstSession.key);
  sendMotion(
    firstSeal.seal(PacketCodec.encode(const MovePacket(dx: 1, dy: 1)))!,
  );
  await Future<void>.delayed(const Duration(milliseconds: 300));
  _check(
    'motion signed with the key the laptop just handed over arrives',
    keyedDelivered.length == 1 &&
        keyedDelivered.single == const MovePacket(dx: 1, dy: 1),
    true,
  );
  final heldBack = firstSeal.seal(
    PacketCodec.encode(const MovePacket(dx: 4, dy: 4)),
  )!;
  firstSession.socket.destroy();
  await Future<void>.delayed(const Duration(milliseconds: 300));
  final secondSession = await _rawPhone(keyPorts.$1);
  _check(
    'the next session gets a different key',
    DatagramSeal.encodeKey(secondSession.key) ==
        DatagramSeal.encodeKey(firstSession.key),
    false,
  );
  sendMotion(heldBack);
  await Future<void>.delayed(const Duration(milliseconds: 300));
  _check(
    'a datagram signed in the earlier session is dropped in the next one',
    keyedDelivered.length,
    1,
  );

  for (var i = 0; i < 12; i++) {
    sendMotion(
      forger.seal(PacketCodec.encode(const MovePacket(dx: 1, dy: 0)))!,
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  _check(
    'forged datagrams do not keep a quiet session alive',
    keyed.state.hasClient,
    false,
  );
  secondSession.socket.destroy();
  await Future<void>.delayed(const Duration(milliseconds: 300));

  final thirdSession = await _rawPhone(keyPorts.$1);
  final thirdSeal = DatagramSeal(thirdSession.key);
  for (var i = 0; i < 12; i++) {
    sendMotion(
      thirdSeal.seal(PacketCodec.encode(const MovePacket(dx: 1, dy: 0)))!,
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  _check('signed datagrams do keep it alive', keyed.state.hasClient, true);
  thirdSession.socket.destroy();
  motion.close();
  await keyed.dispose();

  stdout.writeln('');
  stdout.writeln('a second "accepted" in the same session');
  final firstKey = DatagramSeal.newKey();
  final doubler = await SecureServerSocket.bind(
    InternetAddress.loopbackIPv4,
    0,
    SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(utf8.encode(other.certificatePem))
      ..usePrivateKeyBytes(utf8.encode(other.privateKeyPem)),
  );
  final doublerMotion = await RawDatagramSocket.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  final doublerSeal = DatagramSeal(firstKey);
  final doublerSeen = <Packet>[];
  doublerMotion.listen((event) {
    if (event != RawSocketEvent.read) return;
    final datagram = doublerMotion.receive();
    if (datagram == null) return;
    final frame = doublerSeal.open(datagram.data);
    final packet = frame == null ? null : PacketCodec.decodeOne(frame);
    if (packet != null) doublerSeen.add(packet);
  });
  doubler.listen((socket) {
    unawaited(socket.done.catchError((Object _) => socket));
    socket.listen(
      (_) {},
      onError: (Object _) => socket.destroy(),
      onDone: socket.destroy,
    );
    socket.add(
      PacketCodec.encode(
        PairPacket(PairStage.accepted, DatagramSeal.encodeKey(firstKey)),
      ),
    );
    socket.add(
      PacketCodec.encode(
        PairPacket(
          PairStage.accepted,
          DatagramSeal.encodeKey(DatagramSeal.newKey()),
        ),
      ),
    );
  }, onError: (Object _) {});
  final steady = NetworkTransport();
  await steady.connect(
    TransportEndpoint(
      clientId: _phone,
      host: InternetAddress.loopbackIPv4.address,
      tcpPort: doubler.port,
      udpPort: doublerMotion.port,
      fingerprint: other.fingerprint,
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 400));
  steady.send(const MovePacket(dx: 7, dy: 7));
  await Future<void>.delayed(const Duration(milliseconds: 300));
  _check(
    'does not swap the key the phone signs motion with',
    steady.state == TransportState.connected &&
        doublerSeen.length == 1 &&
        doublerSeen.single == const MovePacket(dx: 7, dy: 7),
    true,
  );
  await steady.dispose();
  doublerMotion.close();
  await doubler.close();

  stdout.writeln('');
  stdout.writeln('a laptop that accepts without handing over a key');
  final keyless = await _lenientImpostor(other);
  final outdated = NetworkTransport();
  final outdatedErrors = <Failure>[];
  final outdatedStates = <TransportState>[];
  outdated.pairingErrors.listen(outdatedErrors.add);
  outdated.states.listen(outdatedStates.add);
  await outdated.connect(
    TransportEndpoint(
      clientId: _phone,
      host: InternetAddress.loopbackIPv4.address,
      tcpPort: keyless.port,
      udpPort: keyPorts.$2,
      fingerprint: other.fingerprint,
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 500));
  _check(
    'is refused, and the phone never reports connected',
    [outdated.state, outdatedStates.contains(TransportState.connected)],
    [TransportState.disconnected, false],
  );
  _check(
    'and the phone is told the laptop needs updating',
    outdatedErrors.isNotEmpty && outdatedErrors.last is VersionFailure,
    true,
  );
  await outdated.dispose();
  await keyless.close();

  stdout.writeln('');
  stdout.writeln('the reconnect secret only ever goes to the pinned laptop');
  final overheard = <PairPacket>[];
  final eavesdropper = await _recordingImpostor(other, overheard);
  final careful = NetworkTransport();
  Object? carefulRefusal;
  try {
    await careful.connect(
      TransportEndpoint(
        clientId: _phone,
        host: InternetAddress.loopbackIPv4.address,
        tcpPort: eavesdropper.port,
        fingerprint: mine.fingerprint,
        secret: _secret,
      ),
    );
  } catch (error) {
    carefulRefusal = error;
  }
  await Future<void>.delayed(const Duration(milliseconds: 300));
  _check(
    'a laptop with the wrong certificate hears nothing, not even the id',
    [carefulRefusal is Failure, overheard.length],
    [true, 0],
  );
  await careful.dispose();
  final newcomer = NetworkTransport();
  await newcomer.connect(
    TransportEndpoint(
      clientId: 'fresh-link-id',
      host: InternetAddress.loopbackIPv4.address,
      tcpPort: eavesdropper.port,
      secret: _secret,
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 300));
  _check(
    'a phone with no pin only introduces itself, with no secret',
    overheard.map((p) => [p.stage, p.detail]).toList(),
    [
      [PairStage.introduce, PairDetail.introduce('fresh-link-id')],
    ],
  );
  await newcomer.dispose();
  await eavesdropper.close();

  stdout.writeln('');
  stdout.writeln('the pairing window on the laptop');
  final windowPorts = await _freePorts();
  final windowed = AgentServer(
    certificate: mine,
    guard: PairingGuard(
      trustedClients: _trust({}),
      pairingWindow: const Duration(milliseconds: 700),
    ),
    tcpPort: windowPorts.$1,
    udpPort: windowPorts.$2,
  );
  final windowStates = <AgentServerState>[];
  windowed.states.listen(windowStates.add);
  windowed.openPairing();
  _check(
    'pairing cannot be opened before the agent listens',
    windowed.state.isPairingOpen,
    false,
  );
  await windowed.start();
  windowed.openPairing();
  _check(
    'opening pairing is published with its end time',
    windowed.state.pairingOpenUntil != null,
    true,
  );
  final waiter = NetworkTransport();
  final waiterErrors = <String>[];
  waiter.pairingErrors.listen((failure) => waiterErrors.add(failure.message));
  await waiter.connect(
    TransportEndpoint(
      clientId: 'window-phone',
      host: InternetAddress.loopbackIPv4.address,
      tcpPort: windowPorts.$1,
      udpPort: windowPorts.$2,
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 200));
  _check(
    'a new phone gets a code while it is open',
    [waiter.state, windowed.state.pairingCode != null],
    [TransportState.pairing, true],
  );
  await Future<void>.delayed(const Duration(milliseconds: 900));
  _check(
    'when the window runs out, the code goes and the waiting phone is let go',
    [
      windowed.state.isPairingOpen,
      windowed.state.pairingCode,
      waiter.state,
      waiterErrors.lastOrNull,
    ],
    [false, null, TransportState.disconnected, PairingGuard.pairingClosed],
  );
  await waiter.dispose();
  windowed.openPairing();
  final stopper = NetworkTransport();
  final stopperErrors = <String>[];
  stopper.pairingErrors.listen((failure) => stopperErrors.add(failure.message));
  await stopper.connect(
    TransportEndpoint(
      clientId: 'window-phone',
      host: InternetAddress.loopbackIPv4.address,
      tcpPort: windowPorts.$1,
      udpPort: windowPorts.$2,
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 200));
  windowed.closePairing();
  await Future<void>.delayed(const Duration(milliseconds: 200));
  _check(
    'Stop pairing also lets go of a phone that is waiting for its code',
    [windowed.state.isPairingOpen, stopper.state, stopperErrors.lastOrNull],
    [false, TransportState.disconnected, PairingGuard.pairingClosed],
  );
  await stopper.dispose();
  await windowed.stop();
  await Future<void>.delayed(const Duration(milliseconds: 100));
  _check(
    'stopping the agent closes pairing',
    [windowed.state.isPairingOpen, windowStates.last.isPairingOpen],
    [false, false],
  );
  await windowed.dispose();

  final capPorts = await _freePorts();
  final capped = AgentServer(
    certificate: mine,
    guard: PairingGuard(trustedClients: _trust({})),
    tcpPort: capPorts.$1,
    udpPort: capPorts.$2,
  );
  await capped.start();
  capped.openPairing();
  final guesses = <String>[];
  for (var i = 0; i < PairingGuard.defaultMaxWrongCodesPerWindow; i++) {
    final guesser = NetworkTransport();
    guesser.pairingErrors.listen((failure) => guesses.add(failure.message));
    await guesser.connect(
      TransportEndpoint(
        clientId: 'guesser-$i',
        host: InternetAddress.loopbackIPv4.address,
        tcpPort: capPorts.$1,
        udpPort: capPorts.$2,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    guesser.submitPairingCode('999999');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await guesser.dispose();
  }
  await Future<void>.delayed(const Duration(milliseconds: 100));
  _check(
    'five wrong codes over five connections stop pairing and say so',
    [
      capped.state.isPairingOpen,
      capped.state.pairingStopped,
      guesses.contains(PairingGuard.pairingStoppedReason),
    ],
    [false, true, true],
  );
  capped.openPairing();
  _check(
    'opening it again clears the stop',
    capped.state.pairingStopped,
    false,
  );
  await capped.dispose();

  final busyPorts = await _freePorts();
  final busy = AgentServer(
    certificate: mine,
    guard: PairingGuard(trustedClients: _trust({_phone})),
    tcpPort: busyPorts.$1,
    udpPort: busyPorts.$2,
  );
  await busy.start();
  busy.openPairing();
  final owner = NetworkTransport();
  await owner.connect(
    TransportEndpoint(
      clientId: _phone,
      host: InternetAddress.loopbackIPv4.address,
      tcpPort: busyPorts.$1,
      udpPort: busyPorts.$2,
      fingerprint: mine.fingerprint,
      secret: _secret,
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 300));
  _check(
    'a paired phone reconnecting closes an open pairing window',
    [owner.state, busy.state.isPairingOpen],
    [TransportState.connected, false],
  );
  final latecomer = NetworkTransport();
  final latecomerErrors = <String>[];
  latecomer.pairingErrors.listen(
    (failure) => latecomerErrors.add(failure.message),
  );
  await latecomer.connect(
    TransportEndpoint(
      clientId: 'second-phone',
      host: InternetAddress.loopbackIPv4.address,
      tcpPort: busyPorts.$1,
      udpPort: busyPorts.$2,
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 300));
  _check(
    'a second phone is told the laptop is busy instead of hanging up silently',
    [latecomer.state, latecomerErrors.lastOrNull, owner.state],
    [
      TransportState.disconnected,
      AgentServer.phoneAlreadyConnected,
      TransportState.connected,
    ],
  );
  await latecomer.dispose();
  await owner.dispose();
  await busy.dispose();

  final retryPorts = await _freePorts();
  final retrying = AgentServer(
    certificate: mine,
    guard: PairingGuard(
      trustedClients: _trust({}),
      handshakeTimeout: const Duration(seconds: 1),
      codeLifetime: const Duration(seconds: 2),
      pairingWindow: const Duration(milliseconds: 1500),
      maxWrongCodesPerWindow: 2,
    ),
    tcpPort: retryPorts.$1,
    udpPort: retryPorts.$2,
  );
  await retrying.start();
  retrying.openPairing();
  final typist = NetworkTransport();
  var asked = 0;
  final typistErrors = <Failure>[];
  typist.codeRequests.listen((_) => asked += 1);
  typist.pairingErrors.listen(typistErrors.add);
  await typist.connect(
    TransportEndpoint(
      clientId: 'typist',
      host: InternetAddress.loopbackIPv4.address,
      tcpPort: retryPorts.$1,
      udpPort: retryPorts.$2,
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 200));
  typist.submitPairingCode('999999');
  await Future<void>.delayed(const Duration(milliseconds: 200));
  _check(
    'a wrong code is answered with the reason and a fresh request for the '
    'code, so the phone asks again',
    [asked, typistErrors.lastOrNull?.message, typist.state],
    [2, NetworkTransport.laptopNotConfirmed, TransportState.pairing],
  );
  typist.submitPairingCode('999999');
  await Future<void>.delayed(const Duration(milliseconds: 200));
  _check(
    'the last allowed wrong code stops pairing without asking again',
    [asked, typistErrors.lastOrNull?.message, typist.state],
    [2, PairingGuard.pairingStoppedReason, TransportState.disconnected],
  );
  await Future<void>.delayed(const Duration(milliseconds: 1600));
  _check(
    'the stop stays on the laptop after the window would have ended',
    [retrying.state.pairingStopped, retrying.state.isPairingOpen],
    [true, false],
  );
  await typist.dispose();
  retrying.openPairing();
  final slow = NetworkTransport();
  final slowErrors = <Failure>[];
  slow.pairingErrors.listen(slowErrors.add);
  await slow.connect(
    TransportEndpoint(
      clientId: 'slow-typist',
      host: InternetAddress.loopbackIPv4.address,
      tcpPort: retryPorts.$1,
      udpPort: retryPorts.$2,
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 1300));
  _check(
    'a phone still on the code page after the handshake timeout keeps its code',
    slow.state,
    TransportState.pairing,
  );
  await Future<void>.delayed(const Duration(milliseconds: 1800));
  _check(
    'and when the code runs out it is told why before the laptop hangs up',
    [slow.state, slowErrors.map((f) => f.message).toList()],
    [
      TransportState.disconnected,
      [PairingGuard.pairingClosed],
    ],
  );
  await slow.dispose();
  await retrying.dispose();

  stdout.writeln('');
  stdout.writeln('a fake laptop relaying to the real one learns nothing');
  final relayPorts = await _freePorts();
  final relayed = AgentServer(
    certificate: mine,
    guard: PairingGuard(trustedClients: _trust({})),
    tcpPort: relayPorts.$1,
    udpPort: relayPorts.$2,
  );
  await relayed.start();
  relayed.openPairing();
  final relayHeard = <PairPacket>[];
  final relay = await _relayImpostor(other, relayPorts.$1, relayHeard);
  final victim = NetworkTransport();
  final victimErrors = <String>[];
  var victimAsked = 0;
  victim.pairingErrors.listen((failure) => victimErrors.add(failure.message));
  victim.codeRequests.listen((_) => victimAsked += 1);
  await victim.connect(
    TransportEndpoint(
      clientId: 'relayed-phone',
      host: InternetAddress.loopbackIPv4.address,
      tcpPort: relay.port,
      udpPort: relayPorts.$2,
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 400));
  final realCode = relayed.guard.visibleCode;
  _check(
    'the relay gets the real laptop to show a code',
    [realCode != null, victim.state],
    [true, TransportState.pairing],
  );
  victim.submitPairingCode(realCode ?? '');
  await Future<void>.delayed(const Duration(milliseconds: 600));
  _check(
    'typing the real code through the relay does not pair, and the phone '
    'says why and asks again',
    [
      victim.state,
      victimErrors.lastOrNull,
      victimAsked,
      relayed.guard.trustedClients.isEmpty,
    ],
    [TransportState.pairing, NetworkTransport.laptopNotConfirmed, 2, true],
  );
  _check(
    'the code itself never crosses the wire, and nothing is accepted',
    [
      relayHeard.any((packet) => packet.detail.contains(realCode ?? '-')),
      relayHeard.any((packet) => packet.stage == PairStage.accepted),
      relayHeard.any((packet) => packet.stage == PairStage.code),
    ],
    [false, false, false],
  );
  await victim.dispose();
  await relay.close();
  await relayed.dispose();

  final quitPorts = await _freePorts();
  final quitting = AgentServer(
    certificate: mine,
    guard: PairingGuard(
      trustedClients: _trust({}),
      pairingWindow: const Duration(milliseconds: 1200),
      maxWrongCodesPerWindow: 1,
    ),
    tcpPort: quitPorts.$1,
    udpPort: quitPorts.$2,
  );
  await quitting.start();
  quitting.openPairing();
  final quitter = await SecureSocket.connect(
    InternetAddress.loopbackIPv4,
    quitPorts.$1,
    onBadCertificate: (_) => true,
  );
  unawaited(quitter.done.catchError((Object _) => quitter));
  quitter.listen((_) {}, onError: (Object _) {});
  quitter.add(
    PacketCodec.encode(
      PairPacket(PairStage.introduce, PairDetail.introduce('quitter')),
    ),
  );
  final guess = Spake2.phone(
    code: '000000',
    phoneId: 'quitter',
    laptopFingerprint: mine.fingerprint,
  );
  quitter.add(
    PacketCodec.encode(
      PairPacket(PairStage.spakeShare, Spake2.encode(guess.share)),
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 300));
  quitter.destroy();
  await Future<void>.delayed(const Duration(milliseconds: 300));
  final stoppedEarly = quitting.state.pairingStopped;
  await Future<void>.delayed(const Duration(milliseconds: 1200));
  _check(
    'a phone that hangs up on its last allowed guess stops pairing, and the '
    'stop outlives the window',
    [stoppedEarly, quitting.state.pairingStopped, quitting.state.isPairingOpen],
    [true, true, false],
  );
  await quitting.dispose();

  stdout.writeln('');
  stdout.writeln('$_passed passed, $_failed failed');
  if (_failed > 0) exitCode = 1;
}

Future<({SecureSocket socket, Uint8List key})> _rawPhone(int port) async {
  final socket = await SecureSocket.connect(
    InternetAddress.loopbackIPv4,
    port,
    onBadCertificate: (_) => true,
  );
  unawaited(socket.done.catchError((Object _) => socket));
  final buffer = PacketBuffer();
  final key = Completer<Uint8List>();
  socket.listen(
    (chunk) {
      for (final packet in buffer.add(chunk)) {
        if (packet is! PairPacket || packet.stage != PairStage.accepted) {
          continue;
        }
        final received = DatagramSeal.decodeKey(packet.detail);
        if (received != null && !key.isCompleted) key.complete(received);
      }
    },
    onError: (Object _) {},
    cancelOnError: true,
  );
  socket.add(
    PacketCodec.encode(
      PairPacket(PairStage.resume, PairDetail.resume(_phone, _secret)),
    ),
  );
  return (
    socket: socket,
    key: await key.future.timeout(const Duration(seconds: 2)),
  );
}
