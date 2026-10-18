import 'dart:io';

import 'package:tapikappflutter/core/protocol/keycodes.dart';
import 'package:tapikappflutter/core/protocol/packet.dart';
import 'package:tapikappflutter/services/injector/injector.dart';
import 'package:tapikappflutter/services/injector/windows_injector.dart';
import 'package:win32/win32.dart';

var _passed = 0;
var _failed = 0;

void _check(String label, Object? actual, Object? expected) {
  final ok = '$actual' == '$expected';
  ok ? _passed += 1 : _failed += 1;
  stdout.writeln('${ok ? 'PASS' : 'FAIL'}  $label');
  if (!ok) stdout.writeln('        expected $expected, got $actual');
}

const WindowsScreen _fullHd = (left: 0, top: 0, width: 1920, height: 1080);

int _scan(int virtualKey) => 0x100 + virtualKey;

WindowsScreen? _nearest(List<WindowsScreen> monitors, int x, int y) {
  WindowsScreen? best;
  var bestDistance = 0;
  for (final monitor in monitors) {
    final right = monitor.left + monitor.width - 1;
    final bottom = monitor.top + monitor.height - 1;
    final dx = x < monitor.left
        ? monitor.left - x
        : (x > right ? x - right : 0);
    final dy = y < monitor.top
        ? monitor.top - y
        : (y > bottom ? y - bottom : 0);
    final distance = dx * dx + dy * dy;
    if (best == null || distance < bestDistance) {
      best = monitor;
      bestDistance = distance;
    }
  }
  return best;
}

class _Rig {
  _Rig({
    this.cursor = (x: 100, y: 200),
    this.screen = _fullHd,
    List<WindowsScreen>? monitors,
    this.accept,
  }) : monitors = monitors ?? <WindowsScreen>[screen];

  WindowsPoint? cursor;
  WindowsScreen screen;
  List<WindowsScreen> monitors;
  int Function(List<WindowsInput>)? accept;
  final List<List<WindowsInput>> calls = <List<WindowsInput>>[];

  late final WindowsInjector injector = WindowsInjector(
    sink: (inputs) {
      calls.add(List<WindowsInput>.of(inputs));
      return accept?.call(inputs) ?? inputs.length;
    },
    cursor: () => cursor,
    screen: () => screen,
    monitorAt: (x, y) => _nearest(monitors, x, y),
    scanCodeFor: _scan,
  );

  List<WindowsInput> take() {
    final all = [for (final call in calls) ...call];
    calls.clear();
    return all;
  }
}

int _extended(int virtualKey) =>
    WindowsInjector.extendedKeys.contains(virtualKey)
    ? KEYEVENTF_EXTENDEDKEY
    : 0;

WindowsKeyInput _down(int virtualKey) => WindowsKeyInput(
  virtualKey: virtualKey,
  scanCode: _scan(virtualKey),
  flags: _extended(virtualKey),
);

WindowsKeyInput _up(int virtualKey) => WindowsKeyInput(
  virtualKey: virtualKey,
  scanCode: _scan(virtualKey),
  flags: _extended(virtualKey) | KEYEVENTF_KEYUP,
);

List<WindowsKeyInput> _unicode(int unit) => [
  WindowsKeyInput(scanCode: unit, flags: KEYEVENTF_UNICODE),
  WindowsKeyInput(scanCode: unit, flags: KEYEVENTF_UNICODE | KEYEVENTF_KEYUP),
];

WindowsMouseInput _moveTo(int x, int y, [WindowsScreen screen = _fullHd]) =>
    WindowsMouseInput(
      flags: WindowsInjector.moveFlags,
      dx: WindowsInjector.normalize(x, screen.left, screen.width),
      dy: WindowsInjector.normalize(y, screen.top, screen.height),
    );

KeyPacket _key(int usage, bool down, [KeyModifiers? modifiers]) => KeyPacket(
  keyCode: usage,
  modifiers: modifiers ?? KeyModifiers.none,
  down: down,
);

void _keyboardMap() {
  stdout.writeln('the keyboard map matches the macOS one');
  final windows = Keycodes.windowsUsages.toSet();
  final macos = Keycodes.macosUsages.toSet();
  _check(
    'every usage the Mac understands has a Windows key',
    macos.difference(windows).length,
    0,
  );
  _check(
    'and Windows understands nothing the Mac does not',
    windows.difference(macos).length,
    0,
  );
  final virtualKeys = [for (final usage in windows) Keycodes.windows(usage)];
  _check(
    'no two usages share a virtual key',
    virtualKeys.toSet().length,
    virtualKeys.length,
  );
  final letters = [
    for (var c = 0x61; c <= 0x7A; c++)
      Keycodes.windows(Keycodes.letter(String.fromCharCode(c))!),
  ];
  _check('a to z map to VK 0x41 to 0x5A', letters, [
    for (var vk = 0x41; vk <= 0x5A; vk++) vk,
  ]);
  _check(
    'control, shift, option and command map to Ctrl, Shift, Alt, Win',
    [
      Keycodes.windows(Keycodes.usageLeftControl),
      Keycodes.windows(Keycodes.usageLeftShift),
      Keycodes.windows(Keycodes.usageLeftOption),
      Keycodes.windows(Keycodes.usageLeftCommand),
    ],
    [VK_LCONTROL, VK_LSHIFT, VK_LMENU, VK_LWIN],
  );
  _check(
    'the arrows are extended keys',
    [
      for (final usage in [
        Keycodes.usageArrowLeft,
        Keycodes.usageArrowRight,
        Keycodes.usageArrowUp,
        Keycodes.usageArrowDown,
      ])
        WindowsInjector.extendedKeys.contains(Keycodes.windows(usage)),
    ],
    [true, true, true, true],
  );
  _check(
    'a letter is not',
    WindowsInjector.extendedKeys.contains(Keycodes.windows(Keycodes.usageA)),
    false,
  );
}

void _absoluteCoordinates() {
  stdout.writeln('');
  stdout.writeln('absolute coordinates land on the exact pixel');
  var misses = 0;
  var checked = 0;
  for (final screen in <WindowsScreen>[
    (left: 0, top: 0, width: 1366, height: 768),
    _fullHd,
    (left: 0, top: 0, width: 2560, height: 1440),
    (left: 0, top: 0, width: 3840, height: 2160),
    (left: -1920, top: -300, width: 5760, height: 1440),
  ]) {
    for (var x = screen.left; x < screen.left + screen.width; x++) {
      final n = WindowsInjector.normalize(x, screen.left, screen.width);
      if (screen.left + n * screen.width ~/ 65536 != x) misses += 1;
      checked += 1;
    }
  }
  _check(
    'every pixel of five desktops round-trips ($checked pixels)',
    misses,
    0,
  );
  _check(
    'the left edge is 0',
    WindowsInjector.normalize(-1920, -1920, 5760),
    0,
  );
  _check(
    'the right edge stays inside 65535',
    WindowsInjector.normalize(1919, 0, 1920) <= 65535,
    true,
  );
  _check(
    'a pixel left of the desktop clamps to 0',
    WindowsInjector.normalize(-5, 0, 1920),
    0,
  );
}

Future<void> _motion() async {
  stdout.writeln('');
  stdout.writeln('motion');
  var rig = _Rig();
  rig.injector.handle(const MovePacket(dx: 40, dy: 25));
  _check(
    'MOVE(40, 25) from (100, 200) is one absolute move to (140, 225)',
    rig.take(),
    [_moveTo(140, 225)],
  );
  for (var i = 0; i < 24; i++) {
    rig.injector.handle(const MovePacket(dx: 1, dy: 0));
  }
  final burst = rig.take();
  _check(
    'a burst of 24 x MOVE(1, 0) accumulates instead of reading a stale cursor',
    burst.last,
    _moveTo(164, 225),
  );
  _check('and sends one input per packet', burst.length, 24);
  rig.injector.handle(const MovePacket(dx: 5000, dy: 5000));
  _check('a huge move stops at the bottom-right pixel', rig.take(), [
    _moveTo(1919, 1079),
  ]);
  rig.cursor = (x: 500, y: 500);
  await Future<void>.delayed(const Duration(milliseconds: 300));
  rig.injector.handle(const MovePacket(dx: 1, dy: 1));
  _check(
    'after 250 ms idle it re-reads where the cursor really is',
    rig.take(),
    [_moveTo(501, 501)],
  );

  const wide = (left: -1920, top: 0, width: 3840, height: 1080);
  rig = _Rig(cursor: (x: -100, y: 50), screen: wide);
  rig.injector.handle(const MovePacket(dx: 10, dy: 0));
  _check('a monitor left of the primary one is reachable', rig.take(), [
    _moveTo(-90, 50, wide),
  ]);
  rig.injector.handle(const MovePacket(dx: -4000, dy: 0));
  _check('and the left edge of the whole desktop is the limit', rig.take(), [
    _moveTo(-1920, 50, wide),
  ]);

  const desktop = (left: 0, top: 0, width: 4480, height: 1440);
  const big = (left: 0, top: 0, width: 2560, height: 1440);
  const small = (left: 2560, top: 0, width: 1920, height: 1080);
  rig = _Rig(
    cursor: (x: 3000, y: 1000),
    screen: desktop,
    monitors: [big, small],
  );
  rig.injector.handle(const MovePacket(dx: 0, dy: 300));
  _check(
    'below a shorter monitor the target stops at its bottom edge, '
    'not in the dead zone',
    rig.take(),
    [_moveTo(3000, 1079, desktop)],
  );
  rig.injector.handle(const MovePacket(dx: 0, dy: -10));
  _check('so moving back up responds at once (no lost motion)', rig.take(), [
    _moveTo(3000, 1069, desktop),
  ]);

  rig = _Rig();
  rig.injector.handle(const MovePacket(dx: 1, dy: 0));
  rig.take();
  await Future<void>.delayed(const Duration(milliseconds: 300));
  rig.cursor = null;
  rig.injector.handle(const MovePacket(dx: 1, dy: 0));
  _check(
    'a move is dropped while the cursor cannot be read',
    rig.take().length,
    0,
  );
  rig.cursor = (x: 300, y: 300);
  rig.injector.handle(const MovePacket(dx: 1, dy: 0));
  _check(
    'and the next move re-reads the cursor instead of reusing the old target',
    rig.take(),
    [_moveTo(301, 300)],
  );
}

Future<void> _buttons() async {
  stdout.writeln('');
  stdout.writeln('buttons');
  final rig = _Rig();
  final injector = rig.injector;
  injector.handle(const ButtonPacket(button: PointerButton.left, down: true));
  _check('left down', rig.take(), [
    WindowsMouseInput(flags: MOUSEEVENTF_LEFTDOWN),
  ]);
  _check('is remembered as held', injector.heldButtons, {PointerButton.left});
  injector.handle(const MovePacket(dx: 5, dy: 0));
  _check('dragging is a plain move while the button is down', rig.take(), [
    _moveTo(105, 200),
  ]);
  injector.handle(const ButtonPacket(button: PointerButton.left, down: false));
  _check('left up', rig.take(), [WindowsMouseInput(flags: MOUSEEVENTF_LEFTUP)]);
  _check('and is no longer held', injector.heldButtons.length, 0);
  injector
    ..handle(const ButtonPacket(button: PointerButton.right, down: true))
    ..handle(const ButtonPacket(button: PointerButton.right, down: false))
    ..handle(const ButtonPacket(button: PointerButton.middle, down: true))
    ..handle(const ButtonPacket(button: PointerButton.middle, down: false));
  _check('right and middle use their own flags', rig.take(), [
    WindowsMouseInput(flags: MOUSEEVENTF_RIGHTDOWN),
    WindowsMouseInput(flags: MOUSEEVENTF_RIGHTUP),
    WindowsMouseInput(flags: MOUSEEVENTF_MIDDLEDOWN),
    WindowsMouseInput(flags: MOUSEEVENTF_MIDDLEUP),
  ]);

  injector.handle(const ButtonPacket(button: PointerButton.left, down: true));
  rig.take();
  rig.cursor = null;
  await Future<void>.delayed(const Duration(milliseconds: 300));
  injector.handle(const ButtonPacket(button: PointerButton.left, down: false));
  _check(
    'a button up still goes out when the cursor cannot be read (lock screen)',
    rig.take(),
    [WindowsMouseInput(flags: MOUSEEVENTF_LEFTUP)],
  );
  _check('and the button is no longer held', injector.heldButtons.length, 0);
}

void _scrolling() {
  stdout.writeln('');
  stdout.writeln('scrolling');
  final rig = _Rig();
  final injector = rig.injector;
  injector.handle(const ScrollPacket(dx: 0, dy: 40));
  _check('40 px up is one wheel notch (120)', rig.take(), [
    WindowsMouseInput(flags: MOUSEEVENTF_WHEEL, mouseData: 120),
  ]);
  injector.handle(const ScrollPacket(dx: 0, dy: -40));
  _check('40 px down is -120', rig.take(), [
    WindowsMouseInput(flags: MOUSEEVENTF_WHEEL, mouseData: -120),
  ]);
  injector.handle(const ScrollPacket(dx: 13, dy: 0));
  _check(
    '13 px sideways is a fine-grained horizontal -39 (a positive dx scrolls '
    'left, as macOS does; Windows counts right as positive)',
    rig.take(),
    [WindowsMouseInput(flags: MOUSEEVENTF_HWHEEL, mouseData: -39)],
  );
  injector.handle(const ScrollPacket(dx: -40, dy: 40));
  _check('a diagonal sends both wheels, horizontal flipped', rig.take(), [
    WindowsMouseInput(flags: MOUSEEVENTF_WHEEL, mouseData: 120),
    WindowsMouseInput(flags: MOUSEEVENTF_HWHEEL, mouseData: 120),
  ]);
  injector.handle(const ScrollPacket(dx: 0, dy: 0));
  _check('a zero scroll sends nothing', rig.take().length, 0);
}

void _keys() {
  stdout.writeln('');
  stdout.writeln('keys and sticky modifiers');
  var rig = _Rig();
  var injector = rig.injector;
  const a = Keycodes.usageA;
  const b = 0x05;
  final vkA = Keycodes.windows(a)!;
  final vkB = Keycodes.windows(b)!;
  const control = KeyModifiers(control: true);

  injector.handle(_key(a, true, control));
  _check('Ctrl+A down presses Ctrl, then A', rig.take(), [
    _down(VK_LCONTROL),
    _down(vkA),
  ]);
  injector.handle(_key(a, false, control));
  _check('and up releases A, then Ctrl', rig.take(), [
    _up(vkA),
    _up(VK_LCONTROL),
  ]);
  _check('leaving nothing held', injector.heldKeys.length, 0);

  const everything = KeyModifiers(
    control: true,
    shift: true,
    option: true,
    command: true,
  );
  injector.handle(_key(a, true, everything));
  _check(
    'all four modifiers go down in the order Ctrl, Shift, Alt, Win',
    rig.take(),
    [
      _down(VK_LCONTROL),
      _down(VK_LSHIFT),
      _down(VK_LMENU),
      _down(VK_LWIN),
      _down(vkA),
    ],
  );
  injector.handle(_key(a, false, everything));
  _check('and come up in reverse', rig.take(), [
    _up(vkA),
    _up(VK_LWIN),
    _up(VK_LMENU),
    _up(VK_LSHIFT),
    _up(VK_LCONTROL),
  ]);

  injector
    ..handle(_key(a, true, control))
    ..handle(_key(a, true, control));
  _check('a repeated down repeats only the key', rig.take(), [
    _down(VK_LCONTROL),
    _down(vkA),
    _down(vkA),
  ]);
  injector.handle(_key(a, false, control));
  _check('and one up still releases everything', rig.take(), [
    _up(vkA),
    _up(VK_LCONTROL),
  ]);

  injector
    ..handle(_key(a, true, control))
    ..handle(_key(b, true, control));
  _check('two keys sharing Ctrl press it once', rig.take(), [
    _down(VK_LCONTROL),
    _down(vkA),
    _down(vkB),
  ]);
  injector.handle(_key(a, false, control));
  _check('releasing the first keeps Ctrl down', rig.take(), [_up(vkA)]);
  injector.handle(_key(b, false, control));
  _check('releasing the second lets Ctrl go', rig.take(), [
    _up(vkB),
    _up(VK_LCONTROL),
  ]);

  const shift = KeyModifiers(shift: true);
  injector
    ..handle(_key(Keycodes.usageLeftShift, true))
    ..handle(_key(a, true, shift))
    ..handle(_key(a, false, shift));
  _check(
    'a held Shift key is not pressed again for a Shift+A mask',
    rig.take(),
    [_down(VK_LSHIFT), _down(vkA), _up(vkA)],
  );
  _check('and stays held after A', injector.heldKeys, {VK_LSHIFT});
  injector.handle(_key(Keycodes.usageLeftShift, false));
  _check('until its own up', rig.take(), [_up(VK_LSHIFT)]);

  injector.handle(_key(Keycodes.usageLeftCommand, false));
  _check(
    'an up for a key it never pressed sends nothing (no lone Win up)',
    rig.take().length,
    0,
  );
  injector.handle(_key(0x32, true));
  _check('a usage with no Windows key sends nothing', rig.take().length, 0);
  injector.handle(_key(Keycodes.usageArrowRight, true));
  final arrow = rig.take().single as WindowsKeyInput;
  _check(
    'an arrow carries the extended-key flag',
    arrow.flags & KEYEVENTF_EXTENDEDKEY != 0,
    true,
  );

  rig = _Rig(accept: (_) => 0);
  injector = rig.injector;
  injector.handle(_key(a, true));
  _check(
    'a SendInput that inserts nothing is counted as a failure',
    injector.failureCount,
    1,
  );

  rig = _Rig();
  injector = rig.injector;
  injector.handle(_key(a, true, control));
  rig.take();
  rig.accept = (_) => 0;
  injector.handle(_key(a, false, control));
  rig.take();
  _check(
    'a rejected key up is kept for a retry instead of forgotten',
    injector.pendingReleases,
    [_up(vkA), _up(VK_LCONTROL)],
  );
  rig.accept = null;
  injector.handle(const MovePacket(dx: 1, dy: 0));
  _check('and goes out ahead of the next input', rig.take(), [
    _up(vkA),
    _up(VK_LCONTROL),
    _moveTo(101, 200),
  ]);
  _check('leaving nothing pending', injector.pendingReleases.length, 0);

  injector.handle(const ButtonPacket(button: PointerButton.left, down: true));
  rig.take();
  rig.accept = (inputs) => inputs.length - 1;
  injector.handle(const TextPacket('a'));
  injector.handle(const ButtonPacket(button: PointerButton.left, down: false));
  rig.take();
  _check(
    'only releases are retried, never typed text',
    injector.pendingReleases,
    [WindowsMouseInput(flags: MOUSEEVENTF_LEFTUP)],
  );
  rig.accept = null;
  injector.releaseAll();
  _check('releaseAll sends the rejected button up', rig.take(), [
    WindowsMouseInput(flags: MOUSEEVENTF_LEFTUP),
  ]);
}

void _media() {
  stdout.writeln('');
  stdout.writeln('media keys');
  final rig = _Rig();
  final injector = rig.injector;
  final expected = <int, int>{
    Keycodes.mediaPlayPause: VK_MEDIA_PLAY_PAUSE,
    Keycodes.mediaNextTrack: VK_MEDIA_NEXT_TRACK,
    Keycodes.mediaPreviousTrack: VK_MEDIA_PREV_TRACK,
    Keycodes.mediaVolumeUp: VK_VOLUME_UP,
    Keycodes.mediaVolumeDown: VK_VOLUME_DOWN,
    Keycodes.mediaMute: VK_VOLUME_MUTE,
  };
  final taps = <List<WindowsInput>>[];
  for (final entry in expected.entries) {
    injector.handle(MediaPacket(entry.key));
    taps.add(List<WindowsInput>.of(rig.calls.single));
    rig.calls.clear();
  }
  _check('each media key is one atomic down-and-up tap', [
    for (final tap in taps) tap.length,
  ], List<int>.filled(expected.length, 2));
  _check('on the matching media virtual key, marked extended', taps, [
    for (final virtualKey in expected.values)
      [_down(virtualKey), _up(virtualKey)],
  ]);
  _check(
    'and nothing is left held afterwards',
    injector.heldKeys.length + injector.pendingReleases.length,
    0,
  );
  injector.handle(const MediaPacket(0x0040));
  _check('an unknown consumer usage sends nothing', rig.take().length, 0);
  rig.accept = (inputs) => 1;
  injector.handle(const MediaPacket(Keycodes.mediaVolumeUp));
  rig.take();
  _check(
    'a rejected media key-up is retried like any other release',
    injector.pendingReleases,
    [_up(VK_VOLUME_UP)],
  );
}

void _text() {
  stdout.writeln('');
  stdout.writeln('text is typed as Unicode, not as key codes');
  final rig = _Rig();
  final injector = rig.injector;
  injector.handle(const TextPacket('hé'));
  _check('"hé" is two Unicode keystrokes', rig.take(), [
    ..._unicode(0x68),
    ..._unicode(0xE9),
  ]);
  injector.handle(const TextPacket('😀'));
  _check('an emoji is both halves of its surrogate pair', rig.take(), [
    ..._unicode(0xD83D),
    ..._unicode(0xDE00),
  ]);
  injector.handle(const TextPacket('a\nb'));
  _check('a newline is a real Enter press', rig.take(), [
    ..._unicode(0x61),
    _down(VK_RETURN),
    _up(VK_RETURN),
    ..._unicode(0x62),
  ]);
  injector.handle(const TextPacket('a\r\nb'));
  _check('CRLF is one Enter, not two', rig.take(), [
    ..._unicode(0x61),
    _down(VK_RETURN),
    _up(VK_RETURN),
    ..._unicode(0x62),
  ]);

  final long = '${'x' * 511}😀${'y' * 588}';
  injector.handle(TextPacket(long));
  final chunks = List<List<WindowsInput>>.of(rig.calls);
  final typed = rig.take();
  _check('1100 units are split into chunks', chunks.length > 1, true);
  _check(
    'no chunk ends on half an emoji',
    chunks.any((chunk) {
      final last = chunk.last as WindowsKeyInput;
      return last.scanCode >= 0xD800 && last.scanCode <= 0xDBFF;
    }),
    false,
  );
  _check(
    'and every unit is typed exactly once',
    typed.length,
    long.codeUnits.length * 2,
  );
}

void _releaseAll() {
  stdout.writeln('');
  stdout.writeln('releaseAll leaves nothing held');
  final rig = _Rig();
  final injector = rig.injector;
  injector
    ..handle(const ButtonPacket(button: PointerButton.left, down: true))
    ..handle(_key(Keycodes.usageLeftShift, true))
    ..handle(_key(Keycodes.usageA, true, const KeyModifiers(control: true)));
  rig.take();
  injector.releaseAll();
  final released = rig.take();
  final vkA = Keycodes.windows(Keycodes.usageA)!;
  _check(
    'the button, the key and both modifiers are released',
    released.toSet(),
    {
      WindowsMouseInput(flags: MOUSEEVENTF_LEFTUP),
      _up(vkA),
      _up(VK_LSHIFT),
      _up(VK_LCONTROL),
    },
  );
  final keyIndex = released.indexOf(_up(vkA));
  final firstModifier = [
    released.indexOf(_up(VK_LSHIFT)),
    released.indexOf(_up(VK_LCONTROL)),
  ].reduce((x, y) => x < y ? x : y);
  _check(
    'ordinary keys come up before modifiers',
    keyIndex < firstModifier,
    true,
  );
  _check(
    'nothing is left held',
    injector.heldKeys.length + injector.heldButtons.length,
    0,
  );
  injector.releaseAll();
  _check('a second releaseAll sends nothing', rig.take().length, 0);
  injector
    ..handle(_key(Keycodes.usageA, true))
    ..dispose();
  rig.take();
  injector.handle(const MovePacket(dx: 1, dy: 1));
  _check('after dispose nothing more is sent', rig.take().length, 0);
}

Future<void> _realApis(bool pointer) async {
  stdout.writeln('');
  stdout.writeln('the real Windows APIs');
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  final opened = WindowsInjector.open();
  _check(
    'open() gives the Windows injector here',
    opened is WindowsInjector,
    true,
  );
  if (opened is! WindowsInjector) return;
  _check(
    'which needs no permission',
    opened.refreshPermission(),
    InjectorPermission.granted,
  );
  final start = opened.readCursor();
  _check('GetCursorPos answers', start != null, true);
  final width = GetSystemMetrics(SM_CXVIRTUALSCREEN);
  final height = GetSystemMetrics(SM_CYVIRTUALSCREEN);
  _check(
    'the virtual desktop has a size ($width x $height)',
    width > 0 && height > 0,
    true,
  );
  final unscanned = [
    for (final usage in Keycodes.windowsUsages)
      if (MapVirtualKey(Keycodes.windows(usage)!, MAPVK_VK_TO_VSC) == 0) usage,
  ];
  _check('every mapped key has a hardware scan code', unscanned, <int>[]);

  if (!pointer || start == null) {
    stdout.writeln(
      'skipping the live cursor probe (pass --pointer to move the real '
      'cursor by at most 24 px and put it back; no clicks, keys or scrolls)',
    );
    opened.dispose();
    return;
  }
  stdout.writeln(
    'live probe: keep your hands off the mouse for about 3 seconds',
  );
  var targetX = start.x;
  var targetY = start.y;
  var undisturbed = 0;
  final misses = <String>[];
  for (var i = 0; i < 25; i++) {
    final x = start.x + (i % 5) * 6 - 12;
    final y = start.y + (i ~/ 5) * 6 - 12;
    opened.handle(MovePacket(dx: x - targetX, dy: y - targetY));
    targetX = x;
    targetY = y;
    final landed = await _settledCursor(opened);
    if (landed == null) continue;
    undisturbed += 1;
    if (landed != (x: x, y: y)) {
      misses.add('($x, $y) -> (${landed.x}, ${landed.y})');
    }
  }
  _check(
    'at least 20 of 25 landings were undisturbed by the real mouse '
    '($undisturbed)',
    undisturbed >= 20,
    true,
  );
  _check(
    'every undisturbed landing hits its exact pixel, 24 px around the cursor',
    misses,
    <String>[],
  );
  opened.handle(MovePacket(dx: start.x - targetX, dy: start.y - targetY));
  final back = await _settledCursor(opened);
  _check('and the cursor goes back to where it started', back, start);
  for (var i = 0; i < 24; i++) {
    opened.handle(const MovePacket(dx: 1, dy: 0));
  }
  final burst = await _settledCursor(opened);
  _check(
    'a burst of 24 x MOVE(1, 0) with no delay lands exactly 24 px right',
    burst,
    (x: start.x + 24, y: start.y),
  );
  opened.handle(const MovePacket(dx: -24, dy: 0));
  final home = await _settledCursor(opened);
  _check('and back again', home, start);
  _check('SendInput never refused an input', opened.failureCount, 0);
  opened.dispose();
}

Future<WindowsPoint?> _settledCursor(WindowsInjector injector) async {
  await Future<void>.delayed(const Duration(milliseconds: 25));
  final first = injector.readCursor();
  await Future<void>.delayed(const Duration(milliseconds: 25));
  final second = injector.readCursor();
  return first == second ? first : null;
}

Future<void> main(List<String> args) async {
  _keyboardMap();
  _absoluteCoordinates();
  await _motion();
  await _buttons();
  _scrolling();
  _keys();
  _media();
  _text();
  _releaseAll();
  if (Platform.isWindows) {
    await _realApis(args.contains('--pointer'));
  } else {
    stdout.writeln('');
    stdout.writeln('not Windows: skipping the real Windows APIs');
  }
  stdout.writeln('');
  stdout.writeln('$_passed passed, $_failed failed');
  if (_failed > 0) exitCode = 1;
}
