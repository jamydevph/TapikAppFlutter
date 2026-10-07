import 'dart:io';

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

int _signed(int byte) => byte > 127 ? byte - 256 : byte;

void main() {
  stdout.writeln('the report descriptor');
  const d = HidReports.descriptor;
  _check(
    'declares the keyboard as report 1',
    _contains(d, [0x85, HidReports.keyboardId]),
    true,
  );
  _check(
    'declares the mouse as report 2',
    _contains(d, [0x85, HidReports.mouseId]),
    true,
  );
  _check(
    'opens and closes every collection',
    d.where((b) => b == 0xA1).length,
    d.where((b) => b == 0xC0).length,
  );
  _check(
    'carries horizontal scroll (AC Pan)',
    _contains(d, [0x0A, 0x38, 0x02]),
    true,
  );

  stdout.writeln('');
  stdout.writeln('the keyboard');
  var hid = HidReports();
  var reports = hid.encode(
    const KeyPacket(
      keyCode: 0x04,
      modifiers: KeyModifiers(command: true),
      down: true,
    ),
  );
  _check('a key press is one report', reports.length, 1);
  _check('on the keyboard report id', reports.single.id, HidReports.keyboardId);
  _check(
    'cmd+a is modifier 0x08 with usage 0x04',
    reports.single.data.toList(),
    [0x08, 0, 0x04, 0, 0, 0, 0, 0],
  );
  reports = hid.encode(
    const KeyPacket(keyCode: 0x04, modifiers: KeyModifiers.none, down: false),
  );
  _check(
    'a key release clears everything, modifiers included',
    reports.single.data.toList(),
    [0, 0, 0, 0, 0, 0, 0, 0],
  );
  _check(
    'every modifier lands on its own bit',
    HidReports.modifierByte(
      const KeyModifiers(
        control: true,
        shift: true,
        option: true,
        command: true,
      ),
    ),
    0x0F,
  );

  stdout.writeln('');
  stdout.writeln(
    'the wire already speaks HID — the Bluetooth keymap is the identity',
  );
  hid = HidReports();
  var identity = true;
  for (final usage in Keycodes.macosUsages) {
    if (Keycodes.isModifier(usage)) continue;
    final data = hid
        .encode(
          KeyPacket(keyCode: usage, modifiers: KeyModifiers.none, down: true),
        )
        .single
        .data;
    if (data[2] != usage) identity = false;
  }
  _check(
    'every key the network path can send goes out unchanged',
    identity,
    true,
  );

  stdout.writeln('');
  stdout.writeln('the mouse');
  hid = HidReports();
  _check(
    'middle click is bit 0x04, not its wire code 0x03 (which would be left+right)',
    HidReports.buttonBit(PointerButton.middle),
    0x04,
  );
  hid.encode(const ButtonPacket(button: PointerButton.left, down: true));
  reports = hid.encode(const MovePacket(dx: 5, dy: 3));
  _check(
    'a move while the button is held carries the button (that is a drag)',
    reports.single.data[0],
    0x01,
  );
  hid.encode(const ButtonPacket(button: PointerButton.left, down: false));
  reports = hid.encode(const MovePacket(dx: 1, dy: 1));
  _check('releasing it clears the drag', reports.single.data[0], 0);

  reports = hid.encode(const MovePacket(dx: 300, dy: -50));
  final sumX = reports.fold(0, (s, r) => s + _signed(r.data[1]));
  final sumY = reports.fold(0, (s, r) => s + _signed(r.data[2]));
  _check('a big move is split, not clipped — x total', sumX, 300);
  _check('y total is preserved too', sumY, -50);
  _check(
    'and no single report exceeds the 8-bit axis',
    reports.every(
      (r) => _signed(r.data[1]).abs() <= 127 && _signed(r.data[2]).abs() <= 127,
    ),
    true,
  );
  _check(
    'a negative step is two\'s complement on the wire',
    hid.encode(const MovePacket(dx: -1, dy: 0)).single.data[1],
    0xFF,
  );

  stdout.writeln('');
  stdout.writeln('scrolling is scaled from pixels to wheel detents');
  hid = HidReports(pixelsPerDetent: 40);
  _check(
    'a scroll smaller than one detent sends nothing yet',
    hid.encode(const ScrollPacket(dx: 0, dy: 20)).length,
    0,
  );
  reports = hid.encode(const ScrollPacket(dx: 0, dy: 20));
  _check('the remainder carries into the next one', reports.length, 1);
  _check('and becomes exactly one detent', _signed(reports.single.data[3]), 1);
  _check(
    'forty pixels is one notch, not forty',
    _signed(hid.encode(const ScrollPacket(dx: 0, dy: 40)).single.data[3]),
    1,
  );

  stdout.writeln('');
  stdout.writeln('typing text');
  hid = HidReports();
  reports = hid.encode(const TextPacket('Hi!'));
  _check(
    'three characters are three presses and three releases',
    reports.length,
    6,
  );
  _check('a capital takes shift', reports[0].data.toList(), [
    0x02,
    0,
    0x0B,
    0,
    0,
    0,
    0,
    0,
  ]);
  _check('a lowercase letter does not', reports[2].data.toList(), [
    0,
    0,
    0x0C,
    0,
    0,
    0,
    0,
    0,
  ]);
  _check(
    'a shifted symbol takes shift on its digit key',
    reports[4].data.toList(),
    [0x02, 0, 0x1E, 0, 0, 0, 0, 0],
  );
  hid = HidReports();
  hid.encode(const TextPacket('añ👋b'));
  _check(
    'characters a HID keyboard cannot type are skipped and counted',
    hid.skippedCharacters,
    2,
  );

  stdout.writeln('');
  stdout.writeln('nothing is left held');
  hid = HidReports();
  hid.encode(const ButtonPacket(button: PointerButton.left, down: true));
  hid.encode(const ButtonPacket(button: PointerButton.right, down: true));
  reports = hid.releaseAll();
  _check(
    'release-all clears the keyboard',
    reports[0].data.every((b) => b == 0),
    true,
  );
  _check('and the mouse', reports[1].data.every((b) => b == 0), true);
  _check('and forgets the held buttons', hid.heldButtons, 0);
  _check(
    'keepalives and pairing never reach the host',
    hid.encode(const PingPacket()).length +
        hid.encode(const PairPacket(PairStage.hello)).length,
    0,
  );

  stdout.writeln('');
  stdout.writeln('$_passed passed, $_failed failed');
  if (_failed > 0) exitCode = 1;
}

bool _contains(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
}
