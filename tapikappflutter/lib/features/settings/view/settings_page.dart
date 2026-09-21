import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/injection.dart';
import '../../../core/format/relative_time.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_mode.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_danger_button.dart';
import '../../../core/widgets/app_slider.dart';
import '../../../core/widgets/app_switch.dart';
import '../../../core/widgets/device_card.dart';
import '../../../core/widgets/settings_group.dart';
import '../../auth/view_model/auth_cubit.dart';
import '../../auth/view_model/auth_state.dart';
import '../view_model/settings_cubit.dart';
import '../view_model/settings_state.dart';
import '../view_model/theme_cubit.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => AppProviders.settingsCubit(context)..start(),
      child: const _SettingsView(),
    );
  }
}

class _SettingsView extends StatelessWidget {
  const _SettingsView();

  static const String emptyDevices =
      'No laptops yet. Pair one from the Connect tab.';

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SafeArea(
      bottom: false,
      child: MultiBlocListener(
        listeners: [
          BlocListener<SettingsCubit, SettingsState>(
            listenWhen: (previous, current) =>
                current.loaded &&
                (!previous.loaded || previous.themeMode != current.themeMode),
            listener: (context, state) {
              context.read<ThemeCubit>().setMode(state.themeMode);
            },
          ),
          BlocListener<SettingsCubit, SettingsState>(
            listenWhen: (previous, current) =>
                current.error != null && previous.errorId != current.errorId,
            listener: (context, state) {
              if (context.read<AuthCubit>().state is! Authenticated) return;
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text(state.error!)));
            },
          ),
          BlocListener<AuthCubit, AuthState>(
            listenWhen: (previous, current) =>
                current is Unauthenticated || current is AuthError,
            listener: (context, state) {
              switch (state) {
                case Unauthenticated():
                  context.go(AppRoutes.login);
                case AuthError(:final message):
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(content: Text(message)));
                default:
                  break;
              }
            },
          ),
        ],
        child: BlocBuilder<SettingsCubit, SettingsState>(
          builder: (context, state) {
            final cubit = context.read<SettingsCubit>();
            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              children: [
                const SizedBox(height: AppSpacing.md + AppSpacing.x3s),
                Text('Settings', style: AppTextStyles.headingXl),
                const SizedBox(height: AppSpacing.xl),
                const SectionLabel('TRACKPAD'),
                const SizedBox(height: AppSpacing.xs + AppSpacing.x3s),
                SettingsGroup(
                  children: [
                    _SensitivityRow(
                      value: state.sensitivity,
                      onChanged: cubit.setSensitivity,
                    ),
                    SettingRow(
                      title: 'Natural scrolling',
                      subtitle: 'Content follows your fingers.',
                      onTap: () =>
                          cubit.setNaturalScrolling(!state.naturalScrolling),
                      trailing: AppSwitch(
                        value: state.naturalScrolling,
                        onChanged: cubit.setNaturalScrolling,
                      ),
                    ),
                    SettingRow(
                      title: 'Haptic feedback',
                      subtitle: 'Vibrate on clicks and key taps.',
                      onTap: () =>
                          cubit.setHapticFeedback(!state.hapticFeedback),
                      trailing: AppSwitch(
                        value: state.hapticFeedback,
                        onChanged: cubit.setHapticFeedback,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                const SectionLabel('APPEARANCE'),
                const SizedBox(height: AppSpacing.xs + AppSpacing.x3s),
                SettingsGroup(
                  children: [
                    _ThemeRow(
                      mode: state.themeMode,
                      onChanged: cubit.setThemeMode,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                const SectionLabel('TRUSTED LAPTOPS'),
                const SizedBox(height: AppSpacing.xs + AppSpacing.x3s),
                if (state.devicesLoaded && state.devices.isEmpty)
                  Text(
                    emptyDevices,
                    style: AppTextStyles.bodyS.copyWith(
                      color: colors.textTertiary,
                    ),
                  )
                else
                  for (var i = 0; i < state.devices.length; i++) ...[
                    if (i > 0) const SizedBox(height: AppSpacing.md),
                    _DeviceTile(
                      device: state.devices[i],
                      revoking: state.isRevoking(state.devices[i].id),
                    ),
                  ],
                const SizedBox(height: AppSpacing.xl),
                const SectionLabel('ACCOUNT'),
                const SizedBox(height: AppSpacing.xs + AppSpacing.x3s),
                const _AccountGroup(),
                const SizedBox(height: AppSpacing.xl),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SensitivityRow extends StatelessWidget {
  const _SensitivityRow({required this.value, required this.onChanged});

  static const double sliderHeight = AppSpacing.x4l;

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final formatted = '${value.toStringAsFixed(1)}×';
    return Padding(
      padding: SettingRow.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Sensitivity',
                  style: AppTextStyles.labelM.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
              ExcludeSemantics(
                child: Text(
                  formatted,
                  style: AppTextStyles.labelM.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(
            height: sliderHeight,
            child: AppSlider(
              value: value,
              min: SettingsCubit.minSensitivity,
              max: SettingsCubit.maxSensitivity,
              label: 'Sensitivity',
              semanticFormatter: (value) => '${value.toStringAsFixed(1)}×',
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeRow extends StatelessWidget {
  const _ThemeRow({required this.mode, required this.onChanged});

  final AppThemeMode mode;
  final ValueChanged<AppThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: SettingRow.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Theme',
            style: AppTextStyles.labelM.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.x3s),
          Text(
            'System follows your phone’s appearance setting.',
            style: AppTextStyles.caption.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.sm),
          _ThemeSelector(mode: mode, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _ThemeSelector extends StatelessWidget {
  const _ThemeSelector({required this.mode, required this.onChanged});

  static const double height = AppSpacing.x3l;
  static const double hitHeight = AppSpacing.x4l;
  static const double inset = AppSpacing.x3s;
  static const double segmentHeight = height - inset * 2;
  static const Duration duration = Duration(milliseconds: 120);

  final AppThemeMode mode;
  final ValueChanged<AppThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SizedBox(
      height: hitHeight,
      child: Stack(
        children: [
          Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: const SizedBox(height: height, width: double.infinity),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: inset),
            child: Row(
              children: [
                for (final option in AppThemeMode.values)
                  Expanded(
                    child: _ThemeSegment(
                      label: _label(option),
                      selected: option == mode,
                      onTap: () => onChanged(option),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _label(AppThemeMode mode) {
    return switch (mode) {
      AppThemeMode.light => 'Light',
      AppThemeMode.dark => 'Dark',
      AppThemeMode.system => 'System',
    };
  }
}

class _ThemeSegment extends StatelessWidget {
  const _ThemeSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Center(
            child: AnimatedContainer(
              duration: _ThemeSelector.duration,
              height: _ThemeSelector.segmentHeight,
              decoration: BoxDecoration(
                color: selected ? colors.primarySubtle : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: selected ? colors.borderFocus : Colors.transparent,
                ),
              ),
              child: Center(
                child: Text(
                  label,
                  style: AppTextStyles.labelM.copyWith(
                    color: selected ? colors.accent : colors.textSecondary,
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

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device, required this.revoking});

  final SettingsDevice device;
  final bool revoking;

  @override
  Widget build(BuildContext context) {
    final card = DeviceCard(
      name: device.name,
      meta: _meta(device),
      status: DeviceCardStatus.available,
      onTap: revoking ? null : () => _showDetails(context),
    );
    return revoking ? Opacity(opacity: AppOpacity.disabled, child: card) : card;
  }

  static String _meta(SettingsDevice device) {
    final trusted = device.trustedAt;
    return trusted == null
        ? '${device.platformLabel} · trusted'
        : '${device.platformLabel} · paired ${RelativeTime.ago(trusted)}';
  }

  void _showDetails(BuildContext context) {
    final cubit = context.read<SettingsCubit>();
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (context) => _DeviceSheet(
        device: device,
        onRevoke: () {
          Navigator.of(context).pop();
          cubit.revoke(device.id);
        },
      ),
    );
  }
}

class _DeviceSheet extends StatelessWidget {
  const _DeviceSheet({required this.device, required this.onRevoke});

  final SettingsDevice device;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final seen = device.lastSeenAt;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.md,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(device.name, style: AppTextStyles.headingM),
              const SizedBox(height: AppSpacing.x2s),
              Text(
                seen == null
                    ? '${device.platformLabel} · never seen'
                    : '${device.platformLabel} · last seen '
                          '${RelativeTime.ago(seen)}',
                style: AppTextStyles.caption.copyWith(
                  color: colors.textTertiary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              const SectionLabel('CERTIFICATE FINGERPRINT'),
              const SizedBox(height: AppSpacing.x2s),
              Text(
                device.certFingerprint.isEmpty
                    ? 'Not recorded yet'
                    : device.certFingerprint,
                style: AppTextStyles.monoS.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Revoking removes this laptop from your account on every '
                'phone. You will need the pairing code to trust it again.',
                style: AppTextStyles.bodyS.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppDangerButton(label: 'Revoke this laptop', onPressed: onRevoke),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountGroup extends StatelessWidget {
  const _AccountGroup();

  Future<void> _signOut(BuildContext context) async {
    final settings = context.read<SettingsCubit>();
    final auth = context.read<AuthCubit>();
    await settings.flushPending();
    await auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthCubit, AuthState>(
      builder: (context, state) {
        final email = state is Authenticated ? state.user.email : null;
        final loading = state is AuthLoading;
        return SettingsGroup(
          children: [
            SettingRow(
              title: email ?? 'Not signed in',
              subtitle: 'Your paired laptops and settings follow this account.',
            ),
            Padding(
              padding: SettingRow.padding,
              child: OutlinedButton(
                onPressed: loading ? null : () => _signOut(context),
                child: const Text('Sign out'),
              ),
            ),
          ],
        );
      },
    );
  }
}
