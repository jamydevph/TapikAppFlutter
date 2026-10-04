import 'dart:io';

import 'package:tapikappflutter/core/error/failure.dart';
import 'package:tapikappflutter/core/protocol/packet.dart';
import 'package:tapikappflutter/services/input/pointer_pump.dart';
import 'package:tapikappflutter/services/transport/transport.dart';

const String _toolClient = 'tapikapp-dev-tool';

class _Recorder implements Transport {
  final List<Packet> sent = <Packet>[];

  @override
  TransportState get state => TransportState.connected;

  @override
  TransportEndpoint? get endpoint =>
      const TransportEndpoint(clientId: _toolClient, host: '127.0.0.1');

  @override
  Stream<TransportState> get states => const Stream<TransportState>.empty();

  @override
  Stream<Packet> get incoming => const Stream<Packet>.empty();

  @override
  Future<void> connect(TransportEndpoint endpoint) async {}

  @override
  void submitPairingCode(String code) {}

  @override
  Stream<Failure> get pairingErrors => const Stream<Failure>.empty();

  @override
  Stream<void> get codeRequests => const Stream<void>.empty();

  @override
  void send(Packet packet) => sent.add(packet);

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> dispose() async {}

  int get movedX => sent.whereType<MovePacket>().fold(0, (a, p) => a + p.dx);
  int get movedY => sent.whereType<MovePacket>().fold(0, (a, p) => a + p.dy);
  int get scrolledY =>
      sent.whereType<ScrollPacket>().fold(0, (a, p) => a + p.dy);
}

var _passed = 0;
var _failed = 0;

void _check(String label, Object? actual, Object? expected) {
  final ok = '$actual' == '$expected';
  ok ? _passed += 1 : _failed += 1;
  stdout.writeln('${ok ? 'PASS' : 'FAIL'}  $label');
  if (!ok) stdout.writeln('        expected $expected, got $actual');
}

const Duration slowFrame = Duration(milliseconds: 16);
const Duration lazyFrame = Duration(milliseconds: 200);

void main() {
  stdout.writeln('one packet per frame, never per event');
  var t = _Recorder();
  var pump = PointerPump(t);
  for (var i = 0; i < 20; i++) {
    pump.addMove(1, 0);
  }
  pump.flush(lazyFrame);
  _check('20 events in one frame produce 1 packet', t.sent.length, 1);
  _check('and a slow drag carries the exact distance', t.movedX, 20);

  stdout.writeln('');
  stdout.writeln('sub-pixel movement is never lost');
  t = _Recorder();
  pump = PointerPump(t);
  for (var i = 0; i < 10; i++) {
    pump.addMove(0.4, 0);
    pump.flush(slowFrame);
  }
  _check('10 frames of 0.4px move 4px', t.movedX, 4);
  _check('a slow drag still emits packets', t.sent.isNotEmpty, true);

  stdout.writeln('');
  stdout.writeln('nothing pending means nothing sent');
  t = _Recorder();
  pump = PointerPump(t);
  pump.flush(slowFrame);
  pump.flush(slowFrame);
  _check('idle frames send no packets', t.sent.length, 0);

  stdout.writeln('');
  stdout.writeln('acceleration');
  t = _Recorder();
  pump = PointerPump(t);
  pump.addMove(2, 0);
  pump.flush(slowFrame);
  _check('a slow drag is 1:1', t.movedX, 2);

  t = _Recorder();
  pump = PointerPump(t);
  pump.addMove(60, 0);
  pump.flush(slowFrame);
  final fast = t.movedX;
  _check('a fast flick is amplified', fast > 60, true);
  _check(
    'but never beyond the max gain',
    fast <= (60 * PointerPump.maxGain).ceil(),
    true,
  );

  stdout.writeln('');
  stdout.writeln('sensitivity');
  t = _Recorder();
  pump = PointerPump(t)..sensitivity = 2;
  pump.addMove(3, 0);
  pump.flush(slowFrame);
  _check('sensitivity 2.0 doubles a slow drag', t.movedX, 6);

  t = _Recorder();
  pump = PointerPump(t)..sensitivity = 0.5;
  pump.addMove(4, 0);
  pump.flush(slowFrame);
  _check('sensitivity 0.5 halves it', t.movedX, 2);

  stdout.writeln('');
  stdout.writeln('scroll direction');
  t = _Recorder();
  pump = PointerPump(t)..naturalScrolling = true;
  pump.addScroll(0, 10);
  pump.flush(slowFrame);
  final natural = t.scrolledY;
  t = _Recorder();
  pump = PointerPump(t)..naturalScrolling = false;
  pump.addScroll(0, 10);
  pump.flush(slowFrame);
  _check(
    'natural and inverted scroll have opposite signs',
    natural.sign == -t.scrolledY.sign && natural != 0,
    true,
  );

  stdout.writeln('');
  stdout.writeln('reset drops pending motion');
  t = _Recorder();
  pump = PointerPump(t);
  pump.addMove(50, 50);
  pump.addScroll(0, 50);
  pump.reset();
  pump.flush(slowFrame);
  _check('a disconnect discards what was queued', t.sent.length, 0);

  stdout.writeln('');
  stdout.writeln('diagonal motion keeps both axes');
  t = _Recorder();
  pump = PointerPump(t);
  pump.addMove(5, -5);
  pump.flush(lazyFrame);
  _check('a slow diagonal is exact on x', t.movedX, 5);
  _check('and on y, sign preserved', t.movedY, -5);

  t = _Recorder();
  pump = PointerPump(t);
  pump.addMove(5, -5);
  pump.flush(slowFrame);
  _check(
    'a fast diagonal is amplified equally on both axes',
    t.movedX == -t.movedY && t.movedX > 5,
    true,
  );

  stdout.writeln('');
  stdout.writeln('$_passed passed, $_failed failed');
  if (_failed > 0) exitCode = 1;
}
