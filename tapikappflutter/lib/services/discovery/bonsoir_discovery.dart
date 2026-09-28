import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

import '../../core/error/failure.dart';
import '../../core/resources/constants.dart';
import 'discovery.dart';

class BonsoirAdvertiser implements AgentAdvertiser {
  BonsoirAdvertiser({
    required this.id,
    required this.name,
    required this.platform,
  });

  final String id;
  final String name;
  final String platform;

  BonsoirBroadcast? _broadcast;
  int _generation = 0;
  bool _disposed = false;

  @override
  Future<void> start() async {
    if (_disposed) return;
    final generation = ++_generation;
    await _release();
    if (_disposed || generation != _generation) return;
    final broadcast = BonsoirBroadcast(
      service: _service(),
      printLogs: kDebugMode,
    );
    try {
      await broadcast.initialize();
      if (_disposed || generation != _generation) {
        await _quietStop(broadcast);
        return;
      }
      await broadcast.start();
      if (_disposed || generation != _generation) {
        await _quietStop(broadcast);
        return;
      }
      _broadcast = broadcast;
    } catch (error) {
      await _quietStop(broadcast);
      throw TransportFailure(
        'This laptop could not announce itself on the network. $error',
      );
    }
  }

  @override
  Future<void> stop() async {
    _generation += 1;
    await _release();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation += 1;
    await _release();
  }

  BonsoirService _service() {
    return BonsoirService(
      name: name,
      type: TapikappConstants.serviceType,
      port: TapikappConstants.tcpPort,
      attributes: {
        DiscoveredAgent.keyId: id,
        DiscoveredAgent.keyPlatform: platform,
        DiscoveredAgent.keyVersion: '${TapikappConstants.protocolVersion}',
        DiscoveredAgent.keyUdpPort: '${TapikappConstants.udpPort}',
      },
    );
  }

  Future<void> _release() async {
    final broadcast = _broadcast;
    _broadcast = null;
    await _quietStop(broadcast);
  }

  static Future<void> _quietStop(BonsoirBroadcast? broadcast) async {
    if (broadcast == null) return;
    try {
      await broadcast.stop();
    } catch (_) {}
  }
}

class BonsoirBrowser implements AgentBrowser {
  final StreamController<List<DiscoveredAgent>> _controller =
      StreamController<List<DiscoveredAgent>>.broadcast();
  final StreamController<Failure> _errors =
      StreamController<Failure>.broadcast();
  final Map<String, DiscoveredAgent> _found = <String, DiscoveredAgent>{};

  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _events;
  int _generation = 0;
  bool _disposed = false;

  @override
  Stream<List<DiscoveredAgent>> get agents => _controller.stream;

  @override
  Stream<Failure> get errors => _errors.stream;

  @override
  List<DiscoveredAgent> get current => _snapshot();

  @override
  Future<void> start() async {
    if (_disposed) return;
    final generation = ++_generation;
    await _release();
    if (_disposed || generation != _generation) return;
    final discovery = BonsoirDiscovery(
      type: TapikappConstants.serviceType,
      printLogs: kDebugMode,
    );
    StreamSubscription<BonsoirDiscoveryEvent>? events;
    try {
      await discovery.initialize();
      if (_disposed || generation != _generation) {
        await _quietStop(discovery, events);
        return;
      }
      events = discovery.eventStream?.listen(
        (event) => _onEvent(discovery, generation, event),
        onError: (Object error) => _onStreamError(generation, error),
      );
      await discovery.start();
      if (_disposed || generation != _generation) {
        await _quietStop(discovery, events);
        return;
      }
      _discovery = discovery;
      _events = events;
    } catch (error) {
      await _quietStop(discovery, events);
      throw TransportFailure(
        'This phone could not search the network for laptops. $error',
      );
    }
  }

  @override
  Future<void> stop() async {
    _generation += 1;
    await _release();
    if (_found.isEmpty) return;
    _found.clear();
    _publish();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation += 1;
    await _release();
    _found.clear();
    await _controller.close();
    await _errors.close();
  }

  void _onEvent(
    BonsoirDiscovery discovery,
    int generation,
    BonsoirDiscoveryEvent event,
  ) {
    if (_disposed || generation != _generation) return;
    switch (event) {
      case BonsoirDiscoveryServiceFoundEvent():
        discovery.serviceResolver.resolveService(event.service);
      case BonsoirDiscoveryServiceResolvedEvent():
        _remember(event.service);
      case BonsoirDiscoveryServiceUpdatedEvent():
        _remember(event.service);
      case BonsoirDiscoveryServiceLostEvent():
        if (_found.remove(event.service.name) == null) return;
        _publish();
      case BonsoirDiscoveryStoppedEvent():
        _discovery = null;
        _events = null;
      case BonsoirDiscoveryStartedEvent():
      case BonsoirDiscoveryServiceResolveFailedEvent():
      case BonsoirDiscoveryUnknownEvent():
        return;
    }
  }

  void _onStreamError(int generation, Object error) {
    if (_disposed || generation != _generation) return;
    if (_errors.isClosed) return;
    _errors.add(
      TransportFailure(
        'This phone could not search the network for laptops. $error',
      ),
    );
  }

  void _remember(BonsoirService service) {
    final agent = _agentFor(service);
    if (agent == null) return;
    _found[service.name] = agent;
    _publish();
  }

  static DiscoveredAgent? _agentFor(BonsoirService service) {
    final hosts = DiscoveredAgent.reachableHosts(service.hostAddresses);
    if (hosts.isEmpty) return null;
    final attributes = service.attributes;
    return DiscoveredAgent(
      id: attributes[DiscoveredAgent.keyId] ?? service.name,
      name: service.name,
      platform: attributes[DiscoveredAgent.keyPlatform] ?? '',
      protocolVersion:
          int.tryParse(attributes[DiscoveredAgent.keyVersion] ?? '') ?? 0,
      hosts: hosts,
      tcpPort: service.port,
      udpPort:
          int.tryParse(attributes[DiscoveredAgent.keyUdpPort] ?? '') ??
          TapikappConstants.udpPort,
    );
  }

  List<DiscoveredAgent> _snapshot() {
    final agents = _found.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return List<DiscoveredAgent>.unmodifiable(agents);
  }

  void _publish() {
    if (_controller.isClosed) return;
    _controller.add(_snapshot());
  }

  Future<void> _release() async {
    final discovery = _discovery;
    final events = _events;
    _discovery = null;
    _events = null;
    await _quietStop(discovery, events);
  }

  static Future<void> _quietStop(
    BonsoirDiscovery? discovery,
    StreamSubscription<BonsoirDiscoveryEvent>? events,
  ) async {
    await events?.cancel();
    if (discovery == null) return;
    try {
      await discovery.stop();
    } catch (_) {}
  }
}
