import 'dart:io';

import 'package:tapikappflutter/core/protocol/codec.dart';
import 'package:tapikappflutter/core/protocol/keycodes.dart';
import 'package:tapikappflutter/core/protocol/packet.dart';

var _passed = 0;
var _failed = 0;

void _check(String label, Object? actual, Object? expected) {
  final ok = '$actual' == '$expected';
  ok ? _passed += 1 : _failed += 1;
  stdout.writeln('${ok ? 'PASS' : 'FAIL'}  $label');
  if (!ok) stdout.writeln('        expected $expected, got $actual');
}

void main() {
  stdout.writeln('letters map to HID keyboard usages');
  _check('a is the base usage', Keycodes.letter('a'), Keycodes.usageA);
  _check('z closes the range', Keycodes.letter('z'), 0x1D);
  _check('uppercase resolves the same', Keycodes.letter('Q'), 0x14);
  _check('lowercase q agrees', Keycodes.letter('q'), Keycodes.letter('Q'));
  _check('a digit is not a letter', Keycodes.letter('1'), null);
  _check('empty is not a letter', Keycodes.letter(''), null);
  _check('a word is not a letter', Keycodes.letter('ab'), null);

  stdout.writeln('');
  stdout.writeln('every key the UI can send is in the macOS map');
  final uiKeys = <String, int>{
    'esc': Keycodes.usageEscape,
    'space': Keycodes.usageSpace,
    'return': Keycodes.usageReturn,
    'delete': Keycodes.usageBackspace,
    'period': Keycodes.usagePeriod,
    'arrow right': Keycodes.usageArrowRight,
    'arrow left': Keycodes.usageArrowLeft,
  };
  for (final entry in uiKeys.entries) {
    _check('${entry.key} resolves', Keycodes.macos(entry.value) != null, true);
  }
  final letters = 'QWERTYUIOPASDFGHJKLZXCVBNM'.split('');
  final unmapped = letters
      .where((l) => Keycodes.macos(Keycodes.letter(l)!) == null)
      .toList();
  _check('all 26 keyboard letters resolve', unmapped, []);

  stdout.writeln('');
  stdout.writeln('the agent platform decides the shortcut modifier');
  _check('macOS uses command', Keycodes.primaryModifier('macOS').command, true);
  _check(
    'macOS does not use control',
    Keycodes.primaryModifier('macOS').control,
    false,
  );
  _check(
    'Windows uses control',
    Keycodes.primaryModifier('Windows').control,
    true,
  );
  _check('Linux uses control', Keycodes.primaryModifier('Linux').control, true);
  _check(
    'an unknown agent falls back to control',
    Keycodes.primaryModifier(null).control,
    true,
  );

  stdout.writeln('');
  stdout.writeln('held modifiers survive the wire');
  const held = KeyModifiers(command: true, shift: true);
  final packet = KeyPacket(
    keyCode: Keycodes.letter('c')!,
    modifiers: held,
    down: true,
  );
  final decoded = PacketCodec.decodeOne(PacketCodec.encode(packet));
  _check('a modified key round-trips', decoded, packet);
  _check(
    'and keeps both modifier bits',
    (decoded as KeyPacket?)?.modifiers.mask,
    held.mask,
  );

  final plain = KeyPacket(
    keyCode: Keycodes.usageArrowRight,
    modifiers: KeyModifiers.none,
    down: false,
  );
  _check(
    'an unmodified key round-trips',
    PacketCodec.decodeOne(PacketCodec.encode(plain)),
    plain,
  );

  stdout.writeln('');
  stdout.writeln('typed text survives the wire');
  const typed = TextPacket('Hello from Tapikapp 👋');
  _check(
    'unicode text round-trips',
    PacketCodec.decodeOne(PacketCodec.encode(typed)),
    typed,
  );

  stdout.writeln('');
  stdout.writeln('$_passed passed, $_failed failed');
  if (_failed > 0) exitCode = 1;
}
