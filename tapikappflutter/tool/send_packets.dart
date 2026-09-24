import 'dart:io';
import 'dart:math' as math;

import 'package:tapikappflutter/core/error/failure.dart';
import 'package:tapikappflutter/core/protocol/packet.dart';
import 'package:tapikappflutter/core/resources/constants.dart';
import 'package:tapikappflutter/services/transport/network_transport.dart';
import 'package:tapikappflutter/services/transport/transport.dart';

const String defaultHost = '127.0.0.1';
const int motionFrames = 120;
const Duration frameInterval = Duration(milliseconds: 8);
const Duration beat = Duration(milliseconds: 400);

Future<void> main(List<String> args) async {
  final host = args.isEmpty ? defaultHost : args.first;
  final transport = NetworkTransport();
  final states = transport.states.listen((state) => stdout.writeln('· $state'));
  final incoming = transport.incoming.listen(
    (packet) => stdout.writeln('· agent sent $packet'),
  );

  stdout.writeln(
    'connecting to $host:${TapikappConstants.tcpPort} '
    '(motion on ${TapikappConstants.udpPort})',
  );
  try {
    await transport.connect(TransportEndpoint(host: host));
  } on Failure catch (failure) {
    stdout.writeln('could not connect: ${failure.message}');
    await states.cancel();
    await incoming.cancel();
    await transport.dispose();
    exitCode = 1;
    return;
  }

  var sent = 0;
  void fire(Packet packet) {
    transport.send(packet);
    sent += 1;
  }

  stdout.writeln('typing a line of text');
  fire(const TextPacket('Hello from Tapikapp 👋'));
  await Future<void>.delayed(beat);

  stdout.writeln('tapping and releasing the left button');
  fire(const ButtonPacket(button: PointerButton.left, down: true));
  fire(const ButtonPacket(button: PointerButton.left, down: false));
  await Future<void>.delayed(beat);

  stdout.writeln('pressing cmd+c then cmd+v');
  for (final code in [8, 9]) {
    fire(
      KeyPacket(
        keyCode: code,
        modifiers: const KeyModifiers(command: true),
        down: true,
      ),
    );
    fire(
      KeyPacket(
        keyCode: code,
        modifiers: const KeyModifiers(command: true),
        down: false,
      ),
    );
  }
  await Future<void>.delayed(beat);

  stdout.writeln('drawing a circle with $motionFrames motion packets');
  for (var i = 0; i < motionFrames; i++) {
    final angle = i * 2 * math.pi / motionFrames;
    fire(
      MovePacket(
        dx: (12 * math.cos(angle)).round(),
        dy: (12 * math.sin(angle)).round(),
      ),
    );
    await Future<void>.delayed(frameInterval);
  }

  stdout.writeln('scrolling down then up');
  for (var i = 0; i < 10; i++) {
    fire(ScrollPacket(dx: 0, dy: i.isEven ? -6 : 6));
    await Future<void>.delayed(frameInterval);
  }

  stdout.writeln('sending a ping');
  fire(const PingPacket());
  await Future<void>.delayed(beat);

  stdout.writeln('sent $sent packets; disconnecting');
  await transport.disconnect();
  await states.cancel();
  await incoming.cancel();
  await transport.dispose();
}
