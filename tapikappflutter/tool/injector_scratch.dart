import 'dart:io';

import 'package:tapikappflutter/core/protocol/packet.dart';
import 'package:tapikappflutter/services/injector/injector.dart';
import 'package:tapikappflutter/services/injector/macos_injector.dart';

Future<void> main(List<String> args) async {
  final injector = MacosInjector.open();
  stdout.writeln('injector: ${injector.runtimeType}');
  if (injector is! MacosInjector) {
    stdout.writeln('not macOS — nothing to check');
    return;
  }
  final cursor = injector.readCursor();
  stdout.writeln('CGEventGetLocation: $cursor');
  stdout.writeln('CoreGraphics events build: ${injector.canBuildEvents()}');
  stdout.writeln('permission: ${injector.refreshPermission()}');

  if (injector.permission != InjectorPermission.granted) {
    stdout.writeln(
      'Accessibility is not granted yet. Requesting — approve Tapikapp in '
      'System Settings, then run this again.',
    );
    await injector.requestPermission();
    stdout.writeln('permission after request: ${injector.permission}');
    injector.dispose();
    exitCode = 1;
    return;
  }

  final start = injector.readCursor()!;
  injector.handle(const MovePacket(dx: 40, dy: 25));
  await Future<void>.delayed(const Duration(milliseconds: 60));
  final moved = injector.readCursor()!;
  final dx = (moved.x - start.x).round();
  final dy = (moved.y - start.y).round();
  stdout.writeln(
    'MOVE(40, 25): $start -> $moved  measured delta ($dx, $dy)  '
    '${dx == 40 && dy == 25 ? 'PASS' : 'FAIL'}',
  );
  injector.handle(MovePacket(dx: -dx, dy: -dy));
  await Future<void>.delayed(const Duration(milliseconds: 60));
  final back = injector.readCursor()!;
  stdout.writeln(
    'returned to start: $back  '
    '${(back.x - start.x).abs() < 1 && (back.y - start.y).abs() < 1 ? 'PASS' : 'FAIL'}',
  );

  final burstStart = injector.readCursor()!;
  for (var i = 0; i < 24; i++) {
    injector.handle(const MovePacket(dx: 1, dy: 0));
  }
  await Future<void>.delayed(const Duration(milliseconds: 200));
  final burstEnd = injector.readCursor()!;
  final burstDx = (burstEnd.x - burstStart.x).round();
  stdout.writeln(
    'BURST 24 x MOVE(1,0) with no delay: moved ${burstDx}px  '
    '${burstDx == 24 ? 'PASS' : 'FAIL'}',
  );
  injector.handle(MovePacket(dx: -burstDx, dy: 0));
  await Future<void>.delayed(const Duration(milliseconds: 120));

  stdout.writeln('drawing a square with the real cursor');
  const step = 6;
  const perSide = 40;
  for (final leg in [
    const MovePacket(dx: step, dy: 0),
    const MovePacket(dx: 0, dy: step),
    const MovePacket(dx: -step, dy: 0),
    const MovePacket(dx: 0, dy: -step),
  ]) {
    for (var i = 0; i < perSide; i++) {
      injector.handle(leg);
      await Future<void>.delayed(const Duration(milliseconds: 8));
    }
  }

  stdout.writeln('scrolling down then up');
  for (var i = 0; i < 12; i++) {
    injector.handle(ScrollPacket(dx: 0, dy: i.isEven ? -8 : 8));
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }

  if (args.contains('--click')) {
    stdout.writeln('clicking where the cursor is');
    injector.handle(const ButtonPacket(button: PointerButton.left, down: true));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    injector.handle(
      const ButtonPacket(button: PointerButton.left, down: false),
    );
  } else {
    stdout.writeln('skipping the click (pass --click to include it)');
  }

  stdout.writeln('releasing anything still held');
  injector.releaseAll();
  injector.dispose();
  stdout.writeln('done');
}
