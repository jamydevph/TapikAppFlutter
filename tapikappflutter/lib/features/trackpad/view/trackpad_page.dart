import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/injection.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_slider.dart';
import '../../../core/widgets/status_pill.dart';
import '../view_model/trackpad_cubit.dart';
import '../view_model/trackpad_state.dart';

class TrackpadPage extends StatelessWidget {
  const TrackpadPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => AppProviders.trackpadCubit(context)..start(),
      child: const _TrackpadView(),
    );
  }
}

class _TrackpadView extends StatelessWidget {
  const _TrackpadView();

  static const String noDeviceTitle = 'No laptop connected';
  static const double headerHeight = 26;
  static const double surfaceMinHeight = 200;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SafeArea(
      bottom: false,
      child: BlocBuilder<TrackpadCubit, TrackpadState>(
        builder: (context, state) {
          final connected = state.connection == TrackpadConnection.connected;
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
                          SizedBox(
                            height: headerHeight,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    state.deviceName ?? noDeviceTitle,
                                    style: AppTextStyles.labelM.copyWith(
                                      color: connected
                                          ? colors.textPrimary
                                          : colors.textSecondary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                _ConnectionPill(connection: state.connection),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Expanded(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                minHeight: surfaceMinHeight,
                              ),
                              child: const _GestureSurface(),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Row(
                            children: [
                              Expanded(
                                child: _ClickBar(
                                  label: 'Left click',
                                  enabled: connected,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: _ClickBar(
                                  label: 'Right click',
                                  enabled: connected,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(
                            height: AppSpacing.md + AppSpacing.x3s,
                          ),
                          Text(
                            'SENSITIVITY',
                            style: AppTextStyles.labelS.copyWith(
                              color: colors.textTertiary,
                            ),
                          ),
                          SizedBox(
                            height: AppSpacing.lg,
                            child: AppSlider(
                              value: state.sensitivity,
                              min: TrackpadCubit.minSensitivity,
                              max: TrackpadCubit.maxSensitivity,
                              label: 'Sensitivity',
                              semanticFormatter: (value) =>
                                  '${value.toStringAsFixed(1)}×',
                              onChanged: context
                                  .read<TrackpadCubit>()
                                  .setSensitivity,
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

class _ConnectionPill extends StatelessWidget {
  const _ConnectionPill({required this.connection});

  final TrackpadConnection connection;

  @override
  Widget build(BuildContext context) {
    return switch (connection) {
      TrackpadConnection.connected => const StatusPill(
        label: 'CONNECTED',
        tone: StatusPillTone.success,
      ),
      TrackpadConnection.connecting => const StatusPill(
        label: 'CONNECTING',
        tone: StatusPillTone.accent,
      ),
      TrackpadConnection.disconnected => const StatusPill(
        label: 'OFFLINE',
        tone: StatusPillTone.muted,
      ),
    };
  }
}

class _GestureSurface extends StatelessWidget {
  const _GestureSurface();

  static const double ringSize = AppSpacing.x3l + AppSpacing.x2s;
  static const double ringStroke = 1.5;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: colors.borderDefault),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: colors.borderStrong,
                  width: ringStroke,
                ),
              ),
              child: const SizedBox.square(dimension: ringSize),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Drag to move · Tap to click',
              style: AppTextStyles.bodyS.copyWith(color: colors.textTertiary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.x2s + 2),
            Text(
              'Two fingers to scroll · Hold to drag',
              style: AppTextStyles.caption.copyWith(color: colors.textTertiary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ClickBar extends StatelessWidget {
  const _ClickBar({required this.label, required this.enabled});

  static const double height = AppComponentSizes.buttonHeight;

  final String label;
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
            height: height,
            child: Center(
              child: Text(
                label,
                style: AppTextStyles.labelM.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
