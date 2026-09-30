import 'dart:math' as math;

import '../../core/protocol/packet.dart';
import '../transport/transport.dart';

class PointerPump {
  PointerPump(this._transport);

  static const double slowSpeed = 220;
  static const double fastSpeed = 2400;
  static const double maxGain = 3.2;
  static const double scrollGain = 1.6;
  static const Duration nominalFrame = Duration(milliseconds: 8);

  final Transport _transport;

  double _moveX = 0;
  double _moveY = 0;
  double _scrollX = 0;
  double _scrollY = 0;
  double _carryX = 0;
  double _carryY = 0;
  double _scrollCarryX = 0;
  double _scrollCarryY = 0;

  double sensitivity = 1;
  bool naturalScrolling = true;

  void addMove(double dx, double dy) {
    _moveX += dx;
    _moveY += dy;
  }

  void addScroll(double dx, double dy) {
    _scrollX += dx;
    _scrollY += dy;
  }

  void flush(Duration frame) {
    _flushMove(frame);
    _flushScroll();
  }

  void reset() {
    _moveX = 0;
    _moveY = 0;
    _scrollX = 0;
    _scrollY = 0;
    _carryX = 0;
    _carryY = 0;
    _scrollCarryX = 0;
    _scrollCarryY = 0;
  }

  void _flushMove(Duration frame) {
    if (_moveX == 0 && _moveY == 0) return;
    final gain = _gainFor(_moveX, _moveY, frame) * sensitivity;
    final x = _moveX * gain + _carryX;
    final y = _moveY * gain + _carryY;
    final dx = x.truncate();
    final dy = y.truncate();
    _carryX = x - dx;
    _carryY = y - dy;
    _moveX = 0;
    _moveY = 0;
    if (dx == 0 && dy == 0) return;
    _transport.send(MovePacket(dx: dx, dy: dy));
  }

  void _flushScroll() {
    if (_scrollX == 0 && _scrollY == 0) return;
    final direction = naturalScrolling ? 1 : -1;
    final x = _scrollX * scrollGain * direction + _scrollCarryX;
    final y = _scrollY * scrollGain * direction + _scrollCarryY;
    final dx = x.truncate();
    final dy = y.truncate();
    _scrollCarryX = x - dx;
    _scrollCarryY = y - dy;
    _scrollX = 0;
    _scrollY = 0;
    if (dx == 0 && dy == 0) return;
    _transport.send(ScrollPacket(dx: dx, dy: dy));
  }

  static double _gainFor(double dx, double dy, Duration frame) {
    final micros = frame.inMicroseconds > 0
        ? frame.inMicroseconds
        : nominalFrame.inMicroseconds;
    final speed = math.sqrt(dx * dx + dy * dy) / (micros / 1000000);
    if (speed <= slowSpeed) return 1;
    final ramp = ((speed - slowSpeed) / (fastSpeed - slowSpeed)).clamp(
      0.0,
      1.0,
    );
    return 1 + ramp * (maxGain - 1);
  }
}
