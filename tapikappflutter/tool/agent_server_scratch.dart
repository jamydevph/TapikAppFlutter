import 'dart:io';

import 'package:tapikappflutter/core/error/failure.dart';
import 'package:tapikappflutter/core/protocol/codec.dart';
import 'package:tapikappflutter/core/protocol/packet.dart';
import 'package:tapikappflutter/services/server/agent_server.dart';
import 'package:tapikappflutter/services/transport/network_transport.dart';
import 'package:tapikappflutter/services/transport/transport.dart';

Future<void> main() async {
  final checks = <_Check>[];
  final ports = await _freePorts();
  final server = AgentServer(tcpPort: ports.$1, udpPort: ports.$2);
  final seen = <Packet>[];
  final states = <AgentServerState>[];
  final packets = server.packets.listen(seen.add);
  final link = server.states.listen(states.add);

  await server.start();
  await _settle();
  checks.add(
    _Check(
      'start binds both ports and reports listening',
      server.state.listening && !server.state.hasClient,
      '${server.state.listening}, client ${server.state.client}',
    ),
  );

  final phone = NetworkTransport();
  await phone.connect(
    TransportEndpoint(
      host: InternetAddress.loopbackIPv4.address,
      tcpPort: ports.$1,
      udpPort: ports.$2,
    ),
  );
  await _settle();
  checks.add(
    _Check(
      'a connecting phone is reported without the v4-mapped prefix',
      server.state.hasClient && !server.state.client!.startsWith('::ffff:'),
      'client ${server.state.client}',
    ),
  );

  const reliable = <Packet>[
    TextPacket('hello 👋'),
    ButtonPacket(button: PointerButton.left, down: true),
    ButtonPacket(button: PointerButton.left, down: false),
    KeyPacket(keyCode: 8, modifiers: KeyModifiers(command: true), down: true),
    PingPacket(),
  ];
  for (final packet in reliable) {
    phone.send(packet);
  }
  await _settle();
  checks.add(
    _Check(
      'keys and clicks arrive over TCP in order',
      seen.toString() == reliable.toString(),
      '${seen.length} of ${reliable.length}',
    ),
  );

  const motion = <Packet>[
    MovePacket(dx: 4, dy: -4),
    ScrollPacket(dx: 0, dy: 9),
  ];
  for (final packet in motion) {
    phone.send(packet);
  }
  await _settle();
  checks.add(
    _Check(
      'motion arrives over UDP',
      seen.length == reliable.length + motion.length &&
          seen.skip(reliable.length).toList().toString() == motion.toString(),
      '${seen.length} total, tail ${seen.skip(reliable.length).toList()}',
    ),
  );
  checks.add(
    _Check(
      'the packet counter matches what was delivered',
      server.packetCount == seen.length,
      '${server.packetCount} counted, ${seen.length} delivered',
    ),
  );

  final stranger = await RawDatagramSocket.bind(InternetAddress.anyIPv6, 0);
  stranger.send(
    PacketCodec.encode(const MovePacket(dx: 99, dy: 99)),
    InternetAddress.loopbackIPv4,
    ports.$2,
  );
  await _settle();
  checks.add(
    _Check(
      'motion from an address that is not the client is ignored',
      server.packetCount == seen.length &&
          !seen.contains(const MovePacket(dx: 99, dy: 99)),
      '${server.packetCount} counted',
    ),
  );
  stranger.close();

  final second = NetworkTransport();
  await second.connect(
    TransportEndpoint(
      host: InternetAddress.loopbackIPv4.address,
      tcpPort: ports.$1,
      udpPort: ports.$2,
    ),
  );
  await _settle();
  final before = server.packetCount;
  second.send(const TextPacket('second phone'));
  await _settle();
  checks.add(
    _Check(
      'a second phone is refused while one is connected',
      server.packetCount == before &&
          server.state.client != null &&
          seen.every((packet) => packet != const TextPacket('second phone')),
      'still ${server.state.client}, count $before',
    ),
  );
  await second.dispose();

  await phone.disconnect();
  await _settle(rounds: 6);
  checks.add(
    _Check(
      'a phone hanging up clears the client but keeps listening',
      server.state.listening && !server.state.hasClient,
      'listening ${server.state.listening}, client ${server.state.client}',
    ),
  );
  await phone.dispose();

  checks.add(await _portInUse(ports.$1, ports.$2));
  checks.add(await _udpClashReleasesTcp());
  checks.add(await _counterResetsPerClient());

  await server.stop();
  await _settle();
  checks.add(
    _Check(
      'stop releases both ports',
      !server.state.listening && !await _isBound(ports.$1),
      'listening ${server.state.listening}',
    ),
  );

  await packets.cancel();
  await link.cancel();
  await server.dispose();

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

Future<_Check> _udpClashReleasesTcp() async {
  final ports = await _freePorts();
  final squatter = await RawDatagramSocket.bind(
    InternetAddress.anyIPv4,
    ports.$2,
    reuseAddress: false,
  );
  final blocked = AgentServer(tcpPort: ports.$1, udpPort: ports.$2);
  Object? thrown;
  try {
    await blocked.start();
  } catch (error) {
    thrown = error;
  }
  await blocked.dispose();
  squatter.close();
  await _settle();
  final freed = !await _isBound(ports.$1);
  final named = thrown is Failure && thrown.message.contains('${ports.$2}');
  return _Check(
    'a UDP clash releases the TCP port and names the UDP port',
    thrown is TransportFailure && freed && named,
    'tcp freed $freed, message '
        '${thrown is Failure ? thrown.message : thrown}',
  );
}

Future<_Check> _counterResetsPerClient() async {
  final ports = await _freePorts();
  final server = AgentServer(tcpPort: ports.$1, udpPort: ports.$2);
  await server.start();
  final counts = <int>[];
  for (var round = 0; round < 2; round++) {
    final phone = NetworkTransport();
    await phone.connect(
      TransportEndpoint(
        host: InternetAddress.loopbackIPv4.address,
        tcpPort: ports.$1,
        udpPort: ports.$2,
      ),
    );
    await _settle();
    for (var i = 0; i <= round; i++) {
      phone.send(const PingPacket());
    }
    await _settle();
    counts.add(server.packetCount);
    await phone.disconnect();
    await _settle(rounds: 6);
    await phone.dispose();
  }
  await server.dispose();
  return _Check(
    'the counter restarts at zero for each phone',
    counts.toString() == [1, 2].toString(),
    'counts $counts',
  );
}

Future<_Check> _portInUse(int tcpPort, int udpPort) async {
  final rival = AgentServer(tcpPort: tcpPort, udpPort: udpPort);
  Object? thrown;
  try {
    await rival.start();
  } catch (error) {
    thrown = error;
  }
  await rival.dispose();
  return _Check(
    'a second agent on the same port fails with a human message',
    thrown is TransportFailure,
    thrown is Failure ? thrown.message : '$thrown',
  );
}

Future<bool> _isBound(int port) async {
  try {
    final probe = await ServerSocket.bind(InternetAddress.anyIPv6, port);
    await probe.close();
    return false;
  } on SocketException {
    return true;
  }
}

Future<(int, int)> _freePorts() async {
  final tcp = await ServerSocket.bind(InternetAddress.anyIPv6, 0);
  final udp = await RawDatagramSocket.bind(InternetAddress.anyIPv6, 0);
  final ports = (tcp.port, udp.port);
  await tcp.close();
  udp.close();
  return ports;
}

Future<void> _settle({int rounds = 4}) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
}

class _Check {
  const _Check(this.name, this.ok, this.detail);

  final String name;
  final bool ok;
  final String detail;
}
