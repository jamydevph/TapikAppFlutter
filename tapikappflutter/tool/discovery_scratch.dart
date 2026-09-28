import 'dart:io';

import 'package:tapikappflutter/core/resources/constants.dart';
import 'package:tapikappflutter/services/discovery/discovery.dart';

var _passed = 0;
var _failed = 0;

void _check(String label, Object? actual, Object? expected) {
  final ok = '$actual' == '$expected';
  if (ok) {
    _passed += 1;
  } else {
    _failed += 1;
  }
  stdout.writeln('${ok ? 'PASS' : 'FAIL'}  $label');
  if (!ok) {
    stdout.writeln('        expected: $expected');
    stdout.writeln('        actual:   $actual');
  }
}

void main() {
  stdout.writeln(
    'address selection — the order mDNSResponder actually returns',
  );
  _check(
    'real dns-sd -G v4v6 output picks the routable IPv4',
    DiscoveredAgent.reachableHosts([
      '::1',
      'fe80::1%lo0',
      'fe80::14a8:4c1d:f464:619%en0',
      '127.0.0.1',
      '192.168.254.110',
    ]),
    ['192.168.254.110'],
  );
  _check(
    'IPv4 ordered ahead of a global IPv6',
    DiscoveredAgent.reachableHosts(['2001:db8::5', '10.0.0.7']),
    ['10.0.0.7', '2001:db8::5'],
  );
  _check(
    'a global IPv6 is kept when there is no IPv4',
    DiscoveredAgent.reachableHosts(['fe80::1%en0', '2001:db8::5']),
    ['2001:db8::5'],
  );
  _check(
    'loopback only yields nothing',
    DiscoveredAgent.reachableHosts(['127.0.0.1', '::1']),
    [],
  );
  _check(
    'unparseable and empty entries are dropped',
    DiscoveredAgent.reachableHosts(['', 'not-an-address', '192.168.1.4']),
    ['192.168.1.4'],
  );
  _check('no addresses at all', DiscoveredAgent.reachableHosts([]), []);
  _check(
    'multiple IPv4 keep discovery order',
    DiscoveredAgent.reachableHosts(['192.168.1.4', '10.0.0.7']),
    ['192.168.1.4', '10.0.0.7'],
  );

  stdout.writeln('');
  stdout.writeln('agent model');
  const agent = DiscoveredAgent(
    id: 'abc',
    name: 'Laptop',
    platform: 'macOS',
    protocolVersion: TapikappConstants.protocolVersion,
    hosts: ['192.168.1.4', '2001:db8::5'],
    tcpPort: TapikappConstants.tcpPort,
    udpPort: TapikappConstants.udpPort,
  );
  _check('host is the first reachable address', agent.host, '192.168.1.4');
  _check('matching protocol version is compatible', agent.isCompatible, true);
  _check(
    'a different protocol version is not compatible',
    const DiscoveredAgent(
      id: 'abc',
      name: 'Laptop',
      platform: 'macOS',
      protocolVersion: 0,
      hosts: ['192.168.1.4'],
      tcpPort: TapikappConstants.tcpPort,
      udpPort: TapikappConstants.udpPort,
    ).isCompatible,
    false,
  );

  stdout.writeln('');
  stdout.writeln('$_passed passed, $_failed failed');
  if (_failed > 0) exitCode = 1;
}
