import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

class AppSwitch extends StatelessWidget {
  const AppSwitch({super.key, required this.value, required this.onChanged});

  static const double width = AppSpacing.x3l + AppSpacing.x2s;
  static const double height = AppSpacing.xl + AppSpacing.x3s;
  static const double thumbInset = AppSpacing.x3s;
  static const double thumbSize = height - thumbInset * 2;
  static const double hitSize = AppSpacing.x4l;
  static const Duration duration = Duration(milliseconds: 120);

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final enabled = onChanged != null;
    return Semantics(
      toggled: value,
      enabled: enabled,
      child: Opacity(
        opacity: enabled ? 1 : AppOpacity.disabled,
        child: InkWell(
          onTap: enabled ? () => onChanged!(!value) : null,
          borderRadius: BorderRadius.circular(AppRadius.full),
          child: SizedBox(
            width: hitSize,
            height: hitSize,
            child: Center(
              child: AnimatedContainer(
                duration: duration,
                width: width,
                height: height,
                padding: const EdgeInsets.all(thumbInset),
                decoration: BoxDecoration(
                  color: value ? colors.primary : colors.textTertiary,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: AnimatedAlign(
                  duration: duration,
                  alignment: value
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.onPrimary,
                      shape: BoxShape.circle,
                      boxShadow: AppShadows.card,
                    ),
                    child: const SizedBox.square(dimension: thumbSize),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
