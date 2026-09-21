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
  });

  final String hostName;
  final String platformLabel;
  final bool isMacOS;
  final bool listening;
  final String? pairingCode;
  final String? connectedPhone;
  final bool launchAtLogin;

  bool get hasConnection => connectedPhone != null;

  AgentState copyWith({
    bool? listening,
    String? Function()? pairingCode,
    String? Function()? connectedPhone,
    bool? launchAtLogin,
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
  ];
}
