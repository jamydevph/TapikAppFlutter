import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';

enum KeyCapType { letter, modifier, wide, accent }

class KeyCap extends StatelessWidget {
  const KeyCap({
    super.key,
    required this.label,
    this.type = KeyCapType.letter,
    this.active,
    this.icon,
    this.width,
    this.height,
    this.onTap,
  });

  static const double defaultHeight = 46;
  static const double letterWidth = 34;
  static const double modifierWidth = 54;
  static const double wideWidth = 140;
  static const double iconSize = AppSpacing.lg;

  final String label;
  final KeyCapType type;
  final bool? active;
  final Widget? icon;
  final double? width;
  final double? height;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final (fill, border, foreground, style) = switch ((type, active ?? false)) {
      (KeyCapType.letter, _) => (
        colors.surfaceAlt,
        null,
        colors.textPrimary,
        AppTextStyles.labelL,
      ),
      (KeyCapType.modifier, false) => (
        colors.surface,
        colors.borderDefault,
        colors.textSecondary,
        AppTextStyles.labelM,
      ),
      (KeyCapType.modifier, true) => (
        colors.primarySubtle,
        colors.borderFocus,
        colors.accent,
        AppTextStyles.labelM,
      ),
      (KeyCapType.wide, _) => (
        colors.surfaceAlt,
        null,
        colors.textSecondary,
        AppTextStyles.labelM,
      ),
      (KeyCapType.accent, _) => (
        colors.primary,
        null,
        colors.onPrimary,
        AppTextStyles.labelM,
      ),
    };
    final defaultWidth = switch (type) {
      KeyCapType.letter => letterWidth,
      KeyCapType.modifier || KeyCapType.accent => modifierWidth,
      KeyCapType.wide => wideWidth,
    };
    return Semantics(
      button: true,
      toggled: active,
      label: icon == null ? null : label,
      child: Material(
        color: fill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          side: border == null ? BorderSide.none : BorderSide(color: border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: width ?? defaultWidth,
            height: height ?? defaultHeight,
            child: Center(
              child: icon != null
                  ? IconTheme(
                      data: IconThemeData(size: iconSize, color: foreground),
                      child: icon!,
                    )
                  : Text(
                      label,
                      style: style.copyWith(color: foreground),
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
