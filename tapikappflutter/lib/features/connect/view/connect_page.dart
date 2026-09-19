import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/injection.dart';
import '../../../core/format/relative_time.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_primary_button.dart';
import '../../../core/widgets/device_card.dart';
import '../../auth/view_model/auth_cubit.dart';
import '../../auth/view_model/auth_state.dart';
import '../view_model/connect_cubit.dart';
import '../view_model/connect_state.dart';

class ConnectPage extends StatelessWidget {
  const ConnectPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => AppProviders.connectCubit(context)..start(),
      child: const _ConnectView(),
    );
  }
}

class _ConnectView extends StatefulWidget {
  const _ConnectView();

  static const String nearbyLabel = 'ON THIS NETWORK';
  static const String offlineLabel = 'OFFLINE';
  static const String emptyNearby = 'No laptops found on this network yet.';
  static const Duration relativeTimeRefresh = Duration(minutes: 1);

  @override
  State<_ConnectView> createState() => _ConnectViewState();
}

class _ConnectViewState extends State<_ConnectView> {
  Timer? _clock;

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  void _syncClock(List<ConnectDevice> offline) {
    final showsRelativeTime = offline.any(
      (device) => device.lastSeenAt != null,
    );
    if (showsRelativeTime) {
      _clock ??= Timer.periodic(
        _ConnectView.relativeTimeRefresh,
        (_) => setState(() {}),
      );
    } else {
      _clock?.cancel();
      _clock = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SafeArea(
      bottom: false,
      child: BlocBuilder<ConnectCubit, ConnectState>(
        builder: (context, state) {
          final nearby = state is ConnectReady
              ? state.nearby
              : const <ConnectDevice>[];
          final offline = state is ConnectReady
              ? state.offline
              : const <ConnectDevice>[];
          _syncClock(offline);
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            children: [
              const SizedBox(height: AppSpacing.md + AppSpacing.x3s),
              const _Header(),
              const SizedBox(height: AppSpacing.xl),
              _SectionLabel(_ConnectView.nearbyLabel),
              const SizedBox(height: AppSpacing.xs + AppSpacing.x3s),
              if (state is ConnectError)
                Text(
                  state.message,
                  style: AppTextStyles.bodyS.copyWith(color: colors.textDanger),
                )
              else if (nearby.isEmpty)
                Text(
                  _ConnectView.emptyNearby,
                  style: AppTextStyles.bodyS.copyWith(
                    color: colors.textTertiary,
                  ),
                )
              else
                ..._cards(nearby),
              if (offline.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xl + AppSpacing.x2s),
                _SectionLabel(_ConnectView.offlineLabel),
                const SizedBox(height: AppSpacing.xs + AppSpacing.x3s),
                ..._cards(offline),
              ],
              const SizedBox(height: AppSpacing.x3l + AppSpacing.x2s),
              OutlinedButton(
                onPressed: () => _showHelp(context),
                child: const Text('Can’t see your laptop?'),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Both devices must be on the same Wi-Fi.',
                style: AppTextStyles.caption.copyWith(
                  color: colors.textTertiary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _cards(List<ConnectDevice> devices) {
    return [
      for (var i = 0; i < devices.length; i++) ...[
        if (i > 0) const SizedBox(height: AppSpacing.md),
        _DeviceTile(device: devices[i]),
      ],
    ];
  }

  void _showHelp(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (context) => const _HelpSheet(),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('Your laptops', style: AppTextStyles.headingXl, maxLines: 1),
        Flexible(
          child: BlocBuilder<AuthCubit, AuthState>(
            builder: (context, state) {
              if (state is! Authenticated) return const SizedBox.shrink();
              final user = state.user;
              final name = user.displayName ?? user.email.split('@').first;
              return _AvatarChip(name: name);
            },
          ),
        ),
      ],
    );
  }
}

class _AvatarChip extends StatelessWidget {
  const _AvatarChip({required this.name});

  static const double height = AppSpacing.xl + AppSpacing.x2s;
  static const double minWidth = AppSpacing.x3l;

  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      height: height,
      constraints: const BoxConstraints(minWidth: minWidth),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x2s),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Center(
        widthFactor: 1,
        child: Text(
          name,
          style: AppTextStyles.labelS.copyWith(color: colors.textSecondary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Text(
      text,
      style: AppTextStyles.overline.copyWith(color: colors.textTertiary),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device});

  final ConnectDevice device;

  @override
  Widget build(BuildContext context) {
    return DeviceCard(
      name: device.name,
      meta: _meta(device),
      status: switch (device.status) {
        ConnectDeviceStatus.connected => DeviceCardStatus.connected,
        ConnectDeviceStatus.available => DeviceCardStatus.available,
        ConnectDeviceStatus.untrusted => DeviceCardStatus.untrusted,
        ConnectDeviceStatus.offline => DeviceCardStatus.offline,
      },
      onTap: device.status == ConnectDeviceStatus.untrusted
          ? () => context.push(AppRoutes.pairing, extra: device.name)
          : null,
    );
  }

  static String _meta(ConnectDevice device) {
    final platform = device.platformLabel;
    switch (device.status) {
      case ConnectDeviceStatus.connected:
        return device.address == null
            ? platform
            : '$platform · ${device.address}';
      case ConnectDeviceStatus.available:
        return '$platform · trusted · tap to connect';
      case ConnectDeviceStatus.untrusted:
        return '$platform · pairing code required';
      case ConnectDeviceStatus.offline:
        final seen = device.lastSeenAt;
        return seen == null
            ? '$platform · never seen'
            : '$platform · last seen ${RelativeTime.ago(seen)}';
    }
  }
}

class _HelpSheet extends StatelessWidget {
  const _HelpSheet();

  static const List<String> tips = [
    'Make sure the laptop and this phone are on the same Wi-Fi network.',
    'Open Tapikapp on the laptop — it only shows up here while it is running.',
    'Some guest and office networks stop devices from seeing each other.',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
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
              Text('Can’t see your laptop?', style: AppTextStyles.headingM),
              const SizedBox(height: AppSpacing.sm),
              for (final tip in tips)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text(
                    tip,
                    style: AppTextStyles.bodyS.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              AppPrimaryButton(
                label: 'Got it',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
