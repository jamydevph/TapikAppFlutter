import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_tab_bar.dart';
import '../../../core/widgets/dots_loader.dart';
import '../../../core/widgets/logo_mark.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  static const Duration holdDuration = Duration(milliseconds: 1200);
  static const String statusText = 'Checking your session…';

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  Timer? _handoff;

  @override
  void initState() {
    super.initState();
    _handoff = Timer(SplashPage.holdDuration, () {
      if (mounted) context.go(AppRoutes.connect);
    });
  }

  @override
  void dispose() {
    _handoff?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      body: MediaQuery.withClampedTextScaling(
        maxScaleFactor: AppTabBar.maxTextScale,
        child: CustomMultiChildLayout(
          delegate: _SplashLayout(),
          children: [
            LayoutId(
              id: _SplashSlot.brand,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const LogoMark(),
                    const SizedBox(height: AppSpacing.xl + AppSpacing.x2s),
                    Text(
                      AppBrand.name,
                      style: AppTextStyles.displayXl,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.x2s),
                    Text(
                      AppBrand.tagline,
                      style: AppTextStyles.bodyM.copyWith(color: colors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            LayoutId(
              id: _SplashSlot.status,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: AppSpacing.lg,
                    right: AppSpacing.lg,
                    bottom: AppSpacing.x2l + AppSpacing.x3s,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const DotsLoader(),
                      const SizedBox(height: AppSpacing.xl),
                      Text(
                        SplashPage.statusText,
                        style: AppTextStyles.caption.copyWith(color: colors.textTertiary),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _SplashSlot { brand, status }

class _SplashLayout extends MultiChildLayoutDelegate {
  static const double brandLift = 10;

  @override
  void performLayout(Size size) {
    final status = layoutChild(_SplashSlot.status, BoxConstraints.loose(size));
    final brand = layoutChild(_SplashSlot.brand, BoxConstraints.loose(size));
    final centred = (size.height - brand.height) / 2 - brandLift;
    final lowest = size.height - status.height - brand.height - AppSpacing.xl;
    positionChild(
      _SplashSlot.brand,
      Offset((size.width - brand.width) / 2, math.max(0, math.min(centred, lowest))),
    );
    positionChild(
      _SplashSlot.status,
      Offset((size.width - status.width) / 2, size.height - status.height),
    );
  }

  @override
  bool shouldRelayout(_SplashLayout oldDelegate) => false;
}
