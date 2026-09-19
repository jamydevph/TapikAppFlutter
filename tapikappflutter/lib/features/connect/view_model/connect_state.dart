import 'package:equatable/equatable.dart';

enum ConnectDeviceStatus { connected, available, untrusted, offline }

class ConnectDevice extends Equatable {
  const ConnectDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.status,
    this.address,
    this.lastSeenAt,
  });

  final String id;
  final String name;
  final String platform;
  final ConnectDeviceStatus status;
  final String? address;
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
  List<Object?> get props => [id, name, platform, status, address, lastSeenAt];
}

sealed class ConnectState extends Equatable {
  const ConnectState();

  @override
  List<Object?> get props => [];
}

class ConnectLoading extends ConnectState {
  const ConnectLoading();
}

class ConnectReady extends ConnectState {
  const ConnectReady({required this.nearby, required this.offline});

  final List<ConnectDevice> nearby;
  final List<ConnectDevice> offline;

  @override
  List<Object?> get props => [nearby, offline];
}

class ConnectError extends ConnectState {
  const ConnectError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
