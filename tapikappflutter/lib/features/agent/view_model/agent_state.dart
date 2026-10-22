import 'package:equatable/equatable.dart';

import '../../../services/injector/injector.dart';
import '../../../services/security/paired_phone.dart';

class AgentState extends Equatable {
  const AgentState({
    required this.hostName,
    required this.platformLabel,
    required this.isMacOS,
    this.laptopId,
    this.listening = false,
    this.pairingCode,
    this.connectedPhone,
    this.connectedPhoneId,
    this.phones = const [],
    this.forgetUnsaved = false,
    this.forgetFailed = false,
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
  final String? connectedPhoneId;
  final List<PairedPhone> phones;
  final bool forgetUnsaved;
  final bool forgetFailed;
  final bool launchAtLogin;
  final int packetCount;
  final String? error;
  final InjectorPermission permission;

  bool get hasConnection => connectedPhone != null;

  int get pairedPhones => phones.length;

  AgentState copyWith({
    bool? listening,
    String? Function()? pairingCode,
    String? Function()? connectedPhone,
    String? Function()? connectedPhoneId,
    List<PairedPhone>? phones,
    bool? forgetUnsaved,
    bool? forgetFailed,
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
      connectedPhoneId: connectedPhoneId == null
          ? this.connectedPhoneId
          : connectedPhoneId(),
      phones: phones ?? this.phones,
      forgetUnsaved: forgetUnsaved ?? this.forgetUnsaved,
      forgetFailed: forgetFailed ?? this.forgetFailed,
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
    connectedPhoneId,
    phones,
    forgetUnsaved,
    forgetFailed,
    launchAtLogin,
    packetCount,
    error,
    permission,
  ];
}
