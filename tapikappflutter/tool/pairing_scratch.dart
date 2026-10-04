import 'dart:io';
import 'dart:math';

import 'package:tapikappflutter/core/protocol/codec.dart';
import 'package:tapikappflutter/core/protocol/packet.dart';
import 'package:tapikappflutter/services/security/pairing_guard.dart';

var _passed = 0;
var _failed = 0;

void _check(String label, Object? actual, Object? expected) {
  final ok = '$actual' == '$expected';
  ok ? _passed += 1 : _failed += 1;
  stdout.writeln('${ok ? 'PASS' : 'FAIL'}  $label');
  if (!ok) stdout.writeln('        expected $expected, got $actual');
}

DateTime _at = DateTime(2026, 1, 1, 12);

PairingGuard _guard({Set<String> trusted = const {}}) {
  _at = DateTime(2026, 1, 1, 12);
  return PairingGuard(
    trustedClients: trusted,
    random: Random(7),
    clock: () => _at,
  );
}

void main() {
  stdout.writeln('an unknown phone must prove physical presence');
  var guard = _guard();
  guard.open();
  var decision = guard.onPacket(const PairPacket(PairStage.hello, 'phone-a'));
  _check('a hello does not grant access', decision.isAccepted, false);
  _check(
    'the agent asks for a code',
    decision.reply?.stage,
    PairStage.codeRequired,
  );
  _check('and shows a 6-digit code', guard.visibleCode?.length, 6);
  _check(
    'the code is digits only',
    RegExp(r'^\d{6}$').hasMatch(guard.visibleCode!),
    true,
  );

  final code = guard.visibleCode!;
  decision = guard.onPacket(const PairPacket(PairStage.code, '000000'));
  final wrongAccepted = decision.isAccepted;
  decision = guard.onPacket(PairPacket(PairStage.code, code));
  _check('a wrong code is refused', wrongAccepted, false);
  _check('the right code is accepted', decision.isAccepted, true);
  _check('and the code stops being shown', guard.visibleCode, null);

  stdout.writeln('');
  stdout.writeln('input is ignored until the handshake completes');
  guard = _guard();
  guard.open();
  final before = guard.onPacket(const MovePacket(dx: 10, dy: 10));
  _check('motion before pairing is not accepted', before.isAccepted, false);
  _check('and is not a rejection either', before.shouldDrop, false);
  guard.onPacket(const PairPacket(PairStage.hello, 'phone-a'));
  guard.onPacket(PairPacket(PairStage.code, guard.visibleCode!));
  final after = guard.onPacket(const MovePacket(dx: 10, dy: 10));
  _check('motion after pairing is accepted', after.isAccepted, true);

  stdout.writeln('');
  stdout.writeln('a remembered phone skips the code');
  guard = _guard(trusted: {'phone-a'});
  guard.open();
  decision = guard.onPacket(const PairPacket(PairStage.hello, 'phone-a'));
  _check('a trusted phone is accepted at hello', decision.isAccepted, true);
  _check('no code is shown', guard.visibleCode, null);
  _check('the reply says accepted', decision.reply?.stage, PairStage.accepted);

  guard = _guard(trusted: {'phone-a'});
  guard.open();
  decision = guard.onPacket(const PairPacket(PairStage.hello, 'phone-b'));
  _check(
    'a different phone still needs the code',
    decision.reply?.stage,
    PairStage.codeRequired,
  );

  stdout.writeln('');
  stdout.writeln('repeated wrong codes back off');
  guard = _guard();
  guard.open();
  guard.onPacket(const PairPacket(PairStage.hello, 'phone-a'));
  final real = guard.visibleCode!;
  for (var i = 0; i < PairingGuard.defaultMaxAttempts; i++) {
    guard.onPacket(const PairPacket(PairStage.code, '111111'));
  }
  _check('the guard is now blocked', guard.blockedFor != null, true);
  final blocked = guard.onPacket(PairPacket(PairStage.code, real));
  _check(
    'even the correct code is refused while blocked',
    blocked.isAccepted,
    false,
  );
  _at = _at.add(const Duration(minutes: 10));
  _check('the block lifts with time', guard.blockedFor, null);

  stdout.writeln('');
  stdout.writeln('one phone cannot lock out another');
  guard = _guard();
  guard.open('192.168.1.50');
  guard.onPacket(const PairPacket(PairStage.hello, 'impostor'));
  for (var i = 0; i < PairingGuard.defaultMaxAttempts; i++) {
    guard.onPacket(const PairPacket(PairStage.code, '111111'));
  }
  _check('the guessing phone is blocked', guard.blockedFor != null, true);
  guard.close();
  guard.open('192.168.1.77');
  _check('a different phone is not', guard.blockedFor, null);
  decision = guard.onPacket(const PairPacket(PairStage.hello, 'phone-a'));
  _check(
    'and is still offered a code',
    decision.reply?.stage,
    PairStage.codeRequired,
  );
  decision = guard.onPacket(PairPacket(PairStage.code, guard.visibleCode!));
  _check('it pairs normally', decision.isAccepted, true);
  _check('and is remembered', decision.rememberClient, 'phone-a');
  _check('by the guard itself', guard.trustedClients.contains('phone-a'), true);

  guard.close();
  guard.open('192.168.1.77');
  decision = guard.onPacket(const PairPacket(PairStage.hello, 'phone-a'));
  _check('so it skips the code next time', decision.isAccepted, true);

  stdout.writeln('');
  stdout.writeln('a penalty does not outlive the window');
  guard = _guard();
  guard.open('192.168.1.50');
  guard.onPacket(const PairPacket(PairStage.hello, 'impostor'));
  for (var i = 0; i < PairingGuard.defaultMaxAttempts; i++) {
    guard.onPacket(const PairPacket(PairStage.code, '111111'));
  }
  _at = _at.add(PairingGuard.penaltyWindow + const Duration(minutes: 1));
  guard.close();
  guard.open('192.168.1.50');
  _check('the same phone starts clean later', guard.blockedFor, null);

  stdout.writeln('');
  stdout.writeln('codes and handshakes expire');
  guard = _guard();
  guard.open();
  guard.onPacket(const PairPacket(PairStage.hello, 'phone-a'));
  final expiring = guard.visibleCode!;
  _at = _at.add(PairingGuard.defaultCodeLifetime + const Duration(seconds: 1));
  decision = guard.onPacket(PairPacket(PairStage.code, expiring));
  _check('an expired code is refused', decision.isAccepted, false);
  _check('and the socket is dropped', decision.shouldDrop, true);

  guard = _guard();
  guard.open();
  _check('a fresh handshake has not timed out', guard.hasTimedOut(), false);
  _at = _at.add(
    PairingGuard.defaultHandshakeTimeout + const Duration(seconds: 1),
  );
  _check('a silent phone times out', guard.hasTimedOut(), true);

  guard = _guard(trusted: {'phone-a'});
  guard.open();
  guard.onPacket(const PairPacket(PairStage.hello, 'phone-a'));
  _at = _at.add(const Duration(hours: 1));
  _check('an accepted session never times out', guard.hasTimedOut(), false);

  stdout.writeln('');
  stdout.writeln('handshake packets survive the wire');
  for (final stage in PairStage.values) {
    final packet = PairPacket(stage, stage == PairStage.code ? '123456' : 'x');
    _check(
      '${stage.name} round-trips',
      PacketCodec.decodeOne(PacketCodec.encode(packet)),
      packet,
    );
  }
  const empty = PairPacket(PairStage.accepted);
  _check(
    'an empty payload round-trips',
    PacketCodec.decodeOne(PacketCodec.encode(empty)),
    empty,
  );

  stdout.writeln('');
  stdout.writeln('$_passed passed, $_failed failed');
  if (_failed > 0) exitCode = 1;
}
