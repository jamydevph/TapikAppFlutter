import 'dart:ffi';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../../core/protocol/keycodes.dart';
import '../../core/protocol/packet.dart';
import 'injector.dart';

sealed class WindowsInput extends Equatable {
  const WindowsInput();
}

class WindowsMouseInput extends WindowsInput {
  const WindowsMouseInput({
    required this.flags,
    this.dx = 0,
    this.dy = 0,
    this.mouseData = 0,
  });

  final int flags;
  final int dx;
  final int dy;
  final int mouseData;

  @override
  List<Object?> get props => [flags, dx, dy, mouseData];
}

class WindowsKeyInput extends WindowsInput {
  const WindowsKeyInput({
    required this.flags,
    this.virtualKey = 0,
    this.scanCode = 0,
  });

  final int flags;
  final int virtualKey;
  final int scanCode;

  bool get isUp => flags & KEYEVENTF_KEYUP != 0;

  @override
  List<Object?> get props => [flags, virtualKey, scanCode];
}

typedef WindowsInputSink = int Function(List<WindowsInput> inputs);
typedef WindowsPoint = ({int x, int y});
typedef WindowsScreen = ({int left, int top, int width, int height});
typedef WindowsMonitorAt = WindowsScreen? Function(int x, int y);

class WindowsInjector implements Injector {
  WindowsInjector({
    WindowsInputSink? sink,
    WindowsPoint? Function()? cursor,
    WindowsScreen Function()? screen,
    WindowsMonitorAt? monitorAt,
    int Function(int virtualKey)? scanCodeFor,
  }) : _sink = sink ?? _sendInput,
       _cursor = cursor ?? _readCursor,
       _screen = screen ?? _readScreen,
       _monitorAt = monitorAt ?? _nearestMonitor,
       _scanCodeFor = scanCodeFor ?? _mapScanCode;

  static const int pixelsPerDetent = 40;
  static const int wheelDelta = 120;
  static const int normalizedExtent = 65536;
  static const int _maxTextUnits = 512;
  static const Duration resyncIdle = Duration(milliseconds: 250);
  static final int moveFlags =
      MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK;
  static const Set<int> extendedKeys = <int>{
    VK_PRIOR,
    VK_NEXT,
    VK_END,
    VK_HOME,
    VK_LEFT,
    VK_UP,
    VK_RIGHT,
    VK_DOWN,
    VK_INSERT,
    VK_DELETE,
    VK_RCONTROL,
    VK_RMENU,
    VK_LWIN,
    VK_RWIN,
  };
  static const Set<int> modifierKeys = <int>{
    VK_LCONTROL,
    VK_RCONTROL,
    VK_LSHIFT,
    VK_RSHIFT,
    VK_LMENU,
    VK_RMENU,
    VK_LWIN,
    VK_RWIN,
  };

  static Injector open() {
    if (!Platform.isWindows) return const UnsupportedInjector();
    return WindowsInjector();
  }

  final WindowsInputSink _sink;
  final WindowsPoint? Function() _cursor;
  final WindowsScreen Function() _screen;
  final WindowsMonitorAt _monitorAt;
  final int Function(int virtualKey) _scanCodeFor;
  final Set<PointerButton> _held = <PointerButton>{};
  final Map<int, int> _holds = <int, int>{};
  final Map<int, List<int>> _maskFor = <int, List<int>>{};
  final List<WindowsInput> _pendingReleases = <WindowsInput>[];
  final Stopwatch _clock = Stopwatch()..start();

  int _failures = 0;
  double _targetX = 0;
  double _targetY = 0;
  bool _synced = false;
  int _lastMoveMs = 0;
  WindowsScreen? _bounds;
  bool _disposed = false;

  int get failureCount => _failures;

  Set<int> get heldKeys => Set<int>.unmodifiable(_holds.keys);

  Set<PointerButton> get heldButtons => Set<PointerButton>.unmodifiable(_held);

  List<WindowsInput> get pendingReleases =>
      List<WindowsInput>.unmodifiable(_pendingReleases);

  @override
  InjectorPermission get permission => InjectorPermission.granted;

  @override
  InjectorPermission refreshPermission() => InjectorPermission.granted;

  @override
  Future<void> requestPermission() async {}

  @override
  void handle(Packet packet) {
    if (_disposed) return;
    try {
      switch (packet) {
        case MovePacket(:final dx, :final dy):
          _move(dx.toDouble(), dy.toDouble());
        case ButtonPacket(:final button, :final down):
          _button(button, down);
        case ScrollPacket(:final dx, :final dy):
          _scroll(dx, dy);
        case KeyPacket(:final keyCode, :final modifiers, :final down):
          _key(keyCode, modifiers, down);
        case TextPacket(:final text):
          _text(text);
        case PairPacket():
          return;
        case PingPacket():
          return;
      }
    } catch (_) {
      _failures += 1;
    }
  }

  @override
  void releaseAll() {
    if (_disposed) return;
    final inputs = <WindowsInput>[
      for (final button in _held)
        WindowsMouseInput(flags: _buttonFlag(button, false)),
      for (final virtualKey in _holds.keys)
        if (!modifierKeys.contains(virtualKey)) _keyInput(virtualKey, false),
      for (final virtualKey in _holds.keys)
        if (modifierKeys.contains(virtualKey)) _keyInput(virtualKey, false),
    ];
    _held.clear();
    _holds.clear();
    _maskFor.clear();
    _send(inputs);
  }

  @override
  void dispose() {
    if (_disposed) return;
    releaseAll();
    _disposed = true;
  }

  WindowsPoint? readCursor() => _disposed ? null : _cursor();

  static int normalize(int pixel, int origin, int extent) {
    if (extent <= 1) return 0;
    final offset = pixel - origin;
    if (offset <= 0) return 0;
    final scaled = (offset * normalizedExtent + extent - 1) ~/ extent;
    return scaled > normalizedExtent - 1 ? normalizedExtent - 1 : scaled;
  }

  static int wheelUnits(int pixels) => pixels * wheelDelta ~/ pixelsPerDetent;

  static List<int> modifiersFor(KeyModifiers modifiers) => <int>[
    if (modifiers.control) VK_LCONTROL,
    if (modifiers.shift) VK_LSHIFT,
    if (modifiers.option) VK_LMENU,
    if (modifiers.command) VK_LWIN,
  ];

  void _move(double dx, double dy) {
    if (!_syncTarget()) return;
    _targetX += dx;
    _targetY += dy;
    _clampTarget();
    final bounds = _bounds!;
    _send([
      WindowsMouseInput(
        flags: moveFlags,
        dx: normalize(_targetX.round(), bounds.left, bounds.width),
        dy: normalize(_targetY.round(), bounds.top, bounds.height),
      ),
    ]);
  }

  void _button(PointerButton button, bool down) {
    _syncTarget();
    _send([WindowsMouseInput(flags: _buttonFlag(button, down))]);
    if (down) {
      _held.add(button);
    } else {
      _held.remove(button);
    }
  }

  void _scroll(int dx, int dy) {
    _send([
      if (dy != 0)
        WindowsMouseInput(flags: MOUSEEVENTF_WHEEL, mouseData: wheelUnits(dy)),
      if (dx != 0)
        WindowsMouseInput(
          flags: MOUSEEVENTF_HWHEEL,
          mouseData: -wheelUnits(dx),
        ),
    ]);
  }

  void _key(int usage, KeyModifiers modifiers, bool down) {
    final virtualKey = Keycodes.windows(usage);
    if (virtualKey == null) return;
    final inputs = <WindowsInput>[];
    if (down) {
      if (_maskFor.containsKey(usage)) {
        inputs.add(_keyInput(virtualKey, true));
      } else {
        final mask = [
          for (final modifier in modifiersFor(modifiers))
            if (modifier != virtualKey) modifier,
        ];
        for (final modifier in mask) {
          _press(inputs, modifier);
        }
        _press(inputs, virtualKey);
        _maskFor[usage] = mask;
      }
    } else {
      final mask = _maskFor.remove(usage);
      if (mask == null) return;
      _release(inputs, virtualKey);
      for (final modifier in mask.reversed) {
        _release(inputs, modifier);
      }
    }
    _send(inputs);
  }

  void _press(List<WindowsInput> inputs, int virtualKey) {
    final count = _holds[virtualKey] ?? 0;
    if (count == 0) inputs.add(_keyInput(virtualKey, true));
    _holds[virtualKey] = count + 1;
  }

  void _release(List<WindowsInput> inputs, int virtualKey) {
    final count = _holds[virtualKey] ?? 0;
    if (count == 0) return;
    if (count == 1) {
      _holds.remove(virtualKey);
      inputs.add(_keyInput(virtualKey, false));
    } else {
      _holds[virtualKey] = count - 1;
    }
  }

  WindowsKeyInput _keyInput(int virtualKey, bool down) {
    var flags = extendedKeys.contains(virtualKey) ? KEYEVENTF_EXTENDEDKEY : 0;
    if (!down) flags |= KEYEVENTF_KEYUP;
    return WindowsKeyInput(
      virtualKey: virtualKey,
      scanCode: _scanCodeFor(virtualKey),
      flags: flags,
    );
  }

  void _text(String text) {
    if (text.isEmpty) return;
    final units = text.codeUnits;
    var start = 0;
    while (start < units.length) {
      var end = start + _maxTextUnits < units.length
          ? start + _maxTextUnits
          : units.length;
      if (end < units.length && _isHighSurrogate(units[end - 1])) {
        end -= 1;
      }
      _send(_typeChunk(units, start, end));
      start = end;
    }
  }

  List<WindowsInput> _typeChunk(List<int> units, int start, int end) {
    final inputs = <WindowsInput>[];
    for (var i = start; i < end; i++) {
      final unit = units[i];
      if (unit == 0x0A && i > 0 && units[i - 1] == 0x0D) continue;
      if (unit == 0x0A || unit == 0x0D) {
        inputs
          ..add(_keyInput(VK_RETURN, true))
          ..add(_keyInput(VK_RETURN, false));
        continue;
      }
      inputs
        ..add(WindowsKeyInput(scanCode: unit, flags: KEYEVENTF_UNICODE))
        ..add(
          WindowsKeyInput(
            scanCode: unit,
            flags: KEYEVENTF_UNICODE | KEYEVENTF_KEYUP,
          ),
        );
    }
    return inputs;
  }

  static bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

  bool _syncTarget() {
    final now = _clock.elapsedMilliseconds;
    final idle = now - _lastMoveMs > resyncIdle.inMilliseconds;
    _lastMoveMs = now;
    if (_synced && !idle) return true;
    final at = _cursor();
    if (at == null) {
      _synced = false;
      return false;
    }
    _targetX = at.x.toDouble();
    _targetY = at.y.toDouble();
    _bounds = _screen();
    _synced = true;
    return true;
  }

  void _clampTarget() {
    final bounds = _bounds;
    if (bounds == null || bounds.width <= 0 || bounds.height <= 0) return;
    _targetX = _targetX.clamp(
      bounds.left.toDouble(),
      (bounds.left + bounds.width - 1).toDouble(),
    );
    _targetY = _targetY.clamp(
      bounds.top.toDouble(),
      (bounds.top + bounds.height - 1).toDouble(),
    );
    final monitor = _monitorAt(_targetX.round(), _targetY.round());
    if (monitor == null || monitor.width <= 0 || monitor.height <= 0) return;
    _targetX = _targetX.clamp(
      monitor.left.toDouble(),
      (monitor.left + monitor.width - 1).toDouble(),
    );
    _targetY = _targetY.clamp(
      monitor.top.toDouble(),
      (monitor.top + monitor.height - 1).toDouble(),
    );
  }

  void _send(List<WindowsInput> inputs) {
    final batch = [..._pendingReleases, ...inputs];
    if (batch.isEmpty) return;
    final inserted = _sink(batch);
    _pendingReleases.clear();
    if (inserted >= batch.length) return;
    _failures += 1;
    for (final input in batch.skip(inserted < 0 ? 0 : inserted)) {
      if (_isRelease(input) && !_pendingReleases.contains(input)) {
        _pendingReleases.add(input);
      }
    }
  }

  static bool _isRelease(WindowsInput input) {
    return switch (input) {
      WindowsKeyInput(:final flags) =>
        flags & KEYEVENTF_KEYUP != 0 && flags & KEYEVENTF_UNICODE == 0,
      WindowsMouseInput(:final flags) =>
        flags &
                (MOUSEEVENTF_LEFTUP |
                    MOUSEEVENTF_RIGHTUP |
                    MOUSEEVENTF_MIDDLEUP) !=
            0,
    };
  }

  static int _buttonFlag(PointerButton button, bool down) {
    return switch (button) {
      PointerButton.left => down ? MOUSEEVENTF_LEFTDOWN : MOUSEEVENTF_LEFTUP,
      PointerButton.right => down ? MOUSEEVENTF_RIGHTDOWN : MOUSEEVENTF_RIGHTUP,
      PointerButton.middle =>
        down ? MOUSEEVENTF_MIDDLEDOWN : MOUSEEVENTF_MIDDLEUP,
    };
  }

  static int _sendInput(List<WindowsInput> inputs) {
    final buffer = calloc<INPUT>(inputs.length);
    try {
      for (var i = 0; i < inputs.length; i++) {
        final entry = buffer[i];
        switch (inputs[i]) {
          case WindowsMouseInput(
            :final flags,
            :final dx,
            :final dy,
            :final mouseData,
          ):
            entry.type = INPUT_MOUSE;
            entry.mi.dx = dx;
            entry.mi.dy = dy;
            entry.mi.mouseData = mouseData;
            entry.mi.dwFlags = MOUSE_EVENT_FLAGS(flags);
          case WindowsKeyInput(
            :final flags,
            :final virtualKey,
            :final scanCode,
          ):
            entry.type = INPUT_KEYBOARD;
            entry.ki.wVk = VIRTUAL_KEY(virtualKey);
            entry.ki.wScan = scanCode;
            entry.ki.dwFlags = KEYBD_EVENT_FLAGS(flags);
        }
      }
      return SendInput(inputs.length, buffer, sizeOf<INPUT>()).value;
    } finally {
      calloc.free(buffer);
    }
  }

  static WindowsPoint? _readCursor() {
    final point = calloc<POINT>();
    try {
      if (!GetCursorPos(point).value) return null;
      return (x: point.ref.x, y: point.ref.y);
    } finally {
      calloc.free(point);
    }
  }

  static WindowsScreen _readScreen() => (
    left: GetSystemMetrics(SM_XVIRTUALSCREEN),
    top: GetSystemMetrics(SM_YVIRTUALSCREEN),
    width: GetSystemMetrics(SM_CXVIRTUALSCREEN),
    height: GetSystemMetrics(SM_CYVIRTUALSCREEN),
  );

  static WindowsScreen? _nearestMonitor(int x, int y) {
    final point = calloc<POINT>();
    final info = calloc<MONITORINFO>();
    try {
      point.ref
        ..x = x
        ..y = y;
      final monitor = MonitorFromPoint(point.ref, MONITOR_DEFAULTTONEAREST);
      if (monitor.address == 0) return null;
      info.ref.cbSize = sizeOf<MONITORINFO>();
      if (!GetMonitorInfo(monitor, info)) return null;
      final rect = info.ref.rcMonitor;
      return (
        left: rect.left,
        top: rect.top,
        width: rect.right - rect.left,
        height: rect.bottom - rect.top,
      );
    } finally {
      calloc.free(point);
      calloc.free(info);
    }
  }

  static int _mapScanCode(int virtualKey) =>
      MapVirtualKey(virtualKey, MAPVK_VK_TO_VSC);
}
