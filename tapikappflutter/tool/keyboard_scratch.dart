import 'dart:io';

import 'package:tapikappflutter/core/protocol/codec.dart';
import 'package:tapikappflutter/core/protocol/keycodes.dart';
import 'package:tapikappflutter/core/protocol/packet.dart';
import 'package:tapikappflutter/services/transport/hid_reports.dart';

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
    'tab': Keycodes.usageTab,
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
  stdout.writeln('every media key on the screen reaches both laptops');
  final mediaKeys = <String, int>{
    'previous track': Keycodes.mediaPreviousTrack,
    'play or pause': Keycodes.mediaPlayPause,
    'next track': Keycodes.mediaNextTrack,
    'volume down': Keycodes.mediaVolumeDown,
    'volume up': Keycodes.mediaVolumeUp,
  };
  for (final entry in mediaKeys.entries) {
    _check(
      '${entry.key} has a Mac and a Windows key',
      Keycodes.macosMedia(entry.value) != null &&
          Keycodes.windowsMedia(entry.value) != null,
      true,
    );
  }
  final macTypes = [
    for (final usage in Keycodes.mediaUsages) Keycodes.macosMedia(usage),
  ];
  final windowsKeys = [
    for (final usage in Keycodes.mediaUsages) Keycodes.windowsMedia(usage),
  ];
  _check(
    'no two media usages share a Mac key type',
    macTypes.toSet().length,
    macTypes.length,
  );
  _check(
    'or a Windows virtual key',
    windowsKeys.toSet().length,
    windowsKeys.length,
  );
  const mute = MediaPacket(Keycodes.mediaMute);
  final decodedMute = PacketCodec.decodeOne(PacketCodec.encode(mute));
  _check(
    'consumer Mute (0xE2) shares a number with keyboard Left Alt, but '
    'travels as a media packet, so it can never press Alt',
    decodedMute is MediaPacket && decodedMute.usage == Keycodes.usageLeftOption,
    true,
  );
  const media = MediaPacket(Keycodes.mediaPlayPause);
  _check(
    'a media tap round-trips the wire',
    PacketCodec.decodeOne(PacketCodec.encode(media)),
    media,
  );

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
  stdout.writeln('the shortcut row sends the right combo for each laptop');
  _check('macOS counts as a Mac', Keycodes.isMac('macOS'), true);
  _check('Windows does not', Keycodes.isMac('windows'), false);
  _check('an unknown laptop does not', Keycodes.isMac(null), false);
  _check(
    'switch app holds the real command key on a Mac',
    Keycodes.appSwitchKey('macOS'),
    Keycodes.usageLeftCommand,
  );
  _check(
    'and the real alt key on Windows',
    Keycodes.appSwitchKey('windows'),
    Keycodes.usageLeftOption,
  );
  const command = KeyModifiers(command: true);
  final hold = Keycodes.appSwitchKey('macOS');
  final hid = HidReports();
  final switchReports = [
    for (final step in [
      KeyPacket(keyCode: hold, modifiers: command, down: true),
      KeyPacket(keyCode: Keycodes.usageTab, modifiers: command, down: true),
      KeyPacket(keyCode: Keycodes.usageTab, modifiers: command, down: false),
      KeyPacket(keyCode: hold, modifiers: KeyModifiers.none, down: false),
    ])
      for (final report in hid.encode(step))
        '${report.data[0]}/${report.data[2]}',
  ];
  _check(
    'over Bluetooth, switch app presses command, adds tab, then lets go',
    switchReports,
    ['8/0', '8/43', '0/0', '0/0'],
  );
  _check(
    'switch app is command+tab on a Mac',
    Keycodes.appSwitchModifier('macos') == const KeyModifiers(command: true),
    true,
  );
  _check(
    'and alt+tab on Windows',
    Keycodes.appSwitchModifier('windows') == const KeyModifiers(option: true),
    true,
  );
  _check(
    'an unknown laptop falls back to alt+tab',
    Keycodes.appSwitchModifier(null) == const KeyModifiers(option: true),
    true,
  );
  final shortcutKeys = [
    for (final letter in ['X', 'C', 'V', 'Z']) Keycodes.letter(letter)!,
    Keycodes.usageTab,
  ];
  _check(
    'cut, copy, paste, undo and tab all reach a Mac',
    shortcutKeys.every((usage) => Keycodes.macos(usage) != null),
    true,
  );
  _check(
    'and a Windows laptop',
    shortcutKeys.every((usage) => Keycodes.windows(usage) != null),
    true,
  );
  final copyOnWindows = PacketCodec.decodeOne(
    PacketCodec.encode(
      KeyPacket(
        keyCode: Keycodes.letter('C')!,
        modifiers: Keycodes.primaryModifier('windows'),
        down: true,
      ),
    ),
  );
  _check(
    'copy for Windows survives the wire as ctrl+c',
    copyOnWindows ==
        KeyPacket(
          keyCode: Keycodes.letter('C')!,
          modifiers: const KeyModifiers(control: true),
          down: true,
        ),
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
