import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/error/failure.dart';
import '../../../data/models/device_model.dart';
import '../../../data/repositories/device_repository.dart';
import '../../../services/discovery/discovery.dart';
import '../../../services/transport/transport.dart';
import 'connect_state.dart';

class ConnectCubit extends Cubit<ConnectState> {
  ConnectCubit(this._devices, this._browser, this._transport)
    : super(const ConnectLoading());

  final DeviceRepository _devices;
  final AgentBrowser _browser;
  final Transport _transport;

  StreamSubscription<List<DeviceModel>>? _registry;
  StreamSubscription<List<DiscoveredAgent>>? _discovery;
  StreamSubscription<Failure>? _discoveryErrors;
  StreamSubscription<TransportState>? _transportStates;

  List<DeviceModel> _trusted = const [];
  List<DiscoveredAgent> _agents = const [];
  DiscoveredAgent? _connectedAgent;
  String? _connectingId;
  String? _connectionError;
  String? _registryError;

  Future<void> start() async {
    _transportStates ??= _transport.states.listen(_onTransportState);
    _discoveryErrors ??= _browser.errors.listen(_onDiscoveryError);
    await _registry?.cancel();
    try {
      _registry = _devices.watchDevices().listen(
        _onRegistry,
        onError: _onRegistryError,
      );
    } on Failure catch (failure) {
      _registryError = failure.message;
    }
    _discovery ??= _browser.agents.listen(_onAgents);
    _agents = _browser.current;
    _syncConnected();
    _publish();
    try {
      await _browser.start();
    } on Failure catch (failure) {
      _onDiscoveryError(failure);
    }
  }

  Future<void> connect(ConnectDevice device) async {
    if (_connectingId != null) return;
    final agent = _agentFor(device.id);
    if (agent == null) return;
    _connectingId = device.id;
    _connectionError = null;
    _publish();
    try {
      await _transport.connect(
        TransportEndpoint(
          host: agent.host,
          label: agent.name,
          tcpPort: agent.tcpPort,
          udpPort: agent.udpPort,
        ),
      );
      _connectedAgent = agent;
    } on Failure catch (failure) {
      _connectionError = failure.message;
      _connectedAgent = null;
    } catch (error) {
      _connectionError = 'Could not connect to ${device.name}.';
      _connectedAgent = null;
    } finally {
      _connectingId = null;
      _publish();
    }
  }

  Future<void> disconnect() async {
    await _transport.disconnect();
    _connectedAgent = null;
    _publish();
  }

  void dismissConnectionError() {
    if (_connectionError == null) return;
    _connectionError = null;
    _publish();
  }

  void _onRegistry(List<DeviceModel> registry) {
    _trusted = registry;
    _registryError = null;
    _publish();
  }

  void _onAgents(List<DiscoveredAgent> agents) {
    _agents = agents;
    _syncConnected();
    _publish();
  }

  void _onTransportState(TransportState state) {
    if (state == TransportState.disconnected) {
      if (_connectedAgent == null) return;
      _connectedAgent = null;
    } else {
      _syncConnected();
    }
    _publish();
  }

  void _onDiscoveryError(Failure failure) {
    _connectionError = failure.message;
    _publish();
  }

  void _onRegistryError(Object error) {
    _registryError = error is Failure
        ? error.message
        : 'Your saved laptops could not be loaded.';
    _publish();
  }

  void _syncConnected() {
    if (_transport.state == TransportState.disconnected) {
      _connectedAgent = null;
      return;
    }
    final endpoint = _transport.endpoint;
    if (endpoint == null) return;
    for (final agent in _agents) {
      if (agent.tcpPort == endpoint.tcpPort &&
          agent.hosts.contains(endpoint.host)) {
        _connectedAgent = agent;
        return;
      }
    }
  }

  DiscoveredAgent? _agentFor(String id) {
    for (final agent in _agents) {
      if (agent.id == id) return agent;
    }
    final connected = _connectedAgent;
    return connected != null && connected.id == id ? connected : null;
  }

  void _publish() {
    if (isClosed) return;
    final trustedIds = {for (final device in _trusted) device.id};
    final visible = <DiscoveredAgent>[..._agents];
    final connected = _connectedAgent;
    if (connected != null && !visible.any((a) => a.id == connected.id)) {
      visible.insert(0, connected);
    }
    final discoveredIds = {for (final agent in visible) agent.id};
    final nearby = [
      for (final agent in visible)
        ConnectDevice(
          id: agent.id,
          name: agent.name,
          platform: agent.platform,
          status: _statusFor(agent, trustedIds),
          address: agent.host,
        ),
    ];
    final offline = [
      for (final device in _trusted)
        if (!discoveredIds.contains(device.id))
          ConnectDevice(
            id: device.id,
            name: device.name,
            platform: device.platform,
            status: ConnectDeviceStatus.offline,
            lastSeenAt: device.lastSeenAt,
          ),
    ]..sort(_byLastSeen);
    emit(
      ConnectReady(
        nearby: nearby,
        offline: offline,
        connectionError: _connectionError,
        registryError: _registryError,
      ),
    );
  }

  ConnectDeviceStatus _statusFor(DiscoveredAgent agent, Set<String> trusted) {
    if (agent.id == _connectedAgent?.id) return ConnectDeviceStatus.connected;
    if (agent.id == _connectingId) return ConnectDeviceStatus.connecting;
    if (!agent.isCompatible) return ConnectDeviceStatus.incompatible;
    return trusted.contains(agent.id)
        ? ConnectDeviceStatus.available
        : ConnectDeviceStatus.untrusted;
  }

  static int _byLastSeen(ConnectDevice a, ConnectDevice b) {
    final left = a.lastSeenAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final right = b.lastSeenAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return right.compareTo(left);
  }

  @override
  Future<void> close() {
    _registry?.cancel();
    _discovery?.cancel();
    _discoveryErrors?.cancel();
    _transportStates?.cancel();
    unawaited(_browser.stop());
    return super.close();
  }
}
