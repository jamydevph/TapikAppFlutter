import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';

class AppDangerButton extends StatelessWidget {
  const AppDangerButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.compact = false,
  });

  static const EdgeInsets compactPadding = EdgeInsets.symmetric(
    horizontal: AppSpacing.md - AppSpacing.x3s,
  );

  final String label;
  final VoidCallback? onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : AppOpacity.disabled,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.textDanger,
          disabledForegroundColor: colors.textDanger,
          backgroundColor: Colors.transparent,
          side: BorderSide(color: colors.borderDanger),
          minimumSize: compact
              ? const Size(0, AppComponentSizes.compactButtonHeight)
              : null,
          padding: compact ? compactPadding : null,
          textStyle: compact ? AppTextStyles.labelM : null,
          shape: compact
              ? RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                )
              : null,
        ),
        child: Text(label),
      ),
    );
  }
}
