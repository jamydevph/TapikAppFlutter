import 'dart:async';
import 'dart:io';

import 'package:tapikappflutter/core/protocol/codec.dart';
import 'package:tapikappflutter/core/protocol/packet.dart';
import 'package:tapikappflutter/services/security/agent_certificate.dart';
import 'package:tapikappflutter/services/security/pairing_guard.dart';
import 'package:tapikappflutter/services/server/agent_server.dart';
import 'package:tapikappflutter/services/transport/network_transport.dart';
import 'package:tapikappflutter/services/transport/transport.dart';

const String _phone = 'latency-scratch-phone';
const int _encodeRuns = 200000;
const int _tcpSamples = 200;
const int _udpSamples = 500;

Future<(int, int)> _freePorts() async {
  final a = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final b = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  final ports = (a.port, b.port);
  await a.close();
  b.close();
  return ports;
}

String _us(double microseconds) => '${microseconds.toStringAsFixed(1)} µs';

String _ms(double microseconds) =>
    '${(microseconds / 1000).toStringAsFixed(3)} ms';

void _report(String label, List<int> samplesUs) {
  if (samplesUs.isEmpty) {
    stdout.writeln('  $label: no samples');
    return;
  }
  final sorted = [...samplesUs]..sort();
  final p50 = sorted[sorted.length ~/ 2].toDouble();
  final p95 = sorted[(sorted.length * 95) ~/ 100].toDouble();
  final worst = sorted.last.toDouble();
  stdout.writeln(
    '  $label  n=${sorted.length}  '
    'p50 ${_ms(p50)}  p95 ${_ms(p95)}  max ${_ms(worst)}',
  );
}

void _measureEncode() {
  stdout.writeln('encode cost (the "< 1 ms encode + write" row of §9)');
  const move = MovePacket(dx: 12, dy: -7);
  const key = KeyPacket(
    keyCode: 0x04,
    modifiers: KeyModifiers.none,
    down: true,
  );
  for (final entry in {'MOVE': move, 'KEY': key}.entries) {
    PacketCodec.encode(entry.value);
    final watch = Stopwatch()..start();
    for (var i = 0; i < _encodeRuns; i++) {
      PacketCodec.encode(entry.value);
    }
    watch.stop();
    final per = watch.elapsedMicroseconds / _encodeRuns;
    stdout.writeln('  ${entry.key}  ${_us(per)} per packet');
  }
}

Future<void> main() async {
  stdout.writeln('generating the agent certificate…');
  final certificate = await AgentCertificate.generate('tapikapp-latency');

  stdout.writeln('');
  _measureEncode();

  final ports = await _freePorts();
  final agent = AgentServer(
    certificate: certificate,
    guard: PairingGuard(trustedClients: const {_phone}),
    tcpPort: ports.$1,
    udpPort: ports.$2,
  );
  final arrivals = <Packet>[];
  final stamps = <int>[];
  final clock = Stopwatch()..start();
  agent.packets.listen((packet) {
    arrivals.add(packet);
    stamps.add(clock.elapsedMicroseconds);
  });
  await agent.start();

  final phone = NetworkTransport();
  await phone.connect(
    TransportEndpoint(
      clientId: _phone,
      host: InternetAddress.loopbackIPv4.address,
      tcpPort: ports.$1,
      udpPort: ports.$2,
      fingerprint: certificate.fingerprint,
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 500));
  if (phone.state != TransportState.connected) {
    stdout.writeln('could not connect: ${phone.state}');
    exitCode = 1;
    return;
  }

  stdout.writeln('');
  stdout.writeln('phone → laptop over loopback, app cost only (no Wi-Fi leg)');

  final tcp = <int>[];
  for (var i = 0; i < _tcpSamples; i++) {
    final before = arrivals.length;
    final sentAt = clock.elapsedMicroseconds;
    phone.send(
      const KeyPacket(keyCode: 0x04, modifiers: KeyModifiers.none, down: true),
    );
    var waited = 0;
    while (arrivals.length == before && waited < 2000) {
      await Future<void>.delayed(const Duration(microseconds: 200));
      waited += 1;
    }
    if (arrivals.length > before) tcp.add(stamps.last - sentAt);
  }
  _report('KEY over TCP  ', tcp);

  final udp = <int>[];
  for (var i = 0; i < _udpSamples; i++) {
    final before = arrivals.length;
    final sentAt = clock.elapsedMicroseconds;
    phone.send(MovePacket(dx: (i % 7) + 1, dy: 1));
    var waited = 0;
    while (arrivals.length == before && waited < 2000) {
      await Future<void>.delayed(const Duration(microseconds: 200));
      waited += 1;
    }
    if (arrivals.length > before) udp.add(stamps.last - sentAt);
  }
  _report('MOVE over UDP ', udp);

  stdout.writeln('');
  stdout.writeln('budget (plan §9, under 25 ms finger-to-cursor)');
  stdout.writeln(
    '  touch → gesture callback   ~8 ms   one frame, not measured here',
  );
  stdout.writeln('  encode + socket write      < 1 ms  measured above');
  stdout.writeln(
    '  Wi-Fi round trip, same AP  3–10 ms not measured (loopback)',
  );
  stdout.writeln(
    '  agent read → CGEventPost   < 1 ms  measured above, minus the post',
  );
  stdout.writeln('  cursor repaint by the OS    ~8 ms   not measured here');

  await phone.disconnect();
  await phone.dispose();
  await agent.dispose();
}
