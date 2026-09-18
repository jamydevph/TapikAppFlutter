import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

class AppBackButton extends StatelessWidget {
  const AppBackButton({
    super.key,
    required this.onPressed,
    this.circled = false,
  });

  static const double hitSize = AppSpacing.x4l;
  static const double circleSize = 36;
  static const Size chevronSize = Size(6, 12);
  static const double chevronStroke = 1.6;

  final VoidCallback? onPressed;
  final bool circled;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final enabled = onPressed != null;
    final glyphColor = !enabled
        ? colors.textTertiary
        : circled
        ? colors.textPrimary
        : colors.textSecondary;
    final glyph = CustomPaint(
      size: chevronSize,
      painter: _ChevronPainter(color: glyphColor, strokeWidth: chevronStroke),
    );
    final visual = circled
        ? SizedBox.square(
            dimension: circleSize,
            child: Ink(
              decoration: BoxDecoration(
                color: colors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: colors.borderDefault),
              ),
              child: Padding(
                padding: const EdgeInsets.only(right: AppSpacing.x3s),
                child: Center(child: glyph),
              ),
            ),
          )
        : glyph;
    final visualWidth = circled ? circleSize : chevronSize.width;
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Back',
      child: SizedBox.square(
        dimension: hitSize,
        child: _CenteredInk(
          onTap: onPressed,
          centerX: visualWidth / 2,
          radius: hitSize / 2,
          child: Align(alignment: Alignment.centerLeft, child: visual),
        ),
      ),
    );
  }
}

class _ChevronPainter extends CustomPainter {
  const _ChevronPainter({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(size.width, 0)
      ..lineTo(0, size.height / 2)
      ..lineTo(size.width, size.height);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
  }
}

class _CenteredInk extends InkResponse {
  const _CenteredInk({
    required super.onTap,
    required this.centerX,
    required super.radius,
    required super.child,
  }) : super(
         highlightShape: BoxShape.circle,
         containedInkWell: true,
         customBorder: const CircleBorder(),
       );

  final double centerX;

  @override
  RectCallback? getRectCallback(RenderBox referenceBox) {
    return () {
      final size = referenceBox.size;
      return Rect.fromCenter(
        center: Offset(centerX, size.height / 2),
        width: size.width,
        height: size.height,
      );
    };
  }
}
