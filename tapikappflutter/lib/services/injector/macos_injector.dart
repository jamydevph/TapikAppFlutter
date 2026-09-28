import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../../core/protocol/keycodes.dart';
import '../../core/protocol/packet.dart';
import 'injector.dart';

typedef _CGPointStruct = CGPoint;

final class CGPoint extends Struct {
  @Double()
  external double x;

  @Double()
  external double y;
}

final class CGRect extends Struct {
  @Double()
  external double x;

  @Double()
  external double y;

  @Double()
  external double width;

  @Double()
  external double height;
}

typedef _EventSourceCreateNative = Pointer<Void> Function(Int32);
typedef _EventSourceCreate = Pointer<Void> Function(int);

typedef _EventCreateNative = Pointer<Void> Function(Pointer<Void>);
typedef _EventCreate = Pointer<Void> Function(Pointer<Void>);

typedef _EventGetLocationNative = _CGPointStruct Function(Pointer<Void>);
typedef _EventGetLocation = _CGPointStruct Function(Pointer<Void>);

typedef _MouseEventCreateNative = Pointer<Void> Function(
  Pointer<Void>,
  Uint32,
  _CGPointStruct,
  Uint32,
);
typedef _MouseEventCreate = Pointer<Void> Function(
  Pointer<Void>,
  int,
  _CGPointStruct,
  int,
);

typedef _ScrollEventCreateNative = Pointer<Void> Function(
  Pointer<Void>,
  Uint32,
  Uint32,
  Int32,
  Int32,
  Int32,
);
typedef _ScrollEventCreate = Pointer<Void> Function(
  Pointer<Void>,
  int,
  int,
  int,
  int,
  int,
);

typedef _KeyEventCreateNative = Pointer<Void> Function(
  Pointer<Void>,
  Uint16,
  Bool,
);
typedef _KeyEventCreate = Pointer<Void> Function(Pointer<Void>, int, bool);

typedef _SetUnicodeNative = Void Function(
  Pointer<Void>,
  UintPtr,
  Pointer<Uint16>,
);
typedef _SetUnicode = void Function(Pointer<Void>, int, Pointer<Uint16>);

typedef _SetFlagsNative = Void Function(Pointer<Void>, Uint64);
typedef _SetFlags = void Function(Pointer<Void>, int);

typedef _GetFlagsNative = Uint64 Function(Pointer<Void>);
typedef _GetFlags = int Function(Pointer<Void>);

typedef _SetFieldNative = Void Function(Pointer<Void>, Uint32, Int64);
typedef _SetField = void Function(Pointer<Void>, int, int);

typedef _DisplayBoundsNative = CGRect Function(Uint32);
typedef _DisplayBounds = CGRect Function(int);

typedef _ActiveDisplaysNative = Int32 Function(
  Uint32,
  Pointer<Uint32>,
  Pointer<Uint32>,
);
typedef _ActiveDisplays = int Function(int, Pointer<Uint32>, Pointer<Uint32>);

typedef _EventPostNative = Void Function(Uint32, Pointer<Void>);
typedef _EventPost = void Function(int, Pointer<Void>);

typedef _ReleaseNative = Void Function(Pointer<Void>);
typedef _Release = void Function(Pointer<Void>);

typedef _TrustedNative = Uint8 Function();
typedef _Trusted = int Function();

typedef _TrustedWithOptionsNative = Uint8 Function(Pointer<Void>);
typedef _TrustedWithOptions = int Function(Pointer<Void>);

typedef _DictionaryCreateNative = Pointer<Void> Function(
  Pointer<Void>,
  Pointer<Pointer<Void>>,
  Pointer<Pointer<Void>>,
  Int64,
  Pointer<Void>,
  Pointer<Void>,
);
typedef _DictionaryCreate = Pointer<Void> Function(
  Pointer<Void>,
  Pointer<Pointer<Void>>,
  Pointer<Pointer<Void>>,
  int,
  Pointer<Void>,
  Pointer<Void>,
);

class MacosInjector implements Injector {
  MacosInjector._(this._bindings);

  static const int _sourceStateHidSystem = 1;
  static const int _tapHid = 0;
  static const int _scrollUnitPixel = 0;
  static const int _eventLeftDown = 1;
  static const int _eventLeftUp = 2;
  static const int _eventRightDown = 3;
  static const int _eventRightUp = 4;
  static const int _eventMouseMoved = 5;
  static const int _eventLeftDragged = 6;
  static const int _eventRightDragged = 7;
  static const int _eventOtherDown = 25;
  static const int _eventOtherUp = 26;
  static const int _eventOtherDragged = 27;
  static const int flagShift = 0x00020000;
  static const int flagControl = 0x00040000;
  static const int flagOption = 0x00080000;
  static const int flagCommand = 0x00100000;
  static const int _maxTextUnits = 512;
  static const int _fieldDeltaX = 4;
  static const int _fieldDeltaY = 5;
  static const int _maxDisplays = 8;
  static const Duration resyncIdle = Duration(milliseconds: 250);
  static const Duration permissionRecheck = Duration(milliseconds: 500);
  static const String settingsUrl =
      'x-apple.systempreferences:com.apple.preference.security'
      '?Privacy_Accessibility';

  static Injector open() {
    if (!Platform.isMacOS) return const UnsupportedInjector();
    try {
      return MacosInjector._(_Bindings.load());
    } on ArgumentError {
      return const UnsupportedInjector();
    }
  }

  final _Bindings _bindings;
  final Set<PointerButton> _held = <PointerButton>{};
  final Set<int> _heldKeys = <int>{};

  final Stopwatch _clock = Stopwatch()..start();

  Pointer<Void> _source = nullptr;
  int _failures = 0;
  double _targetX = 0;
  double _targetY = 0;
  bool _synced = false;
  int _lastMoveMs = 0;
  int _lastPermissionMs = 0;
  _Bounds? _bounds;
  InjectorPermission _permission = InjectorPermission.denied;
  bool _disposed = false;

  @override
  InjectorPermission get permission => _permission;

  @override
  InjectorPermission refreshPermission() {
    if (_disposed) return _permission;
    _permission = _bindings.isTrusted() != 0
        ? InjectorPermission.granted
        : InjectorPermission.denied;
    return _permission;
  }

  @override
  Future<void> requestPermission() async {
    if (_disposed) return;
    _bindings.promptForTrust();
    refreshPermission();
    if (_permission != InjectorPermission.granted) {
      await Process.run('open', [settingsUrl]);
    }
  }

  @override
  void handle(Packet packet) {
    if (_disposed) return;
    if (_permission != InjectorPermission.granted && !_recheckPermission()) {
      return;
    }
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
        case PingPacket():
          return;
      }
    } catch (_) {
      _failures += 1;
    }
  }

  int get failureCount => _failures;

  @override
  void releaseAll() {
    if (_disposed) return;
    for (final button in _held.toList()) {
      _button(button, false);
    }
    for (final usage in _heldKeys.toList()) {
      _key(usage, KeyModifiers.none, false);
    }
    for (final usage in const [
      Keycodes.usageLeftCommand,
      Keycodes.usageLeftOption,
      Keycodes.usageLeftShift,
      Keycodes.usageLeftControl,
    ]) {
      final virtualKey = Keycodes.macos(usage);
      if (virtualKey == null) continue;
      final event = _bindings.keyEventCreate(
        _ensureSource(),
        virtualKey,
        false,
      );
      if (event == nullptr) continue;
      _post(event);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    releaseAll();
    _disposed = true;
    if (_source != nullptr) {
      _bindings.release(_source);
      _source = nullptr;
    }
  }

  CGPointSnapshot? readCursor() {
    if (_disposed) return null;
    final probe = _bindings.eventCreate(nullptr);
    if (probe == nullptr) return null;
    final at = _bindings.eventGetLocation(probe);
    _bindings.release(probe);
    return CGPointSnapshot(at.x, at.y);
  }

  bool canBuildEvents() {
    if (_disposed) return false;
    final source = _ensureSource();
    if (source == nullptr) return false;
    final target = calloc<CGPoint>();
    final snapshot = readCursor();
    if (snapshot == null) {
      calloc.free(target);
      return false;
    }
    target.ref.x = snapshot.x;
    target.ref.y = snapshot.y;
    final move = _bindings.mouseEventCreate(
      source,
      _eventMouseMoved,
      target.ref,
      0,
    );
    final scroll = _bindings.scrollEventCreate(
      source,
      _scrollUnitPixel,
      2,
      1,
      0,
      0,
    );
    calloc.free(target);
    final built = move != nullptr && scroll != nullptr;
    if (move != nullptr) _bindings.release(move);
    if (scroll != nullptr) _bindings.release(scroll);
    return built;
  }

  void _move(double dx, double dy) {
    if (!_syncTarget()) return;
    _targetX += dx;
    _targetY += dy;
    _clampTarget();
    final dragging = _held.isNotEmpty;
    _postAt(
      dragging ? _dragTypeFor(_held.first) : _eventMouseMoved,
      dragging ? _buttonCode(_held.first) : 0,
      dx: dx.round(),
      dy: dy.round(),
    );
  }

  void _button(PointerButton button, bool down) {
    if (!_syncTarget()) return;
    _postAt(_buttonTypeFor(button, down), _buttonCode(button));
    if (down) {
      _held.add(button);
    } else {
      _held.remove(button);
    }
  }

  void _postAt(int type, int button, {int dx = 0, int dy = 0}) {
    final target = calloc<CGPoint>();
    try {
      target.ref.x = _targetX;
      target.ref.y = _targetY;
      final event = _bindings.mouseEventCreate(
        _ensureSource(),
        type,
        target.ref,
        button,
      );
      if (event == nullptr) return;
      if (dx != 0 || dy != 0) {
        _bindings.setField(event, _fieldDeltaX, dx);
        _bindings.setField(event, _fieldDeltaY, dy);
      }
      _post(event);
    } finally {
      calloc.free(target);
    }
  }

  bool _syncTarget() {
    final now = _clock.elapsedMilliseconds;
    final idle = now - _lastMoveMs > resyncIdle.inMilliseconds;
    _lastMoveMs = now;
    if (_synced && !idle) return true;
    final at = readCursor();
    if (at == null) return false;
    _targetX = at.x;
    _targetY = at.y;
    _synced = true;
    _bounds = _bindings.desktopBounds();
    return true;
  }

  void _clampTarget() {
    final bounds = _bounds;
    if (bounds == null) return;
    _targetX = _targetX.clamp(bounds.left, bounds.right);
    _targetY = _targetY.clamp(bounds.top, bounds.bottom);
  }

  bool _recheckPermission() {
    final now = _clock.elapsedMilliseconds;
    if (now - _lastPermissionMs < permissionRecheck.inMilliseconds) {
      return false;
    }
    _lastPermissionMs = now;
    return refreshPermission() == InjectorPermission.granted;
  }

  void _key(int usage, KeyModifiers modifiers, bool down) {
    final virtualKey = Keycodes.macos(usage);
    if (virtualKey == null) return;
    final event = _bindings.keyEventCreate(_ensureSource(), virtualKey, down);
    if (event == nullptr) return;
    _applyFlags(event, modifiers);
    _post(event);
    if (down) {
      _heldKeys.add(usage);
    } else {
      _heldKeys.remove(usage);
    }
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
      _typeChunk(units.sublist(start, end));
      start = end;
    }
  }

  static bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

  void _typeChunk(List<int> units) {
    final buffer = calloc<Uint16>(units.length);
    try {
      for (var i = 0; i < units.length; i++) {
        buffer[i] = units[i];
      }
      for (final down in [true, false]) {
        final event = _bindings.keyEventCreate(_ensureSource(), 0, down);
        if (event == nullptr) continue;
        _bindings.setUnicode(event, units.length, buffer);
        _post(event);
      }
    } finally {
      calloc.free(buffer);
    }
  }

  void _applyFlags(Pointer<Void> event, KeyModifiers modifiers) {
    final mask = _flagsFor(modifiers);
    if (mask == 0) return;
    _bindings.setFlags(event, _bindings.getFlags(event) | mask);
  }

  static int _flagsFor(KeyModifiers modifiers) {
    var flags = 0;
    if (modifiers.command) flags |= flagCommand;
    if (modifiers.option) flags |= flagOption;
    if (modifiers.shift) flags |= flagShift;
    if (modifiers.control) flags |= flagControl;
    return flags;
  }

  void _scroll(int dx, int dy) {
    _post(
      _bindings.scrollEventCreate(
        _ensureSource(),
        _scrollUnitPixel,
        2,
        dy,
        dx,
        0,
      ),
    );
  }

  void _post(Pointer<Void> event) {
    if (event == nullptr) return;
    _bindings.eventPost(_tapHid, event);
    _bindings.release(event);
  }

  Pointer<Void> _ensureSource() {
    if (_source == nullptr) {
      _source = _bindings.eventSourceCreate(_sourceStateHidSystem);
    }
    return _source;
  }

  static int _buttonCode(PointerButton button) {
    return switch (button) {
      PointerButton.left => 0,
      PointerButton.right => 1,
      PointerButton.middle => 2,
    };
  }

  static int _buttonTypeFor(PointerButton button, bool down) {
    return switch (button) {
      PointerButton.left => down ? _eventLeftDown : _eventLeftUp,
      PointerButton.right => down ? _eventRightDown : _eventRightUp,
      PointerButton.middle => down ? _eventOtherDown : _eventOtherUp,
    };
  }

  static int _dragTypeFor(PointerButton button) {
    return switch (button) {
      PointerButton.left => _eventLeftDragged,
      PointerButton.right => _eventRightDragged,
      PointerButton.middle => _eventOtherDragged,
    };
  }
}

class _Bounds {
  const _Bounds(this.left, this.top, this.right, this.bottom);

  static const _Bounds unbounded = _Bounds(
    double.negativeInfinity,
    double.negativeInfinity,
    double.infinity,
    double.infinity,
  );

  final double left;
  final double top;
  final double right;
  final double bottom;
}

class CGPointSnapshot {
  const CGPointSnapshot(this.x, this.y);

  final double x;
  final double y;

  @override
  String toString() => '(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)})';
}

class _Bindings {
  _Bindings._({
    required this.eventSourceCreate,
    required this.eventCreate,
    required this.eventGetLocation,
    required this.mouseEventCreate,
    required this.scrollEventCreate,
    required this.eventPost,
    required this.keyEventCreate,
    required this.setUnicode,
    required this.setFlags,
    required this.getFlags,
    required this.setField,
    required this.release,
    required this.desktopBounds,
    required this.isTrusted,
    required this.promptForTrust,
  });

  static const String applicationServices =
      '/System/Library/Frameworks/ApplicationServices.framework/'
      'ApplicationServices';
  static const String coreFoundation =
      '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation';

  final _EventSourceCreate eventSourceCreate;
  final _EventCreate eventCreate;
  final _EventGetLocation eventGetLocation;
  final _MouseEventCreate mouseEventCreate;
  final _ScrollEventCreate scrollEventCreate;
  final _EventPost eventPost;
  final _KeyEventCreate keyEventCreate;
  final _SetUnicode setUnicode;
  final _SetFlags setFlags;
  final _GetFlags getFlags;
  final _SetField setField;
  final _Release release;
  final _Bounds Function() desktopBounds;
  final _Trusted isTrusted;
  final void Function() promptForTrust;

  static _Bindings load() {
    final services = DynamicLibrary.open(applicationServices);
    final core = DynamicLibrary.open(coreFoundation);
    final release = core.lookupFunction<_ReleaseNative, _Release>('CFRelease');
    final dictionaryCreate = core
        .lookupFunction<_DictionaryCreateNative, _DictionaryCreate>(
          'CFDictionaryCreate',
        );
    final keyCallbacks = core.lookup<Void>('kCFTypeDictionaryKeyCallBacks');
    final valueCallbacks = core.lookup<Void>('kCFTypeDictionaryValueCallBacks');
    final booleanTrue = core.lookup<Pointer<Void>>('kCFBooleanTrue').value;
    final promptKey = services
        .lookup<Pointer<Void>>('kAXTrustedCheckOptionPrompt')
        .value;
    final trustedWithOptions = services
        .lookupFunction<_TrustedWithOptionsNative, _TrustedWithOptions>(
          'AXIsProcessTrustedWithOptions',
        );

    void promptForTrust() {
      final keys = calloc<Pointer<Void>>();
      final values = calloc<Pointer<Void>>();
      keys.value = promptKey;
      values.value = booleanTrue;
      final options = dictionaryCreate(
        nullptr,
        keys,
        values,
        1,
        keyCallbacks,
        valueCallbacks,
      );
      trustedWithOptions(options);
      if (options != nullptr) release(options);
      calloc.free(keys);
      calloc.free(values);
    }

    final displayBounds = services
        .lookupFunction<_DisplayBoundsNative, _DisplayBounds>(
          'CGDisplayBounds',
        );
    final activeDisplays = services
        .lookupFunction<_ActiveDisplaysNative, _ActiveDisplays>(
          'CGGetActiveDisplayList',
        );

    _Bounds desktopBounds() {
      final ids = calloc<Uint32>(MacosInjector._maxDisplays);
      final count = calloc<Uint32>();
      try {
        if (activeDisplays(MacosInjector._maxDisplays, ids, count) != 0 ||
            count.value == 0) {
          return _Bounds.unbounded;
        }
        var left = double.infinity;
        var top = double.infinity;
        var right = double.negativeInfinity;
        var bottom = double.negativeInfinity;
        for (var i = 0; i < count.value; i++) {
          final frame = displayBounds(ids[i]);
          left = frame.x < left ? frame.x : left;
          top = frame.y < top ? frame.y : top;
          final edgeX = frame.x + frame.width - 1;
          final edgeY = frame.y + frame.height - 1;
          right = edgeX > right ? edgeX : right;
          bottom = edgeY > bottom ? edgeY : bottom;
        }
        return _Bounds(left, top, right, bottom);
      } finally {
        calloc.free(ids);
        calloc.free(count);
      }
    }

    return _Bindings._(
      eventSourceCreate: services
          .lookupFunction<_EventSourceCreateNative, _EventSourceCreate>(
            'CGEventSourceCreate',
          ),
      eventCreate: services.lookupFunction<_EventCreateNative, _EventCreate>(
        'CGEventCreate',
      ),
      eventGetLocation: services
          .lookupFunction<_EventGetLocationNative, _EventGetLocation>(
            'CGEventGetLocation',
          ),
      mouseEventCreate: services
          .lookupFunction<_MouseEventCreateNative, _MouseEventCreate>(
            'CGEventCreateMouseEvent',
          ),
      scrollEventCreate: services
          .lookupFunction<_ScrollEventCreateNative, _ScrollEventCreate>(
            'CGEventCreateScrollWheelEvent2',
          ),
      eventPost: services.lookupFunction<_EventPostNative, _EventPost>(
        'CGEventPost',
      ),
      keyEventCreate: services
          .lookupFunction<_KeyEventCreateNative, _KeyEventCreate>(
            'CGEventCreateKeyboardEvent',
          ),
      setUnicode: services.lookupFunction<_SetUnicodeNative, _SetUnicode>(
        'CGEventKeyboardSetUnicodeString',
      ),
      setFlags: services.lookupFunction<_SetFlagsNative, _SetFlags>(
        'CGEventSetFlags',
      ),
      getFlags: services.lookupFunction<_GetFlagsNative, _GetFlags>(
        'CGEventGetFlags',
      ),
      setField: services.lookupFunction<_SetFieldNative, _SetField>(
        'CGEventSetIntegerValueField',
      ),
      release: release,
      desktopBounds: desktopBounds,
      isTrusted: services.lookupFunction<_TrustedNative, _Trusted>(
        'AXIsProcessTrusted',
      ),
      promptForTrust: promptForTrust,
    );
  }
}
