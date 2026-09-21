import 'package:equatable/equatable.dart';

import '../../../core/theme/app_theme_mode.dart';

class SettingsDevice extends Equatable {
  const SettingsDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.certFingerprint,
    this.trustedAt,
    this.lastSeenAt,
  });

  final String id;
  final String name;
  final String platform;
  final String certFingerprint;
  final DateTime? trustedAt;
  final DateTime? lastSeenAt;

  String get platformLabel {
    switch (platform.toLowerCase()) {
      case 'macos':
        return 'macOS';
      case 'windows':
        return 'Windows';
      case 'linux':
        return 'Linux';
      default:
        return platform;
    }
  }

  @override
  List<Object?> get props => [
    id,
    name,
    platform,
    certFingerprint,
    trustedAt,
    lastSeenAt,
  ];
}

class SettingsState extends Equatable {
  const SettingsState({
    this.loaded = false,
    this.sensitivity = 1.0,
    this.naturalScrolling = true,
    this.hapticFeedback = true,
    this.themeMode = AppThemeMode.system,
    this.devices = const [],
    this.devicesLoaded = false,
    this.revokingIds = const {},
    this.error,
    this.errorId = 0,
  });

  final bool loaded;
  final double sensitivity;
  final bool naturalScrolling;
  final bool hapticFeedback;
  final AppThemeMode themeMode;
  final List<SettingsDevice> devices;
  final bool devicesLoaded;
  final Set<String> revokingIds;
  final String? error;
  final int errorId;

  bool isRevoking(String id) => revokingIds.contains(id);

  SettingsState copyWith({
    bool? loaded,
    double? sensitivity,
    bool? naturalScrolling,
    bool? hapticFeedback,
    AppThemeMode? themeMode,
    List<SettingsDevice>? devices,
    bool? devicesLoaded,
    Set<String>? revokingIds,
    String? error,
    int? errorId,
  }) {
    return SettingsState(
      loaded: loaded ?? this.loaded,
      sensitivity: sensitivity ?? this.sensitivity,
      naturalScrolling: naturalScrolling ?? this.naturalScrolling,
      hapticFeedback: hapticFeedback ?? this.hapticFeedback,
      themeMode: themeMode ?? this.themeMode,
      devices: devices ?? this.devices,
      devicesLoaded: devicesLoaded ?? this.devicesLoaded,
      revokingIds: revokingIds ?? this.revokingIds,
      error: error ?? this.error,
      errorId: errorId ?? this.errorId,
    );
  }

  @override
  List<Object?> get props => [
    loaded,
    sensitivity,
    naturalScrolling,
    hapticFeedback,
    themeMode,
    devices,
    devicesLoaded,
    revokingIds,
    error,
    errorId,
  ];
}
