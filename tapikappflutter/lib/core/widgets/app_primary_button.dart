import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

class AppPrimaryButton extends StatelessWidget {
  const AppPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  static const double spinnerSize = AppSpacing.lg;
  static const double spinnerStroke = 2;

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final enabled = onPressed != null && !loading;
    return Opacity(
      opacity: enabled || loading ? 1 : AppOpacity.disabled,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md),
          boxShadow: enabled ? AppShadows.glowPrimary : null,
        ),
        child: FilledButton(
          onPressed: enabled ? onPressed : null,
          child: loading
              ? SizedBox.square(
                  dimension: spinnerSize,
                  child: CircularProgressIndicator(
                    strokeWidth: spinnerStroke,
                    color: colors.textTertiary,
                  ),
                )
              : Text(label),
        ),
      ),
    );
  }
}
