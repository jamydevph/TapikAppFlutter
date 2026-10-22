import 'dart:io';
import 'dart:math';

import 'package:tapikappflutter/core/protocol/codec.dart';
import 'package:tapikappflutter/core/protocol/packet.dart';
import 'package:tapikappflutter/features/agent/view_model/paired_phone_label.dart';
import 'package:tapikappflutter/services/security/paired_phone.dart';
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

PairingGuard _guard({
  Set<String> trusted = const {},
  List<PairedPhone> history = const [],
}) {
  _at = DateTime(2026, 1, 1, 12);
  return PairingGuard(
    trustedClients: trusted,
    history: history,
    random: Random(7),
    clock: () => _at,
  );
}

void _pair(PairingGuard guard, String phone) {
  guard.open();
  guard.onPacket(PairPacket(PairStage.hello, phone));
  guard.onPacket(PairPacket(PairStage.code, guard.visibleCode!));
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
  stdout.writeln('a phone with no pin pairs from scratch');
  guard = _guard(trusted: {'phone-a'});
  guard.open();
  decision = guard.onPacket(const PairPacket(PairStage.introduce, 'phone-a'));
  _check(
    'an introduction is never accepted at once',
    decision.isAccepted,
    false,
  );
  _check(
    'even a trusted phone is asked for the code',
    decision.reply?.stage,
    PairStage.codeRequired,
  );
  _check(
    'its old trust is dropped',
    guard.trustedClients.contains('phone-a'),
    false,
  );
  _check('and reported so it can be saved', decision.forgotClient, 'phone-a');
  decision = guard.onPacket(PairPacket(PairStage.code, guard.visibleCode!));
  _check('the right code pairs it again', decision.isAccepted, true);
  _check(
    'and it is trusted again',
    guard.trustedClients.contains('phone-a'),
    true,
  );

  guard = _guard();
  guard.open();
  decision = guard.onPacket(const PairPacket(PairStage.introduce, 'phone-b'));
  _check(
    'an unknown phone introducing itself has nothing to forget',
    decision.forgotClient,
    null,
  );
  _check(
    'and is asked for the code as usual',
    decision.reply?.stage,
    PairStage.codeRequired,
  );

  stdout.writeln('');
  stdout.writeln('a paired phone can ask to be forgotten');
  guard = _guard(trusted: {'phone-a'});
  guard.open();
  _check(
    'nothing is forgotten before a session exists',
    guard.forgetCurrentClient(),
    null,
  );
  guard.onPacket(const PairPacket(PairStage.hello, 'phone-b'));
  decision = guard.onPacket(const PairPacket(PairStage.forget));
  _check(
    'a forget request during the handshake does nothing',
    decision.outcome,
    PairingOutcome.pending,
  );
  _check('and forgets nobody', guard.trustedClients.contains('phone-a'), true);
  _check(
    'an unaccepted phone cannot forget anyone',
    guard.forgetCurrentClient(),
    null,
  );
  guard.open();
  guard.onPacket(const PairPacket(PairStage.hello, 'phone-a'));
  _check(
    'an accepted phone can be forgotten',
    guard.forgetCurrentClient(),
    'phone-a',
  );
  _check(
    'and is no longer trusted',
    guard.trustedClients.contains('phone-a'),
    false,
  );
  _check(
    'forgetting twice forgets nothing more',
    guard.forgetCurrentClient(),
    null,
  );

  stdout.writeln('');
  stdout.writeln(
    'the laptop remembers when each phone paired and last connected',
  );
  guard = _guard();
  final pairedAt = _at;
  _pair(guard, 'phone-a');
  _check(
    'a new pairing records the time it paired and was seen',
    guard.pairedPhones.single ==
        PairedPhone(id: 'phone-a', pairedAt: pairedAt, lastSeenAt: pairedAt),
    true,
  );
  _check('and says which phone is connected', guard.acceptedClient, 'phone-a');
  _at = _at.add(const Duration(hours: 1));
  guard.close();
  _check(
    'disconnecting updates when it was last seen, not when it paired',
    [
      guard.pairedPhones.single.pairedAt == pairedAt,
      guard.pairedPhones.single.lastSeenAt == _at,
      guard.acceptedClient,
    ],
    [true, true, null],
  );
  _at = _at.add(const Duration(hours: 1));
  guard.open();
  guard.onPacket(const PairPacket(PairStage.hello, 'phone-a'));
  _check(
    'reconnecting with no code counts as seen as well',
    guard.pairedPhones.single.lastSeenAt == _at,
    true,
  );
  guard.close();
  _at = _at.add(const Duration(hours: 1));
  _pair(guard, 'phone-b');
  guard.close();
  _check(
    'the newest pairing is listed first',
    guard.pairedPhones.map((phone) => phone.id).join(','),
    'phone-b,phone-a',
  );

  guard = _guard(
    trusted: {'old-phone', 'dated-phone'},
    history: [
      PairedPhone(id: 'dated-phone', pairedAt: DateTime(2025, 12, 1)),
      PairedPhone(id: 'forgotten-phone', pairedAt: DateTime(2025, 12, 2)),
    ],
  );
  _check(
    'a phone paired before dates were kept is listed last, with no dates',
    [
      guard.pairedPhones.map((phone) => phone.id).join(','),
      guard.pairedPhones.last == const PairedPhone(id: 'old-phone'),
    ],
    ['dated-phone,old-phone', true],
  );
  _check(
    'dates for a phone that is no longer trusted are dropped',
    guard.pairedPhones.any((phone) => phone.id == 'forgotten-phone'),
    false,
  );
  final removed = guard.forgetClient('dated-phone');
  _check(
    'one phone can be forgotten by its id, keeping the others',
    [
      removed ==
          PairedPhone(id: 'dated-phone', pairedAt: DateTime(2025, 12, 1)),
      guard.trustedClients.join(','),
    ],
    [true, 'old-phone'],
  );
  _check(
    'forgetting it twice does nothing',
    guard.forgetClient('dated-phone'),
    null,
  );
  guard.restore(removed!);
  _check(
    'a phone whose forget could not be saved can be put back, dates and all',
    guard.pairedPhones.first == removed,
    true,
  );
  guard.restore(PairedPhone(id: 'dated-phone', pairedAt: DateTime(2020)));
  _check(
    'putting back a phone that is already trusted keeps its current dates',
    guard.pairedPhones.first == removed,
    true,
  );
  guard.open();
  guard.onPacket(const PairPacket(PairStage.introduce, 'dated-phone'));
  _check(
    'a phone pairing again from scratch loses its old dates',
    guard.pairedPhones.any((phone) => phone.id == 'dated-phone'),
    false,
  );
  guard.forgetAllClients();
  _check('forgetting all phones clears every date', guard.pairedPhones, []);

  const dated = PairedPhone(id: 'x');
  final full = PairedPhone(
    id: 'phone-a',
    pairedAt: DateTime(2026, 10, 21, 21, 2),
    lastSeenAt: DateTime(2026, 10, 22, 8),
  );
  _check(
    'saved dates come back the same',
    [
      PairedPhone.fromJson(full.toJson()) == full,
      PairedPhone.fromJson(dated.toJson()) == dated,
    ],
    [true, true],
  );
  _check(
    'a broken saved entry is skipped rather than trusted',
    [
      PairedPhone.fromJson('nope'),
      PairedPhone.fromJson({'id': ''}),
      PairedPhone.fromJson({'paired': 1}),
    ],
    [null, null, null],
  );
  _check(
    'an impossible saved date is dropped instead of crashing the agent',
    [
      PairedPhone.fromJson({'id': 'phone-a', 'paired': 1 << 62}) ==
          const PairedPhone(id: 'phone-a'),
      PairedPhone.fromJson({'id': 'phone-a', 'seen': -1 << 63}) ==
          const PairedPhone(id: 'phone-a'),
    ],
    [true, true],
  );

  stdout.writeln('');
  stdout.writeln('each row on the laptop says which phone it is');
  final now = DateTime(2026, 10, 22, 15);
  final rows = [
    PairedPhone(id: 'a', pairedAt: DateTime(2026, 10, 21, 21, 2)),
    PairedPhone(id: 'b', pairedAt: DateTime(2026, 10, 3, 9)),
    PairedPhone(id: 'c', pairedAt: DateTime(2026, 10, 3, 18, 30)),
    PairedPhone(id: 'd', pairedAt: DateTime(2025, 12, 1)),
    const PairedPhone(id: 'e'),
    const PairedPhone(id: 'f'),
  ];
  final titles = PairedPhoneLabel.titles(rows, now);
  _check(
    'a phone is named by the day it paired',
    titles['a'],
    'Phone paired 21 Oct',
  );
  _check(
    'two phones paired the same day also show the time',
    [titles['b'], titles['c']],
    ['Phone paired 3 Oct, 9:00 AM', 'Phone paired 3 Oct, 6:30 PM'],
  );
  _check(
    'a pairing from another year shows the year',
    titles['d'],
    'Phone paired 1 Dec 2025',
  );
  _check(
    'phones paired before this update are told apart by number',
    [titles['e'], titles['f']],
    ['Phone paired earlier', 'Phone paired earlier (2)'],
  );
  final reordered = PairedPhoneLabel.titles(rows.reversed.toList(), now);
  _check(
    'and keep their numbers when the list order changes',
    [reordered['e'], reordered['f'], reordered['b']],
    [titles['e'], titles['f'], titles['b']],
  );
  String seen(Duration ago) => PairedPhoneLabel.status(
    PairedPhone(id: 'x', lastSeenAt: now.subtract(ago)),
    connected: false,
    now: now,
  );
  _check(
    'the connected phone says so',
    PairedPhoneLabel.status(rows.first, connected: true, now: now),
    'Connected now',
  );
  _check(
    'the others say when they were last connected',
    [
      seen(const Duration(seconds: 20)),
      seen(const Duration(minutes: 5)),
      seen(const Duration(minutes: 70)),
      seen(const Duration(hours: 5)),
      seen(const Duration(hours: 20)),
      seen(const Duration(hours: 30)),
      seen(const Duration(days: 3)),
      seen(const Duration(days: 21)),
    ],
    [
      'Last connected just now',
      'Last connected 5 min ago',
      'Last connected 1 hour ago',
      'Last connected 5 hours ago',
      'Last connected 20 hours ago',
      'Last connected yesterday',
      'Last connected 3 days ago',
      'Last connected on 1 Oct',
    ],
  );
  _check(
    'a phone not seen since this update says that instead',
    PairedPhoneLabel.status(
      const PairedPhone(id: 'e'),
      connected: false,
      now: now,
    ),
    'Not connected since this update',
  );

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
