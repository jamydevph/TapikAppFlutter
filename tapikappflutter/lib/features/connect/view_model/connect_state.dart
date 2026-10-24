import 'package:equatable/equatable.dart';

enum ConnectDeviceStatus {
  connected,
  connecting,
  available,
  untrusted,
  incompatible,
  outdatedPhone,
  offline,
}

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

  bool get isConnectable =>
      status == ConnectDeviceStatus.available ||
      status == ConnectDeviceStatus.untrusted;

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

enum BluetoothAccess { needsPermission, blocked, off, ready }

class BluetoothSection extends Equatable {
  const BluetoothSection({
    required this.access,
    this.computers = const [],
    this.error,
  });

  final BluetoothAccess access;
  final List<ConnectDevice> computers;
  final String? error;

  @override
  List<Object?> get props => [access, computers, error];
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
  const ConnectReady({
    required this.nearby,
    required this.offline,
    this.needsPairingCode = false,
    this.pairingLaptop,
    this.pairingLaptopId,
    this.connectionError,
    this.registryError,
    this.bluetooth,
  });

  final List<ConnectDevice> nearby;
  final List<ConnectDevice> offline;
  final bool needsPairingCode;
  final String? pairingLaptop;
  final String? pairingLaptopId;
  final String? connectionError;
  final String? registryError;
  final BluetoothSection? bluetooth;

  @override
  List<Object?> get props => [
    nearby,
    offline,
    needsPairingCode,
    pairingLaptop,
    pairingLaptopId,
    connectionError,
    registryError,
    bluetooth,
  ];
}

class ConnectError extends ConnectState {
  const ConnectError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
