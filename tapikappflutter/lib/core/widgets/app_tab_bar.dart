import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';

class AppTabItem {
  const AppTabItem({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

class AppTabBar extends StatelessWidget {
  const AppTabBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  static const double barHeight = 56;
  static const double topInset = 8;
  static const double horizontalPadding = 14;
  static const double itemWidth = 64;
  static const double iconSize = 22;
  static const double iconGap = 5;
  static const double indicatorWidth = 24;
  static const double indicatorHeight = 3;
  static const double maxTextScale = 1.3;
  static const double minLabelGap = 4;

  final List<AppTabItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: colors.elevated,
      shape: Border(top: BorderSide(color: colors.borderDefault)),
      borderOnForeground: false,
      child: SafeArea(
        top: false,
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: maxTextScale,
          child: Padding(
            padding: const EdgeInsets.only(
              top: topInset,
              left: horizontalPadding,
              right: horizontalPadding,
            ),
            child: SizedBox(
              height: barHeight,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final labelScaler = _labelScaler(
                    context,
                    constraints.maxWidth / items.length - minLabelGap,
                  );
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (var i = 0; i < items.length; i++)
                        Flexible(
                          child: _TabButton(
                            item: items[i],
                            selected: i == currentIndex,
                            labelScaler: labelScaler,
                            onTap: () => onTap(i),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  TextScaler _labelScaler(BuildContext context, double room) {
    final scaler = MediaQuery.textScalerOf(context);
    final fontSize = AppTextStyles.labelS.fontSize!;
    final scale = scaler.scale(fontSize) / fontSize;
    if (scale <= 1) return scaler;
    final direction = Directionality.of(context);
    final boldText = MediaQuery.boldTextOf(context);
    var fit = scale;
    for (final item in items) {
      for (final selected in [false, true]) {
        final style = _TabButton.labelStyle(selected)
            .copyWith(fontWeight: boldText ? FontWeight.bold : null);
        final wide = _labelWidth(item.label, style, scale, direction);
        if (wide <= room) continue;
        final normal = _labelWidth(item.label, style, 1, direction);
        fit = math.min(
          fit,
          1 + (room - normal) * (scale - 1) / (wide - normal),
        );
      }
    }
    return TextScaler.linear(math.max(1.0, fit));
  }

  static double _labelWidth(
    String label,
    TextStyle style,
    double scale,
    TextDirection direction,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: direction,
      textScaler: TextScaler.linear(scale),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.item,
    required this.selected,
    required this.labelScaler,
    required this.onTap,
  });

  static TextStyle labelStyle(bool selected) => AppTextStyles.labelS.copyWith(
    fontWeight: selected ? FontWeight.w600 : null,
    letterSpacing: selected ? 0 : null,
  );

  final AppTabItem item;
  final bool selected;
  final TextScaler labelScaler;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final color = selected ? colors.accent : colors.navInactive;
    return Semantics(
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: AppTabBar.itemWidth,
            minHeight: AppTabBar.barHeight,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(item.icon, size: AppTabBar.iconSize, color: color),
                  const SizedBox(height: AppTabBar.iconGap),
                  Text(
                    item.label,
                    style: labelStyle(selected).copyWith(color: color),
                    textScaler: labelScaler,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              if (selected)
                Positioned(
                  top: -AppTabBar.topInset,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.accent,
                      borderRadius: BorderRadius.circular(
                        AppTabBar.indicatorHeight / 2,
                      ),
                    ),
                    child: const SizedBox(
                      width: AppTabBar.indicatorWidth,
                      height: AppTabBar.indicatorHeight,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
