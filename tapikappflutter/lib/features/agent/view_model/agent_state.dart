import 'package:equatable/equatable.dart';

import '../../../services/injector/injector.dart';

class AgentState extends Equatable {
  const AgentState({
    required this.hostName,
    required this.platformLabel,
    required this.isMacOS,
    this.laptopId,
    this.listening = false,
    this.pairingCode,
    this.connectedPhone,
    this.pairedPhones = 0,
    this.forgetUnsaved = false,
    this.launchAtLogin = false,
    this.packetCount = 0,
    this.error,
    this.permission = InjectorPermission.denied,
  });

  final String hostName;
  final String platformLabel;
  final bool isMacOS;
  final String? laptopId;
  final bool listening;
  final String? pairingCode;
  final String? connectedPhone;
  final int pairedPhones;
  final bool forgetUnsaved;
  final bool launchAtLogin;
  final int packetCount;
  final String? error;
  final InjectorPermission permission;

  bool get hasConnection => connectedPhone != null;

  AgentState copyWith({
    bool? listening,
    String? Function()? pairingCode,
    String? Function()? connectedPhone,
    int? pairedPhones,
    bool? forgetUnsaved,
    bool? launchAtLogin,
    int? packetCount,
    String? Function()? error,
    InjectorPermission? permission,
  }) {
    return AgentState(
      hostName: hostName,
      platformLabel: platformLabel,
      isMacOS: isMacOS,
      laptopId: laptopId,
      listening: listening ?? this.listening,
      pairingCode: pairingCode == null ? this.pairingCode : pairingCode(),
      connectedPhone: connectedPhone == null
          ? this.connectedPhone
          : connectedPhone(),
      pairedPhones: pairedPhones ?? this.pairedPhones,
      forgetUnsaved: forgetUnsaved ?? this.forgetUnsaved,
      launchAtLogin: launchAtLogin ?? this.launchAtLogin,
      packetCount: packetCount ?? this.packetCount,
      error: error == null ? this.error : error(),
      permission: permission ?? this.permission,
    );
  }

  @override
  List<Object?> get props => [
    hostName,
    platformLabel,
    isMacOS,
    laptopId,
    listening,
    pairingCode,
    connectedPhone,
    pairedPhones,
    forgetUnsaved,
    launchAtLogin,
    packetCount,
    error,
    permission,
  ];
}
