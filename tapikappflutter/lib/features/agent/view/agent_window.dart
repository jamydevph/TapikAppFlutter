import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_danger_button.dart';
import '../../../core/widgets/app_switch.dart';
import '../../../core/widgets/app_tab_bar.dart';
import '../../../core/widgets/logo_mark.dart';
import '../../../core/widgets/settings_group.dart';
import '../../../core/widgets/status_pill.dart';
import '../view_model/agent_cubit.dart';
import '../view_model/agent_state.dart';

class AgentWindow extends StatelessWidget {
  const AgentWindow({super.key});

  static const Size windowSize = Size(400, 640);
  static const String pairingHint =
      'A code appears here when a new phone asks to pair.';
  static const String noPhoneTitle = 'No phone connected';
  static const String noPhoneHint =
      'Open Tapikapp on your phone and pick this laptop.';
  static const String connectedHint = 'Connected over Wi-Fi';

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      body: MediaQuery.withClampedTextScaling(
        maxScaleFactor: AppTabBar.maxTextScale,
        child: BlocBuilder<AgentCubit, AgentState>(
          builder: (context, state) {
            final cubit = context.read<AgentCubit>();
            final trayName = state.isMacOS ? 'menu bar' : 'system tray';
            final machine = state.isMacOS ? 'Mac' : 'PC';
            return LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - AppSpacing.xl * 2,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Header(state: state),
                          const SizedBox(height: AppSpacing.xl),
                          const SectionLabel('PAIRING CODE'),
                          const SizedBox(
                            height: AppSpacing.xs + AppSpacing.x3s,
                          ),
                          _CodeSlot(code: state.pairingCode),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            AgentWindow.pairingHint,
                            style: AppTextStyles.caption.copyWith(
                              color: colors.textTertiary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          const SectionLabel('CONNECTED PHONE'),
                          const SizedBox(
                            height: AppSpacing.xs + AppSpacing.x3s,
                          ),
                          _PhoneCard(
                            phoneName: state.connectedPhone,
                            onDisconnect: state.hasConnection
                                ? cubit.disconnect
                                : null,
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          const SectionLabel('STARTUP'),
                          const SizedBox(
                            height: AppSpacing.xs + AppSpacing.x3s,
                          ),
                          SettingsGroup(
                            children: [
                              SettingRow(
                                title: 'Launch at login',
                                subtitle:
                                    'Start the agent when you sign in to this $machine.',
                                onTap: () => cubit.setLaunchAtLogin(
                                  !state.launchAtLogin,
                                ),
                                trailing: AppSwitch(
                                  value: state.launchAtLogin,
                                  onChanged: cubit.setLaunchAtLogin,
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          const SizedBox(height: AppSpacing.xl),
                          Text(
                            'Closing this window keeps ${AppBrand.name} running in the '
                            '$trayName.',
                            style: AppTextStyles.caption.copyWith(
                              color: colors.textTertiary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state});

  static const double gap = AppSpacing.md - AppSpacing.x3s;

  final AgentState state;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
      children: [
        const LogoMark(size: AppComponentSizes.logoMarkCompact, glow: false),
        const SizedBox(width: gap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${AppBrand.name} Agent',
                style: AppTextStyles.headingM.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.x3s),
              Text(
                '${state.hostName} · ${state.platformLabel}',
                style: AppTextStyles.caption.copyWith(
                  color: colors.textTertiary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        state.listening
            ? const StatusPill(label: 'LISTENING', tone: StatusPillTone.success)
            : const StatusPill(label: 'OFFLINE', tone: StatusPillTone.muted),
      ],
    );
  }
}

class _CodeSlot extends StatelessWidget {
  const _CodeSlot({required this.code});

  static const int length = 6;
  static const double boxWidth = 50;
  static const double boxHeight = 60;
  static const double gap = AppSpacing.xs;
  static const String placeholder = '•';

  final String? code;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final digits = code ?? '';
    return Semantics(
      label: code == null ? 'No pairing code yet' : 'Pairing code $code',
      child: ExcludeSemantics(
        child: Row(
          children: [
            for (var i = 0; i < length; i++) ...[
              if (i > 0) const SizedBox(width: gap),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: colors.borderDefault),
                ),
                child: SizedBox(
                  width: boxWidth,
                  height: boxHeight,
                  child: Center(
                    child: Text(
                      i < digits.length ? digits[i] : placeholder,
                      style: AppTextStyles.headingXl.copyWith(
                        color: i < digits.length
                            ? colors.textPrimary
                            : colors.textTertiary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PhoneCard extends StatelessWidget {
  const _PhoneCard({required this.phoneName, required this.onDisconnect});

  static const double badgeSize = AppSpacing.x4l;
  static const double glyphSize = AppSpacing.xl;

  final String? phoneName;
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final connected = phoneName != null;
    return SettingsGroup(
      children: [
        SettingRow(
          leading: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: SizedBox.square(
              dimension: badgeSize,
              child: Icon(
                Icons.smartphone_rounded,
                size: glyphSize,
                color: connected ? colors.textSuccess : colors.textSecondary,
              ),
            ),
          ),
          title: phoneName ?? AgentWindow.noPhoneTitle,
          subtitle: connected
              ? AgentWindow.connectedHint
              : AgentWindow.noPhoneHint,
          trailing: connected
              ? const StatusPill(
                  label: 'CONNECTED',
                  tone: StatusPillTone.success,
                )
              : null,
        ),
        Padding(
          padding: SettingRow.padding,
          child: AppDangerButton(label: 'Disconnect', onPressed: onDisconnect),
        ),
      ],
    );
  }
}
