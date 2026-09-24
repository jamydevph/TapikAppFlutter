import 'package:equatable/equatable.dart';

class AgentState extends Equatable {
  const AgentState({
    required this.hostName,
    required this.platformLabel,
    required this.isMacOS,
    this.listening = false,
    this.pairingCode,
    this.connectedPhone,
    this.launchAtLogin = false,
    this.packetCount = 0,
    this.error,
  });

  final String hostName;
  final String platformLabel;
  final bool isMacOS;
  final bool listening;
  final String? pairingCode;
  final String? connectedPhone;
  final bool launchAtLogin;
  final int packetCount;
  final String? error;

  bool get hasConnection => connectedPhone != null;

  AgentState copyWith({
    bool? listening,
    String? Function()? pairingCode,
    String? Function()? connectedPhone,
    bool? launchAtLogin,
    int? packetCount,
    String? Function()? error,
  }) {
    return AgentState(
      hostName: hostName,
      platformLabel: platformLabel,
      isMacOS: isMacOS,
      listening: listening ?? this.listening,
      pairingCode: pairingCode == null ? this.pairingCode : pairingCode(),
      connectedPhone: connectedPhone == null
          ? this.connectedPhone
          : connectedPhone(),
      launchAtLogin: launchAtLogin ?? this.launchAtLogin,
      packetCount: packetCount ?? this.packetCount,
      error: error == null ? this.error : error(),
    );
  }

  @override
  List<Object?> get props => [
    hostName,
    platformLabel,
    isMacOS,
    listening,
    pairingCode,
    connectedPhone,
    launchAtLogin,
    packetCount,
    error,
  ];
}
