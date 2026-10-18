import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/app_primary_button.dart';
import 'pairing_route.dart';

class LaptopMismatchPage extends StatelessWidget {
  const LaptopMismatchPage({super.key, this.request});

  static const double badgeSize = 56;
  static const double glyphSize = 28;
  static const double badgeTint = 0.12;
  static const double cardTint = 0.08;

  final PairingRequest? request;

  void _close(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.connect);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final laptop = request?.laptop ?? 'the laptop';
    final seen = request?.laptopId;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: AppSpacing.x2s),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: AppBackButton(onPressed: () => _close(context)),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.danger.withValues(alpha: badgeTint),
                            shape: BoxShape.circle,
                          ),
                          child: SizedBox.square(
                            dimension: badgeSize,
                            child: Icon(
                              Icons.gpp_maybe_outlined,
                              size: glyphSize,
                              color: colors.textDanger,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Text(
                        'This may not be your laptop',
                        style: AppTextStyles.displayL,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Your phone sees a different ID than the one on '
                        '$laptop. Tapikapp stopped pairing and forgot this '
                        'laptop, so nothing you type will reach it.',
                        style: AppTextStyles.bodyM.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      if (seen != null) ...[
                        const SizedBox(height: AppSpacing.xl),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.danger.withValues(alpha: cardTint),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'ID THIS PHONE SAW',
                                  style: AppTextStyles.overline.copyWith(
                                    color: colors.textTertiary,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.x2s),
                                Text(
                                  seen,
                                  style: AppTextStyles.monoM.copyWith(
                                    color: colors.textDanger,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        'Check you picked the right laptop, then try again. '
                        'If the IDs still don’t match, someone on this Wi-Fi '
                        'may be pretending to be it. Don’t pair.',
                        style: AppTextStyles.bodyS.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                      const Spacer(),
                      const SizedBox(height: AppSpacing.xl),
                      AppPrimaryButton(
                        label: 'Back to laptops',
                        onPressed: () => _close(context),
                      ),
                      const SizedBox(
                        height: AppSpacing.x4l + AppSpacing.xs - AppSpacing.x3s,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
