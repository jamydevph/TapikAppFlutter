import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';
import 'status_pill.dart';

enum DeviceCardStatus { connected, available, untrusted, offline }

class DeviceCard extends StatelessWidget {
  const DeviceCard({
    super.key,
    required this.name,
    required this.meta,
    required this.status,
    this.onTap,
  });

  static const double height = 80;
  static const double padding = AppSpacing.md - AppSpacing.x3s;
  static const double gap = AppSpacing.md - AppSpacing.x3s;
  static const double badgeSize = AppSpacing.x4l;
  static const double textGap = AppSpacing.x2s - 1;
  static const Size glyphSize = Size(20, 13);
  static const double glyphStroke = 1.6;
  static const Size chevronSize = Size(6, 12);
  static const double chevronStroke = 1.8;
  static const double connectedBorder = 1.5;

  final String name;
  final String meta;
  final DeviceCardStatus status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final connected = status == DeviceCardStatus.connected;
    final card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: connected ? AppShadows.glowPrimary : null,
      ),
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: connected
              ? BorderSide(color: colors.borderFocus, width: connectedBorder)
              : BorderSide(color: colors.borderDefault),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: padding),
              child: Row(
                children: [
                  _PlatformBadge(
                    color: connected
                        ? colors.textSuccess
                        : colors.textSecondary,
                  ),
                  const SizedBox(width: gap),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: AppTextStyles.headingM.copyWith(
                            color: colors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: textGap),
                        Text(
                          meta,
                          style: AppTextStyles.caption.copyWith(
                            color: colors.textTertiary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: gap),
                  _trailing(colors),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return MergeSemantics(
      child: status == DeviceCardStatus.offline
          ? Opacity(opacity: AppOpacity.disabled, child: card)
          : card,
    );
  }

  Widget _trailing(AppColors colors) {
    switch (status) {
      case DeviceCardStatus.connected:
        return const StatusPill(
          label: 'CONNECTED',
          tone: StatusPillTone.success,
        );
      case DeviceCardStatus.untrusted:
        return const StatusPill(label: 'NEW', tone: StatusPillTone.accent);
      case DeviceCardStatus.offline:
        return const StatusPill(label: 'OFFLINE', tone: StatusPillTone.muted);
      case DeviceCardStatus.available:
        return CustomPaint(
          size: chevronSize,
          painter: _ChevronPainter(
            color: colors.textTertiary,
            strokeWidth: chevronStroke,
          ),
        );
    }
  }
}

class _PlatformBadge extends StatelessWidget {
  const _PlatformBadge({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: SizedBox.square(
        dimension: DeviceCard.badgeSize,
        child: Center(
          child: CustomPaint(
            size: DeviceCard.glyphSize,
            painter: _LaptopPainter(
              color: color,
              strokeWidth: DeviceCard.glyphStroke,
            ),
          ),
        ),
      ),
    );
  }
}

class _LaptopPainter extends CustomPainter {
  const _LaptopPainter({required this.color, required this.strokeWidth});

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
    final inset = strokeWidth / 2;
    final screen = Rect.fromLTRB(
      2 + inset,
      inset,
      size.width - 2 - inset,
      size.height - 3.5,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(screen, Radius.circular(strokeWidth)),
      paint,
    );
    final baseY = size.height - inset;
    canvas.drawLine(
      Offset(inset, baseY),
      Offset(size.width - inset, baseY),
      paint,
    );
  }

  @override
  bool shouldRepaint(_LaptopPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
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
      ..moveTo(0, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(0, size.height);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
  }
}
