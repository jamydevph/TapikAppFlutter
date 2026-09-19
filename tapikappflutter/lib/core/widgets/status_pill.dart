import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';

enum StatusPillTone { success, accent, muted }

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.tone});

  static const double height = 26;
  static const double dotSize = 7;
  static const double gap = AppSpacing.xs - AppSpacing.x3s;
  static const double leadingPadding = AppSpacing.xs + AppSpacing.x3s;
  static const double trailingPadding = AppSpacing.sm;

  final String label;
  final StatusPillTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final (fill, dot, text, glow) = switch (tone) {
      StatusPillTone.success => (
        colors.surfaceAlt,
        colors.success,
        colors.textSuccess,
        AppShadows.glowSuccess,
      ),
      StatusPillTone.accent => (
        colors.primarySubtle,
        colors.primary,
        colors.accent,
        null,
      ),
      StatusPillTone.muted => (
        colors.surfaceAlt,
        colors.borderStrong,
        colors.textTertiary,
        null,
      ),
    };
    return Container(
      height: height,
      padding: const EdgeInsets.only(
        left: leadingPadding,
        right: trailingPadding,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: dot,
              shape: BoxShape.circle,
              boxShadow: glow,
            ),
            child: const SizedBox.square(dimension: dotSize),
          ),
          const SizedBox(width: gap),
          Text(label, style: AppTextStyles.labelS.copyWith(color: text)),
        ],
      ),
    );
  }
}
