import 'dart:io';
import 'dart:math';

import 'package:tapikappflutter/core/protocol/codec.dart';
import 'package:tapikappflutter/core/protocol/packet.dart';
import 'package:tapikappflutter/core/protocol/pair_detail.dart';
import 'package:tapikappflutter/features/agent/view_model/paired_phone_label.dart';
import 'package:tapikappflutter/services/security/paired_phone.dart';
import 'package:tapikappflutter/services/security/pairing_guard.dart';
import 'package:tapikappflutter/services/security/reconnect_secret.dart';
import 'package:tapikappflutter/services/security/spake2.dart';

const String _secret = 'scratch-secret';
const String _laptop = 'AB:CD:EF:01';

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
  bool pairing = true,
  int maxWrongCodes = PairingGuard.defaultMaxWrongCodesPerWindow,
}) {
  _at = DateTime(2026, 1, 1, 12);
  final guard = PairingGuard(
    trustedClients: {
      for (final id in trusted) id: ReconnectSecret.hash(_secret),
    },
    history: history,
    maxWrongCodesPerWindow: maxWrongCodes,
    random: Random(7),
    clock: () => _at,
  );
  if (pairing) guard.openPairing();
  return guard;
}

PairPacket _introduce(String phone) =>
    PairPacket(PairStage.introduce, PairDetail.introduce(phone));

PairPacket _resume(String phone, [String secret = _secret]) =>
    PairPacket(PairStage.resume, PairDetail.resume(phone, secret));

String? _pair(PairingGuard guard, String phone) {
  guard.openPairing();
  guard.open('', _laptop);
  guard.onPacket(_introduce(phone));
  return _enter(guard, guard.visibleCode!, phone).issuedSecret;
}

PairingDecision _enter(
  PairingGuard guard,
  String code,
  String phone, {
  String laptop = _laptop,
}) {
  final spake = Spake2.phone(
    code: code,
    phoneId: phone,
    laptopFingerprint: laptop,
  );
  final answer = guard.onPacket(
    PairPacket(PairStage.spakeShare, Spake2.encode(spake.share)),
  );
  final reply = answer.reply;
  if (reply == null || reply.stage != PairStage.spakeShare) return answer;
  final parts = PairDetail.parts(reply.detail);
  final session = spake.finish(Spake2.decode(parts.first, Spake2.shareLength)!);
  final tag = Spake2.decode(parts.last, Spake2.confirmLength)!;
  final confirmed = session != null && session.acceptsB(tag);
  return guard.onPacket(
    PairPacket(
      PairStage.spakeConfirm,
      confirmed ? Spake2.encode(session.confirmA) : '',
    ),
  );
}

void main() {
  stdout.writeln('an unknown phone must prove physical presence');
  var guard = _guard();
  guard.open('', _laptop);
  var decision = guard.onPacket(_introduce('phone-a'));
  _check('an introduction does not grant access', decision.isAccepted, false);
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
  decision = _enter(guard, '000000', 'phone-a');
  final wrongAccepted = decision.isAccepted;
  decision = _enter(guard, code, 'phone-a');
  _check('a wrong code is refused', wrongAccepted, false);
  _check('the right code is accepted', decision.isAccepted, true);
  _check('and the code stops being shown', guard.visibleCode, null);
  final issued = decision.issuedSecret;
  _check(
    'the laptop issues a reconnect secret with the acceptance',
    issued != null && ReconnectSecret.isToken(issued) && issued.length == 43,
    true,
  );
  _check(
    'and keeps only its hash',
    guard.trustedClients['phone-a'],
    ReconnectSecret.hash(issued!),
  );
  _check('pairing closes once a phone pairs', guard.isPairingOpen, false);

  stdout.writeln('');
  stdout.writeln('input is ignored until the handshake completes');
  guard = _guard();
  guard.open('', _laptop);
  final before = guard.onPacket(const MovePacket(dx: 10, dy: 10));
  _check('motion before pairing is not accepted', before.isAccepted, false);
  _check('and is not a rejection either', before.shouldDrop, false);
  guard.onPacket(_introduce('phone-a'));
  _enter(guard, guard.visibleCode!, 'phone-a');
  final after = guard.onPacket(const MovePacket(dx: 10, dy: 10));
  _check('motion after pairing is accepted', after.isAccepted, true);

  stdout.writeln('');
  stdout.writeln('a remembered phone skips the code only with its secret');
  guard = _guard(trusted: {'phone-a'}, pairing: false);
  guard.open('', _laptop);
  decision = guard.onPacket(_resume('phone-a'));
  _check(
    'a trusted phone with its secret is accepted',
    decision.isAccepted,
    true,
  );
  _check('no code is shown', guard.visibleCode, null);
  _check('the reply says accepted', decision.reply?.stage, PairStage.accepted);
  _check('and no new secret is issued', decision.issuedSecret, null);

  guard = _guard(trusted: {'phone-a'});
  guard.open('', _laptop);
  decision = guard.onPacket(_resume('phone-a', 'stolen-guess'));
  _check(
    'the right phone id with the wrong secret is asked for the code',
    [decision.isAccepted, decision.reply?.stage],
    [false, PairStage.codeRequired],
  );

  guard = _guard(trusted: {'phone-a'});
  guard.open('', _laptop);
  decision = guard.onPacket(_resume('phone-b'));
  _check(
    'a different phone still needs the code',
    decision.reply?.stage,
    PairStage.codeRequired,
  );

  guard = _guard(trusted: {'phone-a'});
  guard.open('', _laptop);
  decision = guard.onPacket(const PairPacket(PairStage.hello, 'phone-a'));
  _check(
    'a v3 hello with a trusted id is refused outright',
    [decision.isAccepted, decision.shouldDrop, decision.reply?.detail],
    [false, true, PairingGuard.outdatedPhone],
  );
  guard.open('', _laptop);
  decision = guard.onPacket(const PairPacket(PairStage.introduce, '3 phone-a'));
  _check(
    'an introduction from an older protocol is refused',
    [decision.shouldDrop, decision.reply?.detail],
    [true, PairingGuard.outdatedPhone],
  );
  guard.open('', _laptop);
  decision = guard.onPacket(const PairPacket(PairStage.introduce, '4 phone a'));
  _check(
    'a malformed introduction is refused',
    [decision.shouldDrop, guard.visibleCode],
    [true, null],
  );
  guard.open('', _laptop);
  decision = guard.onPacket(const PairPacket(PairStage.resume, '4 phone-a'));
  _check(
    'a resume without a secret is refused',
    [decision.isAccepted, decision.shouldDrop],
    [false, true],
  );

  stdout.writeln('');
  stdout.writeln('repeated wrong codes back off');
  guard = _guard(maxWrongCodes: 100);
  guard.open('', _laptop);
  guard.onPacket(_introduce('phone-a'));
  final real = guard.visibleCode!;
  for (var i = 0; i < PairingGuard.defaultMaxAttempts; i++) {
    _enter(guard, '111111', 'phone-a');
  }
  _check('the guard is now blocked', guard.blockedFor != null, true);
  final blocked = _enter(guard, real, 'phone-a');
  _check(
    'even the correct code is refused while blocked',
    blocked.isAccepted,
    false,
  );
  _at = _at.add(const Duration(minutes: 10));
  _check('the block lifts with time', guard.blockedFor, null);

  stdout.writeln('');
  stdout.writeln('one phone cannot lock out another');
  guard = _guard(maxWrongCodes: 100);
  guard.open('192.168.1.50', _laptop);
  guard.onPacket(_introduce('impostor'));
  for (var i = 0; i < PairingGuard.defaultMaxAttempts; i++) {
    _enter(guard, '111111', 'impostor');
  }
  _check('the guessing phone is blocked', guard.blockedFor != null, true);
  guard.close();
  guard.open('192.168.1.77', _laptop);
  _check('a different phone is not', guard.blockedFor, null);
  decision = guard.onPacket(_introduce('phone-a'));
  _check(
    'and is still offered a code',
    decision.reply?.stage,
    PairStage.codeRequired,
  );
  decision = _enter(guard, guard.visibleCode!, 'phone-a');
  _check('it pairs normally', decision.isAccepted, true);
  _check('and is remembered', decision.rememberClient, 'phone-a');
  _check(
    'by the guard itself',
    guard.trustedClients.containsKey('phone-a'),
    true,
  );
  final secretA = decision.issuedSecret!;

  guard.close();
  guard.open('192.168.1.77', _laptop);
  decision = guard.onPacket(_resume('phone-a', secretA));
  _check('so it skips the code next time', decision.isAccepted, true);

  stdout.writeln('');
  stdout.writeln('a penalty does not outlive the window');
  guard = _guard(maxWrongCodes: 100);
  guard.open('192.168.1.50', _laptop);
  guard.onPacket(_introduce('impostor'));
  for (var i = 0; i < PairingGuard.defaultMaxAttempts; i++) {
    _enter(guard, '111111', 'impostor');
  }
  _at = _at.add(PairingGuard.penaltyWindow + const Duration(minutes: 1));
  guard.close();
  guard.open('192.168.1.50', _laptop);
  _check('the same phone starts clean later', guard.blockedFor, null);

  stdout.writeln('');
  stdout.writeln('codes and handshakes expire');
  guard = _guard();
  guard.open('', _laptop);
  guard.onPacket(_introduce('phone-a'));
  final expiring = guard.visibleCode!;
  _at = _at.add(PairingGuard.defaultCodeLifetime + const Duration(seconds: 1));
  decision = _enter(guard, expiring, 'phone-a');
  _check('an expired code is refused', decision.isAccepted, false);
  _check('and the socket is dropped', decision.shouldDrop, true);

  guard = _guard();
  guard.open('', _laptop);
  _check('a fresh handshake has not timed out', guard.hasTimedOut(), false);
  _at = _at.add(
    PairingGuard.defaultHandshakeTimeout + const Duration(seconds: 1),
  );
  _check('a silent phone times out', guard.hasTimedOut(), true);

  guard = _guard();
  guard.open('', _laptop);
  _at = _at.add(const Duration(seconds: 20));
  guard.onPacket(_introduce('phone-a'));
  _at = _at.add(
    PairingGuard.defaultHandshakeTimeout + const Duration(seconds: 1),
  );
  _check(
    'a phone typing its code gets the whole code lifetime, not 30 seconds',
    guard.hasTimedOut(),
    false,
  );
  _at = _at.add(PairingGuard.defaultCodeLifetime);
  _check('but not longer', guard.hasTimedOut(), true);

  guard = _guard(trusted: {'phone-a'});
  guard.open('', _laptop);
  guard.onPacket(_resume('phone-a'));
  _at = _at.add(const Duration(hours: 1));
  _check('an accepted session never times out', guard.hasTimedOut(), false);

  stdout.writeln('');
  stdout.writeln('pairing again replaces the old secret');
  guard = _guard(trusted: {'phone-a'});
  guard.open('', _laptop);
  decision = guard.onPacket(_introduce('phone-a'));
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
    'an introduction alone forgets nothing, so it cannot un-pair a phone',
    guard.trustedClients['phone-a'],
    ReconnectSecret.hash(_secret),
  );
  decision = _enter(guard, guard.visibleCode!, 'phone-a');
  _check('the right code pairs it again', decision.isAccepted, true);
  _check(
    'and the new secret replaces the old one',
    guard.trustedClients['phone-a'],
    ReconnectSecret.hash(decision.issuedSecret!),
  );
  guard.close();
  guard.open('', _laptop);
  decision = guard.onPacket(_resume('phone-a'));
  _check('so the old secret no longer gets in', decision.isAccepted, false);

  stdout.writeln('');
  stdout.writeln('the laptop accepts new phones only while pairing is open');
  guard = _guard(trusted: {'phone-a'}, pairing: false);
  guard.open('', _laptop);
  decision = guard.onPacket(_introduce('phone-b'));
  _check(
    'a new phone is turned away while pairing is closed',
    [decision.shouldDrop, decision.reply?.detail, guard.visibleCode],
    [true, PairingGuard.pairingClosed, null],
  );
  guard.open('', _laptop);
  decision = guard.onPacket(_resume('phone-a', 'wrong-secret'));
  _check(
    'so is a known id with the wrong secret',
    [decision.shouldDrop, decision.reply?.detail],
    [true, PairingGuard.pairingClosed],
  );
  guard.open('', _laptop);
  decision = guard.onPacket(_resume('phone-a'));
  _check(
    'a paired phone reconnects without anyone opening pairing',
    decision.isAccepted,
    true,
  );
  guard.close();
  guard.openPairing();
  _check(
    'opening pairing lasts two minutes',
    guard.pairingOpenUntil,
    _at.add(PairingGuard.defaultPairingWindow),
  );
  guard.open('', _laptop);
  decision = guard.onPacket(_introduce('phone-b'));
  _check(
    'a new phone then gets a code',
    decision.reply?.stage,
    PairStage.codeRequired,
  );
  _check('and the laptop is waiting for it', guard.awaitsCode, true);
  final late = guard.visibleCode!;
  _at = _at.add(PairingGuard.defaultPairingWindow);
  _check(
    'after two minutes pairing is closed and the code is hidden',
    [guard.isPairingOpen, guard.pairingOpenUntil, guard.visibleCode],
    [false, null, null],
  );
  decision = _enter(guard, late, 'phone-b');
  _check(
    'so the code no longer works',
    [decision.isAccepted, decision.reply?.detail],
    [false, PairingGuard.pairingClosed],
  );

  guard = _guard();
  guard.open('', _laptop);
  guard.onPacket(_introduce('phone-b'));
  guard.closePairing();
  _check(
    'stopping pairing hides the code at once',
    [guard.visibleCode, guard.awaitsCode, guard.pairingStopped],
    [null, false, false],
  );

  guard = _guard();
  final wrongs = <String?>[];
  for (var i = 0; i < PairingGuard.defaultMaxWrongCodesPerWindow; i++) {
    guard.close();
    guard.open('10.0.0.$i', _laptop);
    guard.onPacket(_introduce('guesser-$i'));
    wrongs.add(_enter(guard, '999999', 'guesser-$i').reply?.detail);
  }
  _check(
    'five wrong codes in one window stop pairing, even from five addresses',
    [guard.isPairingOpen, guard.pairingStopped, wrongs.last],
    [false, true, PairingGuard.pairingStoppedReason],
  );
  guard.close();
  guard.open('10.0.0.99', _laptop);
  decision = guard.onPacket(_introduce('guesser-99'));
  _check(
    'and nobody new gets a code until the laptop opens pairing again',
    [decision.shouldDrop, guard.visibleCode],
    [true, null],
  );
  _check(
    'and it tells them why, not just that pairing is closed',
    decision.reply?.detail,
    PairingGuard.pairingStoppedReason,
  );
  guard.openPairing();
  _check('opening it again clears the stop', guard.pairingStopped, false);

  guard = _guard(trusted: {'phone-a'});
  guard.open('', _laptop);
  guard.onPacket(_resume('phone-a'));
  _check(
    'a paired phone reconnecting closes the window, since only one phone '
    'can be connected',
    guard.isPairingOpen,
    false,
  );
  _check(
    'ids and secrets longer than 64 characters are not tokens',
    [ReconnectSecret.isToken('a' * 64), ReconnectSecret.isToken('a' * 65)],
    [true, false],
  );

  stdout.writeln('');
  stdout.writeln('reconnect secrets');
  final made = {for (var i = 0; i < 20; i++) ReconnectSecret.generate()};
  _check('every secret is new', made.length, 20);
  _check(
    'a secret matches only its own hash',
    [
      ReconnectSecret.matches(_secret, ReconnectSecret.hash(_secret)),
      ReconnectSecret.matches('other', ReconnectSecret.hash(_secret)),
      ReconnectSecret.matches(_secret, 'short'),
    ],
    [true, false, false],
  );
  _check(
    'a new phone id is a 22-character token',
    [
      ReconnectSecret.newClientId().length,
      ReconnectSecret.isToken(ReconnectSecret.newClientId()),
    ],
    [22, true],
  );

  stdout.writeln('');
  stdout.writeln('a paired phone can ask to be forgotten');
  guard = _guard(trusted: {'phone-a'});
  guard.open('', _laptop);
  _check(
    'nothing is forgotten before a session exists',
    guard.forgetCurrentClient(),
    null,
  );
  guard.onPacket(_introduce('phone-b'));
  decision = guard.onPacket(const PairPacket(PairStage.forget));
  _check(
    'a forget request during the handshake does nothing',
    decision.outcome,
    PairingOutcome.pending,
  );
  _check(
    'and forgets nobody',
    guard.trustedClients.containsKey('phone-a'),
    true,
  );
  _check(
    'an unaccepted phone cannot forget anyone',
    guard.forgetCurrentClient(),
    null,
  );
  guard.open('', _laptop);
  guard.onPacket(_resume('phone-a'));
  _check(
    'an accepted phone can be forgotten',
    guard.forgetCurrentClient(),
    'phone-a',
  );
  _check(
    'and is no longer trusted',
    guard.trustedClients.containsKey('phone-a'),
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
  final secretOfA = _pair(guard, 'phone-a')!;
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
  guard.open('', _laptop);
  guard.onPacket(_resume('phone-a', secretOfA));
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
      removed?.phone ==
          PairedPhone(id: 'dated-phone', pairedAt: DateTime(2025, 12, 1)),
      guard.trustedClients.keys.join(','),
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
    [
      guard.pairedPhones.first == removed.phone,
      guard.trustedClients['dated-phone'] == ReconnectSecret.hash(_secret),
    ],
    [true, true],
  );
  guard.restore(
    TrustedPhone(
      PairedPhone(id: 'dated-phone', pairedAt: DateTime(2020)),
      ReconnectSecret.hash('other'),
    ),
  );
  _check(
    'putting back a phone that is already trusted keeps its current dates',
    [
      guard.pairedPhones.first == removed.phone,
      guard.trustedClients['dated-phone'] == ReconnectSecret.hash(_secret),
    ],
    [true, true],
  );
  guard.open('', _laptop);
  guard.onPacket(_introduce('dated-phone'));
  _enter(guard, guard.visibleCode!, 'dated-phone');
  _check(
    'a phone pairing again with a code gets new dates',
    guard.pairedPhones.firstWhere((p) => p.id == 'dated-phone').pairedAt,
    _at,
  );
  guard.close();
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
  stdout.writeln('the code is checked with SPAKE2, never sent');
  guard = _guard();
  guard.open('', _laptop);
  guard.onPacket(_introduce('phone-a'));
  decision = guard.onPacket(PairPacket(PairStage.code, guard.visibleCode!));
  _check(
    'a typed code sent in the clear is refused as an older phone',
    [decision.isAccepted, decision.shouldDrop, decision.reply?.detail],
    [false, true, PairingGuard.outdatedPhone],
  );

  guard = _guard();
  guard.open('', _laptop);
  final early = Spake2.phone(
    code: '123456',
    phoneId: 'phone-a',
    laptopFingerprint: _laptop,
  );
  decision = guard.onPacket(
    PairPacket(PairStage.spakeShare, Spake2.encode(early.share)),
  );
  _check(
    'a share before any introduction is refused',
    [decision.isAccepted, decision.shouldDrop],
    [false, true],
  );

  guard = _guard();
  guard.open('', _laptop);
  guard.onPacket(_introduce('phone-a'));
  final shown = guard.visibleCode!;
  decision = _enter(guard, shown, 'phone-a', laptop: 'FA:KE:00:01');
  _check(
    'a phone that sees another certificate cannot pair, even with the right '
    'code, and is asked again',
    [decision.isAccepted, decision.outcome, decision.reply],
    [false, PairingOutcome.retry, null],
  );
  _check(
    'that attempt still counts against the window',
    [guard.isPairingOpen, guard.trustedClients.containsKey('phone-a')],
    [true, false],
  );
  decision = _enter(guard, shown, 'phone-a');
  _check(
    'the same code then works from the real laptop’s point of view',
    decision.isAccepted,
    true,
  );

  guard = _guard();
  guard.open('', _laptop);
  guard.onPacket(_introduce('phone-a'));
  decision = guard.onPacket(const PairPacket(PairStage.spakeShare, 'AAAA'));
  _check(
    'a malformed share is refused and dropped',
    [decision.isAccepted, decision.shouldDrop],
    [false, true],
  );

  guard = _guard();
  guard.open('', _laptop);
  guard.onPacket(_introduce('phone-a'));
  final first = Spake2.phone(
    code: guard.visibleCode!,
    phoneId: 'phone-a',
    laptopFingerprint: _laptop,
  );
  final firstReply = guard.onPacket(
    PairPacket(PairStage.spakeShare, Spake2.encode(first.share)),
  );
  decision = guard.onPacket(
    PairPacket(PairStage.spakeShare, Spake2.encode(first.share)),
  );
  _check(
    'a second share before confirming is refused',
    [firstReply.reply?.stage, decision.shouldDrop],
    [PairStage.spakeShare, true],
  );

  guard = _guard();
  guard.open('', _laptop);
  guard.onPacket(_introduce('phone-a'));
  final forger = Spake2.phone(
    code: '000000',
    phoneId: 'phone-a',
    laptopFingerprint: _laptop,
  );
  guard.onPacket(PairPacket(PairStage.spakeShare, Spake2.encode(forger.share)));
  decision = guard.onPacket(
    PairPacket(PairStage.spakeConfirm, Spake2.encode(List.filled(32, 7))),
  );
  _check(
    'a forged confirmation is refused, dropped and trusts nothing',
    [
      decision.isAccepted,
      decision.shouldDrop,
      guard.trustedClients.containsKey('phone-a'),
    ],
    [false, true, false],
  );

  guard = _guard();
  guard.open('', _laptop);
  guard.onPacket(_introduce('phone-a'));
  decision = guard.onPacket(const PairPacket(PairStage.spakeConfirm, 'x'));
  _check(
    'a confirmation with no share before it is refused',
    [decision.isAccepted, decision.shouldDrop],
    [false, true],
  );

  guard = _guard();
  guard.open('', _laptop);
  guard.onPacket(_introduce('phone-a'));
  final shares = <String>{};
  for (var i = 0; i < 3; i++) {
    final phone = Spake2.phone(
      code: '000000',
      phoneId: 'phone-a',
      laptopFingerprint: _laptop,
    );
    final answer = guard.onPacket(
      PairPacket(PairStage.spakeShare, Spake2.encode(phone.share)),
    );
    shares.add(PairDetail.parts(answer.reply!.detail).first);
    guard.onPacket(const PairPacket(PairStage.spakeConfirm));
  }
  _check('the laptop uses a fresh share every time', shares.length, 3);

  guard = _guard();
  for (var i = 0; i < PairingGuard.defaultMaxWrongCodesPerWindow; i++) {
    guard.close();
    guard.open('10.0.1.$i', _laptop);
    guard.onPacket(_introduce('silent-$i'));
    final silent = Spake2.phone(
      code: '000000',
      phoneId: 'silent-$i',
      laptopFingerprint: _laptop,
    );
    guard.onPacket(
      PairPacket(PairStage.spakeShare, Spake2.encode(silent.share)),
    );
  }
  _check(
    'hanging up after the laptop’s answer still counts as a wrong code',
    [guard.isPairingOpen, guard.pairingStopped],
    [true, false],
  );
  guard.close();
  _check(
    'so the fifth silent hang-up stops pairing',
    [guard.isPairingOpen, guard.pairingStopped],
    [false, true],
  );

  guard = _guard();
  for (var i = 0; i < PairingGuard.defaultMaxWrongCodesPerWindow; i++) {
    guard.close();
    guard.open('10.0.2.$i', _laptop);
    guard.onPacket(_introduce('garbler-$i'));
    decision = guard.onPacket(const PairPacket(PairStage.spakeShare, 'AAAA'));
  }
  _check(
    'a malformed fifth share also stops pairing, so no dead code is shown',
    [guard.isPairingOpen, guard.pairingStopped, decision.reply?.detail],
    [false, true, PairingGuard.pairingStoppedReason],
  );

  guard = _guard();
  guard.open('', _laptop);
  guard.onPacket(_introduce('phone-a'));
  decision = guard.onPacket(_introduce('phone-b'));
  _check(
    'a second introduction on one connection is refused',
    [decision.shouldDrop, decision.reply?.detail],
    [true, PairingGuard.introducedTwice],
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
