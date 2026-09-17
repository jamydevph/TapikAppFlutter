import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

class AppCheckbox extends StatelessWidget {
  const AppCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
  });

  static const double boxSize = 20;
  static const double gap = AppSpacing.xs + AppSpacing.x3s;

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget label;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final enabled = onChanged != null;
    return Semantics(
      checked: value,
      enabled: enabled,
      child: InkWell(
        onTap: enabled ? () => onChanged!(!value) : null,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.x2s),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: boxSize,
                height: boxSize,
                decoration: BoxDecoration(
                  color: value ? colors.primary : colors.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  border: value
                      ? null
                      : Border.all(color: colors.borderDefault),
                ),
                child: value
                    ? Icon(
                        Icons.check_rounded,
                        size: boxSize - AppSpacing.x2s,
                        color: colors.onPrimary,
                      )
                    : null,
              ),
              const SizedBox(width: gap),
              Expanded(child: label),
            ],
          ),
        ),
      ),
    );
  }
}
