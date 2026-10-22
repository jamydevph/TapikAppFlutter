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
import '../../../services/injector/injector.dart';
import '../../../services/security/paired_phone.dart';
import '../view_model/agent_cubit.dart';
import '../view_model/agent_state.dart';
import '../view_model/paired_phone_label.dart';

class AgentWindow extends StatelessWidget {
  const AgentWindow({super.key});

  static const Size windowSize = Size(400, 760);
  static const String pairingHint =
      'A code appears here when a new phone asks to pair.';
  static const String noPhoneTitle = 'No phone connected';
  static const String noPhoneHint =
      'Open Tapikapp on your phone and pick this laptop.';
  static const String connectedHint = 'Connected over Wi-Fi';
  static const String forgetHint =
      'Forget removes one phone; it needs the pairing code next time. '
      'Forget all phones removes every phone at once.';
  static const String forgetUnsavedHint =
      'Tapikapp couldn’t save that, so the phones would be trusted again '
      'after a restart. Press Forget all phones to try again.';
  static const String forgetFailedHint =
      'Tapikapp couldn’t save that, so the phone is still paired. '
      'Press Forget to try again.';

  static Future<void> _confirmForgetAll(
    BuildContext context,
    AgentCubit cubit,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) =>
          BlocProvider.value(value: cubit, child: const _ForgetAllDialog()),
    );
    if (confirmed == true) await cubit.forgetAllPhones();
  }

  static Future<void> _confirmForget(
    BuildContext context,
    AgentCubit cubit,
    PairedPhone phone,
    String title,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: _ForgetPhoneDialog(phoneId: phone.id, phoneTitle: title),
      ),
    );
    if (confirmed == true) await cubit.forgetPhone(phone.id);
  }

  static String _accessTitle(InjectorPermission permission) {
    return switch (permission) {
      InjectorPermission.granted => 'Tapikapp can control this computer',
      InjectorPermission.denied => 'Tapikapp cannot move the cursor yet',
      InjectorPermission.unsupported => 'Control is not available here',
    };
  }

  static String _accessHint(InjectorPermission permission, String machine) {
    return switch (permission) {
      InjectorPermission.granted =>
        'Your phone can move the pointer and click.',
      InjectorPermission.denied =>
        'Allow Tapikapp under Accessibility so it can move this '
            "$machine's pointer.",
      InjectorPermission.unsupported =>
        'This build cannot send input to the system.',
    };
  }

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
                          if (state.laptopId case final laptopId?) ...[
                            const SizedBox(height: AppSpacing.xl),
                            const SectionLabel('LAPTOP ID'),
                            const SizedBox(
                              height: AppSpacing.xs + AppSpacing.x3s,
                            ),
                            _LaptopIdCard(laptopId: laptopId),
                          ],
                          const SizedBox(height: AppSpacing.xl),
                          const SectionLabel('CONNECTED PHONE'),
                          const SizedBox(
                            height: AppSpacing.xs + AppSpacing.x3s,
                          ),
                          _PhoneCard(
                            phoneName: state.connectedPhone,
                            packetCount: state.packetCount,
                            onDisconnect: state.hasConnection
                                ? cubit.disconnect
                                : null,
                          ),
                          if (state.error != null) ...[
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              state.error!,
                              style: AppTextStyles.caption.copyWith(
                                color: colors.textDanger,
                              ),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.xl),
                          const SectionLabel('PAIRED PHONES'),
                          const SizedBox(
                            height: AppSpacing.xs + AppSpacing.x3s,
                          ),
                          _PairedPhonesCard(
                            phones: state.phones,
                            connectedId: state.connectedPhoneId,
                            onForget: (phone, title) =>
                                _confirmForget(context, cubit, phone, title),
                            onForgetAll:
                                state.pairedPhones > 0 || state.forgetUnsaved
                                ? () => _confirmForgetAll(context, cubit)
                                : null,
                          ),
                          if (state.forgetUnsaved || state.forgetFailed) ...[
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              state.forgetUnsaved
                                  ? AgentWindow.forgetUnsavedHint
                                  : AgentWindow.forgetFailedHint,
                              style: AppTextStyles.caption.copyWith(
                                color: colors.textDanger,
                              ),
                            ),
                          ] else if (state.pairedPhones > 0) ...[
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              AgentWindow.forgetHint,
                              style: AppTextStyles.caption.copyWith(
                                color: colors.textTertiary,
                              ),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.xl),
                          const SectionLabel('CONTROL ACCESS'),
                          const SizedBox(
                            height: AppSpacing.xs + AppSpacing.x3s,
                          ),
                          SettingsGroup(
                            children: [
                              SettingRow(
                                title: _accessTitle(state.permission),
                                subtitle: _accessHint(
                                  state.permission,
                                  machine,
                                ),
                                trailing: switch (state.permission) {
                                  InjectorPermission.granted =>
                                    const StatusPill(
                                      label: 'ALLOWED',
                                      tone: StatusPillTone.success,
                                    ),
                                  InjectorPermission.denied => OutlinedButton(
                                    onPressed: cubit.grantAccessibility,
                                    child: const Text('Allow'),
                                  ),
                                  InjectorPermission.unsupported =>
                                    const StatusPill(
                                      label: 'UNAVAILABLE',
                                      tone: StatusPillTone.muted,
                                    ),
                                },
                              ),
                            ],
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

class _LaptopIdCard extends StatelessWidget {
  const _LaptopIdCard({required this.laptopId});

  static const String hint =
      'Your phone shows this ID while pairing. Pair only if the two match.';

  final String laptopId;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.primarySubtle,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                laptopId,
                maxLines: 1,
                style: AppTextStyles.monoM.copyWith(color: colors.textPrimary),
              ),
            ),
            const SizedBox(height: AppSpacing.x2s),
            Text(
              hint,
              style: AppTextStyles.bodyS.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _PairedPhonesCard extends StatelessWidget {
  const _PairedPhonesCard({
    required this.phones,
    required this.connectedId,
    required this.onForget,
    required this.onForgetAll,
  });

  static const String forgetAll = 'Forget all phones';

  final List<PairedPhone> phones;
  final String? connectedId;
  final void Function(PairedPhone phone, String title) onForget;
  final VoidCallback? onForgetAll;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final titles = PairedPhoneLabel.titles(phones, now);
    return SettingsGroup(
      children: [
        if (phones.isEmpty)
          const SettingRow(
            title: 'No phones paired yet',
            subtitle: 'A phone is added once its pairing code is typed.',
          ),
        for (final phone in phones)
          SettingRow(
            leading: _PhoneBadge(connected: phone.id == connectedId),
            title: titles[phone.id]!,
            subtitle: PairedPhoneLabel.status(
              phone,
              connected: phone.id == connectedId,
              now: now,
            ),
            trailing: AppDangerButton(
              label: 'Forget',
              compact: true,
              onPressed: () => onForget(phone, titles[phone.id]!),
            ),
          ),
        Padding(
          padding: SettingRow.padding,
          child: AppDangerButton(label: forgetAll, onPressed: onForgetAll),
        ),
      ],
    );
  }
}

class _ForgetAllDialog extends StatelessWidget {
  const _ForgetAllDialog();

  @override
  Widget build(BuildContext context) {
    final disconnects = context.select<AgentCubit, bool>(
      (cubit) => cubit.state.hasConnection,
    );
    return _ForgetDialog(
      title: 'Forget all phones?',
      message: disconnects
          ? 'Every phone will need a pairing code to connect again. '
                'The phone that’s connected now will be disconnected.'
          : 'Every phone will need a pairing code to connect again.',
      confirmLabel: 'Forget all',
    );
  }
}

class _ForgetPhoneDialog extends StatelessWidget {
  const _ForgetPhoneDialog({required this.phoneId, required this.phoneTitle});

  final String phoneId;
  final String phoneTitle;

  @override
  Widget build(BuildContext context) {
    final disconnects = context.select<AgentCubit, bool>(
      (cubit) => cubit.state.connectedPhoneId == phoneId,
    );
    return _ForgetDialog(
      title: 'Forget this phone?',
      message: disconnects
          ? '$phoneTitle will need a pairing code to connect again. '
                'It’s connected now, so it disconnects straight away.'
          : '$phoneTitle will need a pairing code to connect again.',
      confirmLabel: 'Forget',
    );
  }
}

class _ForgetDialog extends StatelessWidget {
  const _ForgetDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
  });

  static const double width = 340;

  final String title;
  final String message;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Dialog(
      backgroundColor: colors.elevated,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(AppSpacing.xl),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: colors.borderDefault),
      ),
      child: SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: AppTextStyles.headingM.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                message,
                style: AppTextStyles.bodyS.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: AppDangerButton(
                      label: confirmLabel,
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhoneBadge extends StatelessWidget {
  const _PhoneBadge({required this.connected});

  static const double size = AppSpacing.x4l;
  static const double glyphSize = AppSpacing.xl;

  final bool connected;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: SizedBox.square(
        dimension: size,
        child: Icon(
          Icons.smartphone_rounded,
          size: glyphSize,
          color: connected ? colors.textSuccess : colors.textSecondary,
        ),
      ),
    );
  }
}

class _PhoneCard extends StatelessWidget {
  const _PhoneCard({
    required this.phoneName,
    required this.packetCount,
    required this.onDisconnect,
  });

  final String? phoneName;
  final int packetCount;
  final VoidCallback? onDisconnect;

  static String _formatCount(int count) {
    final digits = count.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return '$buffer packet${count == 1 ? '' : 's'}';
  }

  @override
  Widget build(BuildContext context) {
    final connected = phoneName != null;
    return SettingsGroup(
      children: [
        SettingRow(
          leading: _PhoneBadge(connected: connected),
          title: phoneName ?? AgentWindow.noPhoneTitle,
          subtitle: connected
              ? '${AgentWindow.connectedHint} · '
                    '${_formatCount(packetCount)} received'
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
