import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/connection_header.dart';
import '../../../core/widgets/key_cap.dart';
import '../view_model/presenter_cubit.dart';
import '../view_model/presenter_state.dart';

class PresenterPage extends StatelessWidget {
  const PresenterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => PresenterCubit(),
      child: const _PresenterView(),
    );
  }
}

class _PresenterView extends StatelessWidget {
  const _PresenterView();

  static const double surfaceMinHeight = 200;
  static const double controlHeight = AppComponentSizes.buttonHeight;
  static final double captionMinHeight =
      AppTextStyles.caption.fontSize! * AppTextStyles.caption.height! * 2;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SafeArea(
      bottom: false,
      child: BlocBuilder<PresenterCubit, PresenterState>(
        builder: (context, state) {
          final connected = state.connection == PresenterConnection.connected;
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.xs + AppSpacing.x3s,
              AppSpacing.xl,
              AppSpacing.x4l + AppSpacing.xs,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ConnectionHeader(
                            deviceName: state.deviceName,
                            status: switch (state.connection) {
                              PresenterConnection.connected =>
                                ConnectionHeaderStatus.connected,
                              PresenterConnection.connecting =>
                                ConnectionHeaderStatus.connecting,
                              PresenterConnection.disconnected =>
                                ConnectionHeaderStatus.offline,
                            },
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Expanded(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                minHeight: surfaceMinHeight,
                              ),
                              child: _AdvanceSurface(enabled: connected),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Row(
                            children: [
                              Expanded(child: _PreviousBar(enabled: connected)),
                              const SizedBox(width: AppSpacing.sm),
                              KeyCap(
                                label: 'Black screen',
                                icon: const Icon(Icons.tv_off_rounded),
                                type: KeyCapType.modifier,
                                active: state.screenBlanked,
                                width: controlHeight,
                                height: controlHeight,
                                onTap: context
                                    .read<PresenterCubit>()
                                    .toggleBlackScreen,
                              ),
                            ],
                          ),
                          const SizedBox(
                            height: AppSpacing.md + AppSpacing.x3s,
                          ),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: MediaQuery.textScalerOf(context)
                                  .scale(captionMinHeight),
                            ),
                            child: Text(
                              state.screenBlanked
                                  ? 'Screen is black. Tap the key again to show your slides.'
                                  : 'Tap anywhere on the big pad to advance. '
                                        'Use the bar below to go back a slide.',
                              style: AppTextStyles.caption.copyWith(
                                color: colors.textTertiary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _AdvanceSurface extends StatelessWidget {
  const _AdvanceSurface({required this.enabled});

  static const double glyphSize = AppSpacing.x5l;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Opacity(
      opacity: enabled ? 1 : AppOpacity.disabled,
      child: Material(
        color: colors.surfaceAlt,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          side: BorderSide(color: colors.borderDefault),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? () {} : null,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.arrow_forward_rounded,
                  size: glyphSize,
                  color: colors.textSecondary,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Next slide',
                  style: AppTextStyles.headingM.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.x2s + AppSpacing.x3s),
                Text(
                  'Tap anywhere',
                  style: AppTextStyles.caption.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviousBar extends StatelessWidget {
  const _PreviousBar({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Opacity(
      opacity: enabled ? 1 : AppOpacity.disabled,
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: colors.borderDefault),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? () {} : null,
          child: SizedBox(
            height: _PresenterView.controlHeight,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.arrow_back_rounded,
                  size: KeyCap.iconSize,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'Previous slide',
                  style: AppTextStyles.labelM.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
