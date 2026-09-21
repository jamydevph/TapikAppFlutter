import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

class AppDangerButton extends StatelessWidget {
  const AppDangerButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

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
        ),
        child: Text(label),
      ),
    );
  }
}
