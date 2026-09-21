import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';
import 'status_pill.dart';

enum ConnectionHeaderStatus { offline, connecting, connected }

class ConnectionHeader extends StatelessWidget {
  const ConnectionHeader({
    super.key,
    required this.deviceName,
    required this.status,
  });

  static const double height = StatusPill.height;
  static const String noDeviceTitle = 'No laptop connected';

  final String? deviceName;
  final ConnectionHeaderStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final connected = status == ConnectionHeaderStatus.connected;
    return SizedBox(
      height: height,
      child: Row(
        children: [
          Expanded(
            child: Text(
              deviceName ?? noDeviceTitle,
              style: AppTextStyles.labelM.copyWith(
                color: connected ? colors.textPrimary : colors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          switch (status) {
            ConnectionHeaderStatus.connected => const StatusPill(
              label: 'CONNECTED',
              tone: StatusPillTone.success,
            ),
            ConnectionHeaderStatus.connecting => const StatusPill(
              label: 'CONNECTING',
              tone: StatusPillTone.accent,
            ),
            ConnectionHeaderStatus.offline => const StatusPill(
              label: 'OFFLINE',
              tone: StatusPillTone.muted,
            ),
          },
        ],
      ),
    );
  }
}
