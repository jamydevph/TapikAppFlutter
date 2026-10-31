import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/app_typography.dart';
import '../view_model/connect_cubit.dart';
import '../view_model/connect_state.dart';

class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({super.key, required this.onConnect});

  static const Duration animation = Duration(milliseconds: 220);
  static const Offset hiddenOffset = Offset(0, -0.4);

  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return BlocSelector<ConnectCubit, ConnectState, LinkNotice?>(
      selector: (state) => state is ConnectReady ? state.linkNotice : null,
      builder: (context, notice) {
        return SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.x2s,
              AppSpacing.md,
              0,
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: animation,
                transitionBuilder: (child, progress) => FadeTransition(
                  opacity: progress,
                  child: SlideTransition(
                    position: Tween(
                      begin: hiddenOffset,
                      end: Offset.zero,
                    ).animate(progress),
                    child: child,
                  ),
                ),
                child: notice == null
                    ? const SizedBox.shrink()
                    : _BannerCard(
                        key: ValueKey(notice.kind),
                        notice: notice,
                        onConnect: onConnect,
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({super.key, required this.notice, required this.onConnect});

  static const double iconSize = AppSpacing.lg;
  static const double syncGlyph = AppSpacing.md - AppSpacing.x3s;
  static const double gap = AppSpacing.xs + AppSpacing.x3s;
  static const double padding = AppSpacing.sm + AppSpacing.x3s;
  static const String connect = 'Connect';
  static const String dismiss = 'Dismiss';

  final LinkNotice notice;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final gaveUp = notice.kind == LinkNoticeKind.gaveUp;
    final (fill, icon, title, body) = switch (notice.kind) {
      LinkNoticeKind.lost => (
        colors.toastDanger,
        Icons.cancel,
        'Connection lost',
        '${notice.laptop} stopped answering.',
      ),
      LinkNoticeKind.reconnecting => (
        colors.toastWarning,
        Icons.sync,
        'Reconnecting…',
        'Trying ${notice.laptop} again.',
      ),
      LinkNoticeKind.restored => (
        colors.toastSuccess,
        Icons.check_circle,
        'Reconnected',
        'Back on ${notice.laptop}.',
      ),
      LinkNoticeKind.gaveUp => (
        colors.toastDanger,
        Icons.cancel,
        'Couldn’t reconnect',
        notice.detail ??
            '${notice.laptop} isn’t answering. Check Wi-Fi, then try again.',
      ),
    };
    final ink = colors.onToast;
    return Semantics(
      container: true,
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(AppRadius.md),
          boxShadow: AppShadows.raised,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            padding,
            AppSpacing.sm,
            gaveUp ? AppSpacing.x2s : padding,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              if (notice.kind == LinkNoticeKind.reconnecting)
                DecoratedBox(
                  decoration: BoxDecoration(color: ink, shape: BoxShape.circle),
                  child: SizedBox.square(
                    dimension: iconSize,
                    child: Icon(icon, size: syncGlyph, color: fill),
                  ),
                )
              else
                Icon(icon, size: iconSize, color: ink),
              const SizedBox(width: gap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.labelM.copyWith(color: ink),
                    ),
                    const SizedBox(height: AppSpacing.x3s),
                    Text(body, style: AppTextStyles.bodyS.copyWith(color: ink)),
                  ],
                ),
              ),
              if (gaveUp) ...[
                TextButton(
                  onPressed: () {
                    context.read<ConnectCubit>().dismissLinkNotice();
                    onConnect();
                  },
                  style: TextButton.styleFrom(foregroundColor: ink),
                  child: const Text(connect),
                ),
                IconButton(
                  tooltip: dismiss,
                  onPressed: context.read<ConnectCubit>().dismissLinkNotice,
                  icon: Icon(Icons.close, color: ink),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
