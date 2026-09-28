import 'dart:io';

import 'package:equatable/equatable.dart';

import '../../core/error/failure.dart';
import '../../core/resources/constants.dart';

class DiscoveredAgent extends Equatable {
  const DiscoveredAgent({
    required this.id,
    required this.name,
    required this.platform,
    required this.protocolVersion,
    required this.hosts,
    required this.tcpPort,
    required this.udpPort,
  });

  static const String keyId = 'id';
  static const String keyPlatform = 'platform';
  static const String keyVersion = 'version';
  static const String keyUdpPort = 'udp';

  final String id;
  final String name;
  final String platform;
  final int protocolVersion;
  final List<String> hosts;
  final int tcpPort;
  final int udpPort;

  String get host => hosts.first;

  bool get isCompatible => protocolVersion == TapikappConstants.protocolVersion;

  static List<String> reachableHosts(List<String> addresses) {
    final ipv4 = <String>[];
    final ipv6 = <String>[];
    for (final address in addresses) {
      if (address.isEmpty) continue;
      final parsed = InternetAddress.tryParse(address.split('%').first);
      if (parsed == null || parsed.isLoopback || parsed.isLinkLocal) continue;
      if (parsed.type == InternetAddressType.IPv4) {
        ipv4.add(address);
      } else {
        ipv6.add(address);
      }
    }
    return List<String>.unmodifiable([...ipv4, ...ipv6]);
  }

  @override
  List<Object?> get props => [
    id,
    name,
    platform,
    protocolVersion,
    hosts,
    tcpPort,
    udpPort,
  ];
}

abstract class AgentAdvertiser {
  Future<void> start();

  Future<void> stop();

  Future<void> dispose();
}

abstract class AgentBrowser {
  Stream<List<DiscoveredAgent>> get agents;

  Stream<Failure> get errors;

  List<DiscoveredAgent> get current;

  Future<void> start();

  Future<void> stop();

  Future<void> dispose();
}
