import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

class LogoMark extends StatelessWidget {
  const LogoMark({
    super.key,
    this.size = AppComponentSizes.logoMark,
    this.glow = true,
  });

  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _LogoMarkPainter(
          tile: colors.primary,
          glyph: colors.onPrimary,
          glow: glow,
        ),
      ),
    );
  }
}

class _LogoMarkPainter extends CustomPainter {
  const _LogoMarkPainter({
    required this.tile,
    required this.glyph,
    required this.glow,
  });

  static const double _designSize = 88;
  static const double _cornerRadius = 28;
  static const double _stroke = 5;

  final Color tile;
  final Color glyph;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / _designSize;
    canvas.scale(scale);
    final rect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(0, 0, _designSize, _designSize),
      const Radius.circular(_cornerRadius),
    );
    if (glow) {
      final shadow = AppShadows.glowPrimary.first;
      canvas.save();
      canvas.translate(shadow.offset.dx, shadow.offset.dy);
      canvas.drawRRect(
        rect,
        Paint()
          ..color = shadow.color
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, shadow.blurRadius / 2),
      );
      canvas.restore();
    }
    canvas.drawRRect(rect, Paint()..color = tile);
    final stroke = Paint()
      ..color = glyph
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;
    _drawArc(canvas, stroke, x0: 26, x1: 58, y: 23, radius: 18.7);
    _drawArc(canvas, stroke, x0: 30, x1: 54, y: 34, radius: 15);
    canvas.drawCircle(const Offset(33, 55), 9, Paint()..color = glyph);
  }

  void _drawArc(
    Canvas canvas,
    Paint paint, {
    required double x0,
    required double x1,
    required double y,
    required double radius,
  }) {
    final halfChord = (x1 - x0) / 2;
    final center = Offset(
      (x0 + x1) / 2,
      y + math.sqrt(radius * radius - halfChord * halfChord),
    );
    final start = math.atan2(y - center.dy, x0 - center.dx);
    final end = math.atan2(y - center.dy, x1 - center.dx);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      start,
      end - start,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_LogoMarkPainter oldDelegate) {
    return tile != oldDelegate.tile ||
        glyph != oldDelegate.glyph ||
        glow != oldDelegate.glow;
  }
}
